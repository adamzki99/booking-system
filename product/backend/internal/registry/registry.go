// Package registry wires command handlers and projections into the event store.
package registry

import (
	"context"
	"fmt"

	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/dispatcher"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/projection"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Registry holds the application's command and projection infrastructure.
type Registry struct {
	Store       eventstore.Store
	Commands    *command.Service
	Dispatcher  *dispatcher.Dispatcher
	Projections *projection.Runner
	pool        *pgxpool.Pool
}

// New runs migrations and wires recorded events to the projection runner.
func New(ctx context.Context, store eventstore.Store, pool *pgxpool.Pool) (*Registry, error) {
	if err := eventstore.Migrate(ctx, pool); err != nil {
		return nil, fmt.Errorf("registry: migrate: %w", err)
	}
	d := dispatcher.New()
	runner := projection.NewRunner(store, projection.NewPostgresCheckpointStore(pool))
	d.Subscribe(runner.Handle)
	return &Registry{
		Store:       store,
		Commands:    command.NewService(store, d),
		Dispatcher:  d,
		Projections: runner,
		pool:        pool,
	}, nil
}

// RegisterCommand registers a command handler by command type.
func (r *Registry) RegisterCommand(commandType string, handler command.Handler) {
	r.Commands.Register(commandType, handler)
}

// RegisterProjection registers a read model for live events and replay.
func (r *Registry) RegisterProjection(p projection.Projection) {
	r.Projections.Register(p)
}

// DB returns the pool used by read-model projections.
func (r *Registry) DB() *pgxpool.Pool {
	return r.pool
}
