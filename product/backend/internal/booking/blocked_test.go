package booking

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

func superResolver() *fakeUserResolver {
	return &fakeUserResolver{byID: map[string]user.User{
		"super-1": {ID: "super-1", Email: "super@example.com", Role: user.RoleSuper},
	}}
}

func TestHandleBlockTimePeriodEmitsBlockedEvent(t *testing.T) {
	handler := handleBlockTimePeriod(superResolver())

	from := time.Now().Add(24 * time.Hour)
	to := from.Add(2 * time.Hour)
	events, err := handler(context.Background(), BlockTimePeriod{
		From:        from,
		To:          to,
		RequesterID: "super-1",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	event := events[0]
	if event.AggregateType != BlockedPeriodAggregateType {
		t.Fatalf("aggregate type = %q", event.AggregateType)
	}
	if event.AggregateID == "" {
		t.Fatal("expected generated period id")
	}
	if event.EventType != BlockedPeriodBlockedEventType {
		t.Fatalf("event type = %q", event.EventType)
	}
	var payload BlockedPeriodBlockedPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		t.Fatal(err)
	}
	if payload.PeriodID != event.AggregateID || payload.ByUserID != "super-1" {
		t.Fatalf("payload = %+v", payload)
	}
	if !payload.From.Equal(from) || !payload.To.Equal(to) {
		t.Fatalf("payload interval = %v..%v", payload.From, payload.To)
	}
}

func TestHandleBlockTimePeriodRejectsNonSuper(t *testing.T) {
	handler := handleBlockTimePeriod(basicResolver())

	from := time.Now().Add(24 * time.Hour)
	_, err := handler(context.Background(), BlockTimePeriod{
		From:        from,
		To:          from.Add(time.Hour),
		RequesterID: "user-1",
	})
	if !errors.Is(err, ErrForbidden) {
		t.Fatalf("expected ErrForbidden, got %v", err)
	}
}

func TestHandleBlockTimePeriodRejectsInvalidInterval(t *testing.T) {
	handler := handleBlockTimePeriod(superResolver())

	from := time.Now().Add(24 * time.Hour)
	_, err := handler(context.Background(), BlockTimePeriod{
		From:        from,
		To:          from.Add(-time.Hour),
		RequesterID: "super-1",
	})
	if !errors.Is(err, ErrInvalidInterval) {
		t.Fatalf("expected ErrInvalidInterval, got %v", err)
	}
}

type fakeBlockedReader struct {
	overlap bool
	err     error
	list    []BlockedPeriod
}

func (f *fakeBlockedReader) HasOverlap(_ context.Context, _, _ time.Time) (bool, error) {
	return f.overlap, f.err
}

func (f *fakeBlockedReader) List(_ context.Context) ([]BlockedPeriod, error) {
	return f.list, nil
}

func TestHandleCreateBookingRejectsBlockedPeriodForBasicUser(t *testing.T) {
	bookings := &fakeBookingsReader{byID: map[string]Booking{}}
	blocked := &fakeBlockedReader{overlap: true}
	handler := handleCreateBooking(bookings, blocked, basicResolver())

	start := time.Now().Add(24 * time.Hour)
	_, err := handler(context.Background(), CreateBooking{
		ID:     "booking-1",
		UserID: "user-1",
		Start:  start,
		End:    start.Add(time.Hour),
	})
	if !errors.Is(err, ErrBlockedPeriod) {
		t.Fatalf("expected ErrBlockedPeriod, got %v", err)
	}
}

func TestHandleCreateBookingAllowsSuperOverBlockedPeriod(t *testing.T) {
	bookings := &fakeBookingsReader{byID: map[string]Booking{}}
	blocked := &fakeBlockedReader{overlap: true}
	users := &fakeUserResolver{byID: map[string]user.User{
		"super-1": {ID: "super-1", Email: "super@example.com", Role: user.RoleSuper},
	}}
	handler := handleCreateBooking(bookings, blocked, users)

	start := time.Now().Add(24 * time.Hour)
	events, err := handler(context.Background(), CreateBooking{
		ID:     "booking-1",
		UserID: "super-1",
		Start:  start,
		End:    start.Add(time.Hour),
	})
	if err != nil {
		t.Fatalf("expected super booking to be accepted, got %v", err)
	}
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
}

func TestHandleCreateBookingAllowsBasicOutsideBlockedPeriod(t *testing.T) {
	bookings := &fakeBookingsReader{byID: map[string]Booking{}}
	blocked := &fakeBlockedReader{overlap: false}
	handler := handleCreateBooking(bookings, blocked, basicResolver())

	start := time.Now().Add(24 * time.Hour)
	events, err := handler(context.Background(), CreateBooking{
		ID:     "booking-1",
		UserID: "user-1",
		Start:  start,
		End:    start.Add(time.Hour),
	})
	if err != nil {
		t.Fatalf("expected booking outside blocked period, got %v", err)
	}
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
}
