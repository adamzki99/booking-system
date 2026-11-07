// Package projection maintains read models from recorded events.
package projection

import (
	"context"
	"fmt"
	"sort"
	"sync"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// Projection is a named read model built from events.
type Projection interface {
	Name() string
	Apply(context.Context, eventstore.Event) error
	Reset(context.Context) error
}

// CheckpointStore persists a projection's last applied event ID.
type CheckpointStore interface {
	Get(context.Context, string) (int64, error)
	Set(context.Context, string, int64) error
	Reset(context.Context, string) error
}

// Runner applies live and replayed events to registered projections.
type Runner struct {
	store       eventstore.Store
	checkpoints CheckpointStore
	mu          sync.Mutex
	projections map[string]Projection
}

// NewRunner creates a projection runner.
func NewRunner(store eventstore.Store, checkpoints CheckpointStore) *Runner {
	return &Runner{
		store:       store,
		checkpoints: checkpoints,
		projections: make(map[string]Projection),
	}
}

// Register adds a projection to the runner.
func (r *Runner) Register(projection Projection) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.projections[projection.Name()] = projection
}

// Handle applies events newer than each projection's checkpoint.
func (r *Runner) Handle(ctx context.Context, events []eventstore.Event) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.handleLocked(ctx, events)
}

// CatchUp loads the event history and applies events after each checkpoint.
func (r *Runner) CatchUp(ctx context.Context) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	events, err := r.store.LoadAll(ctx)
	if err != nil {
		return fmt.Errorf("projection: catch up: %w", err)
	}
	return r.handleLocked(ctx, events)
}

// Rebuild resets one read model and replays the complete event history into it.
func (r *Runner) Rebuild(ctx context.Context, name string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	projection, ok := r.projections[name]
	if !ok {
		return fmt.Errorf("projection %s: not registered", name)
	}
	if err := r.resetLocked(ctx, name, projection); err != nil {
		return err
	}
	events, err := r.store.LoadAll(ctx)
	if err != nil {
		return fmt.Errorf("projection %s: rebuild: %w", name, err)
	}
	return r.applyLocked(ctx, name, projection, events)
}

// RebuildAll resets and replays every registered read model.
func (r *Runner) RebuildAll(ctx context.Context) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	names := make([]string, 0, len(r.projections))
	for name := range r.projections {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		if err := r.resetLocked(ctx, name, r.projections[name]); err != nil {
			return err
		}
	}
	events, err := r.store.LoadAll(ctx)
	if err != nil {
		return fmt.Errorf("projection: rebuild all: %w", err)
	}
	for _, name := range names {
		if err := r.applyLocked(ctx, name, r.projections[name], events); err != nil {
			return err
		}
	}
	return nil
}

func (r *Runner) resetLocked(ctx context.Context, name string, projection Projection) error {
	if err := projection.Reset(ctx); err != nil {
		return fmt.Errorf("projection %s: reset: %w", name, err)
	}
	if err := r.checkpoints.Reset(ctx, name); err != nil {
		return fmt.Errorf("projection %s: reset checkpoint: %w", name, err)
	}
	return nil
}

func (r *Runner) handleLocked(ctx context.Context, events []eventstore.Event) error {
	for name, projection := range r.projections {
		if err := r.applyLocked(ctx, name, projection, events); err != nil {
			return err
		}
	}
	return nil
}

func (r *Runner) applyLocked(ctx context.Context, name string, projection Projection, events []eventstore.Event) error {
	ctx, span := otel.Tracer("projection").Start(ctx, "projection.apply", trace.WithAttributes(attribute.String("projection.name", name), attribute.Int("event.count", len(events))))
	defer span.End()
	checkpoint, err := r.checkpoints.Get(ctx, name)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return fmt.Errorf("projection %s: get checkpoint: %w", name, err)
	}
	for _, event := range events {
		if event.ID <= checkpoint {
			continue
		}
		if err := projection.Apply(ctx, event); err != nil {
			span.RecordError(err)
			span.SetStatus(codes.Error, err.Error())
			return fmt.Errorf("projection %s: apply event %d: %w", name, event.ID, err)
		}
		if err := r.checkpoints.Set(ctx, name, event.ID); err != nil {
			span.RecordError(err)
			span.SetStatus(codes.Error, err.Error())
			return fmt.Errorf("projection %s: set checkpoint %d: %w", name, event.ID, err)
		}
		checkpoint = event.ID
	}
	return nil
}
