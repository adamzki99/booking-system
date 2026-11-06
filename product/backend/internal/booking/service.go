package booking

import (
	"context"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

// commandExecutor runs commands against the event store.
type commandExecutor interface {
	Execute(context.Context, command.Command) error
}

// Directory resolves users from the user directory read model.
type Directory interface {
	GetByID(ctx context.Context, id string) (user.User, error)
	GetByEmail(ctx context.Context, email string) (user.User, error)
}

// bookingsReader is the part of the bookings read model command handlers and
// the service need.
type bookingsReader interface {
	HasOverlap(ctx context.Context, start, end time.Time) (bool, error)
	GetByID(ctx context.Context, id string) (Booking, error)
	List(ctx context.Context, from, to *time.Time) ([]Booking, error)
}

// BookingService orchestrates booking commands, read-back, and the calendar.
type BookingService struct {
	commands commandExecutor
	bookings bookingsReader
	users    Directory
	blocked  blockedReader
}

// NewService creates a booking service.
func NewService(commands commandExecutor, bookings bookingsReader, users Directory, blocked blockedReader) *BookingService {
	return &BookingService{commands: commands, bookings: bookings, users: users, blocked: blocked}
}

// CreateBooking creates a booking for the authenticated user and returns it.
func (s *BookingService) CreateBooking(ctx context.Context, email string, start, end time.Time) (Booking, error) {
	u, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		return Booking{}, ErrForbidden
	}
	id := NewID()
	if err := s.commands.Execute(ctx, CreateBooking{
		ID:     id,
		UserID: u.ID,
		Start:  start,
		End:    end,
	}); err != nil {
		return Booking{}, err
	}
	return s.bookings.GetByID(ctx, id)
}

// CancelBooking cancels a booking. The owner may always cancel their own
// booking; super users may cancel any booking.
func (s *BookingService) CancelBooking(ctx context.Context, email, bookingID string) error {
	u, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		return ErrForbidden
	}
	b, err := s.bookings.GetByID(ctx, bookingID)
	if err != nil {
		return err
	}
	if b.UserID != u.ID {
		if !u.Role.AtLeast(user.RoleSuper) {
			return ErrNotOwner
		}
		return s.commands.Execute(ctx, CancelAnyBooking{
			BookingID:   b.ID,
			RequesterID: u.ID,
		})
	}
	return s.commands.Execute(ctx, CancelOwnBooking{
		BookingID: b.ID,
		UserID:    u.ID,
	})
}

// ListBookings returns active bookings in the optional [from, to) range.
func (s *BookingService) ListBookings(ctx context.Context, from, to *time.Time) ([]Booking, error) {
	return s.bookings.List(ctx, from, to)
}

// BlockTimePeriod blocks basic users from creating bookings that overlap the
// interval (super users only).
func (s *BookingService) BlockTimePeriod(ctx context.Context, email string, from, to time.Time) error {
	u, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		return ErrForbidden
	}
	if !u.Role.AtLeast(user.RoleSuper) {
		return ErrForbidden
	}
	return s.commands.Execute(ctx, BlockTimePeriod{
		From:        from,
		To:          to,
		RequesterID: u.ID,
	})
}

// ListBlockedPeriods returns the blocked periods in the read model.
func (s *BookingService) ListBlockedPeriods(ctx context.Context) ([]BlockedPeriod, error) {
	if s.blocked == nil {
		return nil, ErrBlockedPeriodsUnavailable
	}
	return s.blocked.List(ctx)
}
