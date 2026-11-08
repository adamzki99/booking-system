package booking

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

func TestHandleCreateBookingEmitsCreatedEvent(t *testing.T) {
	bookings := &fakeBookingsReader{byID: map[string]Booking{}}
	handler := handleCreateBooking(bookings, nil, nil, nil)

	start := time.Now().Add(24 * time.Hour)
	end := start.Add(time.Hour)
	events, err := handler(context.Background(), CreateBooking{
		ID:     "booking-1",
		UserID: "user-1",
		Start:  start,
		End:    end,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	event := events[0]
	if event.AggregateType != AggregateType {
		t.Fatalf("aggregate type = %q", event.AggregateType)
	}
	if event.AggregateID != "booking-1" {
		t.Fatalf("aggregate id = %q", event.AggregateID)
	}
	if event.EventType != BookingCreatedEventType {
		t.Fatalf("event type = %q", event.EventType)
	}
	var payload BookingCreatedPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		t.Fatal(err)
	}
	if payload.BookingID != "booking-1" || payload.UserID != "user-1" {
		t.Fatalf("payload = %+v", payload)
	}
	if !payload.Start.Equal(start) || !payload.End.Equal(end) {
		t.Fatalf("payload interval = %v..%v", payload.Start, payload.End)
	}
}

func TestHandleCreateBookingGeneratesID(t *testing.T) {
	bookings := &fakeBookingsReader{}
	handler := handleCreateBooking(bookings, nil, nil, nil)

	start := time.Now().Add(24 * time.Hour)
	events, err := handler(context.Background(), CreateBooking{
		UserID: "user-1",
		Start:  start,
		End:    start.Add(time.Hour),
	})
	if err != nil {
		t.Fatal(err)
	}
	if events[0].AggregateID == "" {
		t.Fatal("expected generated aggregate id")
	}
}

func TestHandleCreateBookingRejectsDoubleBooking(t *testing.T) {
	bookings := &fakeBookingsReader{overlap: true}
	handler := handleCreateBooking(bookings, nil, nil, nil)

	start := time.Now().Add(24 * time.Hour)
	_, err := handler(context.Background(), CreateBooking{
		UserID: "user-1",
		Start:  start,
		End:    start.Add(time.Hour),
	})
	if !errors.Is(err, ErrDoubleBooking) {
		t.Fatalf("expected ErrDoubleBooking, got %v", err)
	}
}

func TestHandleCreateBookingRejectsInvalidInterval(t *testing.T) {
	bookings := &fakeBookingsReader{}
	handler := handleCreateBooking(bookings, nil, nil, nil)

	start := time.Now().Add(24 * time.Hour)
	_, err := handler(context.Background(), CreateBooking{
		UserID: "user-1",
		Start:  start,
		End:    start.Add(-time.Hour),
	})
	if !errors.Is(err, ErrInvalidInterval) {
		t.Fatalf("expected ErrInvalidInterval, got %v", err)
	}
}

func TestHandleCreateBookingRequiresUser(t *testing.T) {
	bookings := &fakeBookingsReader{}
	handler := handleCreateBooking(bookings, nil, nil, nil)

	start := time.Now().Add(24 * time.Hour)
	_, err := handler(context.Background(), CreateBooking{
		Start: start,
		End:   start.Add(time.Hour),
	})
	if err == nil {
		t.Fatal("expected error for missing user id")
	}
}

func TestHandleCancelOwnBookingEmitsCancelledEvent(t *testing.T) {
	bookings := &fakeBookingsReader{byID: map[string]Booking{
		"booking-1": {ID: "booking-1", UserID: "user-1", Status: StatusActive},
	}}
	handler := handleCancelOwnBooking(bookings)

	events, err := handler(context.Background(), CancelOwnBooking{
		BookingID: "booking-1",
		UserID:    "user-1",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	event := events[0]
	if event.EventType != BookingCancelledEventType || event.AggregateID != "booking-1" {
		t.Fatalf("event = %+v", event)
	}
	var payload BookingCancelledPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		t.Fatal(err)
	}
	if payload.BookingID != "booking-1" || payload.CancelledBy != "user-1" {
		t.Fatalf("payload = %+v", payload)
	}
}

func TestHandleCancelOwnBookingRejectsNonOwner(t *testing.T) {
	bookings := &fakeBookingsReader{byID: map[string]Booking{
		"booking-1": {ID: "booking-1", UserID: "user-1", Status: StatusActive},
	}}
	handler := handleCancelOwnBooking(bookings)

	_, err := handler(context.Background(), CancelOwnBooking{
		BookingID: "booking-1",
		UserID:    "user-2",
	})
	if !errors.Is(err, ErrNotOwner) {
		t.Fatalf("expected ErrNotOwner, got %v", err)
	}
}

func TestHandleCancelOwnBookingRejectsAlreadyCancelled(t *testing.T) {
	bookings := &fakeBookingsReader{byID: map[string]Booking{
		"booking-1": {ID: "booking-1", UserID: "user-1", Status: StatusCancelled},
	}}
	handler := handleCancelOwnBooking(bookings)

	_, err := handler(context.Background(), CancelOwnBooking{
		BookingID: "booking-1",
		UserID:    "user-1",
	})
	if !errors.Is(err, ErrAlreadyCancelled) {
		t.Fatalf("expected ErrAlreadyCancelled, got %v", err)
	}
}

func TestHandleCancelAnyBookingEmitsCancelledEvent(t *testing.T) {
	bookings := &fakeBookingsReader{byID: map[string]Booking{
		"booking-1": {ID: "booking-1", UserID: "user-1", Status: StatusActive},
	}}
	users := &fakeUserResolver{byID: map[string]user.User{
		"super-1": {ID: "super-1", Email: "super@example.com", Role: user.RoleSuper},
	}}
	handler := handleCancelAnyBooking(bookings, users)

	events, err := handler(context.Background(), CancelAnyBooking{
		BookingID:   "booking-1",
		RequesterID: "super-1",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	event := events[0]
	if event.AggregateType != AggregateType || event.AggregateID != "booking-1" {
		t.Fatalf("event = %+v", event)
	}
	if event.EventType != BookingCancelledEventType {
		t.Fatalf("event type = %q", event.EventType)
	}
	var payload BookingCancelledPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		t.Fatal(err)
	}
	if payload.BookingID != "booking-1" || payload.CancelledBy != "super-1" {
		t.Fatalf("payload = %+v", payload)
	}
}

func TestHandleCancelAnyBookingRejectsNonSuper(t *testing.T) {
	bookings := &fakeBookingsReader{byID: map[string]Booking{
		"booking-1": {ID: "booking-1", UserID: "user-1", Status: StatusActive},
	}}
	handler := handleCancelAnyBooking(bookings, basicResolver())

	_, err := handler(context.Background(), CancelAnyBooking{
		BookingID:   "booking-1",
		RequesterID: "user-2",
	})
	if !errors.Is(err, ErrForbidden) {
		t.Fatalf("expected ErrForbidden, got %v", err)
	}
}

func TestHandleCancelAnyBookingRejectsUnknownRequester(t *testing.T) {
	bookings := &fakeBookingsReader{byID: map[string]Booking{
		"booking-1": {ID: "booking-1", UserID: "user-1", Status: StatusActive},
	}}
	handler := handleCancelAnyBooking(bookings, &fakeUserResolver{byID: map[string]user.User{}})

	_, err := handler(context.Background(), CancelAnyBooking{
		BookingID:   "booking-1",
		RequesterID: "user-2",
	})
	if !errors.Is(err, ErrForbidden) {
		t.Fatalf("expected ErrForbidden, got %v", err)
	}
}

func TestHandleCancelAnyBookingRejectsUnknownBooking(t *testing.T) {
	users := &fakeUserResolver{byID: map[string]user.User{
		"super-1": {ID: "super-1", Email: "super@example.com", Role: user.RoleSuper},
	}}
	handler := handleCancelAnyBooking(&fakeBookingsReader{byID: map[string]Booking{}}, users)

	_, err := handler(context.Background(), CancelAnyBooking{
		BookingID:   "missing",
		RequesterID: "super-1",
	})
	if !errors.Is(err, ErrBookingNotFound) {
		t.Fatalf("expected ErrBookingNotFound, got %v", err)
	}
}

func TestHandleCancelAnyBookingRejectsAlreadyCancelled(t *testing.T) {
	bookings := &fakeBookingsReader{byID: map[string]Booking{
		"booking-1": {ID: "booking-1", UserID: "user-1", Status: StatusCancelled},
	}}
	users := &fakeUserResolver{byID: map[string]user.User{
		"super-1": {ID: "super-1", Email: "super@example.com", Role: user.RoleSuper},
	}}
	handler := handleCancelAnyBooking(bookings, users)

	_, err := handler(context.Background(), CancelAnyBooking{
		BookingID:   "booking-1",
		RequesterID: "super-1",
	})
	if !errors.Is(err, ErrAlreadyCancelled) {
		t.Fatalf("expected ErrAlreadyCancelled, got %v", err)
	}
}

func TestHandleCancelOwnBookingRejectsUnknown(t *testing.T) {
	bookings := &fakeBookingsReader{byID: map[string]Booking{}}
	handler := handleCancelOwnBooking(bookings)

	_, err := handler(context.Background(), CancelOwnBooking{
		BookingID: "missing",
		UserID:    "user-1",
	})
	if !errors.Is(err, ErrBookingNotFound) {
		t.Fatalf("expected ErrBookingNotFound, got %v", err)
	}
}

func TestHandleCreateBookingRejectsRuleViolation(t *testing.T) {
	bookings := &fakeBookingsReader{}
	rules := &fakeRules{err: ErrBookingRuleViolation}
	handler := handleCreateBooking(bookings, nil, nil, rules)

	start := time.Now().Add(24 * time.Hour)
	_, err := handler(context.Background(), CreateBooking{
		UserID: "user-1",
		Start:  start,
		End:    start.Add(time.Hour),
	})
	if !errors.Is(err, ErrBookingRuleViolation) {
		t.Fatalf("expected ErrBookingRuleViolation, got %v", err)
	}
}
