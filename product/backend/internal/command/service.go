// Package command dispatches validated commands to the append-only event store.
package command

import (
	"context"
	"errors"
	"fmt"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"

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
func (s *Service) Execute(ctx context.Context, cmd Command) error {
	ctx, span := s.tracer.Start(ctx, "command.execute", trace.WithAttributes(attribute.String("command.type", cmd.CommandType())))
	defer span.End()

	handler, ok := s.handlers[cmd.CommandType()]
	if !ok {
		err := fmt.Errorf("%w: %s", ErrUnknownCommand, cmd.CommandType())
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return err
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
	if err := s.publisher.Publish(ctx, recorded); err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return err
	}
	return nil
}
