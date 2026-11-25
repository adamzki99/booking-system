package broadcast

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

func testNotifier(t *testing.T, users []user.User) (*Notifier, *fakeEnqueuer) {
	t.Helper()
	enqueuer := &fakeEnqueuer{}
	n := NewNotifier(enqueuer, fakeLister{users: users}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	return n, enqueuer
}

type fakeLister struct {
	users []user.User
}

func (f fakeLister) List(_ context.Context) ([]user.User, error) { return f.users, nil }

func TestBroadcastNotifierEnqueuesOneItemPerBasicUser(t *testing.T) {
	users := []user.User{
		{ID: "u1", Email: "alice@example.com", Role: user.RoleBasic, Active: true},
		{ID: "u2", Email: "bob@example.com", Role: user.RoleBasic, Active: true},
		// Not reached: super user, inactive user, blank email.
		{ID: "s1", Email: "super@example.com", Role: user.RoleSuper, Active: true},
		{ID: "u3", Email: "old@example.com", Role: user.RoleBasic, Active: false},
		{ID: "u4", Email: "   ", Role: user.RoleBasic, Active: true},
	}
	n, enqueuer := testNotifier(t, users)

	event := broadcastEvent(t)
	if err := n.Handle(context.Background(), []eventstore.Event{event}); err != nil {
		t.Fatal(err)
	}
	items := enqueuer.all()
	if len(items) != 2 {
		t.Fatalf("enqueued %d items: %+v", len(items), items)
	}
	var tos []string
	for _, item := range items {
		tos = append(tos, item.RecipientEmail)
		if item.EventID != event.ID || item.Kind != notification.KindBroadcast ||
			item.Subject != "Sauna closed" || item.Body == "" {
			t.Fatalf("item = %+v", item)
		}
	}
	if !contains(tos, "alice@example.com") || !contains(tos, "bob@example.com") ||
		contains(tos, "super@example.com") || contains(tos, "old@example.com") {
		t.Fatalf("recipients = %v", tos)
	}
}

func TestBroadcastNotifierIgnoresOtherEvents(t *testing.T) {
	users := []user.User{{ID: "u1", Email: "alice@example.com", Role: user.RoleBasic, Active: true}}
	n, enqueuer := testNotifier(t, users)

	err := n.Handle(context.Background(), []eventstore.Event{
		{ID: 1, EventType: "booking.created"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := enqueuer.all(); len(got) != 0 {
		t.Fatalf("unexpected items: %+v", got)
	}
}

func TestBroadcastNotifierSwallowsEnqueueError(t *testing.T) {
	enqueuer := &fakeEnqueuer{err: errors.New("outbox down")}
	n := NewNotifier(enqueuer, fakeLister{users: []user.User{
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
