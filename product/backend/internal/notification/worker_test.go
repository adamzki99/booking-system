package notification

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"sync"
	"testing"
	"time"
)

type deliveredEmail struct {
	to, subject, body string
}

// scriptedSender returns a scripted error for each call, then succeeds. When
// alwaysErr is set it fails every call.
type scriptedSender struct {
	mu        sync.Mutex
	results   []error
	alwaysErr error
	delivered []deliveredEmail
}

func (s *scriptedSender) Send(_ context.Context, to, subject, body string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.alwaysErr != nil {
		return s.alwaysErr
	}
	if len(s.results) == 0 {
		s.delivered = append(s.delivered, deliveredEmail{to, subject, body})
		return nil
	}
	err := s.results[0]
	s.results = s.results[1:]
	if err != nil {
		return err
	}
	s.delivered = append(s.delivered, deliveredEmail{to, subject, body})
	return nil
}

func (s *scriptedSender) messages() []deliveredEmail {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]deliveredEmail, len(s.delivered))
	copy(out, s.delivered)
	return out
}

func fastPolicy() Policy {
	return Policy{MaxAttempts: 5, BaseDelay: time.Nanosecond, MaxDelay: time.Microsecond}
}

func testWorker(store Store, sender *scriptedSender, policy Policy) *Worker {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	return NewWorker(store, sender, logger, policy)
}

func enqueueBooking(t *testing.T, store Store, eventID int64) {
	t.Helper()
	if err := store.Enqueue(context.Background(), Item{
		EventID:        eventID,
		Kind:           KindBookingCreated,
		RecipientEmail: "alice@example.com",
		Subject:        "Booking confirmed",
		Body:           "Your booking is confirmed.",
	}); err != nil {
		t.Fatal(err)
	}
}

func TestWorkerRetriesTransientFailureThenSucceeds(t *testing.T) {
	ctx := context.Background()
	store := NewMemoryStore()
	enqueueBooking(t, store, 11)
	sender := &scriptedSender{results: []error{errors.New("smtp down"), errors.New("smtp still down"), nil}}
	w := testWorker(store, sender, fastPolicy())

	for pass := 1; pass <= 3; pass++ {
		stats, err := w.ProcessOnce(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if stats.Sent+stats.Retried != 1 {
			t.Fatalf("pass %d: processed %+v, want one item", pass, stats)
		}
	}

	items := store.Items()
	if len(items) != 1 {
		t.Fatalf("items = %d, want 1", len(items))
	}
	if items[0].Status != StatusSent {
		t.Fatalf("status = %q, want %q", items[0].Status, StatusSent)
	}
	if items[0].Attempts != 3 {
		t.Fatalf("attempts = %d, want 3", items[0].Attempts)
	}
	if messages := sender.messages(); len(messages) != 1 || messages[0].to != "alice@example.com" {
		t.Fatalf("delivered = %+v", messages)
	}
}

func TestWorkerMarksPermanentFailureAfterMaxAttempts(t *testing.T) {
	ctx := context.Background()
	store := NewMemoryStore()
	enqueueBooking(t, store, 12)
	policy := fastPolicy()
	policy.MaxAttempts = 3
	sender := &scriptedSender{alwaysErr: errors.New("smtp down")}
	w := testWorker(store, sender, policy)

	for pass := 1; pass <= 3; pass++ {
		stats, err := w.ProcessOnce(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if pass < 3 && stats.Retried != 1 {
			t.Fatalf("pass %d: stats = %+v, want one retry", pass, stats)
		}
		if pass == 3 && stats.Failed != 1 {
			t.Fatalf("pass %d: stats = %+v, want one permanent failure", pass, stats)
		}
	}
	// A permanently failed row is not due again: no further send is attempted.
	stats, err := w.ProcessOnce(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if stats != (Stats{}) {
		t.Fatalf("stats after failure = %+v, want zero", stats)
	}
	items := store.Items()
	if len(items) != 1 {
		t.Fatalf("items = %d, want 1", len(items))
	}
	if items[0].Status != StatusFailed {
		t.Fatalf("status = %q, want %q", items[0].Status, StatusFailed)
	}
	if items[0].Attempts != 3 {
		t.Fatalf("attempts = %d, want 3", items[0].Attempts)
	}
	if items[0].LastError == "" {
		t.Fatal("expected the permanent failure cause to be stored")
	}
}

func TestBackoffGrowsAndCaps(t *testing.T) {
	policy := Policy{BaseDelay: time.Second, MaxDelay: 10 * time.Second}
	if got := backoffFor(1, policy); got != 2*time.Second {
		t.Fatalf("backoff(1) = %v, want 2s", got)
	}
	previous := time.Duration(0)
	for attempts := 1; attempts <= 12; attempts++ {
		got := backoffFor(attempts, policy)
		if got > policy.MaxDelay {
			t.Fatalf("backoff(%d) = %v exceeds cap %v", attempts, got, policy.MaxDelay)
		}
		if got < previous {
			t.Fatalf("backoff(%d) = %v decreased from %v", attempts, got, previous)
		}
		previous = got
	}
	if got := backoffFor(20, policy); got != policy.MaxDelay {
		t.Fatalf("backoff(20) = %v, want cap %v", got, policy.MaxDelay)
	}
}

func TestClaimWithoutSendDoesNotBurnAnAttempt(t *testing.T) {
	ctx := context.Background()
	store := NewMemoryStore()
	enqueueBooking(t, store, 15)

	if _, err := store.Due(ctx, time.Now(), 10); err != nil {
		t.Fatal(err)
	}
	// Simulate a worker dying after the claim but before delivering: no
	// terminal update runs, so attempts must stay at zero.
	if got := store.Items()[0].Attempts; got != 0 {
		t.Fatalf("attempts after claim = %d, want 0", got)
	}
	// Once the lease expires the row is due again with its attempts intact.
	due, err := store.Due(ctx, time.Now().Add(claimLease+time.Second), 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(due) != 1 || due[0].Attempts != 0 {
		t.Fatalf("reclaimed rows = %+v, want one row with zero attempts", due)
	}
}

func TestEnqueueIsIdempotentForSameEventKindRecipient(t *testing.T) {
	store := NewMemoryStore()
	enqueueBooking(t, store, 13)
	enqueueBooking(t, store, 13) // replayed event

	if items := store.Items(); len(items) != 1 {
		t.Fatalf("items = %d, want 1", len(items))
	}
}

func TestDueClaimsRowsSoASecondDrainCannotResend(t *testing.T) {
	ctx := context.Background()
	store := NewMemoryStore()
	enqueueBooking(t, store, 14)

	first, err := store.Due(ctx, time.Now(), 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(first) != 1 {
		t.Fatalf("first due = %d, want 1", len(first))
	}
	second, err := store.Due(ctx, time.Now(), 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(second) != 0 {
		t.Fatalf("second due = %d, want 0 (claimed row must not be re-sent)", len(second))
	}
}
