package broadcast

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

type fakeEnqueuer struct {
	items []notification.Item
	err   error
}

func (f *fakeEnqueuer) Enqueue(_ context.Context, item notification.Item) error {
	if f.err != nil {
		return f.err
	}
	f.items = append(f.items, item)
	return nil
}

func testNotifier(t *testing.T, users []user.User) (*Notifier, *fakeEnqueuer) {
	t.Helper()
	outbox := &fakeEnqueuer{}
	n := NewNotifier(outbox, fakeLister{users: users}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	return n, outbox
}

type fakeLister struct {
	users []user.User
}

func (f fakeLister) List(_ context.Context) ([]user.User, error) { return f.users, nil }

func TestBroadcastNotifierEnqueuesAllBasicUsers(t *testing.T) {
	users := []user.User{
		{ID: "u1", Email: "alice@example.com", Role: user.RoleBasic, Active: true},
		{ID: "u2", Email: "bob@example.com", Role: user.RoleBasic, Active: true},
		// Not reached: super user, inactive user, blank email.
		{ID: "s1", Email: "super@example.com", Role: user.RoleSuper, Active: true},
		{ID: "u3", Email: "old@example.com", Role: user.RoleBasic, Active: false},
		{ID: "u4", Email: "   ", Role: user.RoleBasic, Active: true},
	}
	n, outbox := testNotifier(t, users)

	event := broadcastEvent(t)
	if err := n.Handle(context.Background(), []eventstore.Event{event}); err != nil {
		t.Fatal(err)
	}
	if len(outbox.items) != 2 {
		t.Fatalf("enqueued %d items: %+v", len(outbox.items), outbox.items)
	}
	var recipients []string
	for _, item := range outbox.items {
		recipients = append(recipients, item.RecipientEmail)
		if item.Kind != notification.KindBroadcast || item.EventID != event.ID ||
			item.Subject != "Sauna closed" || item.Body == "" {
			t.Fatalf("item = %+v", item)
		}
	}
	if !contains(recipients, "alice@example.com") || !contains(recipients, "bob@example.com") ||
		contains(recipients, "super@example.com") || contains(recipients, "old@example.com") {
		t.Fatalf("recipients = %v", recipients)
	}
}

func TestBroadcastNotifierIgnoresOtherEvents(t *testing.T) {
	n, outbox := testNotifier(t, []user.User{
		{ID: "u1", Email: "alice@example.com", Role: user.RoleBasic, Active: true},
	})

	err := n.Handle(context.Background(), []eventstore.Event{
		{ID: 1, EventType: "booking.created"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(outbox.items) != 0 {
		t.Fatalf("unexpected items: %+v", outbox.items)
	}
}

func TestBroadcastNotifierToleratesEnqueueError(t *testing.T) {
	outbox := &fakeEnqueuer{err: errors.New("outbox down")}
	n := NewNotifier(outbox, fakeLister{users: []user.User{
		{ID: "u1", Email: "alice@example.com", Role: user.RoleBasic, Active: true},
	}}, testLogger())

	err := n.Handle(context.Background(), []eventstore.Event{broadcastEvent(t)})
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
}

func contains(list []string, needle string) bool {
	for _, s := range list {
		if s == needle {
			return true
		}
	}
	return false
}

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func broadcastEvent(t *testing.T) eventstore.Event {
	t.Helper()
	payload, err := json.Marshal(MessageBroadcastPayload{
		BroadcastID: "broadcast-1",
		Subject:     "Sauna closed",
		Body:        "The sauna is closed for maintenance.",
		ByUserID:    "super-1",
		BroadcastAt: time.Now(),
	})
	if err != nil {
		t.Fatal(err)
	}
	return eventstore.Event{ID: 1, EventType: MessageBroadcastEventType, Payload: payload}
}
