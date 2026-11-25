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
	aggA := "a-" + t.Name()
	aggB := "b-" + t.Name()
	ev1 := Event{AggregateType: "sauna", AggregateID: aggA, EventType: "Created", Payload: []byte(`{"n":1}`), OccurredAt: now}
	ev2 := Event{AggregateType: "sauna", AggregateID: aggA, EventType: "Updated", Payload: []byte(`{"n":2}`), OccurredAt: now.Add(time.Second)}
	ev3 := Event{AggregateType: "sauna", AggregateID: aggB, EventType: "Created", Payload: []byte(`{"n":3}`), OccurredAt: now}

	if _, err := store.Append(ctx, ev1, ev2); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Append(ctx, ev3); err != nil {
		t.Fatal(err)
	}

	all, err := store.LoadAll(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(all) < 3 {
		t.Fatalf("expected at least 3, got %d", len(all))
	}
	// Events replay in database ID order.
	if all[0].EventType != "Created" {
		t.Fatalf("unexpected first: %+v", all[0])
	}

	agg, err := store.LoadByAggregate(ctx, "sauna", aggA)
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
	if _, err := store.Append(context.Background()); err != nil {
		t.Fatal(err)
	}
}

func TestPostgresStoreAppendReturnsRecordedEvents(t *testing.T) {
	pool := newTestPool(t)
	store := NewPostgresStore(pool)
	now := time.Now().UTC()
	events := []Event{
		{AggregateType: "sample", AggregateID: "recorded-" + t.Name(), EventType: "Created", Payload: []byte(`{"n":1}`), OccurredAt: now},
		{AggregateType: "sample", AggregateID: "recorded-" + t.Name(), EventType: "Updated", Payload: []byte(`{"n":2}`), OccurredAt: now},
	}

	recorded, err := store.Append(context.Background(), events...)
	if err != nil {
		t.Fatal(err)
	}
	if len(recorded) != len(events) {
		t.Fatalf("expected %d recorded events, got %d", len(events), len(recorded))
	}
	for i, event := range recorded {
		if event.ID == 0 {
			t.Fatalf("event %d has no database ID", i)
		}
		if event.RecordedAt.IsZero() {
			t.Fatalf("event %d has no recorded_at timestamp", i)
		}
		if event.EventType != events[i].EventType {
			t.Fatalf("expected event type %q, got %q", events[i].EventType, event.EventType)
		}
		if i > 0 && event.ID <= recorded[i-1].ID {
			t.Fatalf("expected increasing IDs, got %d then %d", recorded[i-1].ID, event.ID)
		}
	}
}
