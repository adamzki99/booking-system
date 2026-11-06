package booking

import "time"

const (
	// AggregateType is the booking event aggregate type.
	AggregateType = "booking"

	// BookingCreatedEventType records a created booking.
	BookingCreatedEventType = "booking.created"
	// BookingCancelledEventType records a cancelled booking.
	BookingCancelledEventType = "booking.cancelled"
)

// BookingCreatedPayload is the payload for booking.created events.
type BookingCreatedPayload struct {
	BookingID string    `json:"booking_id"`
	UserID    string    `json:"user_id"`
	Start     time.Time `json:"start"`
	End       time.Time `json:"end"`
	CreatedAt time.Time `json:"created_at"`
}

// BookingCancelledPayload is the payload for booking.cancelled events.
type BookingCancelledPayload struct {
	BookingID   string    `json:"booking_id"`
	CancelledBy string    `json:"cancelled_by"`
	CancelledAt time.Time `json:"cancelled_at"`
}
