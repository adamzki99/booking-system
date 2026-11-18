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

type bookingReader interface {
	GetByID(ctx context.Context, id string) (booking.Booking, error)
}

type e2eApp struct {
	Server         *httptest.Server
	Sender         *captureSender
	Pool           *pgxpool.Pool
	Outbox         notification.Store
	Worker         *notification.Worker
	DeliverySender *flakySender
	Bookings       bookingReader
}

// DrainNotifications runs outbox worker passes until no due deliveries remain.
// It makes email assertions deterministic now that delivery is asynchronous.
func (a *e2eApp) DrainNotifications(t *testing.T) {
	t.Helper()
	for i := 0; i < 20; i++ {
		stats, err := a.Worker.ProcessOnce(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if stats.Claimed == 0 {
			return
		}
	}
	t.Fatal("notifications did not drain")
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
	delivery := &flakySender{delegate: sender}
	outbox := notification.NewMemoryStore()
	bookings, blocked := booking.Register(app, users, nil)
	booking.RegisterNotify(app, outbox, users, bookings, slog.Default())
	broadcast.Register(app, users)
	broadcast.RegisterNotify(app, outbox, users, slog.Default())
	worker := notification.NewWorker(outbox, delivery, slog.Default(), notification.Policy{
		MaxAttempts: 5,
		BaseDelay:   time.Nanosecond,
	})
	userService := user.NewService(app.Commands, users, sender, nil)
	bookingService := booking.NewService(app.Commands, bookings, users, blocked)
	broadcastService := broadcast.NewService(app.Commands, users)
	authService := auth.NewService(app.Commands, sender, ratelimit.NewLimiter(), users)
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
		Middleware:       auth.NewSessionMiddleware(authProj.Sessions, users),
		UserService:      userService,
		BookingService:   bookingService,
		BroadcastService: broadcastService,
		Bookings:         bookings,
	}
	mux := server.NewMux(deps)
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return &e2eApp{
		Server:         ts,
		Sender:         sender,
		Pool:           pool,
		Outbox:         outbox,
		Worker:         worker,
		DeliverySender: delivery,
		Bookings:       bookings,
	}
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
