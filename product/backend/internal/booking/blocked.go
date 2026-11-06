package booking

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	// BlockedPeriodAggregateType is the blocked-period event aggregate type.
	BlockedPeriodAggregateType = "blocked_period"

	// BlockedPeriodBlockedEventType records a blocked period. Blocked periods
	// are append-only: there is no unblock or delete (AGENTS.md).
	BlockedPeriodBlockedEventType = "blocked_period.blocked"

	// BlockTimePeriodCommandType identifies BlockTimePeriod commands.
	BlockTimePeriodCommandType = "booking.BlockTimePeriod"
)

// BlockTimePeriod blocks basic users from creating bookings that overlap the
// interval (super users only).
type BlockTimePeriod struct {
	From        time.Time
	To          time.Time
	RequesterID string
}

// CommandType implements command.Command.
func (BlockTimePeriod) CommandType() string { return BlockTimePeriodCommandType }

// BlockedPeriodBlockedPayload is the payload for blocked_period.blocked events.
type BlockedPeriodBlockedPayload struct {
	PeriodID  string    `json:"period_id"`
	From      time.Time `json:"from"`
	To        time.Time `json:"to"`
	ByUserID  string    `json:"by_user_id"`
	BlockedAt time.Time `json:"blocked_at"`
}

// BlockedPeriod is a row in the blocked_periods read model.
type BlockedPeriod struct {
	ID        string    `json:"id"`
	Start     time.Time `json:"start"`
	End       time.Time `json:"end"`
	BlockedBy string    `json:"blocked_by"`
	BlockedAt time.Time `json:"blocked_at"`
}

// blockedReader is the part of the blocked-periods read model command handlers
// and the service need.
type blockedReader interface {
	HasOverlap(ctx context.Context, start, end time.Time) (bool, error)
	List(ctx context.Context) ([]BlockedPeriod, error)
}

// ValidateBlockedInterval reports whether the interval is well-formed: start
// strictly before end.
func ValidateBlockedInterval(from, to time.Time) error {
	if !from.Before(to) {
		return ErrInvalidInterval
	}
	return nil
}

func handleBlockTimePeriod(users Directory) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var c BlockTimePeriod
		switch typed := cmd.(type) {
		case BlockTimePeriod:
			c = typed
		case *BlockTimePeriod:
			if typed == nil {
				return nil, errors.New("booking: command is nil")
			}
			c = *typed
		default:
			return nil, fmt.Errorf("booking: expected BlockTimePeriod, got %T", cmd)
		}

		if c.RequesterID == "" {
			return nil, errors.New("booking: requester id is required")
		}
		u, err := users.GetByID(ctx, c.RequesterID)
		if err != nil || !u.Role.AtLeast(user.RoleSuper) {
			return nil, ErrForbidden
		}
		if err := ValidateBlockedInterval(c.From, c.To); err != nil {
			return nil, err
		}

		now := time.Now().UTC()
		id := NewID()
		payload, err := json.Marshal(BlockedPeriodBlockedPayload{
			PeriodID:  id,
			From:      c.From,
			To:        c.To,
			ByUserID:  c.RequesterID,
			BlockedAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("booking: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: BlockedPeriodAggregateType,
			AggregateID:   id,
			EventType:     BlockedPeriodBlockedEventType,
			Payload:       payload,
			OccurredAt:    now,
		}}, nil
	}
}

// BlockedPeriodsProjection maintains the blocked_periods read model.
type BlockedPeriodsProjection struct {
	pool *pgxpool.Pool
}

// NewBlockedPeriodsProjection creates a blocked-periods read-model projection.
func NewBlockedPeriodsProjection(pool *pgxpool.Pool) *BlockedPeriodsProjection {
	return &BlockedPeriodsProjection{pool: pool}
}

// Name identifies this projection in checkpoint bookkeeping.
func (p *BlockedPeriodsProjection) Name() string { return "blocked_periods" }

// Apply applies blocked-period events to the blocked_periods read model.
func (p *BlockedPeriodsProjection) Apply(ctx context.Context, event eventstore.Event) error {
	if event.EventType != BlockedPeriodBlockedEventType {
		return nil
	}
	var payload BlockedPeriodBlockedPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("blocked period projection: decode event %d: %w", event.ID, err)
	}
	_, err := p.pool.Exec(ctx,
		`INSERT INTO blocked_periods (id, start, "end", blocked_by, blocked_at)
		 VALUES ($1, $2, $3, $4, $5)
		 ON CONFLICT (id) DO UPDATE
		 SET start = EXCLUDED.start,
		     "end" = EXCLUDED."end",
		     blocked_by = EXCLUDED.blocked_by,
		     blocked_at = EXCLUDED.blocked_at`,
		payload.PeriodID, payload.From, payload.To, payload.ByUserID, payload.BlockedAt,
	)
	if err != nil {
		return fmt.Errorf("blocked period projection: apply block event %d: %w", event.ID, err)
	}
	return nil
}

// Reset clears the derived blocked_periods read model.
func (p *BlockedPeriodsProjection) Reset(ctx context.Context) error {
	if _, err := p.pool.Exec(ctx, `TRUNCATE blocked_periods`); err != nil {
		return fmt.Errorf("blocked period projection: reset: %w", err)
	}
	return nil
}

// HasOverlap reports whether an active blocked period overlaps the half-open
// interval [start, end).
func (p *BlockedPeriodsProjection) HasOverlap(ctx context.Context, start, end time.Time) (bool, error) {
	var overlaps bool
	err := p.pool.QueryRow(ctx,
		`SELECT EXISTS (
			SELECT 1 FROM blocked_periods
			WHERE start < $2 AND "end" > $1
		)`, start, end,
	).Scan(&overlaps)
	if err != nil {
		return false, fmt.Errorf("blocked period projection: overlap: %w", err)
	}
	return overlaps, nil
}

// List returns blocked periods ordered by start.
func (p *BlockedPeriodsProjection) List(ctx context.Context) ([]BlockedPeriod, error) {
	rows, err := p.pool.Query(ctx,
		`SELECT id, start, "end", blocked_by, blocked_at FROM blocked_periods ORDER BY start, id`)
	if err != nil {
		return nil, fmt.Errorf("blocked period projection: list: %w", err)
	}
	defer rows.Close()

	out := []BlockedPeriod{}
	for rows.Next() {
		var b BlockedPeriod
		if err := rows.Scan(&b.ID, &b.Start, &b.End, &b.BlockedBy, &b.BlockedAt); err != nil {
			return nil, fmt.Errorf("blocked period projection: scan: %w", err)
		}
		out = append(out, b)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("blocked period projection: rows: %w", err)
	}
	return out, nil
}
