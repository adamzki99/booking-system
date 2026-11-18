package notification_test

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"os"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/notification"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

type sentMessage struct {
	to, subject, body string
}

type countingSender struct {
	mu        sync.Mutex
	failTimes int
	calls     int
	sent      []sentMessage
}

func (s *countingSender) Send(_ context.Context, to, subject, body string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.calls++
	if s.calls <= s.failTimes {
		return errors.New("smtp down")
	}
	s.sent = append(s.sent, sentMessage{to, subject, body})
	return nil
}

func (s *countingSender) messages() []sentMessage {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]sentMessage, len(s.sent))
	copy(out, s.sent)
	return out
}

var eventIDSeq atomic.Int64

func uniqueEventID() int64 { return time.Now().UnixNano() + eventIDSeq.Add(1) }

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func testPolicy() notification.Policy {
	return notification.Policy{MaxAttempts: 5, BaseDelay: time.Nanosecond, MaxDelay: time.Microsecond}
}

func enqueue(t *testing.T, store notification.Store, eventID int64) {
	t.Helper()
	if err := store.Enqueue(context.Background(), notification.Item{
		EventID:        eventID,
		Kind:           notification.KindBookingCreated,
		RecipientEmail: "alice@example.com",
		Subject:        "Booking confirmed",
		Body:           "Your booking is confirmed.",
	}); err != nil {
		t.Fatal(err)
	}
}

func rowState(t *testing.T, pool *pgxpool.Pool, eventID int64) (string, int, *string) {
	t.Helper()
	var status string
	var attempts int
	var lastError *string
	err := pool.QueryRow(context.Background(), `
		SELECT status, attempts, last_error FROM notification_outbox WHERE event_id = $1`,
		eventID).Scan(&status, &attempts, &lastError)
	if err != nil {
		t.Fatal(err)
	}
	return status, attempts, lastError
}

func rowCount(t *testing.T, pool *pgxpool.Pool, eventID int64) int {
	t.Helper()
	var count int
	if err := pool.QueryRow(context.Background(),
		`SELECT count(*) FROM notification_outbox WHERE event_id = $1`, eventID).Scan(&count); err != nil {
		t.Fatal(err)
	}
	return count
}

func TestPostgresStoreEnqueuePersists(t *testing.T) {
	pool := newNotificationTestPool(t)
	store := notification.NewPostgresStore(pool)
	id := uniqueEventID()
	enqueue(t, store, id)

	if got := rowCount(t, pool, id); got != 1 {
		t.Fatalf("rows = %d, want 1", got)
	}
	status, attempts, _ := rowState(t, pool, id)
	if status != notification.StatusPending || attempts != 0 {
		t.Fatalf("status = %q, attempts = %d, want pending/0", status, attempts)
	}
}

func TestWorkerRestartPicksUpPendingDelivery(t *testing.T) {
	pool := newNotificationTestPool(t)
	store := notification.NewPostgresStore(pool)
	id := uniqueEventID()
	enqueue(t, store, id)
	ctx := context.Background()

	// The first worker fails once and reschedules the row.
	firstSender := &countingSender{failTimes: 1}
	first := notification.NewWorker(store, firstSender, testLogger(), testPolicy())
	stats, err := first.ProcessOnce(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if stats.Retried != 1 {
		t.Fatalf("first pass stats = %+v, want one retry", stats)
	}

	// A new worker over the same pool, created after the first one stopped,
	// still sees the pending row and delivers it.
	secondSender := &countingSender{}
	second := notification.NewWorker(store, secondSender, testLogger(), testPolicy())
	stats, err = second.ProcessOnce(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if stats.Sent != 1 {
		t.Fatalf("second pass stats = %+v, want one delivery", stats)
	}
	status, attempts, _ := rowState(t, pool, id)
	if status != notification.StatusSent || attempts != 2 {
		t.Fatalf("status = %q, attempts = %d, want sent/2", status, attempts)
	}
	if messages := secondSender.messages(); len(messages) != 1 || messages[0].to != "alice@example.com" {
		t.Fatalf("delivered = %+v", messages)
	}
}

func TestPostgresStoreUniqueBlocksReplayedEvent(t *testing.T) {
	pool := newNotificationTestPool(t)
	store := notification.NewPostgresStore(pool)
	id := uniqueEventID()
	enqueue(t, store, id) // original event
	enqueue(t, store, id) // replayed event

	if got := rowCount(t, pool, id); got != 1 {
		t.Fatalf("rows = %d, want 1 for a replayed event", got)
	}
}

func TestPostgresStoreFailedRowsRemainQueryable(t *testing.T) {
	pool := newNotificationTestPool(t)
	store := notification.NewPostgresStore(pool)
	id := uniqueEventID()
	enqueue(t, store, id)
	policy := testPolicy()
	policy.MaxAttempts = 1
	worker := notification.NewWorker(store, &countingSender{failTimes: 100}, testLogger(), policy)

	stats, err := worker.ProcessOnce(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if stats.Failed != 1 {
		t.Fatalf("stats = %+v, want one permanent failure", stats)
	}
	status, attempts, lastError := rowState(t, pool, id)
	if status != notification.StatusFailed || attempts != 1 {
		t.Fatalf("status = %q, attempts = %d, want failed/1", status, attempts)
	}
	if lastError == nil || *lastError == "" {
		t.Fatal("expected the failure cause to be stored")
	}
}

func newNotificationTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	ctx := context.Background()

	if url := os.Getenv("DATABASE_URL"); url != "" {
		pool, err := pgxpool.New(ctx, url)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(pool.Close)
		if err := eventstore.Migrate(ctx, pool); err != nil {
			t.Fatal(err)
		}
		return pool
	}

	container, err := postgres.Run(ctx, "postgres:16",
		postgres.WithDatabase("test"),
		postgres.WithUsername("test"),
		postgres.WithPassword("test"),
		testcontainers.WithWaitStrategy(wait.ForLog("database system is ready to accept connections").WithOccurrence(2)),
	)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = container.Terminate(ctx) })

	url, err := container.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	if err := eventstore.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	return pool
}
