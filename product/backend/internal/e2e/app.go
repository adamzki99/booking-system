package e2e

import (
	"context"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/booking"
	"github.com/adamzki99/booking-system/product/backend/internal/broadcast"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/notification"
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
	Store  eventstore.Store
	Worker *notification.Worker
	t      *testing.T
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
	outbox := notification.NewPostgresStore(pool)
	booking.RegisterNotify(app, outbox, users, bookings, slog.Default())
	broadcast.Register(app, users)
	broadcast.RegisterNotify(app, outbox, users, slog.Default())
	// Tiny backoff keeps deterministic drains fast while still exercising the
	// real retry path against the durable store.
	worker := notification.NewWorker(outbox, sender, slog.Default(), notification.Policy{
		MaxAttempts: 5,
		BaseDelay:   time.Nanosecond,
		MaxDelay:    time.Microsecond,
	})
	userService := user.NewService(app.Commands, users, sender, nil)
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
		Auth:             authService,
		Middleware:       auth.NewSessionMiddleware(authProj.Sessions),
		UserService:      userService,
		BookingService:   bookingService,
		BroadcastService: broadcast.NewService(app.Commands, users),
		Bookings:         bookings,
	}
	mux := server.NewMux(deps)
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return &e2eApp{Server: ts, Sender: sender, Pool: pool, Store: store, Worker: worker, t: t}
}

// DrainNotifications runs the worker until no delivery work remains. Tests
// call it after an action that enqueues booking or broadcast mail.
func (a *e2eApp) DrainNotifications(ctx context.Context) {
	a.t.Helper()
	for pass := 0; pass < 20; pass++ {
		stats, err := a.Worker.ProcessOnce(ctx)
		if err != nil {
			a.t.Fatal(err)
		}
		if stats.Sent+stats.Retried+stats.Failed == 0 {
			return
		}
	}
	a.t.Fatal("notification worker did not drain within 20 passes")
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
