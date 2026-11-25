package ical

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// CalendarTokenProjection maintains the calendar_tokens read model.
type CalendarTokenProjection struct {
	pool *pgxpool.Pool
}

// NewCalendarTokenProjection creates a calendar-token read-model projection.
func NewCalendarTokenProjection(pool *pgxpool.Pool) *CalendarTokenProjection {
	return &CalendarTokenProjection{pool: pool}
}

// Name identifies this projection in checkpoint bookkeeping.
func (p *CalendarTokenProjection) Name() string { return "calendar_tokens" }

// Apply applies calendar token events to the read model.
func (p *CalendarTokenProjection) Apply(ctx context.Context, event eventstore.Event) error {
	switch event.EventType {
	case CalendarTokenGeneratedEventType:
		var payload CalendarTokenGeneratedPayload
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			return fmt.Errorf("ical projection: decode event %d: %w", event.ID, err)
		}
		_, err := p.pool.Exec(ctx,
			`INSERT INTO calendar_tokens (user_id, token_hash, created_at)
			 VALUES ($1, $2, $3)
			 ON CONFLICT (user_id) DO UPDATE
			 SET token_hash = EXCLUDED.token_hash,
			     created_at = EXCLUDED.created_at`,
			payload.UserID, payload.TokenHash, payload.GeneratedAt,
		)
		if err != nil {
			return fmt.Errorf("ical projection: apply event %d: %w", event.ID, err)
		}
	}
	return nil
}

// Reset clears the derived calendar_tokens read model.
func (p *CalendarTokenProjection) Reset(ctx context.Context) error {
	if _, err := p.pool.Exec(ctx, `TRUNCATE calendar_tokens`); err != nil {
		return fmt.Errorf("ical projection: reset: %w", err)
	}
	return nil
}

// UserIDByTokenHash resolves a user id from a token hash.
func (p *CalendarTokenProjection) UserIDByTokenHash(ctx context.Context, hash string) (string, error) {
	var userID string
	err := p.pool.QueryRow(ctx, `SELECT user_id FROM calendar_tokens WHERE token_hash = $1`, hash).Scan(&userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", errors.New("ical: token not found")
		}
		return "", fmt.Errorf("ical projection: lookup: %w", err)
	}
	return userID, nil
}

// Aliases.
func (p *CalendarTokenProjection) UserIDByToken(ctx context.Context, hash string) (string, error) {
	return p.UserIDByTokenHash(ctx, hash)
}
func (p *CalendarTokenProjection) UserByTokenHash(ctx context.Context, hash string) (string, error) {
	return p.UserIDByTokenHash(ctx, hash)
}
