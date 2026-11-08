package ical

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/ratelimit"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

// newHTTPTestPool provides a migrated database; DATABASE_URL takes precedence
// when set.
func newHTTPTestPool(t *testing.T) *pgxpool.Pool {
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
	t.Cleanup(pool.Close)
	return pool
}

func getFeed(h http.HandlerFunc, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	rec := httptest.NewRecorder()
	h(rec, req)
	return rec
}

func TestHandleFeedRateLimiting(t *testing.T) {
	pool := newHTTPTestPool(t)
	if err := eventstore.Migrate(context.Background(), pool); err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	if _, err := pool.Exec(ctx, `TRUNCATE calendar_tokens`); err != nil {
		t.Fatal(err)
	}

	token, hash, err := GenerateToken()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO calendar_tokens (user_id, token_hash) VALUES (gen_random_uuid(), $1)`, hash,
	); err != nil {
		t.Fatal(err)
	}

	// A valid token is limited to 10 requests per 15-minute window: the 11th
	// request in quick succession must be rejected.
	t.Run("limits repeated requests per token", func(t *testing.T) {
		h := HandleFeed(NewCalendarTokenProjection(pool), nil, ratelimit.NewLimiter())
		for i := 0; i < 10; i++ {
			if code := getFeed(h, "/calendar/"+token+".ics").Code; code != http.StatusOK {
				t.Fatalf("request %d status = %d, want %d", i+1, code, http.StatusOK)
			}
		}
		if code := getFeed(h, "/calendar/"+token+".ics").Code; code != http.StatusTooManyRequests {
			t.Fatalf("11th request status = %d, want %d", code, http.StatusTooManyRequests)
		}
	})

	// Invalid tokens are still limited: distinct unknown tokens avoid the
	// per-token key, so 30 requests (per IP per hour) succeed as repeated
	// 404s before the IP limit rejects the 31st.
	t.Run("limits repeated requests per IP", func(t *testing.T) {
		h := HandleFeed(NewCalendarTokenProjection(pool), nil, ratelimit.NewLimiter())
		for i := 0; i < 30; i++ {
			path := fmt.Sprintf("/calendar/unknown-token-%d.ics", i)
			if code := getFeed(h, path).Code; code != http.StatusNotFound {
				t.Fatalf("request %d status = %d, want %d", i+1, code, http.StatusNotFound)
			}
		}
		if code := getFeed(h, "/calendar/unknown-token-30.ics").Code; code != http.StatusTooManyRequests {
			t.Fatalf("31st request status = %d, want %d", code, http.StatusTooManyRequests)
		}
	})

	// Backward compatibility: a nil limiter disables rate limiting entirely.
	t.Run("nil limiter disables limiting", func(t *testing.T) {
		h := HandleFeed(NewCalendarTokenProjection(pool), nil, nil)
		for i := 0; i < 15; i++ {
			if code := getFeed(h, "/calendar/"+token+".ics").Code; code != http.StatusOK {
				t.Fatalf("request %d status = %d, want %d", i+1, code, http.StatusOK)
			}
		}
	})
}
