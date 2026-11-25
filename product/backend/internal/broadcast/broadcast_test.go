package broadcast_test

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/broadcast"
	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

type fakeExecutor struct {
	err  error
	last command.Command
}

func (f *fakeExecutor) Execute(_ context.Context, cmd command.Command) error {
	f.last = cmd
	return f.err
}

type fakeDirectory struct {
	byID    map[string]user.User
	byEmail map[string]user.User
}

func (f *fakeDirectory) GetByID(_ context.Context, id string) (user.User, error) {
	u, ok := f.byID[id]
	if !ok {
		return user.User{}, user.ErrUserNotFound
	}
	return u, nil
}

func (f *fakeDirectory) GetByEmail(_ context.Context, email string) (user.User, error) {
	u, ok := f.byEmail[email]
	if !ok {
		return user.User{}, user.ErrUserNotFound
	}
	return u, nil
}

func testDirectory() *fakeDirectory {
	return &fakeDirectory{
		byID: map[string]user.User{
			"super-1": {ID: "super-1", Email: "super@example.com", Role: user.RoleSuper},
			"user-1":  {ID: "user-1", Email: "alice@example.com", Role: user.RoleBasic},
		},
		byEmail: map[string]user.User{
			"super@example.com": {ID: "super-1", Email: "super@example.com", Role: user.RoleSuper},
			"alice@example.com": {ID: "user-1", Email: "alice@example.com", Role: user.RoleBasic},
		},
	}
}

func TestHandleBroadcastMessageEmitsEvent(t *testing.T) {
	handler := broadcast.HandleBroadcastMessage(testDirectory())

	events, err := handler(context.Background(), broadcast.BroadcastMessage{
		Subject:     "Sauna closed",
		Body:        "The sauna is closed for maintenance all of next week.",
		RequesterID: "super-1",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	event := events[0]
	if event.AggregateType != broadcast.AggregateType {
		t.Fatalf("aggregate type = %q", event.AggregateType)
	}
	if event.AggregateID == "" {
		t.Fatal("expected generated broadcast id")
	}
	if event.EventType != broadcast.MessageBroadcastEventType {
		t.Fatalf("event type = %q", event.EventType)
	}
	var payload broadcast.MessageBroadcastPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		t.Fatal(err)
	}
	if payload.Subject != "Sauna closed" || payload.ByUserID != "super-1" {
		t.Fatalf("payload = %+v", payload)
	}
}

func TestHandleBroadcastMessageRejectsNonSuper(t *testing.T) {
	handler := broadcast.HandleBroadcastMessage(testDirectory())

	_, err := handler(context.Background(), broadcast.BroadcastMessage{
		Subject:     "Sauna closed",
		Body:        "The sauna is closed.",
		RequesterID: "user-1",
	})
	if !errors.Is(err, broadcast.ErrForbidden) {
		t.Fatalf("expected ErrForbidden, got %v", err)
	}
}

func TestHandleBroadcastMessageRejectsUnknownRequester(t *testing.T) {
	handler := broadcast.HandleBroadcastMessage(testDirectory())

	_, err := handler(context.Background(), broadcast.BroadcastMessage{
		Subject:     "Sauna closed",
		Body:        "The sauna is closed.",
		RequesterID: "missing",
	})
	if !errors.Is(err, broadcast.ErrForbidden) {
		t.Fatalf("expected ErrForbidden, got %v", err)
	}
}

func TestHandleBroadcastMessageRejectsEmptySubject(t *testing.T) {
	handler := broadcast.HandleBroadcastMessage(testDirectory())

	_, err := handler(context.Background(), broadcast.BroadcastMessage{
		Subject:     "   ",
		Body:        "The sauna is closed.",
		RequesterID: "super-1",
	})
	if !errors.Is(err, broadcast.ErrInvalidSubject) {
		t.Fatalf("expected ErrInvalidSubject, got %v", err)
	}
}

func TestHandleBroadcastMessageRejectsEmptyBody(t *testing.T) {
	handler := broadcast.HandleBroadcastMessage(testDirectory())

	_, err := handler(context.Background(), broadcast.BroadcastMessage{
		Subject:     "Sauna closed",
		Body:        "",
		RequesterID: "super-1",
	})
	if !errors.Is(err, broadcast.ErrInvalidBody) {
		t.Fatalf("expected ErrInvalidBody, got %v", err)
	}
}

// checkEventPayloadTypes ensures payloads round-trip.
func TestMessageBroadcastPayloadRoundTrip(t *testing.T) {
	now := time.Now().UTC()
	payload := broadcast.MessageBroadcastPayload{
		BroadcastID: "b1",
		Subject:     "s",
		Body:        "b",
		ByUserID:    "super-1",
		BroadcastAt: now,
	}
	data, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	var back broadcast.MessageBroadcastPayload
	if err := json.Unmarshal(data, &back); err != nil {
		t.Fatal(err)
	}
	if back.BroadcastID != payload.BroadcastID || back.Subject != payload.Subject || back.Body != payload.Body {
		t.Fatalf("round trip mismatch: %+v", back)
	}
}

var _ eventstore.Event // import guard removed if unused
