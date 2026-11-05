package sample

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Item is a row in the sample read model.
type Item struct {
	ID        string
	Name      string
	CreatedAt time.Time
}

// Projection maintains the sample_items read model.
type Projection struct {
	pool *pgxpool.Pool
}

// NewProjection creates a sample read-model projection.
func NewProjection(pool *pgxpool.Pool) *Projection {
	return &Projection{pool: pool}
}

// Name identifies this projection in checkpoint bookkeeping.
func (p *Projection) Name() string { return "sample_items" }

// Apply applies a SampleCreated event to the read model.
func (p *Projection) Apply(ctx context.Context, event eventstore.Event) error {
	if event.AggregateType != AggregateType || event.EventType != CreatedEventType {
		return nil
	}
	var payload createdPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("sample projection: decode event %d: %w", event.ID, err)
	}
	_, err := p.pool.Exec(ctx,
		`INSERT INTO sample_items (id, name, created_at)
		 VALUES ($1, $2, $3)
		 ON CONFLICT (id) DO UPDATE
		 SET name = EXCLUDED.name, created_at = EXCLUDED.created_at`,
		event.AggregateID, payload.Name, event.OccurredAt,
	)
	if err != nil {
		return fmt.Errorf("sample projection: apply event %d: %w", event.ID, err)
	}
	return nil
}

// Reset clears the derived sample read model.
func (p *Projection) Reset(ctx context.Context) error {
	if _, err := p.pool.Exec(ctx, `TRUNCATE sample_items`); err != nil {
		return fmt.Errorf("sample projection: reset: %w", err)
	}
	return nil
}

// List returns samples from the read model in ID order.
func (p *Projection) List(ctx context.Context) ([]Item, error) {
	rows, err := p.pool.Query(ctx, `SELECT id, name, created_at FROM sample_items ORDER BY id`)
	if err != nil {
		return nil, fmt.Errorf("sample projection: list: %w", err)
	}
	defer rows.Close()

	items := []Item{}
	for rows.Next() {
		var item Item
		if err := rows.Scan(&item.ID, &item.Name, &item.CreatedAt); err != nil {
			return nil, fmt.Errorf("sample projection: scan: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("sample projection: rows: %w", err)
	}
	return items, nil
}
