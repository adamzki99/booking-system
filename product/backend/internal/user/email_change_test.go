package user_test

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

const emailChangeSubject = "Confirm your new email"

// fakeSender captures verification emails.
type fakeSender struct {
	mu       sync.Mutex
	messages []sentMessage
}

type sentMessage struct {
	To      string
	Subject string
	Body    string
}

func (s *fakeSender) Send(_ context.Context, to, subject, body string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.messages = append(s.messages, sentMessage{To: to, Subject: subject, Body: body})
	return nil
}

func (s *fakeSender) all() []sentMessage {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]sentMessage, len(s.messages))
	copy(out, s.messages)
	return out
}

func (s *fakeSender) reset() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.messages = nil
}

func (s *fakeSender) lastSubject(subject string) (sentMessage, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := len(s.messages) - 1; i >= 0; i-- {
		if s.messages[i].Subject == subject {
			return s.messages[i], true
		}
	}
	return sentMessage{}, false
}

func newEmailChangeService(ta *userTestApp, sender *fakeSender) *user.UserService {
	return user.NewService(ta.app.Commands, ta.users, ta.changes, sender, nil)
}

// requestChange drives the request step through the service and returns the
// plaintext verification code from the captured email.
func requestChange(t *testing.T, svc *user.UserService, sender *fakeSender, ctx context.Context, userID, newEmail, requesterEmail string) string {
	t.Helper()
	if _, err := svc.RequestEmailChange(ctx, userID, newEmail, requesterEmail, "1.2.3.4"); err != nil {
		t.Fatalf("RequestEmailChange: %v", err)
	}
	msg, ok := sender.lastSubject(emailChangeSubject)
	if !ok {
		t.Fatal("no verification email captured")
	}
	code := strings.TrimSpace(msg.Body)
	if code == "" {
		t.Fatal("verification email has empty code")
	}
	return code
}

func TestRequestEmailChangeLeavesAccountUnchangedAndMailsCode(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)
	sender := &fakeSender{}
	svc := newEmailChangeService(ta, sender)

	pending, err := svc.RequestEmailChange(ctx, basicID, "New@Example.com", basicEmail, "1.2.3.4")
	if err != nil {
		t.Fatal(err)
	}
	if pending.NewEmail != "new@example.com" {
		t.Fatalf("pending email = %q, want normalized new@example.com", pending.NewEmail)
	}
	if !pending.ExpiresAt.After(time.Now().UTC()) {
		t.Fatalf("expiresAt = %v, want in the future", pending.ExpiresAt)
	}

	// The login address is unchanged.
	got, err := ta.users.GetByID(ctx, basicID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Email != basicEmail {
		t.Fatalf("email = %q, want unchanged %q", got.Email, basicEmail)
	}

	// A pending change row exists and a code was mailed to the new address only.
	if _, err := ta.changes.Pending(ctx, basicID); err != nil {
		t.Fatalf("pending change row: %v", err)
	}
	msgs := sender.all()
	if len(msgs) != 1 {
		t.Fatalf("sent %d emails, want 1", len(msgs))
	}
	if msgs[0].To != "new@example.com" || msgs[0].Subject != emailChangeSubject {
		t.Fatalf("unexpected email %+v", msgs[0])
	}
}

func TestEmailChangeFlowEndToEndThroughService(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)
	sender := &fakeSender{}
	svc := newEmailChangeService(ta, sender)

	code := requestChange(t, svc, sender, ctx, basicID, "renamed@example.com", basicEmail)

	updated, err := svc.ConfirmEmailChange(ctx, basicID, code, basicEmail)
	if err != nil {
		t.Fatal(err)
	}
	if updated.Email != "renamed@example.com" {
		t.Fatalf("email = %q, want renamed@example.com", updated.Email)
	}

	// The pending row is consumed.
	if _, err := ta.changes.Pending(ctx, basicID); !errors.Is(err, user.ErrNoPendingEmailChange) {
		t.Fatalf("pending after confirm = %v, want ErrNoPendingEmailChange", err)
	}

	// Events: request and commit under the user aggregate; the session
	// re-keying event is recorded under the auth aggregate.
	events := ta.eventsFor(t, basicID)
	var requested, emailChanged bool
	for _, e := range events {
		switch e.EventType {
		case user.UserEmailChangeRequestedEventType:
			requested = true
		case user.UserEmailChangedEventType:
			emailChanged = true
		}
	}
	if !requested || !emailChanged {
		t.Fatalf("missing user events: requested=%v emailChanged=%v (%+v)",
			requested, emailChanged, events)
	}
	authEvents, err := ta.store.LoadByAggregate(ctx, auth.AggregateType, basicID)
	if err != nil {
		t.Fatal(err)
	}
	var sessionChanged bool
	for _, e := range authEvents {
		if e.EventType == auth.SessionIdentityChangedEventType {
			sessionChanged = true
		}
	}
	if !sessionChanged {
		t.Fatalf("missing auth.session_identity_changed event, got %+v", authEvents)
	}
}

func TestEmailChangeWithoutVerificationNeverCommits(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)
	sender := &fakeSender{}
	svc := newEmailChangeService(ta, sender)

	_ = requestChange(t, svc, sender, ctx, basicID, "renamed@example.com", basicEmail)

	// Wrong code is rejected and the original address survives.
	if _, err := svc.ConfirmEmailChange(ctx, basicID, "ZZZZZZ", basicEmail); !errors.Is(err, user.ErrInvalidChangeCode) {
		t.Fatalf("expected ErrInvalidChangeCode, got %v", err)
	}
	got, err := ta.users.GetByID(ctx, basicID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Email != basicEmail {
		t.Fatalf("email = %q, want unchanged %q after wrong code", got.Email, basicEmail)
	}

	// Confirm without any pending request is rejected.
	otherID := ta.seedUser(t, "other@example.com", user.RoleBasic)
	if _, err := svc.ConfirmEmailChange(ctx, otherID, "123456", "other@example.com"); !errors.Is(err, user.ErrNoPendingEmailChange) {
		t.Fatalf("expected ErrNoPendingEmailChange, got %v", err)
	}
	got, err = ta.users.GetByID(ctx, otherID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Email != "other@example.com" {
		t.Fatalf("email = %q, want unchanged", got.Email)
	}
}

func TestEmailChangeExpiredVerificationRejected(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)

	code, err := auth.GenerateCode()
	if err != nil {
		t.Fatal(err)
	}
	hash, err := auth.HashCode(code)
	if err != nil {
		t.Fatal(err)
	}
	// An expired pending change cannot be produced by the request command
	// (it rejects already-expired codes); record the expired event directly
	// and catch up the projection.
	payload, err := json.Marshal(user.UserEmailChangeRequestedPayload{
		UserID:      basicID,
		OldEmail:    basicEmail,
		NewEmail:    "renamed@example.com",
		CodeHash:    hash,
		ExpiresAt:   time.Now().UTC().Add(-time.Minute),
		RequestedAt: time.Now().UTC().Add(-time.Hour),
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ta.store.Append(ctx, eventstore.Event{
		AggregateType: user.AggregateType,
		AggregateID:   basicID,
		EventType:     user.UserEmailChangeRequestedEventType,
		Payload:       payload,
		OccurredAt:    time.Now().UTC().Add(-time.Hour),
	}); err != nil {
		t.Fatal(err)
	}
	if err := ta.app.Projections.CatchUp(ctx); err != nil {
		t.Fatal(err)
	}

	if _, err := ta.service.ConfirmEmailChange(ctx, basicID, code, basicEmail); !errors.Is(err, user.ErrEmailChangeExpired) {
		t.Fatalf("expected ErrEmailChangeExpired, got %v", err)
	}
	got, err := ta.users.GetByID(ctx, basicID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Email != basicEmail {
		t.Fatalf("email = %q, want unchanged %q after expired verification", got.Email, basicEmail)
	}
}

func TestEmailChangeDuplicateAddressesRejected(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	ta.seedUser(t, basicEmail, user.RoleBasic)
	otherID := ta.seedUser(t, "other@example.com", user.RoleBasic)
	sender := &fakeSender{}
	svc := newEmailChangeService(ta, sender)

	// Requesting another user's address is rejected without sending a code.
	if _, err := svc.RequestEmailChange(ctx, otherID, basicEmail, "other@example.com", "1.2.3.4"); !errors.Is(err, user.ErrDuplicateEmail) {
		t.Fatalf("expected ErrDuplicateEmail, got %v", err)
	}
	if msgs := sender.all(); len(msgs) != 0 {
		t.Fatalf("sent %d emails on duplicate request, want 0", len(msgs))
	}
	got, err := ta.users.GetByID(ctx, otherID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Email != "other@example.com" {
		t.Fatalf("email = %q, want unchanged after duplicate request", got.Email)
	}

	// A claim made between request and confirm loses at confirm time.
	code := requestChange(t, svc, sender, ctx, otherID, "contested@example.com", "other@example.com")
	if err := ta.app.Commands.Execute(ctx, user.SeedUserCommand{Email: "contested@example.com", Role: user.RoleBasic}); err != nil {
		t.Fatal(err)
	}
	sender.reset()
	if _, err := svc.ConfirmEmailChange(ctx, otherID, code, "other@example.com"); !errors.Is(err, user.ErrDuplicateEmail) {
		t.Fatalf("expected ErrDuplicateEmail at confirm, got %v", err)
	}
	if got, err := ta.users.GetByID(ctx, otherID); err != nil || got.Email != "other@example.com" {
		t.Fatalf("email = %q err = %v, want unchanged after contested confirm", got.Email, err)
	}
}

func TestEmailChangeAuthorization(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)
	otherID := ta.seedUser(t, "other@example.com", user.RoleBasic)
	sender := &fakeSender{}
	svc := newEmailChangeService(ta, sender)

	// An unrelated basic user cannot request or confirm someone else's change.
	if _, err := svc.RequestEmailChange(ctx, basicID, "hijack@example.com", "other@example.com", "1.2.3.4"); !errors.Is(err, user.ErrForbidden) {
		t.Fatalf("expected ErrForbidden on request, got %v", err)
	}
	if _, err := svc.ConfirmEmailChange(ctx, otherID, "123456", basicEmail); !errors.Is(err, user.ErrForbidden) {
		t.Fatalf("expected ErrForbidden on confirm, got %v", err)
	}
}
