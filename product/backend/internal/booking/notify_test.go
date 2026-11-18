package booking

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/notification"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func createdEvent(t *testing.T, userID string) eventstore.Event {
	t.Helper()
	payload, err := json.Marshal(BookingCreatedPayload{
		BookingID: "booking-1",
		UserID:    userID,
		Start:     time.Now(),
		End:       time.Now().Add(time.Hour),
		CreatedAt: time.Now(),
	})
	if err != nil {
		t.Fatal(err)
	}
	return eventstore.Event{ID: 1, EventType: BookingCreatedEventType, Payload: payload}
}

func cancelledEvent(t *testing.T, userID string) eventstore.Event {
	t.Helper()
	payload, err := json.Marshal(BookingCancelledPayload{
		BookingID:   "booking-1",
		CancelledBy: userID,
		CancelledAt: time.Now(),
	})
	if err != nil {
		t.Fatal(err)
	}
	return eventstore.Event{ID: 2, EventType: BookingCancelledEventType, Payload: payload}
}

func assertItem(t *testing.T, outbox *fakeEnqueuer, eventID int64, kind, recipient, subject string) {
	t.Helper()
	if len(outbox.items) != 1 {
		t.Fatalf("enqueued %d items, want 1: %+v", len(outbox.items), outbox.items)
	}
	item := outbox.items[0]
	if item.EventID != eventID || item.Kind != kind ||
		item.RecipientEmail != recipient || item.Subject != subject || item.Body == "" {
		t.Fatalf("item = %+v", item)
	}
}

func TestNotifierEnqueuesConfirmation(t *testing.T) {
	outbox := &fakeEnqueuer{}
	users := &fakeUserResolver{byID: map[string]user.User{
		"user-1": {ID: "user-1", Email: "alice@example.com"},
	}}
	n := &Notifier{outbox: outbox, users: users, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{createdEvent(t, "user-1")}); err != nil {
		t.Fatal(err)
	}
	assertItem(t, outbox, 1, notification.KindBookingCreated, "alice@example.com", createdSubject)
}

func TestNotifierEnqueuesCancellation(t *testing.T) {
	outbox := &fakeEnqueuer{}
	users := &fakeUserResolver{byID: map[string]user.User{
		"user-1": {ID: "user-1", Email: "alice@example.com"},
	}}
	n := &Notifier{outbox: outbox, users: users, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{cancelledEvent(t, "user-1")}); err != nil {
		t.Fatal(err)
	}
	assertItem(t, outbox, 2, notification.KindBookingCancelled, "alice@example.com", cancelledSubject)
}

func TestNotifierEnqueuesCancellationToBookingOwner(t *testing.T) {
	outbox := &fakeEnqueuer{}
	// user-1 is the super user cancelling; user-2 owns the booking.
	users := &fakeUserResolver{byID: map[string]user.User{
		"user-1": {ID: "user-1", Email: "super@example.com"},
		"user-2": {ID: "user-2", Email: "owner@example.com"},
	}}
	bookings := &fakeBookingsReader{byID: map[string]Booking{
		"booking-1": {ID: "booking-1", UserID: "user-2", Status: StatusCancelled},
	}}
	n := &Notifier{outbox: outbox, users: users, bookings: bookings, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{cancelledEvent(t, "user-1")}); err != nil {
		t.Fatal(err)
	}
	assertItem(t, outbox, 2, notification.KindBookingCancelled, "owner@example.com", cancelledSubject)
}

func TestNotifierIgnoresOtherEvents(t *testing.T) {
	outbox := &fakeEnqueuer{}
	n := &Notifier{outbox: outbox, users: &fakeUserResolver{}, logger: testLogger()}

	err := n.Handle(context.Background(), []eventstore.Event{
		{ID: 1, EventType: "user.created"},
		{ID: 2, EventType: "auth.session_created"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(outbox.items) != 0 {
		t.Fatalf("unexpected items: %+v", outbox.items)
	}
}

func TestNotifierToleratesEnqueueError(t *testing.T) {
	outbox := &fakeEnqueuer{err: errors.New("outbox down")}
	users := &fakeUserResolver{byID: map[string]user.User{
		"user-1": {ID: "user-1", Email: "alice@example.com"},
	}}
	n := &Notifier{outbox: outbox, users: users, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{createdEvent(t, "user-1")}); err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
}

func TestNotifierIgnoresUserResolveError(t *testing.T) {
	outbox := &fakeEnqueuer{}
	users := &fakeUserResolver{byIDErr: errors.New("db down")}
	n := &Notifier{outbox: outbox, users: users, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{createdEvent(t, "user-1")}); err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if len(outbox.items) != 0 {
		t.Fatalf("unexpected items: %+v", outbox.items)
	}
}
