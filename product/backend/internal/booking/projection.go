package booking

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// BookingsProjection maintains the bookings read model.
type BookingsProjection struct {
	pool *pgxpool.Pool
}

// NewBookingsProjection creates a bookings read-model projection.
func NewBookingsProjection(pool *pgxpool.Pool) *BookingsProjection {
	return &BookingsProjection{pool: pool}
}

// Name identifies this projection in checkpoint bookkeeping.
func (p *BookingsProjection) Name() string { return "bookings" }

// Apply applies booking events to the bookings read model.
func (p *BookingsProjection) Apply(ctx context.Context, event eventstore.Event) error {
	switch event.EventType {
	case BookingCreatedEventType:
		var payload BookingCreatedPayload
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			return fmt.Errorf("booking projection: decode event %d: %w", event.ID, err)
		}
		_, err := p.pool.Exec(ctx,
			`INSERT INTO bookings (id, user_id, start, "end", status, created_at)
			 VALUES ($1, $2, $3, $4, 'active', $5)
			 ON CONFLICT (id) DO UPDATE
			 SET user_id = EXCLUDED.user_id,
			     start = EXCLUDED.start,
			     "end" = EXCLUDED."end",
			     status = 'active',
			     created_at = EXCLUDED.created_at`,
			payload.BookingID, payload.UserID, payload.Start, payload.End, payload.CreatedAt,
		)
		if err != nil {
			return fmt.Errorf("booking projection: apply create event %d: %w", event.ID, err)
		}
	case BookingCancelledEventType:
		var payload BookingCancelledPayload
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			return fmt.Errorf("booking projection: decode event %d: %w", event.ID, err)
		}
		_, err := p.pool.Exec(ctx,
			`UPDATE bookings SET status = 'cancelled', cancelled_by = $2, cancelled_at = $3 WHERE id = $1`,
			payload.BookingID, payload.CancelledBy, payload.CancelledAt,
		)
		if err != nil {
			return fmt.Errorf("booking projection: apply cancel event %d: %w", event.ID, err)
		}
	}
	return nil
}

// Reset clears the derived bookings read model.
func (p *BookingsProjection) Reset(ctx context.Context) error {
	if _, err := p.pool.Exec(ctx, `TRUNCATE bookings`); err != nil {
		return fmt.Errorf("booking projection: reset: %w", err)
	}
	return nil
}

// HasOverlap reports whether an active booking overlaps the half-open interval
// [start, end).
func (p *BookingsProjection) HasOverlap(ctx context.Context, start, end time.Time) (bool, error) {
	var overlaps bool
	err := p.pool.QueryRow(ctx,
		`SELECT EXISTS (
			SELECT 1 FROM bookings
			WHERE status = 'active' AND start < $2 AND "end" > $1
		)`, start, end,
	).Scan(&overlaps)
	if err != nil {
		return false, fmt.Errorf("booking projection: overlap: %w", err)
	}
	return overlaps, nil
}

// GetByID returns a booking by id.
func (p *BookingsProjection) GetByID(ctx context.Context, id string) (Booking, error) {
	row := p.pool.QueryRow(ctx, bookingColumns+` WHERE id = $1`, id)
	b, err := scanBooking(row)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Booking{}, ErrBookingNotFound
		}
		return Booking{}, fmt.Errorf("booking projection: get: %w", err)
	}
	return b, nil
}

// ListByUser returns all bookings for a user, ordered by start.
func (p *BookingsProjection) ListByUser(ctx context.Context, userID string) ([]Booking, error) {
	rows, err := p.pool.Query(ctx, bookingColumns+` WHERE user_id = $1 ORDER BY start, id`, userID)
	if err != nil {
		return nil, fmt.Errorf("booking projection: list by user: %w", err)
	}
	defer rows.Close()
	out := []Booking{}
	for rows.Next() {
		b, err := scanBooking(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("booking projection: rows: %w", err)
	}
	return out, nil
}

// List returns active bookings overlapping the optional [from, to) range,
// ordered by start.
func (p *BookingsProjection) List(ctx context.Context, from, to *time.Time) ([]Booking, error) {
	query := bookingColumns + ` WHERE status = 'active'`
	var conds []string
	var args []any
	if from != nil {
		args = append(args, *from)
		conds = append(conds, fmt.Sprintf(`"end" > $%d`, len(args)))
	}
	if to != nil {
		args = append(args, *to)
		conds = append(conds, fmt.Sprintf(`start < $%d`, len(args)))
	}
	if len(conds) > 0 {
		query += ` AND ` + strings.Join(conds, ` AND `)
	}
	query += ` ORDER BY start, id`

	rows, err := p.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("booking projection: list: %w", err)
	}
	defer rows.Close()

	out := []Booking{}
	for rows.Next() {
		b, err := scanBooking(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("booking projection: rows: %w", err)
	}
	return out, nil
}

const bookingColumns = `SELECT id, user_id, start, "end", status, cancelled_by, created_at, cancelled_at FROM bookings`

type rowScanner interface {
	Scan(dest ...any) error
}

func scanBooking(rows rowScanner) (Booking, error) {
	var b Booking
	var status string
	var cancelledBy *string
	var cancelledAt *time.Time
	if err := rows.Scan(&b.ID, &b.UserID, &b.Start, &b.End, &status, &cancelledBy, &b.CreatedAt, &cancelledAt); err != nil {
		return Booking{}, err
	}
	b.Status = Status(status)
	b.CancelledBy = cancelledBy
	b.CancelledAt = cancelledAt
	return b, nil
}
