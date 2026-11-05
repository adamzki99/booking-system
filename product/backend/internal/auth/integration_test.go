package auth_test

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/ratelimit"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

type testApp struct {
	pool    *pgxpool.Pool
	sender  *fakeSender
	service *auth.AuthService
}

func newTestApp(t *testing.T) *testApp {
	t.Helper()
	ctx := context.Background()
	pool := newAuthTestPool(t)
	store := eventstore.NewPostgresStore(pool)
	app, err := registry.New(ctx, store, pool)
	if err != nil {
		t.Fatal(err)
	}
	auth.Register(app)
	sender := &fakeSender{}
	service := auth.NewService(app.Commands, sender, ratelimit.NewLimiter())
	return &testApp{pool: pool, sender: sender, service: service}
}

func TestRequestCodeCreatesLoginCodeRow(t *testing.T) {
	ta := newTestApp(t)
	ctx := context.Background()

	if err := ta.service.RequestCode(ctx, "alice@example.com", "1.2.3.4"); err != nil {
		t.Fatal(err)
	}

	var count int
	if err := ta.pool.QueryRow(ctx,
		`SELECT count(*) FROM login_codes WHERE email = 'alice@example.com'`,
	).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("expected 1 login code row, got %d", count)
	}
}

func TestVerifyCreatesSessionAndConsumesCode(t *testing.T) {
	ta := newTestApp(t)
	ctx := context.Background()

	if err := ta.service.RequestCode(ctx, "alice@example.com", "1.2.3.4"); err != nil {
		t.Fatal(err)
	}
	code := ta.sender.body
	if code == "" {
		t.Fatal("no code emailed")
	}

	token, err := ta.service.Verify(ctx, "alice@example.com", code, "1.2.3.4")
	if err != nil {
		t.Fatal(err)
	}
	if token == "" {
		t.Fatal("expected a session token")
	}

	var email string
	if err := ta.pool.QueryRow(ctx,
		`SELECT email FROM sessions WHERE token_hash = $1`, auth.HashToken(token),
	).Scan(&email); err != nil {
		t.Fatal(err)
	}
	if email != "alice@example.com" {
		t.Fatalf("session email = %q", email)
	}

	var consumed bool
	if err := ta.pool.QueryRow(ctx,
		`SELECT (consumed_at IS NOT NULL) FROM login_codes WHERE email = 'alice@example.com'`,
	).Scan(&consumed); err != nil {
		t.Fatal(err)
	}
	if !consumed {
		t.Fatal("expected login code to be consumed")
	}
}

func TestVerifyRejectsInvalidCode(t *testing.T) {
	ta := newTestApp(t)
	ctx := context.Background()

	if err := ta.service.RequestCode(ctx, "alice@example.com", "1.2.3.4"); err != nil {
		t.Fatal(err)
	}
	wrong := "AAAAAA"
	if wrong == ta.sender.body {
		wrong = "BBBBBB"
	}

	_, err := ta.service.Verify(ctx, "alice@example.com", wrong, "1.2.3.4")
	if !errors.Is(err, auth.ErrInvalidOrExpiredCode) {
		t.Fatalf("expected ErrInvalidOrExpiredCode, got %v", err)
	}
}

func TestVerifyRejectsExpiredCode(t *testing.T) {
	ta := newTestApp(t)
	ctx := context.Background()

	if err := ta.service.RequestCode(ctx, "alice@example.com", "1.2.3.4"); err != nil {
		t.Fatal(err)
	}
	if _, err := ta.pool.Exec(ctx,
		`UPDATE login_codes SET expires_at = now() - interval '1 minute' WHERE email = 'alice@example.com'`,
	); err != nil {
		t.Fatal(err)
	}

	_, err := ta.service.Verify(ctx, "alice@example.com", ta.sender.body, "1.2.3.4")
	if !errors.Is(err, auth.ErrInvalidOrExpiredCode) {
		t.Fatalf("expected ErrInvalidOrExpiredCode, got %v", err)
	}
}

func TestVerifyRejectsReplayedCode(t *testing.T) {
	ta := newTestApp(t)
	ctx := context.Background()

	if err := ta.service.RequestCode(ctx, "alice@example.com", "1.2.3.4"); err != nil {
		t.Fatal(err)
	}
	code := ta.sender.body
	if _, err := ta.service.Verify(ctx, "alice@example.com", code, "1.2.3.4"); err != nil {
		t.Fatal(err)
	}

	if _, err := ta.service.Verify(ctx, "alice@example.com", code, "1.2.3.4"); !errors.Is(err, auth.ErrInvalidOrExpiredCode) {
		t.Fatalf("expected ErrInvalidOrExpiredCode on replay, got %v", err)
	}
}

func TestRequestCodeRateLimited(t *testing.T) {
	ta := newTestApp(t)
	ctx := context.Background()

	for i := 0; i < 5; i++ {
		if err := ta.service.RequestCode(ctx, "alice@example.com", "1.2.3.4"); err != nil {
			t.Fatalf("request %d: %v", i+1, err)
		}
	}
	if err := ta.service.RequestCode(ctx, "alice@example.com", "1.2.3.4"); !errors.Is(err, auth.ErrRateLimited) {
		t.Fatalf("expected ErrRateLimited, got %v", err)
	}
}

func TestVerifyRateLimited(t *testing.T) {
	ta := newTestApp(t)
	ctx := context.Background()

	for i := 0; i < 10; i++ {
		if _, err := ta.service.Verify(ctx, "alice@example.com", "AAAAAA", "1.2.3.4"); errors.Is(err, auth.ErrRateLimited) {
			t.Fatalf("attempt %d unexpectedly rate limited", i+1)
		}
	}
	if _, err := ta.service.Verify(ctx, "alice@example.com", "AAAAAA", "1.2.3.4"); !errors.Is(err, auth.ErrRateLimited) {
		t.Fatalf("expected ErrRateLimited, got %v", err)
	}
}

func newAuthTestPool(t *testing.T) *pgxpool.Pool {
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
