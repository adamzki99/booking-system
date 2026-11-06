// Package booking implements the booking domain: creating and cancelling a
// booking, the booking calendar read model, and the authenticated HTTP
// endpoints that expose them.
package booking

import (
	"crypto/rand"
	"errors"
	"fmt"
	"time"
)

// Status is a booking's lifecycle state.
type Status string

const (
	// StatusActive is a booking that has not been cancelled.
	StatusActive Status = "active"
	// StatusCancelled is a booking that has been cancelled.
	StatusCancelled Status = "cancelled"
)

// Booking is a row in the bookings read model.
type Booking struct {
	ID          string     `json:"id"`
	UserID      string     `json:"userId"`
	Start       time.Time  `json:"start"`
	End         time.Time  `json:"end"`
	Status      Status     `json:"status"`
	CancelledBy *string    `json:"cancelledBy,omitempty"`
	CreatedAt   time.Time  `json:"createdAt"`
	CancelledAt *time.Time `json:"cancelledAt,omitempty"`
}

// Error sentinels.
var (
	// ErrInvalidInterval indicates start is not strictly before end.
	ErrInvalidInterval = errors.New("booking: invalid interval")
	// ErrStartInPast indicates start is not in the future.
	ErrStartInPast = errors.New("booking: start must be in the future")
	// ErrDoubleBooking indicates an active booking already overlaps the slot.
	ErrDoubleBooking = errors.New("booking: slot already booked")
	// ErrBookingNotFound indicates no booking exists with the given id.
	ErrBookingNotFound = errors.New("booking: booking not found")
	// ErrNotOwner indicates the caller does not own the booking.
	ErrNotOwner = errors.New("booking: not the owner")
	// ErrAlreadyCancelled indicates the booking is already cancelled.
	ErrAlreadyCancelled = errors.New("booking: already cancelled")
	// ErrBlockedPeriod indicates the slot overlaps a blocked period.
	ErrBlockedPeriod = errors.New("booking: slot overlaps a blocked period")
	// ErrBlockedPeriodsUnavailable indicates the blocked-periods read model is
	// not wired up.
	ErrBlockedPeriodsUnavailable = errors.New("booking: blocked periods unavailable")
	// ErrForbidden indicates the caller is not allowed to act.
	ErrForbidden = errors.New("booking: forbidden")
)

// ValidateInterval reports whether the interval is well-formed: start strictly
// before end and start strictly after now.
func ValidateInterval(start, end, now time.Time) error {
	if !start.Before(end) {
		return ErrInvalidInterval
	}
	if !start.After(now) {
		return ErrStartInPast
	}
	return nil
}

// NewID generates a new UUID string for a booking.
func NewID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("booking-%d", time.Now().UnixNano())
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
