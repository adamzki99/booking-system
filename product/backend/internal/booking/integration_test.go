package booking_test

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/booking"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

const testUserID = "00000000-0000-0000-0000-000000000001"

type bookingTestApp struct {
	pool     *pgxpool.Pool
	store    eventstore.Store
	app      *registry.Registry
	bookings *booking.BookingsProjection
	blocked  *booking.BlockedPeriodsProjection
}

func newBookingTestApp(t *testing.T) *bookingTestApp {
	t.Helper()
	ctx := context.Background()
	pool := newBookingTestPool(t)
	store := eventstore.NewPostgresStore(pool)
	app, err := registry.New(ctx, store, pool)
	if err != nil {
		t.Fatal(err)
	}
	users := user.Register(app)
	bookings, blocked := booking.Register(app, users)
	return &bookingTestApp{pool: pool, store: store, app: app, bookings: bookings, blocked: blocked}
}

func TestCreateBookingAppendsEventAndRow(t *testing.T) {
	ta := newBookingTestApp(t)
	ctx := context.Background()

	start := time.Now().Add(24 * time.Hour).Truncate(time.Second)
	end := start.Add(time.Hour)

	err := ta.app.Commands.Execute(ctx, booking.CreateBooking{
		ID:     "10000000-0000-0000-0000-000000000001",
		UserID: testUserID,
		Start:  start,
		End:    end,
	})
	if err != nil {
		t.Fatal(err)
	}

	var count int
	if err := ta.pool.QueryRow(ctx,
		`SELECT count(*) FROM bookings WHERE id = '10000000-0000-0000-0000-000000000001'`,
	).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("expected 1 booking row, got %d", count)
	}

	events, err := ta.store.LoadByAggregate(ctx, booking.AggregateType, "10000000-0000-0000-0000-000000000001")
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || events[0].EventType != booking.BookingCreatedEventType {
		t.Fatalf("expected one booking.created event, got %+v", events)
	}
}

func TestCreateBookingRejectsOverlap(t *testing.T) {
	ta := newBookingTestApp(t)
	ctx := context.Background()

	start := time.Now().Add(24 * time.Hour).Truncate(time.Second)

	if err := ta.app.Commands.Execute(ctx, booking.CreateBooking{
		ID:     "20000000-0000-0000-0000-000000000001",
		UserID: testUserID,
		Start:  start,
		End:    start.Add(time.Hour),
	}); err != nil {
		t.Fatal(err)
	}

	// Overlapping interval [start+30m, start+90m) must be rejected.
	err := ta.app.Commands.Execute(ctx, booking.CreateBooking{
		ID:     "20000000-0000-0000-0000-000000000002",
		UserID: testUserID,
		Start:  start.Add(30 * time.Minute),
		End:    start.Add(90 * time.Minute),
	})
	if !errors.Is(err, booking.ErrDoubleBooking) {
		t.Fatalf("expected ErrDoubleBooking, got %v", err)
	}

	// Adjacent interval [start+1h, start+2h) must be accepted.
	if err := ta.app.Commands.Execute(ctx, booking.CreateBooking{
		ID:     "20000000-0000-0000-0000-000000000003",
		UserID: testUserID,
		Start:  start.Add(time.Hour),
		End:    start.Add(2 * time.Hour),
	}); err != nil {
		t.Fatalf("adjacent booking should be accepted, got %v", err)
	}
}

func TestCancelOwnBookingFlipsStatusWithoutDeleting(t *testing.T) {
	ta := newBookingTestApp(t)
	ctx := context.Background()

	start := time.Now().Add(24 * time.Hour).Truncate(time.Second)
	id := "30000000-0000-0000-0000-000000000001"

	if err := ta.app.Commands.Execute(ctx, booking.CreateBooking{
		ID:     id,
		UserID: testUserID,
		Start:  start,
		End:    start.Add(time.Hour),
	}); err != nil {
		t.Fatal(err)
	}

	if err := ta.app.Commands.Execute(ctx, booking.CancelOwnBooking{
		BookingID: id,
		UserID:    testUserID,
	}); err != nil {
		t.Fatal(err)
	}

	var status string
	if err := ta.pool.QueryRow(ctx,
		`SELECT status FROM bookings WHERE id = $1`, id,
	).Scan(&status); err != nil {
		t.Fatal(err)
	}
	if status != "cancelled" {
		t.Fatalf("status = %q, want cancelled", status)
	}

	got, err := ta.bookings.GetByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	if got.Status != booking.StatusCancelled {
		t.Fatalf("projection status = %q, want cancelled", got.Status)
	}
	if got.CancelledBy == nil || *got.CancelledBy != testUserID {
		t.Fatalf("cancelled_by = %v", got.CancelledBy)
	}

	// Cancelling again must be rejected as already cancelled.
	err = ta.app.Commands.Execute(ctx, booking.CancelOwnBooking{BookingID: id, UserID: testUserID})
	if !errors.Is(err, booking.ErrAlreadyCancelled) {
		t.Fatalf("expected ErrAlreadyCancelled, got %v", err)
	}
}

func TestRebuildAllReproducesState(t *testing.T) {
	ta := newBookingTestApp(t)
	ctx := context.Background()

	start := time.Now().Add(24 * time.Hour).Truncate(time.Second)
	id := "40000000-0000-0000-0000-000000000001"

	if err := ta.app.Commands.Execute(ctx, booking.CreateBooking{
		ID:     id,
		UserID: testUserID,
		Start:  start,
		End:    start.Add(time.Hour),
	}); err != nil {
		t.Fatal(err)
	}

	before, err := ta.bookings.GetByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	if err := ta.app.Projections.RebuildAll(ctx); err != nil {
		t.Fatal(err)
	}
	after, err := ta.bookings.GetByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	if before.ID != after.ID || before.Status != after.Status || !before.Start.Equal(after.Start) || !before.End.Equal(after.End) {
		t.Fatalf("rebuilt read model differs:\nbefore: %+v\nafter:  %+v", before, after)
	}
}

func TestBlockTimePeriodBlocksBasicBookings(t *testing.T) {
	ta := newBookingTestApp(t)
	ctx := context.Background()

	superID := "00000000-0000-0000-0000-000000000002"
	basicID := "00000000-0000-0000-0000-000000000003"
	seedUser(t, ta.pool, superID, "super@example.com", "super")
	seedUser(t, ta.pool, basicID, "basic@example.com", "basic")

	from := time.Now().Add(24 * time.Hour).Truncate(time.Second)
	to := from.Add(2 * time.Hour)
	if err := ta.app.Commands.Execute(ctx, booking.BlockTimePeriod{
		From:        from,
		To:          to,
		RequesterID: superID,
	}); err != nil {
		t.Fatal(err)
	}

	periods, err := ta.blocked.List(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(periods) != 1 || !periods[0].Start.Equal(from) || !periods[0].End.Equal(to) {
		t.Fatalf("blocked periods = %+v", periods)
	}
	overlaps, err := ta.blocked.HasOverlap(ctx, from.Add(time.Minute), from.Add(2*time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	if !overlaps {
		t.Fatal("expected overlap inside blocked period")
	}

	// A basic user cannot book inside the blocked period.
	bookingID := "50000000-0000-0000-0000-000000000001"
	err = ta.app.Commands.Execute(ctx, booking.CreateBooking{
		ID:     bookingID,
		UserID: basicID,
		Start:  from.Add(time.Minute),
		End:    from.Add(90 * time.Minute),
	})
	if !errors.Is(err, booking.ErrBlockedPeriod) {
		t.Fatalf("expected ErrBlockedPeriod, got %v", err)
	}

	// A super user may book inside the blocked period.
	if err := ta.app.Commands.Execute(ctx, booking.CreateBooking{
		ID:     "50000000-0000-0000-0000-000000000002",
		UserID: superID,
		Start:  from.Add(time.Minute),
		End:    from.Add(90 * time.Minute),
	}); err != nil {
		t.Fatalf("expected super booking inside blocked period, got %v", err)
	}

	// A basic user may book outside the blocked period.
	if err := ta.app.Commands.Execute(ctx, booking.CreateBooking{
		ID:     "50000000-0000-0000-0000-000000000003",
		UserID: basicID,
		Start:  to.Add(time.Hour),
		End:    to.Add(2 * time.Hour),
	}); err != nil {
		t.Fatalf("expected booking outside blocked period, got %v", err)
	}
}

func seedUser(t *testing.T, pool *pgxpool.Pool, id, email, role string) {
	t.Helper()
	ctx := context.Background()
	if _, err := pool.Exec(ctx,
		`INSERT INTO users (id, email, role, address, active, created_at, updated_at)
		 VALUES ($1, $2, $3, '', true, now(), now())
		 ON CONFLICT (id) DO NOTHING`,
		id, email, role,
	); err != nil {
		t.Fatal(err)
	}
}

func newBookingTestPool(t *testing.T) *pgxpool.Pool {
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
