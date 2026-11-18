// Package notification implements a durable outbox for transactional email.
// Notifiers enqueue intended deliveries; a worker drains them with bounded
// retries. Domain events stay append-only and are never rolled back because a
// delivery failed.
package notification

import (
	"context"
	"log/slog"
	"sort"
	"strings"
	"sync"
	"time"

	"go.opentelemetry.io/otel"
)

// Delivery kinds recorded in the outbox.
const (
	KindBookingCreated   = "booking.created"
	KindBookingCancelled = "booking.cancelled"
	KindBroadcast        = "broadcast"
)

// Delivery states. Permanently failed rows are kept for operator inspection.
const (
	StatusPending = "pending"
	StatusSent    = "sent"
	StatusFailed  = "failed"
)

// claimLease makes an in-flight row invisible to the next drain. If a worker
// dies mid-send, the lease expires and the row becomes due again.
const claimLease = 30 * time.Second

var (
	meter               = otel.Meter("notification")
	enqueuedCounter, _  = meter.Int64Counter("notifications.enqueued")
	sentCounter, _      = meter.Int64Counter("notifications.sent")
	retriedCounter, _   = meter.Int64Counter("notifications.retried")
	failedCounter, _    = meter.Int64Counter("notifications.failed")
	enqueueFailCount, _ = meter.Int64Counter("notifications.enqueue_failed")
)

// Item is one intended email delivery persisted as durable work.
type Item struct {
	ID             int64
	EventID        int64
	Kind           string
	RecipientEmail string
	Subject        string
	Body           string
	Status         string
	Attempts       int
	NextAttemptAt  time.Time
	LastError      string
	CreatedAt      time.Time
	SentAt         *time.Time
}

// Enqueuer is the narrow write seam used by notifiers.
type Enqueuer interface {
	Enqueue(ctx context.Context, item Item) error
}

// Store is the durable outbox used by the worker.
type Store interface {
	Enqueuer
	// Due claims up to limit pending rows that are due at now. Claiming leases
	// the row so a concurrent drain cannot deliver it twice. Attempts are
	// counted only when a send completes, so a worker killed mid-send does not
	// burn an attempt.
	Due(ctx context.Context, now time.Time, limit int) ([]Item, error)
	MarkSent(ctx context.Context, id int64, at time.Time) error
	Retry(ctx context.Context, id int64, nextAt time.Time, cause string) error
	Fail(ctx context.Context, id int64, cause string) error
}

// EnqueueDelivery persists one intended delivery. An enqueue failure is
// counted and logged, never propagated: the domain event is already recorded
// and must not be rolled back because delivery could not be queued.
func EnqueueDelivery(ctx context.Context, outbox Enqueuer, item Item, logger *slog.Logger, eventID int64, label string) {
	if err := outbox.Enqueue(ctx, item); err != nil {
		enqueueFailCount.Add(ctx, 1)
		logger.Error("notification enqueue: "+label,
			"event", eventID, "recipient", MaskRecipient(item.RecipientEmail), "err", err)
	}
}

// MemoryStore is an in-memory Store for unit tests.
type MemoryStore struct {
	mu     sync.Mutex
	nextID int64
	items  []Item
}

// NewMemoryStore creates an empty in-memory outbox.
func NewMemoryStore() *MemoryStore { return &MemoryStore{} }

// Enqueue adds an item unless the same (event, kind, recipient) is already
// queued. This is the idempotency guarantee for replayed or double-published
// events.
func (s *MemoryStore) Enqueue(ctx context.Context, item Item) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, existing := range s.items {
		if existing.EventID == item.EventID && existing.Kind == item.Kind &&
			existing.RecipientEmail == item.RecipientEmail {
			return nil
		}
	}
	s.nextID++
	item.ID = s.nextID
	item.Status = StatusPending
	item.NextAttemptAt = time.Now().UTC()
	item.CreatedAt = time.Now().UTC()
	s.items = append(s.items, item)
	enqueuedCounter.Add(ctx, 1)
	return nil
}

// Due claims up to limit due rows, ordered by next attempt time.
func (s *MemoryStore) Due(ctx context.Context, now time.Time, limit int) ([]Item, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if limit <= 0 {
		return nil, nil
	}
	indexes := make([]int, 0, len(s.items))
	for i := range s.items {
		item := &s.items[i]
		if item.Status == StatusPending && !item.NextAttemptAt.After(now) {
			indexes = append(indexes, i)
		}
	}
	sort.SliceStable(indexes, func(a, b int) bool {
		if s.items[indexes[a]].NextAttemptAt.Equal(s.items[indexes[b]].NextAttemptAt) {
			return s.items[indexes[a]].ID < s.items[indexes[b]].ID
		}
		return s.items[indexes[a]].NextAttemptAt.Before(s.items[indexes[b]].NextAttemptAt)
	})
	if len(indexes) > limit {
		indexes = indexes[:limit]
	}
	leaseUntil := now.Add(claimLease)
	claimed := make([]Item, 0, len(indexes))
	for _, i := range indexes {
		item := &s.items[i]
		item.NextAttemptAt = leaseUntil
		claimed = append(claimed, *item)
	}
	return claimed, nil
}

// MarkSent records a successful delivery.
func (s *MemoryStore) MarkSent(ctx context.Context, id int64, at time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.items {
		if s.items[i].ID == id {
			s.items[i].Status = StatusSent
			s.items[i].Attempts++
			s.items[i].SentAt = &at
			s.items[i].LastError = ""
			sentCounter.Add(ctx, 1)
			return nil
		}
	}
	return nil
}

// Retry reschedules a transiently failed delivery.
func (s *MemoryStore) Retry(ctx context.Context, id int64, nextAt time.Time, cause string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.items {
		if s.items[i].ID == id {
			s.items[i].Status = StatusPending
			s.items[i].Attempts++
			s.items[i].NextAttemptAt = nextAt
			s.items[i].LastError = cause
			retriedCounter.Add(ctx, 1)
			return nil
		}
	}
	return nil
}

// Fail permanently fails a delivery. The row is retained for inspection.
func (s *MemoryStore) Fail(ctx context.Context, id int64, cause string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.items {
		if s.items[i].ID == id {
			s.items[i].Status = StatusFailed
			s.items[i].Attempts++
			s.items[i].LastError = cause
			failedCounter.Add(ctx, 1)
			return nil
		}
	}
	return nil
}

// Items returns a snapshot of the stored rows for assertions.
func (s *MemoryStore) Items() []Item {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]Item, len(s.items))
	copy(out, s.items)
	return out
}

// MaskRecipient removes the local part of an address from logs. Operators can
// correlate by domain only; the message subject and body are never logged.
func MaskRecipient(email string) string {
	at := strings.LastIndex(email, "@")
	if at <= 0 || at == len(email)-1 {
		return "<invalid>"
	}
	return "<redacted>@" + email[at+1:]
}
