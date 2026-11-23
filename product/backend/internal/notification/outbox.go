// Package notification implements a durable outbox for recoverable email
// delivery. Event subscribers enqueue intended deliveries; a separate worker
// retries transient sender failures without touching the event stream.
package notification

import (
	"context"
	"sort"
	"strings"
	"sync"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/metric"
)

// Delivery kinds stored in the outbox.
const (
	KindBookingCreated   = "booking.created"
	KindBookingCancelled = "booking.cancelled"
	KindBroadcast        = "broadcast"
)

// Delivery statuses stored in the outbox.
const (
	StatusPending = "pending"
	StatusSent    = "sent"
	StatusFailed  = "failed"
)

// claimLease keeps a claimed row out of Due until the lease expires. If a
// worker crashes mid-send, the next worker picks the row up after the lease.
const claimLease = 30 * time.Second

// Item is one intended delivery. ID is assigned by the store on Enqueue.
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
	SentAt         time.Time
}

// Enqueuer records an intended delivery. This is the seam used by event
// subscribers: enqueue errors are handled by the caller, never propagated to
// the command path.
type Enqueuer interface {
	Enqueue(ctx context.Context, item Item) error
}

// Store is a durable outbox. Due atomically claims rows so two workers cannot
// send the same item twice. List exposes rows for operator inspection.
type Store interface {
	Enqueuer
	Due(ctx context.Context, now time.Time, limit int) ([]Item, error)
	MarkSent(ctx context.Context, id int64, at time.Time) error
	Retry(ctx context.Context, id int64, nextAt time.Time, cause string) error
	Fail(ctx context.Context, id int64, cause string) error
	List(ctx context.Context, status string) ([]Item, error)
}

// Metrics are created lazily so telemetry.Init (called early in main) can
// install the global meter provider before the first delivery is recorded.
type metrics struct {
	enqueued, sent, retried, failed, enqueueFailed metric.Int64Counter
}

var (
	metricsOnce      sync.Once
	meterStats       metrics
	pendingGaugeOnce sync.Once
)

func recordMetrics() *metrics {
	metricsOnce.Do(func() {
		m := otel.Meter("notification")
		meterStats.enqueued, _ = m.Int64Counter("notifications.enqueued",
			metric.WithDescription("Notification deliveries stored for delivery."))
		meterStats.sent, _ = m.Int64Counter("notifications.sent",
			metric.WithDescription("Notification deliveries delivered successfully."))
		meterStats.retried, _ = m.Int64Counter("notifications.retried",
			metric.WithDescription("Notification deliveries scheduled for retry."))
		meterStats.failed, _ = m.Int64Counter("notifications.failed",
			metric.WithDescription("Notification deliveries permanently failed."))
		meterStats.enqueueFailed, _ = m.Int64Counter("notifications.enqueue_failed",
			metric.WithDescription("Failures while storing an intended delivery."))
	})
	return &meterStats
}

// ObservePending registers an observable gauge that reports the current number
// of pending deliveries. The count function is called by the metric reader; it
// should be cheap and read-only.
func ObservePending(count func(context.Context) (int64, error)) {
	if count == nil {
		return
	}
	pendingGaugeOnce.Do(func() {
		m := otel.Meter("notification")
		_, _ = m.Int64ObservableGauge("notifications.pending",
			metric.WithDescription("Notification deliveries currently awaiting delivery."),
			metric.WithInt64Callback(func(ctx context.Context, o metric.Int64Observer) error {
				n, err := count(ctx)
				if err != nil {
					return err
				}
				o.Observe(n)
				return nil
			}))
	})
}

func recordEnqueued(ctx context.Context)       { recordMetrics().enqueued.Add(ctx, 1) }
func recordSent(ctx context.Context)           { recordMetrics().sent.Add(ctx, 1) }
func recordRetried(ctx context.Context)        { recordMetrics().retried.Add(ctx, 1) }
func recordFailed(ctx context.Context)         { recordMetrics().failed.Add(ctx, 1) }
func recordEnqueueFailure(ctx context.Context) { recordMetrics().enqueueFailed.Add(ctx, 1) }

// ReportEnqueueFailure increments the enqueue-failure counter. Notifiers call
// it when durable enqueueing itself fails; the recorded command still stands.
func ReportEnqueueFailure(ctx context.Context) { recordEnqueueFailure(ctx) }

// MaskRecipient returns a log-safe form of an address: only the domain is
// kept. Subject and body are never logged by this package.
func MaskRecipient(email string) string {
	at := strings.LastIndex(email, "@")
	if at < 0 || at == len(email)-1 {
		return "***"
	}
	return "***@" + email[at+1:]
}

// MemoryStore is an in-memory Store for unit tests. It applies the same
// idempotency and claim semantics as PostgresStore.
type MemoryStore struct {
	mu     sync.Mutex
	nextID int64
	items  []*Item
}

// NewMemoryStore creates an empty in-memory outbox.
func NewMemoryStore() *MemoryStore { return &MemoryStore{} }

func (s *MemoryStore) Enqueue(ctx context.Context, item Item) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, existing := range s.items {
		if existing.EventID == item.EventID && existing.Kind == item.Kind && existing.RecipientEmail == item.RecipientEmail {
			return nil
		}
	}
	s.nextID++
	stored := item
	stored.ID = s.nextID
	stored.Status = StatusPending
	stored.Attempts = 0
	stored.NextAttemptAt = time.Now()
	stored.CreatedAt = stored.NextAttemptAt
	s.items = append(s.items, &stored)
	recordEnqueued(ctx)
	return nil
}

func (s *MemoryStore) Due(_ context.Context, now time.Time, limit int) ([]Item, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	indexes := make([]int, 0, len(s.items))
	for i, item := range s.items {
		if item.Status == StatusPending && !item.NextAttemptAt.After(now) {
			indexes = append(indexes, i)
		}
	}
	sort.SliceStable(indexes, func(a, b int) bool {
		return s.items[indexes[a]].NextAttemptAt.Before(s.items[indexes[b]].NextAttemptAt)
	})
	if limit > 0 && len(indexes) > limit {
		indexes = indexes[:limit]
	}
	// Claiming counts as an attempt, matching PostgresStore.Due: a crashed
	// worker must not be able to retry forever without recording progress.
	out := make([]Item, 0, len(indexes))
	for _, i := range indexes {
		item := s.items[i]
		item.Attempts++
		item.NextAttemptAt = now.Add(claimLease)
		out = append(out, *item)
	}
	return out, nil
}

func (s *MemoryStore) MarkSent(ctx context.Context, id int64, at time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	item := s.find(id)
	if item == nil {
		return nil
	}
	item.Status = StatusSent
	item.SentAt = at
	recordSent(ctx)
	return nil
}

func (s *MemoryStore) Retry(ctx context.Context, id int64, nextAt time.Time, cause string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	item := s.find(id)
	if item == nil {
		return nil
	}
	item.NextAttemptAt = nextAt
	item.LastError = cause
	recordRetried(ctx)
	return nil
}

func (s *MemoryStore) Fail(ctx context.Context, id int64, cause string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	item := s.find(id)
	if item == nil {
		return nil
	}
	item.Status = StatusFailed
	item.LastError = cause
	recordFailed(ctx)
	return nil
}

func (s *MemoryStore) PendingCount(_ context.Context) (int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var n int64
	for _, item := range s.items {
		if item.Status == StatusPending {
			n++
		}
	}
	return n, nil
}

func (s *MemoryStore) List(_ context.Context, status string) ([]Item, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]Item, 0, len(s.items))
	for _, item := range s.items {
		if status != "" && item.Status != status {
			continue
		}
		out = append(out, *item)
	}
	return out, nil
}

// find returns an item by id. Callers must hold s.mu.
func (s *MemoryStore) find(id int64) *Item {
	for _, item := range s.items {
		if item.ID == id {
			return item
		}
	}
	return nil
}
