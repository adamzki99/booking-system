package booking

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/notification"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

type fakeEnqueuer struct {
	mu    sync.Mutex
	items []notification.Item
	err   error
}

func (f *fakeEnqueuer) Enqueue(_ context.Context, item notification.Item) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.items = append(f.items, item)
	return f.err
}

func (f *fakeEnqueuer) all() []notification.Item {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := make([]notification.Item, len(f.items))
	copy(out, f.items)
	return out
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

func TestNotifierEnqueuesConfirmation(t *testing.T) {
	enqueuer := &fakeEnqueuer{}
	users := &fakeUserResolver{byID: map[string]user.User{
		"user-1": {ID: "user-1", Email: "alice@example.com"},
	}}
	n := &Notifier{enqueuer: enqueuer, users: users, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{createdEvent(t, "user-1")}); err != nil {
		t.Fatal(err)
	}
	items := enqueuer.all()
	if len(items) != 1 {
		t.Fatalf("enqueued %d items, want 1", len(items))
	}
	item := items[0]
	if item.EventID != 1 || item.Kind != notification.KindBookingCreated {
		t.Fatalf("item = %+v", item)
	}
	if item.RecipientEmail != "alice@example.com" || item.Subject != createdSubject || item.Body == "" {
		t.Fatalf("item = %+v", item)
	}
}

func TestNotifierEnqueuesCancellation(t *testing.T) {
	enqueuer := &fakeEnqueuer{}
	users := &fakeUserResolver{byID: map[string]user.User{
		"user-1": {ID: "user-1", Email: "alice@example.com"},
	}}
	n := &Notifier{enqueuer: enqueuer, users: users, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{cancelledEvent(t, "user-1")}); err != nil {
		t.Fatal(err)
	}
	items := enqueuer.all()
	if len(items) != 1 {
		t.Fatalf("enqueued %d items, want 1", len(items))
	}
	item := items[0]
	if item.EventID != 2 || item.Kind != notification.KindBookingCancelled ||
		item.RecipientEmail != "alice@example.com" || item.Subject != cancelledSubject {
		t.Fatalf("item = %+v", item)
	}
}

func TestNotifierEnqueuesCancellationToBookingOwner(t *testing.T) {
	enqueuer := &fakeEnqueuer{}
	// user-1 is the super user cancelling; user-2 owns the booking.
	users := &fakeUserResolver{byID: map[string]user.User{
		"user-1": {ID: "user-1", Email: "super@example.com"},
		"user-2": {ID: "user-2", Email: "owner@example.com"},
	}}
	bookings := &fakeBookingsReader{byID: map[string]Booking{
		"booking-1": {ID: "booking-1", UserID: "user-2", Status: StatusCancelled},
	}}
	n := &Notifier{enqueuer: enqueuer, users: users, bookings: bookings, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{cancelledEvent(t, "user-1")}); err != nil {
		t.Fatal(err)
	}
	items := enqueuer.all()
	if len(items) != 1 || items[0].RecipientEmail != "owner@example.com" {
		t.Fatalf("items = %+v", items)
	}
	if items[0].Kind != notification.KindBookingCancelled {
		t.Fatalf("kind = %q", items[0].Kind)
	}
}

func TestNotifierIgnoresOtherEvents(t *testing.T) {
	enqueuer := &fakeEnqueuer{}
	users := &fakeUserResolver{}
	n := &Notifier{enqueuer: enqueuer, users: users, logger: testLogger()}

	err := n.Handle(context.Background(), []eventstore.Event{
		{ID: 1, EventType: "user.created"},
		{ID: 2, EventType: "auth.session_created"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := enqueuer.all(); len(got) != 0 {
		t.Fatalf("unexpected items: %+v", got)
	}
}

func TestNotifierSwallowsEnqueueError(t *testing.T) {
	enqueuer := &fakeEnqueuer{err: errors.New("outbox down")}
	users := &fakeUserResolver{byID: map[string]user.User{
		"user-1": {ID: "user-1", Email: "alice@example.com"},
	}}
	n := &Notifier{enqueuer: enqueuer, users: users, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{createdEvent(t, "user-1")}); err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
}

func TestNotifierSwallowsUserResolveError(t *testing.T) {
	enqueuer := &fakeEnqueuer{}
	users := &fakeUserResolver{byIDErr: errors.New("db down")}
	n := &Notifier{enqueuer: enqueuer, users: users, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{createdEvent(t, "user-1")}); err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if got := enqueuer.all(); len(got) != 0 {
		t.Fatalf("unexpected items: %+v", got)
	}
}
