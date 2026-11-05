package eventstore

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	ctx := context.Background()

	if url := os.Getenv("DATABASE_URL"); url != "" {
		pool, err := pgxpool.New(ctx, url)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { pool.Close() })
		if err := Migrate(ctx, pool); err != nil {
			t.Fatal(err)
		}
		// clean table for isolation
		_, _ = pool.Exec(ctx, "TRUNCATE events RESTART IDENTITY")
		return pool
	}

	pgC, err := postgres.Run(ctx, "postgres:16",
		postgres.WithDatabase("test"),
		postgres.WithUsername("test"),
		postgres.WithPassword("test"),
		testcontainers.WithWaitStrategy(wait.ForLog("database system is ready to accept connections").WithOccurrence(2)),
	)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = pgC.Terminate(ctx) })

	url, err := pgC.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { pool.Close() })
	if err := Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	return pool
}

func TestPostgresStoreAppendAndReplay(t *testing.T) {
	pool := newTestPool(t)
	store := NewPostgresStore(pool)
	ctx := context.Background()

	now := time.Now().UTC()
	ev1 := Event{AggregateType: "sauna", AggregateID: "a", EventType: "Created", Payload: []byte(`{"n":1}`), OccurredAt: now}
	ev2 := Event{AggregateType: "sauna", AggregateID: "a", EventType: "Updated", Payload: []byte(`{"n":2}`), OccurredAt: now.Add(time.Second)}
	ev3 := Event{AggregateType: "sauna", AggregateID: "b", EventType: "Created", Payload: []byte(`{"n":3}`), OccurredAt: now}

	if err := store.Append(ctx, ev1, ev2); err != nil {
		t.Fatal(err)
	}
	if err := store.Append(ctx, ev3); err != nil {
		t.Fatal(err)
	}

	all, err := store.LoadAll(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 3 {
		t.Fatalf("expected 3, got %d", len(all))
	}
	// order by recorded_at, id
	if all[0].EventType != "Created" || all[0].AggregateID != "a" {
		t.Fatalf("unexpected first: %+v", all[0])
	}

	agg, err := store.LoadByAggregate(ctx, "sauna", "a")
	if err != nil {
		t.Fatal(err)
	}
	if len(agg) != 2 {
		t.Fatalf("expected 2 for aggregate a, got %d", len(agg))
	}
	if agg[0].EventType != "Created" || agg[1].EventType != "Updated" {
		t.Fatalf("unexpected order: %+v", agg)
	}
	// recorded_at from DB
	if agg[0].RecordedAt.IsZero() {
		t.Fatal("recorded_at should be set")
	}
	// ID assigned
	if agg[0].ID == 0 {
		t.Fatal("id should be assigned")
	}
}

func TestPostgresStoreEmptyAppend(t *testing.T) {
	pool := newTestPool(t)
	store := NewPostgresStore(pool)
	if err := store.Append(context.Background()); err != nil {
		t.Fatal(err)
	}
}
