package projection_test

import (
	"context"
	"os"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/projection"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

func TestPostgresCheckpointStore(t *testing.T) {
	pool := newProjectionTestPool(t)
	checkpoints := projection.NewPostgresCheckpointStore(pool)
	ctx := context.Background()
	name := "checkpoint-" + t.Name()

	got, err := checkpoints.Get(ctx, name)
	if err != nil {
		t.Fatal(err)
	}
	if got != 0 {
		t.Fatalf("expected an empty checkpoint, got %d", got)
	}
	if err := checkpoints.Set(ctx, name, 12); err != nil {
		t.Fatal(err)
	}
	if err := checkpoints.Set(ctx, name, 15); err != nil {
		t.Fatal(err)
	}
	got, err = checkpoints.Get(ctx, name)
	if err != nil {
		t.Fatal(err)
	}
	if got != 15 {
		t.Fatalf("expected checkpoint 15, got %d", got)
	}
	if err := checkpoints.Reset(ctx, name); err != nil {
		t.Fatal(err)
	}
	got, err = checkpoints.Get(ctx, name)
	if err != nil {
		t.Fatal(err)
	}
	if got != 0 {
		t.Fatalf("expected reset checkpoint 0, got %d", got)
	}
}

func newProjectionTestPool(t *testing.T) *pgxpool.Pool {
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
