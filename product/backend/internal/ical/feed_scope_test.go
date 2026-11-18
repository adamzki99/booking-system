package ical

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/booking"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/jackc/pgx/v5/pgxpool"
)

// listBookingsFake implements the feed's BookingsReader seam. It records the
// range arguments and returns a fixed set of bookings.
type listBookingsFake struct {
	bookings []booking.Booking
	calls    int
	from, to *time.Time
}

func (f *listBookingsFake) List(_ context.Context, from, to *time.Time) ([]booking.Booking, error) {
	f.calls++
	f.from, f.to = from, to
	return f.bookings, nil
}

// newFeedTokenFixture migrates the database, clears the read models used here,
// and inserts one valid token. It returns the pool and the plaintext token.
func newFeedTokenFixture(t *testing.T) (*pgxpool.Pool, string) {
	t.Helper()
	pool := newHTTPTestPool(t)
	ctx := context.Background()
	if err := eventstore.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `TRUNCATE bookings, calendar_tokens`); err != nil {
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
	return pool, token
}

func feedCreateEvent(id, userID string, start time.Time) eventstore.Event {
	payload, _ := json.Marshal(booking.BookingCreatedPayload{
		BookingID: id,
		UserID:    userID,
		Start:     start,
		End:       start.Add(time.Hour),
		CreatedAt: start.Add(-24 * time.Hour),
	})
	return eventstore.Event{
		AggregateType: booking.AggregateType,
		AggregateID:   id,
		EventType:     booking.BookingCreatedEventType,
		Payload:       payload,
		OccurredAt:    start.Add(-24 * time.Hour),
	}
}

func feedCancelEvent(id, userID string, at time.Time) eventstore.Event {
	payload, _ := json.Marshal(booking.BookingCancelledPayload{
		BookingID:   id,
		CancelledBy: userID,
		CancelledAt: at,
	})
	return eventstore.Event{
		AggregateType: booking.AggregateType,
		AggregateID:   id,
		EventType:     booking.BookingCancelledEventType,
		Payload:       payload,
		OccurredAt:    at,
	}
}

// TestHandleFeedReturnsSharedActiveBookings proves the feed serves the shared
// booking calendar: every active booking from the reader is emitted, with no
// per-user filter and no time range.
func TestHandleFeedReturnsSharedActiveBookings(t *testing.T) {
	pool, token := newFeedTokenFixture(t)
	start := time.Date(2030, 1, 2, 10, 0, 0, 0, time.UTC)
	reader := &listBookingsFake{bookings: []booking.Booking{
		{ID: "aaaaaaaa-0000-0000-0000-000000000001", Status: booking.StatusActive, Start: start, End: start.Add(time.Hour)},
		{ID: "aaaaaaaa-0000-0000-0000-000000000002", Status: booking.StatusActive, Start: start.Add(2 * time.Hour), End: start.Add(3 * time.Hour)},
	}}

	rec := getFeed(HandleFeed(NewCalendarTokenProjection(pool), reader, nil, nil), "/calendar/"+token+".ics")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.Contains(ct, "text/calendar") {
		t.Fatalf("Content-Type = %q, want text/calendar", ct)
	}
	body := rec.Body.String()
	for _, want := range []string{
		"BEGIN:VCALENDAR", "VERSION:2.0",
		"UID:aaaaaaaa-0000-0000-0000-000000000001",
		"UID:aaaaaaaa-0000-0000-0000-000000000002",
		"STATUS:CONFIRMED",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("feed body missing %q:\n%s", want, body)
		}
	}
	if reader.calls != 1 {
		t.Fatalf("reader calls = %d, want 1", reader.calls)
	}
	if reader.from != nil || reader.to != nil {
		t.Fatalf("reader range = (%v, %v), want unbounded (nil, nil)", reader.from, reader.to)
	}
}

// TestHandleFeedRejectsInvalidTokenWithoutListing proves an invalid token gets
// a non-calendar error and never queries bookings.
func TestHandleFeedRejectsInvalidTokenWithoutListing(t *testing.T) {
	pool, _ := newFeedTokenFixture(t)
	reader := &listBookingsFake{}

	rec := getFeed(HandleFeed(NewCalendarTokenProjection(pool), reader, nil, nil), "/calendar/not-a-token.ics")
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
	if ct := rec.Header().Get("Content-Type"); strings.Contains(ct, "text/calendar") {
		t.Fatalf("Content-Type = %q, want non-calendar error", ct)
	}
	if reader.calls != 0 {
		t.Fatalf("reader calls = %d, want 0 for invalid token", reader.calls)
	}
}

// TestHandleFeedReflectsCancellationOnRefresh proves a cancelled booking drops
// out of the shared calendar on the next feed fetch.
func TestHandleFeedReflectsCancellationOnRefresh(t *testing.T) {
	pool, token := newFeedTokenFixture(t)
	ctx := context.Background()
	projection := booking.NewBookingsProjection(pool)
	const activeID = "bbbbbbbb-0000-0000-0000-000000000001"
	const cancelID = "bbbbbbbb-0000-0000-0000-000000000002"
	const userID = "cccccccc-0000-0000-0000-000000000001"
	start := time.Date(2030, 2, 3, 10, 0, 0, 0, time.UTC)

	if err := projection.Apply(ctx, feedCreateEvent(activeID, userID, start)); err != nil {
		t.Fatal(err)
	}
	if err := projection.Apply(ctx, feedCreateEvent(cancelID, userID, start.Add(2*time.Hour))); err != nil {
		t.Fatal(err)
	}

	h := HandleFeed(NewCalendarTokenProjection(pool), projection, nil, nil)
	rec := getFeed(h, "/calendar/"+token+".ics")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	body := rec.Body.String()
	if !strings.Contains(body, "UID:"+activeID) || !strings.Contains(body, "UID:"+cancelID) {
		t.Fatalf("initial feed missing a booking:\n%s", body)
	}

	if err := projection.Apply(ctx, feedCancelEvent(cancelID, userID, start.Add(12*time.Hour))); err != nil {
		t.Fatal(err)
	}

	rec = getFeed(h, "/calendar/"+token+".ics")
	body = rec.Body.String()
	if rec.Code != http.StatusOK {
		t.Fatalf("status after cancel = %d, want %d", rec.Code, http.StatusOK)
	}
	if !strings.Contains(body, "UID:"+activeID) {
		t.Fatalf("feed after cancel missing active booking:\n%s", body)
	}
	if strings.Contains(body, "UID:"+cancelID) {
		t.Fatalf("feed after cancel still contains cancelled booking:\n%s", body)
	}

	list, err := projection.List(ctx, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 || list[0].ID != activeID {
		t.Fatalf("projection.List = %+v, want only %s", list, activeID)
	}
}
