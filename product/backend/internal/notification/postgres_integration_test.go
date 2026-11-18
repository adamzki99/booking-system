package notification_test

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/notification"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

type failingSender struct{}

func (failingSender) Send(context.Context, string, string, string) error {
	return errors.New("smtp down")
}

type recordingSender struct {
	sent []string
}

func (r *recordingSender) Send(_ context.Context, to, _, _ string) error {
	r.sent = append(r.sent, to)
	return nil
}

func drainUntil(t *testing.T, worker *notification.Worker, done func(notification.Stats) bool) notification.Stats {
	t.Helper()
	var total notification.Stats
	for i := 0; i < 20; i++ {
		stats, err := worker.ProcessOnce(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		total.Claimed += stats.Claimed
		total.Sent += stats.Sent
		total.Retried += stats.Retried
		total.Failed += stats.Failed
		if done(stats) {
			return total
		}
		time.Sleep(2 * time.Millisecond)
	}
	t.Fatalf("drain condition not reached: %+v", total)
	return total
}

func integrationLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func TestPostgresOutboxPersistsAcrossWorkerRestart(t *testing.T) {
	pool := newNotificationTestPool(t)
	store := notification.NewPostgresStore(pool)
	ctx := context.Background()
	item := notification.Item{
		EventID:        101,
		Kind:           notification.KindBookingCreated,
		RecipientEmail: "alice@example.com",
		Subject:        "Booking confirmed",
		Body:           "Your booking is confirmed.",
	}
	if err := store.Enqueue(ctx, item); err != nil {
		t.Fatal(err)
	}
	// Replaying the same event must not create duplicate work.
	if err := store.Enqueue(ctx, item); err != nil {
		t.Fatal(err)
	}
	rows, err := store.List(ctx, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 {
		t.Fatalf("rows after replay = %d, want 1", len(rows))
	}

	first := notification.NewWorker(store, failingSender{}, integrationLogger(), notification.Policy{
		MaxAttempts: 5,
		BaseDelay:   time.Millisecond,
	})
	drainUntil(t, first, func(s notification.Stats) bool { return s.Retried > 0 })
	pending, err := store.List(ctx, notification.StatusPending)
	if err != nil {
		t.Fatal(err)
	}
	if len(pending) != 1 || pending[0].Attempts != 1 || pending[0].LastError == "" {
		t.Fatalf("pending work not persisted: %+v", pending)
	}

	// A brand-new worker over the same pool picks up the still-pending row.
	secondSender := &recordingSender{}
	second := notification.NewWorker(store, secondSender, integrationLogger(), notification.Policy{
		MaxAttempts: 5,
		BaseDelay:   time.Millisecond,
	})
	drainUntil(t, second, func(s notification.Stats) bool { return s.Sent > 0 })
	if len(secondSender.sent) != 1 || secondSender.sent[0] != "alice@example.com" {
		t.Fatalf("redeliveries = %v", secondSender.sent)
	}
	sent, err := store.List(ctx, notification.StatusSent)
	if err != nil {
		t.Fatal(err)
	}
	if len(sent) != 1 || sent[0].Attempts != 2 {
		t.Fatalf("sent rows = %+v", sent)
	}
}

func TestPostgresFailedRowsRemainQueryable(t *testing.T) {
	pool := newNotificationTestPool(t)
	store := notification.NewPostgresStore(pool)
	ctx := context.Background()
	if err := store.Enqueue(ctx, notification.Item{
		EventID:        102,
		Kind:           notification.KindBroadcast,
		RecipientEmail: "bob@example.com",
		Subject:        "Sauna closed",
		Body:           "Maintenance",
	}); err != nil {
		t.Fatal(err)
	}
	worker := notification.NewWorker(store, failingSender{}, integrationLogger(), notification.Policy{
		MaxAttempts: 2,
		BaseDelay:   time.Millisecond,
	})
	drainUntil(t, worker, func(s notification.Stats) bool { return s.Failed > 0 })

	failed, err := store.List(ctx, notification.StatusFailed)
	if err != nil {
		t.Fatal(err)
	}
	if len(failed) != 1 {
		t.Fatalf("failed rows = %+v", failed)
	}
	if failed[0].Attempts != 2 || !strings.Contains(failed[0].LastError, "smtp down") {
		t.Fatalf("failed row = %+v", failed[0])
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
