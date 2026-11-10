package e2e

import (
	"context"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/booking"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/ratelimit"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
	"github.com/adamzki99/booking-system/product/backend/internal/server"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

const (
	basicEmail = "basic@example.com"
	superEmail = "super@example.com"
)

type e2eApp struct {
	Server *httptest.Server
	Sender *captureSender
	Pool   *pgxpool.Pool
}

func newE2EApp(t *testing.T) *e2eApp {
	t.Helper()
	ctx := context.Background()
	pool := newE2EPool(t)
	store := eventstore.NewPostgresStore(pool)
	app, err := registry.New(ctx, store, pool)
	if err != nil {
		t.Fatal(err)
	}
	authProj := auth.Register(app)
	users := user.Register(app)
	sender := &captureSender{}
	bookings, blocked := booking.Register(app, users, nil)
	booking.RegisterNotify(app, sender, users, bookings, slog.Default())
	userService := user.NewService(app.Commands, users)
	bookingService := booking.NewService(app.Commands, bookings, users, blocked)
	authService := auth.NewService(app.Commands, sender, ratelimit.NewLimiter())
	if err := app.Projections.CatchUp(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := userService.SeedUsers(ctx, []user.SeedUser{
		{Email: basicEmail, Role: user.RoleBasic},
		{Email: superEmail, Role: user.RoleSuper},
	}); err != nil {
		t.Fatal(err)
	}
	deps := server.Deps{
		Auth:           authService,
		Middleware:     auth.NewSessionMiddleware(authProj.Sessions),
		UserService:    userService,
		BookingService: bookingService,
		Bookings:       bookings,
	}
	mux := server.NewMux(deps)
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return &e2eApp{Server: ts, Sender: sender, Pool: pool}
}

func newE2EPool(t *testing.T) *pgxpool.Pool {
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

var _ = http.StatusOK
