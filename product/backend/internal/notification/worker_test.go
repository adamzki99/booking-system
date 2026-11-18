package notification

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"strings"
	"sync"
	"testing"
	"time"
)

type sentMessage struct {
	to, subject, body string
}

// scriptedSender fails the first fail calls, then succeeds and records the
// message. It is safe for concurrent use by worker tests.
type scriptedSender struct {
	mu    sync.Mutex
	fail  int
	calls int
	sent  []sentMessage
}

func (s *scriptedSender) Send(_ context.Context, to, subject, body string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.calls++
	if s.calls <= s.fail {
		return errors.New("smtp down")
	}
	s.sent = append(s.sent, sentMessage{to: to, subject: subject, body: body})
	return nil
}

func (s *scriptedSender) callCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.calls
}

func testLogger(t *testing.T, buf *bytes.Buffer) *slog.Logger {
	t.Helper()
	if buf == nil {
		buf = &bytes.Buffer{}
	}
	return slog.New(slog.NewTextHandler(buf, nil))
}

func sampleItem() Item {
	return Item{
		EventID:        7,
		Kind:           KindBookingCreated,
		RecipientEmail: "alice@example.com",
		Subject:        "booking-subject-secret",
		Body:           "booking-body-secret",
	}
}

func TestWorkerRetriesTransientFailureThenSucceeds(t *testing.T) {
	ctx := context.Background()
	store := NewMemoryStore()
	if err := store.Enqueue(ctx, sampleItem()); err != nil {
		t.Fatal(err)
	}
	sender := &scriptedSender{fail: 2}
	worker := NewWorker(store, sender, testLogger(t, nil), Policy{
		MaxAttempts: 5,
		BaseDelay:   time.Nanosecond,
	})

	delivered := false
	for i := 0; i < 10; i++ {
		stats, err := worker.ProcessOnce(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if stats.Sent == 1 {
			delivered = true
			break
		}
	}
	if !delivered {
		t.Fatal("notification was not delivered after transient failures")
	}
	if got := sender.callCount(); got != 3 {
		t.Fatalf("send calls = %d, want 3", got)
	}
	items, err := store.List(ctx, StatusSent)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 {
		t.Fatalf("sent rows = %d, want 1", len(items))
	}
	if items[0].Attempts != 3 {
		t.Fatalf("attempts = %d, want 3", items[0].Attempts)
	}
	if items[0].RecipientEmail != "alice@example.com" || items[0].Subject != "booking-subject-secret" {
		t.Fatalf("delivered item = %+v", items[0])
	}
}

func TestWorkerMakesPermanentFailureObservableAndStopsRetrying(t *testing.T) {
	ctx := context.Background()
	store := NewMemoryStore()
	if err := store.Enqueue(ctx, sampleItem()); err != nil {
		t.Fatal(err)
	}
	sender := &scriptedSender{fail: 100}
	worker := NewWorker(store, sender, testLogger(t, nil), Policy{
		MaxAttempts: 3,
		BaseDelay:   time.Nanosecond,
	})

	failed := false
	for i := 0; i < 10; i++ {
		stats, err := worker.ProcessOnce(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if stats.Failed == 1 {
			failed = true
			break
		}
	}
	if !failed {
		t.Fatal("notification was not marked permanently failed")
	}
	if got := sender.callCount(); got != 3 {
		t.Fatalf("send calls = %d, want 3 (bounded)", got)
	}
	rows, err := store.List(ctx, StatusFailed)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].LastError == "" {
		t.Fatalf("failed rows = %+v", rows)
	}
	if rows[0].Attempts != 3 {
		t.Fatalf("attempts = %d, want 3", rows[0].Attempts)
	}
	stats, err := worker.ProcessOnce(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if stats.Claimed != 0 {
		t.Fatalf("claimed %d rows after permanent failure, want 0", stats.Claimed)
	}
}

func TestWorkerLogsOmitSensitiveContent(t *testing.T) {
	ctx := context.Background()
	var logs bytes.Buffer
	store := NewMemoryStore()
	if err := store.Enqueue(ctx, sampleItem()); err != nil {
		t.Fatal(err)
	}
	sender := &scriptedSender{fail: 0}
	worker := NewWorker(store, sender, testLogger(t, &logs), Policy{BaseDelay: time.Nanosecond})
	if _, err := worker.ProcessOnce(ctx); err != nil {
		t.Fatal(err)
	}
	got := logs.String()
	for _, want := range []string{"event_id=7", "kind=" + KindBookingCreated, "attempts=1", "to=***@example.com"} {
		if !strings.Contains(got, want) {
			t.Fatalf("log missing %q: %s", want, got)
		}
	}
	for _, leak := range []string{"alice@example.com", "booking-subject-secret", "booking-body-secret"} {
		if strings.Contains(got, leak) {
			t.Fatalf("log leaked %q: %s", leak, got)
		}
	}
}

func TestPolicyDelayGrowsAndCaps(t *testing.T) {
	policy := Policy{BaseDelay: 10 * time.Millisecond, MaxDelay: 35 * time.Millisecond}
	want := []time.Duration{10, 20, 35, 35}
	for i, expected := range want {
		if got := policy.Delay(i + 1); got != expected*time.Millisecond {
			t.Fatalf("Delay(%d) = %v, want %v", i+1, got, expected)
		}
	}
}

func TestEnqueueIsIdempotent(t *testing.T) {
	ctx := context.Background()
	store := NewMemoryStore()
	item := sampleItem()
	if err := store.Enqueue(ctx, item); err != nil {
		t.Fatal(err)
	}
	if err := store.Enqueue(ctx, item); err != nil {
		t.Fatal(err)
	}
	rows, err := store.List(ctx, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 {
		t.Fatalf("rows = %d, want 1 (duplicate processing)", len(rows))
	}
}

func TestDueClaimsEachRowOnce(t *testing.T) {
	ctx := context.Background()
	store := NewMemoryStore()
	if err := store.Enqueue(ctx, sampleItem()); err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	first, err := store.Due(ctx, now, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(first) != 1 || first[0].Attempts != 1 {
		t.Fatalf("first claim = %+v", first)
	}
	second, err := store.Due(ctx, now, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(second) != 0 {
		t.Fatalf("second claim = %+v, want none (lease)", second)
	}
}

func TestWorkerRunStopsOnContextCancel(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	worker := NewWorker(NewMemoryStore(), &scriptedSender{}, testLogger(t, nil), Policy{})
	done := make(chan error, 1)
	go func() { done <- worker.Run(ctx, time.Millisecond) }()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("Run did not stop on context cancellation")
	}
}

func TestMaskRecipient(t *testing.T) {
	cases := map[string]string{
		"alice@example.com": "***@example.com",
		"no-at-sign":        "***",
		"trailing@":         "***",
	}
	for in, want := range cases {
		if got := MaskRecipient(in); got != want {
			t.Fatalf("MaskRecipient(%q) = %q, want %q", in, got, want)
		}
	}
}
