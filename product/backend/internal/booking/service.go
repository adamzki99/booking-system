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

// userResolver resolves a user from the users read model.
type userResolver interface {
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
	users    userResolver
}

// NewService creates a booking service.
func NewService(commands commandExecutor, bookings bookingsReader, users userResolver) *BookingService {
	return &BookingService{commands: commands, bookings: bookings, users: users}
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

// CancelOwnBooking cancels the authenticated user's own booking.
func (s *BookingService) CancelOwnBooking(ctx context.Context, email, bookingID string) error {
	u, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		return ErrForbidden
	}
	return s.commands.Execute(ctx, CancelOwnBooking{
		BookingID: bookingID,
		UserID:    u.ID,
	})
}

// ListBookings returns active bookings in the optional [from, to) range.
func (s *BookingService) ListBookings(ctx context.Context, from, to *time.Time) ([]Booking, error) {
	return s.bookings.List(ctx, from, to)
}
