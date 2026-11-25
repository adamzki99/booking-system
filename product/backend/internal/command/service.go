// Package command dispatches validated commands to the append-only event store.
package command

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/metrics"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// ErrUnknownCommand indicates that no handler is registered for a command type.
var ErrUnknownCommand = errors.New("command: unknown command type")

// Command is a request to record domain events.
type Command interface {
	CommandType() string
}

// Handler validates a command and returns candidate events without storing them.
type Handler func(context.Context, Command) ([]eventstore.Event, error)

// Store records command events.
type Store interface {
	Append(context.Context, ...eventstore.Event) ([]eventstore.Event, error)
}

// Publisher delivers recorded events to subscribers.
type Publisher interface {
	Publish(context.Context, []eventstore.Event) error
}

// LockStore is a Store that can serialize command execution with a
// database-level advisory lock.
type LockStore interface {
	Store
	eventstore.Locker
}

// LockCommand is a Command that requires serialized execution under a
// database-level advisory lock. The lock is held for validation, append, and
// publication so read-model checks cannot race with concurrent commands.
type LockCommand interface {
	Command
	LockKey() int64
}

// Service orchestrates command validation, event recording, and publication.
type Service struct {
	store     Store
	publisher Publisher
	handlers  map[string]Handler
	tracer    trace.Tracer
}

// NewService creates a command service.
func NewService(store Store, publisher Publisher) *Service {
	return &Service{
		store:     store,
		publisher: publisher,
		handlers:  make(map[string]Handler),
		tracer:    otel.Tracer("command"),
	}
}

// Register associates a command type with its validation handler.
func (s *Service) Register(commandType string, handler Handler) {
	s.handlers[commandType] = handler
}

// Execute dispatches a command to its registered handler.
func (s *Service) Execute(ctx context.Context, cmd Command) (err error) {
	start := time.Now()
	ctx, span := s.tracer.Start(ctx, "command.execute", trace.WithAttributes(attribute.String("command.type", cmd.CommandType())))
	defer func() {
		outcome := "ok"
		if err != nil {
			outcome = "error"
		}
		metrics.CommandHandled(ctx, cmd.CommandType(), outcome, time.Since(start))
		span.End()
	}()

	handler, ok := s.handlers[cmd.CommandType()]
	if !ok {
		err = fmt.Errorf("%w: %s", ErrUnknownCommand, cmd.CommandType())
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return err
	}
	if release, locked, lockErr := s.lock(ctx, cmd); lockErr != nil {
		err = lockErr
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return err
	} else if locked {
		// Release runs on every path, including handler and append failures.
		// A release failure destroys the locked connection, so the lock is
		// never leaked; the command result is already determined, so the
		// error itself is not surfaced.
		defer func() { _ = release() }()
	}
	events, err := handler(ctx, cmd)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return err
	}
	recorded, err := s.store.Append(ctx, events...)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return err
	}
	for _, e := range recorded {
		metrics.EventAppended(ctx, e.EventType)
	}
	if err = s.publisher.Publish(ctx, recorded); err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return err
	}
	return nil
}

// lock acquires the advisory lock requested by the command when both the
// command and the store opt in. Commands and stores that do not implement the
// lock interfaces execute unchanged.
func (s *Service) lock(ctx context.Context, cmd Command) (release func() error, locked bool, err error) {
	lockCommand, ok := cmd.(LockCommand)
	if !ok {
		return nil, false, nil
	}
	lockStore, ok := s.store.(LockStore)
	if !ok {
		return nil, false, nil
	}
	release, err = lockStore.Lock(ctx, lockCommand.LockKey())
	if err != nil {
		return nil, false, fmt.Errorf("command: acquire lock: %w", err)
	}
	return release, true, nil
}
