package registry_test

import (
	"context"
	"os"
	"reflect"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
	"github.com/adamzki99/booking-system/product/backend/internal/sample"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

func TestSampleFlowReplayAndCatchUp(t *testing.T) {
	pool := newRegistryTestPool(t)
	store := eventstore.NewPostgresStore(pool)
	ctx := context.Background()
	app, err := registry.New(ctx, store, pool)
	if err != nil {
		t.Fatal(err)
	}
	readModel := sample.Register(app)

	createdAt := time.Date(2026, time.November, 5, 12, 0, 0, 0, time.UTC)
	id := "sample-" + t.Name()
	cmd := sample.CreateSample{ID: id, Name: "Cedar", OccurredAt: createdAt}
	if err := app.Commands.Execute(ctx, cmd); err != nil {
		t.Fatal(err)
	}

	events, err := store.LoadByAggregate(ctx, sample.AggregateType, id)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || events[0].EventType != sample.CreatedEventType || events[0].ID == 0 {
		t.Fatalf("expected one recorded SampleCreated event, got %+v", events)
	}
	assertSample(t, readModel, id, sample.Item{ID: id, Name: "Cedar", CreatedAt: createdAt})

	before, err := readModel.List(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := app.Projections.RebuildAll(ctx); err != nil {
		t.Fatal(err)
	}
	after, err := readModel.List(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(after, before) {
		t.Fatalf("rebuilt read model differs:\nbefore: %+v\nafter:  %+v", before, after)
	}

	catchUpID := id + "-catch-up"
	_, err = store.Append(ctx, eventstore.Event{
		AggregateType: sample.AggregateType,
		AggregateID:   catchUpID,
		EventType:     sample.CreatedEventType,
		Payload:       []byte(`{"name":"Birch"}`),
		OccurredAt:    createdAt.Add(time.Hour),
	})
	if err != nil {
		t.Fatal(err)
	}
	assertSampleMissing(t, readModel, catchUpID)
	if err := app.Projections.CatchUp(ctx); err != nil {
		t.Fatal(err)
	}
	assertSample(t, readModel, catchUpID, sample.Item{ID: catchUpID, Name: "Birch", CreatedAt: createdAt.Add(time.Hour)})
}

func assertSample(t *testing.T, readModel *sample.Projection, id string, want sample.Item) {
	t.Helper()
	items, err := readModel.List(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for _, item := range items {
		if item.ID == id {
			if item.Name != want.Name || !item.CreatedAt.Equal(want.CreatedAt) {
				t.Fatalf("expected sample %+v, got %+v", want, item)
			}
			return
		}
	}
	t.Fatalf("sample %q not found in %+v", id, items)
}

func assertSampleMissing(t *testing.T, readModel *sample.Projection, id string) {
	t.Helper()
	items, err := readModel.List(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for _, item := range items {
		if item.ID == id {
			t.Fatalf("sample %q was projected before catch-up", id)
		}
	}
}

func newRegistryTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	ctx := context.Background()

	if url := os.Getenv("DATABASE_URL"); url != "" {
		pool, err := pgxpool.New(ctx, url)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(pool.Close)
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
	return pool
}
