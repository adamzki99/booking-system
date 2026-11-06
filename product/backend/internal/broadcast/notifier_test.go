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
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

type sentEmail struct {
	to, subject, body string
}

type fakeSender struct {
	mu     sync.Mutex
	emails []sentEmail
	err    error
}

func (f *fakeSender) Send(_ context.Context, to, subject, body string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.emails = append(f.emails, sentEmail{to: to, subject: subject, body: body})
	return f.err
}

func testNotifier(t *testing.T, users []user.User) (*Notifier, *fakeSender) {
	t.Helper()
	sender := &fakeSender{}
	n := NewNotifier(sender, fakeLister{users: users}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	return n, sender
}

type fakeLister struct {
	users []user.User
}

func (f fakeLister) List(_ context.Context) ([]user.User, error) { return f.users, nil }

func TestBroadcastNotifierEmailsAllBasicUsers(t *testing.T) {
	users := []user.User{
		{ID: "u1", Email: "alice@example.com", Role: user.RoleBasic, Active: true},
		{ID: "u2", Email: "bob@example.com", Role: user.RoleBasic, Active: true},
		// Not reached: super user, inactive user.
		{ID: "s1", Email: "super@example.com", Role: user.RoleSuper, Active: true},
		{ID: "u3", Email: "old@example.com", Role: user.RoleBasic, Active: false},
	}
	n, sender := testNotifier(t, users)

	event := broadcastEvent(t)
	if err := n.Handle(context.Background(), []eventstore.Event{event}); err != nil {
		t.Fatal(err)
	}
	if len(sender.emails) != 2 {
		t.Fatalf("sent %d emails: %+v", len(sender.emails), sender.emails)
	}
	var tos []string
	for _, m := range sender.emails {
		tos = append(tos, m.to)
	}
	if !contains(tos, "alice@example.com") || !contains(tos, "bob@example.com") ||
		contains(tos, "super@example.com") || contains(tos, "old@example.com") {
		t.Fatalf("recipients = %v", tos)
	}
	for _, m := range sender.emails {
		if m.subject != "Sauna closed" || m.body == "" {
			t.Fatalf("message = %+v", m)
		}
	}
}

func TestBroadcastNotifierIgnoresOtherEvents(t *testing.T) {
	users := []user.User{{ID: "u1", Email: "alice@example.com", Role: user.RoleBasic, Active: true}}
	n, sender := testNotifier(t, users)

	err := n.Handle(context.Background(), []eventstore.Event{
		{ID: 1, EventType: "booking.created"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(sender.emails) != 0 {
		t.Fatalf("unexpected emails: %+v", sender.emails)
	}
}

func TestBroadcastNotifierSwallowsSendError(t *testing.T) {
	sender := &fakeSender{err: errors.New("smtp down")}
	n := NewNotifier(sender, fakeLister{users: []user.User{
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
