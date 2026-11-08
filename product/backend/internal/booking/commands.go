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
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

const (
	// CreateBookingCommandType identifies CreateBooking commands.
	CreateBookingCommandType = "booking.CreateBooking"
	// CancelOwnBookingCommandType identifies CancelOwnBooking commands.
	CancelOwnBookingCommandType = "booking.CancelOwnBooking"
	// CancelAnyBookingCommandType identifies CancelAnyBooking commands.
	CancelAnyBookingCommandType = "booking.CancelAnyBooking"
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

// CancelAnyBooking cancels any user's booking (super users only).
type CancelAnyBooking struct {
	BookingID   string
	RequesterID string
}

// CommandType implements command.Command.
func (CancelAnyBooking) CommandType() string { return CancelAnyBookingCommandType }

// Register wires the booking and blocked-period commands and projections into
// the registry. users is the user directory used for role checks.
func Register(r *registry.Registry, users Directory, rules BookingRules) (*BookingsProjection, *BlockedPeriodsProjection) {
	bookings := NewBookingsProjection(r.DB())
	blocked := NewBlockedPeriodsProjection(r.DB())
	r.RegisterCommand(CreateBookingCommandType, handleCreateBooking(bookings, blocked, users, rules))
	r.RegisterCommand(CancelOwnBookingCommandType, handleCancelOwnBooking(bookings))
	r.RegisterCommand(CancelAnyBookingCommandType, handleCancelAnyBooking(bookings, users))
	r.RegisterCommand(BlockTimePeriodCommandType, handleBlockTimePeriod(users))
	r.RegisterProjection(bookings)
	r.RegisterProjection(blocked)
	return bookings, blocked
}

func handleCreateBooking(bookings bookingsReader, blocked blockedReader, users Directory, rules BookingRules) command.Handler {
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
		if rules != nil {
			if err := rules.ValidateBooking(ctx, c.Start, c.End); err != nil {
				return nil, err
			}
		}
		overlaps, err := bookings.HasOverlap(ctx, c.Start, c.End)
		if err != nil {
			return nil, err
		}
		if overlaps {
			return nil, ErrDoubleBooking
		}
		if blocked != nil && !createsAsSuper(ctx, users, c.UserID) {
			blockedOverlaps, err := blocked.HasOverlap(ctx, c.Start, c.End)
			if err != nil {
				return nil, err
			}
			if blockedOverlaps {
				return nil, ErrBlockedPeriod
			}
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
		event, err := newBookingCancelledEvent(b, c.UserID, now)
		if err != nil {
			return nil, err
		}
		return []eventstore.Event{event}, nil
	}
}

func handleCancelAnyBooking(bookings bookingsReader, users Directory) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var c CancelAnyBooking
		switch typed := cmd.(type) {
		case CancelAnyBooking:
			c = typed
		case *CancelAnyBooking:
			if typed == nil {
				return nil, errors.New("booking: command is nil")
			}
			c = *typed
		default:
			return nil, fmt.Errorf("booking: expected CancelAnyBooking, got %T", cmd)
		}

		if c.BookingID == "" {
			return nil, errors.New("booking: booking id is required")
		}
		if c.RequesterID == "" {
			return nil, errors.New("booking: requester id is required")
		}
		u, err := users.GetByID(ctx, c.RequesterID)
		if err != nil || !u.Role.AtLeast(user.RoleSuper) {
			return nil, ErrForbidden
		}

		b, err := bookings.GetByID(ctx, c.BookingID)
		if err != nil {
			return nil, err
		}
		if b.Status != StatusActive {
			return nil, ErrAlreadyCancelled
		}

		now := time.Now().UTC()
		event, err := newBookingCancelledEvent(b, c.RequesterID, now)
		if err != nil {
			return nil, err
		}
		return []eventstore.Event{event}, nil
	}
}

// createsAsSuper reports whether the booking's creation should be treated as a
// super-user action. Unknown or unresolvable users are treated as basic users.
func createsAsSuper(ctx context.Context, users Directory, userID string) bool {
	if users == nil {
		return false
	}
	u, err := users.GetByID(ctx, userID)
	if err != nil {
		return false
	}
	return u.Role.AtLeast(user.RoleSuper)
}

// newBookingCancelledEvent builds the booking.cancelled event for a booking.
func newBookingCancelledEvent(b Booking, cancelledBy string, now time.Time) (eventstore.Event, error) {
	payload, err := json.Marshal(BookingCancelledPayload{
		BookingID:   b.ID,
		CancelledBy: cancelledBy,
		CancelledAt: now,
	})
	if err != nil {
		return eventstore.Event{}, fmt.Errorf("booking: marshal event: %w", err)
	}
	return eventstore.Event{
		AggregateType: AggregateType,
		AggregateID:   b.ID,
		EventType:     BookingCancelledEventType,
		Payload:       payload,
		OccurredAt:    now,
	}, nil
}
