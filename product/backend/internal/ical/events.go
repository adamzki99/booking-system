package ical

import "time"

const (
	// AggregateType is the calendar-token event aggregate type.
	AggregateType = "calendar"

	// CalendarTokenGeneratedEventType records a (re)generated calendar token.
	CalendarTokenGeneratedEventType = "calendar.token_generated"

	// Alias.
	TokenGeneratedEventType = CalendarTokenGeneratedEventType
)

// CalendarTokenGeneratedPayload is the payload for calendar.token_generated events.
type CalendarTokenGeneratedPayload struct {
	UserID      string    `json:"user_id"`
	TokenHash   string    `json:"token_hash"`
	GeneratedAt time.Time `json:"generated_at"`
}

// Alias.
type TokenGeneratedPayload = CalendarTokenGeneratedPayload