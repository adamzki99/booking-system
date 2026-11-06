package booking

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
)

const (
	// CreateBookingCommandType identifies CreateBooking commands.
	CreateBookingCommandType = "booking.CreateBooking"
	// CancelOwnBookingCommandType identifies CancelOwnBooking commands.
	CancelOwnBookingCommandType = "booking.CancelOwnBooking"
)

// CreateBooking creates a booking for a user in the given interval.
type CreateBooking struct {
	ID     string
	UserID string
	Start  time.Time
	End    time.Time
}

// CommandType implements command.Command.
func (CreateBooking) CommandType() string { return CreateBookingCommandType }

// CancelOwnBooking cancels the caller's own booking.
type CancelOwnBooking struct {
	BookingID string
	UserID    string
}

// CommandType implements command.Command.
func (CancelOwnBooking) CommandType() string { return CancelOwnBookingCommandType }

// Register wires the booking commands and projection into the registry.
func Register(r *registry.Registry) *BookingsProjection {
	bookings := NewBookingsProjection(r.DB())
	r.RegisterCommand(CreateBookingCommandType, handleCreateBooking(bookings))
	r.RegisterCommand(CancelOwnBookingCommandType, handleCancelOwnBooking(bookings))
	r.RegisterProjection(bookings)
	return bookings
}

func handleCreateBooking(bookings bookingsReader) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var c CreateBooking
		switch typed := cmd.(type) {
		case CreateBooking:
			c = typed
		case *CreateBooking:
			if typed == nil {
				return nil, errors.New("booking: command is nil")
			}
			c = *typed
		default:
			return nil, fmt.Errorf("booking: expected CreateBooking, got %T", cmd)
		}

		if c.UserID == "" {
			return nil, errors.New("booking: user id is required")
		}
		now := time.Now().UTC()
		if err := ValidateInterval(c.Start, c.End, now); err != nil {
			return nil, err
		}
		overlaps, err := bookings.HasOverlap(ctx, c.Start, c.End)
		if err != nil {
			return nil, err
		}
		if overlaps {
			return nil, ErrDoubleBooking
		}

		id := c.ID
		if id == "" {
			id = NewID()
		}
		payload, err := json.Marshal(BookingCreatedPayload{
			BookingID: id,
			UserID:    c.UserID,
			Start:     c.Start,
			End:       c.End,
			CreatedAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("booking: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: AggregateType,
			AggregateID:   id,
			EventType:     BookingCreatedEventType,
			Payload:       payload,
			OccurredAt:    now,
		}}, nil
	}
}

func handleCancelOwnBooking(bookings bookingsReader) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var c CancelOwnBooking
		switch typed := cmd.(type) {
		case CancelOwnBooking:
			c = typed
		case *CancelOwnBooking:
			if typed == nil {
				return nil, errors.New("booking: command is nil")
			}
			c = *typed
		default:
			return nil, fmt.Errorf("booking: expected CancelOwnBooking, got %T", cmd)
		}

		if c.BookingID == "" {
			return nil, errors.New("booking: booking id is required")
		}
		if c.UserID == "" {
			return nil, errors.New("booking: user id is required")
		}

		b, err := bookings.GetByID(ctx, c.BookingID)
		if err != nil {
			return nil, err
		}
		if b.UserID != c.UserID {
			return nil, ErrNotOwner
		}
		if b.Status != StatusActive {
			return nil, ErrAlreadyCancelled
		}

		now := time.Now().UTC()
		payload, err := json.Marshal(BookingCancelledPayload{
			BookingID:   b.ID,
			CancelledBy: c.UserID,
			CancelledAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("booking: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: AggregateType,
			AggregateID:   b.ID,
			EventType:     BookingCancelledEventType,
			Payload:       payload,
			OccurredAt:    now,
		}}, nil
	}
}
