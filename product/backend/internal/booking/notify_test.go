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

func TestNotifierSendsConfirmation(t *testing.T) {
	sender := &fakeSender{}
	users := &fakeUserResolver{byID: map[string]user.User{
		"user-1": {ID: "user-1", Email: "alice@example.com"},
	}}
	n := &Notifier{sender: sender, users: users, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{createdEvent(t, "user-1")}); err != nil {
		t.Fatal(err)
	}
	if sender.to != "alice@example.com" {
		t.Fatalf("to = %q", sender.to)
	}
	if sender.subject != createdSubject {
		t.Fatalf("subject = %q", sender.subject)
	}
	if sender.body == "" {
		t.Fatal("expected a confirmation body")
	}
}

func TestNotifierSendsCancellation(t *testing.T) {
	sender := &fakeSender{}
	users := &fakeUserResolver{byID: map[string]user.User{
		"user-1": {ID: "user-1", Email: "alice@example.com"},
	}}
	n := &Notifier{sender: sender, users: users, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{cancelledEvent(t, "user-1")}); err != nil {
		t.Fatal(err)
	}
	if sender.to != "alice@example.com" {
		t.Fatalf("to = %q", sender.to)
	}
	if sender.subject != cancelledSubject {
		t.Fatalf("subject = %q", sender.subject)
	}
}

func TestNotifierIgnoresOtherEvents(t *testing.T) {
	sender := &fakeSender{}
	users := &fakeUserResolver{}
	n := &Notifier{sender: sender, users: users, logger: testLogger()}

	err := n.Handle(context.Background(), []eventstore.Event{
		{ID: 1, EventType: "user.created"},
		{ID: 2, EventType: "auth.session_created"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if sender.to != "" {
		t.Fatalf("unexpected email to %q", sender.to)
	}
}

func TestNotifierSwallowsSendError(t *testing.T) {
	sender := &fakeSender{err: errors.New("smtp down")}
	users := &fakeUserResolver{byID: map[string]user.User{
		"user-1": {ID: "user-1", Email: "alice@example.com"},
	}}
	n := &Notifier{sender: sender, users: users, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{createdEvent(t, "user-1")}); err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
}

func TestNotifierSwallowsUserResolveError(t *testing.T) {
	sender := &fakeSender{}
	users := &fakeUserResolver{byIDErr: errors.New("db down")}
	n := &Notifier{sender: sender, users: users, logger: testLogger()}

	if err := n.Handle(context.Background(), []eventstore.Event{createdEvent(t, "user-1")}); err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if sender.to != "" {
		t.Fatalf("unexpected email to %q", sender.to)
	}
}
