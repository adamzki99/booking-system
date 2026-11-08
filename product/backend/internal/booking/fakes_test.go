package booking

import (
	"context"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

// fakeBookingsReader is an in-memory bookings read model for tests.
type fakeBookingsReader struct {
	overlap     bool
	overlapErr  error
	byID        map[string]Booking
	byIDErr     error
	getByIDFunc func(id string) (Booking, error)
	list        []Booking
	listErr     error
}

func (f *fakeBookingsReader) HasOverlap(_ context.Context, _, _ time.Time) (bool, error) {
	return f.overlap, f.overlapErr
}

func (f *fakeBookingsReader) GetByID(_ context.Context, id string) (Booking, error) {
	if f.getByIDFunc != nil {
		return f.getByIDFunc(id)
	}
	if f.byIDErr != nil {
		return Booking{}, f.byIDErr
	}
	b, ok := f.byID[id]
	if !ok {
		return Booking{}, ErrBookingNotFound
	}
	return b, nil
}

func (f *fakeBookingsReader) List(_ context.Context, _, _ *time.Time) ([]Booking, error) {
	return f.list, f.listErr
}

// fakeUserResolver is an in-memory user resolver for tests.
type fakeUserResolver struct {
	byID       map[string]user.User
	byIDErr    error
	byEmail    map[string]user.User
	byEmailErr error
}

func (f *fakeUserResolver) GetByID(_ context.Context, id string) (user.User, error) {
	if f.byIDErr != nil {
		return user.User{}, f.byIDErr
	}
	u, ok := f.byID[id]
	if !ok {
		return user.User{}, user.ErrUserNotFound
	}
	return u, nil
}

func (f *fakeUserResolver) GetByEmail(_ context.Context, email string) (user.User, error) {
	if f.byEmailErr != nil {
		return user.User{}, f.byEmailErr
	}
	u, ok := f.byEmail[email]
	if !ok {
		return user.User{}, user.ErrUserNotFound
	}
	return u, nil
}

// basicResolver returns a resolver with basic users user-1 and user-2.
func basicResolver() *fakeUserResolver {
	return &fakeUserResolver{byID: map[string]user.User{
		"user-1": {ID: "user-1", Email: "user-1@example.com", Role: user.RoleBasic},
		"user-2": {ID: "user-2", Email: "user-2@example.com", Role: user.RoleBasic},
	}}
}

// superByEmail returns a resolver with a super user at super@example.com.
func superByEmail() *fakeUserResolver {
	return &fakeUserResolver{byEmail: map[string]user.User{
		"super@example.com": {ID: "super-1", Email: "super@example.com", Role: user.RoleSuper},
	}}
}

// basicByEmail returns a resolver with a basic user at basic@example.com.
func basicByEmail() *fakeUserResolver {
	return &fakeUserResolver{byEmail: map[string]user.User{
		"basic@example.com": {ID: "user-2", Email: "basic@example.com", Role: user.RoleBasic},
	}}
}

// fakeSender records the most recent email.
type fakeSender struct {
	to, subject, body string
	err               error
}

func (f *fakeSender) Send(_ context.Context, to, subject, body string) error {
	f.to, f.subject, f.body = to, subject, body
	return f.err
}

// fakeExecutor records the last executed command.
type fakeExecutor struct {
	last command.Command
	err  error
}

func (f *fakeExecutor) Execute(_ context.Context, cmd command.Command) error {
	f.last = cmd
	return f.err
}

// fakeRules is an in-memory BookingRules for tests.
type fakeRules struct {
	err error
}

func (f *fakeRules) ValidateBooking(_ context.Context, _, _ time.Time) error {
	return f.err
}

// fakeValidator is an in-memory BookingValidator for tests.
type fakeValidator struct {
	err error
	got []Booking
}

func (f *fakeValidator) ValidateBooking(_ context.Context, candidate Booking, existing []Booking) error {
	f.got = existing
	return f.err
}
