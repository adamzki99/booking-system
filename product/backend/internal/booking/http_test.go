package booking

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

func newTestService(exec *fakeExecutor, bookings *fakeBookingsReader, users *fakeUserResolver) *BookingService {
	return NewService(exec, bookings, users, nil)
}

func aliceResolver() *fakeUserResolver {
	return &fakeUserResolver{byEmail: map[string]user.User{
		"alice@example.com": {ID: "user-1", Email: "alice@example.com"},
	}}
}

func TestHandleCreateBookingCreated(t *testing.T) {
	bookings := &fakeBookingsReader{
		getByIDFunc: func(id string) (Booking, error) {
			return Booking{ID: id, UserID: "user-1", Status: StatusActive}, nil
		},
	}
	svc := newTestService(&fakeExecutor{}, bookings, aliceResolver())

	body := `{"start":"2026-12-01T10:00:00Z","end":"2026-12-01T11:00:00Z"}`
	req := httptest.NewRequest(http.MethodPost, "/bookings", strings.NewReader(body))
	req = req.WithContext(auth.WithEmail(req.Context(), "alice@example.com"))
	rec := httptest.NewRecorder()

	HandleCreateBooking(svc)(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want %d (body %s)", rec.Code, http.StatusCreated, rec.Body.String())
	}
	var out map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if out["id"] == "" || out["status"] != "active" {
		t.Fatalf("body = %s", rec.Body.String())
	}
}

func TestHandleCreateBookingUnauthorized(t *testing.T) {
	svc := newTestService(&fakeExecutor{}, &fakeBookingsReader{}, aliceResolver())

	body := `{"start":"2026-12-01T10:00:00Z","end":"2026-12-01T11:00:00Z"}`
	req := httptest.NewRequest(http.MethodPost, "/bookings", strings.NewReader(body))
	rec := httptest.NewRecorder()

	HandleCreateBooking(svc)(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusUnauthorized)
	}
}

func TestHandleCreateBookingConflict(t *testing.T) {
	bookings := &fakeBookingsReader{}
	svc := newTestService(&fakeExecutor{err: ErrDoubleBooking}, bookings, aliceResolver())

	body := `{"start":"2026-12-01T10:00:00Z","end":"2026-12-01T11:00:00Z"}`
	req := httptest.NewRequest(http.MethodPost, "/bookings", strings.NewReader(body))
	req = req.WithContext(auth.WithEmail(req.Context(), "alice@example.com"))
	rec := httptest.NewRecorder()

	HandleCreateBooking(svc)(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusConflict)
	}
}

func TestHandleCreateBookingBadRequest(t *testing.T) {
	svc := newTestService(&fakeExecutor{}, &fakeBookingsReader{}, aliceResolver())

	req := httptest.NewRequest(http.MethodPost, "/bookings", strings.NewReader(`not json`))
	req = req.WithContext(auth.WithEmail(req.Context(), "alice@example.com"))
	rec := httptest.NewRecorder()

	HandleCreateBooking(svc)(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

func TestHandleCancelOwnBookingNoContent(t *testing.T) {
	bookings := &fakeBookingsReader{
		getByIDFunc: func(id string) (Booking, error) {
			return Booking{ID: id, UserID: "user-1", Status: StatusActive}, nil
		},
	}
	svc := newTestService(&fakeExecutor{}, bookings, aliceResolver())

	req := httptest.NewRequest(http.MethodPost, "/bookings/booking-1/cancel", nil)
	req.SetPathValue("id", "booking-1")
	req = req.WithContext(auth.WithEmail(req.Context(), "alice@example.com"))
	rec := httptest.NewRecorder()

	HandleCancelBooking(svc)(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusNoContent)
	}
}

func TestHandleCancelBookingForbidden(t *testing.T) {
	bookings := &fakeBookingsReader{
		getByIDFunc: func(id string) (Booking, error) {
			return Booking{ID: id, UserID: "user-1", Status: StatusActive}, nil
		},
	}
	svc := newTestService(&fakeExecutor{err: ErrNotOwner}, bookings, aliceResolver())

	req := httptest.NewRequest(http.MethodPost, "/bookings/booking-1/cancel", nil)
	req.SetPathValue("id", "booking-1")
	req = req.WithContext(auth.WithEmail(req.Context(), "alice@example.com"))
	rec := httptest.NewRecorder()

	HandleCancelBooking(svc)(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusForbidden)
	}
}

func TestHandleCancelBookingAsSuperCancelsAny(t *testing.T) {
	exec := &fakeExecutor{}
	users := &fakeUserResolver{byEmail: map[string]user.User{
		"super@example.com": {ID: "super-1", Email: "super@example.com", Role: user.RoleSuper},
	}}
	bookings := &fakeBookingsReader{
		getByIDFunc: func(id string) (Booking, error) {
			return Booking{ID: id, UserID: "user-1", Status: StatusActive}, nil
		},
	}
	svc := newTestService(exec, bookings, users)

	req := httptest.NewRequest(http.MethodPost, "/bookings/booking-1/cancel", nil)
	req.SetPathValue("id", "booking-1")
	req = req.WithContext(auth.WithEmail(req.Context(), "super@example.com"))
	rec := httptest.NewRecorder()

	HandleCancelBooking(svc)(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want %d (body %s)", rec.Code, http.StatusNoContent, rec.Body.String())
	}
	cancel, ok := exec.last.(CancelAnyBooking)
	if !ok {
		t.Fatalf("expected CancelAnyBooking command, got %T", exec.last)
	}
	if cancel.BookingID != "booking-1" || cancel.RequesterID != "super-1" {
		t.Fatalf("command = %+v", cancel)
	}
}

func TestHandleCancelBookingRejectsForeignBooking(t *testing.T) {
	users := &fakeUserResolver{byEmail: map[string]user.User{
		"charlie@example.com": {ID: "user-2", Email: "charlie@example.com", Role: user.RoleBasic},
	}}
	bookings := &fakeBookingsReader{
		getByIDFunc: func(id string) (Booking, error) {
			return Booking{ID: id, UserID: "user-1", Status: StatusActive}, nil
		},
	}
	svc := newTestService(&fakeExecutor{}, bookings, users)

	req := httptest.NewRequest(http.MethodPost, "/bookings/booking-1/cancel", nil)
	req.SetPathValue("id", "booking-1")
	req = req.WithContext(auth.WithEmail(req.Context(), "charlie@example.com"))
	rec := httptest.NewRecorder()

	HandleCancelBooking(svc)(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want %d (body %s)", rec.Code, http.StatusForbidden, rec.Body.String())
	}
}

func TestHandleBlockTimePeriodCreated(t *testing.T) {
	exec := &fakeExecutor{}
	users := superByEmail()
	bookings := &fakeBookingsReader{byID: map[string]Booking{}}
	blocked := &fakeBlockedReader{}
	svc := NewService(exec, bookings, users, blocked)

	body := `{"start":"2026-12-01T10:00:00Z","end":"2026-12-01T12:00:00Z"}`
	req := httptest.NewRequest(http.MethodPost, "/blocked-periods", strings.NewReader(body))
	req = req.WithContext(auth.WithEmail(req.Context(), "super@example.com"))
	rec := httptest.NewRecorder()

	HandleBlockTimePeriod(svc)(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want %d (body %s)", rec.Code, http.StatusCreated, rec.Body.String())
	}
	cmd, ok := exec.last.(BlockTimePeriod)
	if !ok {
		t.Fatalf("expected BlockTimePeriod command, got %T", exec.last)
	}
	if cmd.RequesterID != "super-1" {
		t.Fatalf("command = %+v", cmd)
	}
}

func TestHandleBlockTimePeriodForbidden(t *testing.T) {
	svc := NewService(&fakeExecutor{}, &fakeBookingsReader{byID: map[string]Booking{}}, basicByEmail(), &fakeBlockedReader{})

	body := `{"start":"2026-12-01T10:00:00Z","end":"2026-12-01T12:00:00Z"}`
	req := httptest.NewRequest(http.MethodPost, "/blocked-periods", strings.NewReader(body))
	req = req.WithContext(auth.WithEmail(req.Context(), "basic@example.com"))
	rec := httptest.NewRecorder()

	HandleBlockTimePeriod(svc)(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want %d (body %s)", rec.Code, http.StatusForbidden, rec.Body.String())
	}
}

func TestHandleListBlockedPeriods(t *testing.T) {
	svc := NewService(&fakeExecutor{}, &fakeBookingsReader{}, aliceResolver(), &fakeBlockedReader{list: []BlockedPeriod{
		{ID: "p1", BlockedBy: "super-1"},
	}})

	req := httptest.NewRequest(http.MethodGet, "/blocked-periods", nil)
	req = req.WithContext(auth.WithEmail(req.Context(), "alice@example.com"))
	rec := httptest.NewRecorder()

	HandleListBlockedPeriods(svc)(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d (body %s)", rec.Code, http.StatusOK, rec.Body.String())
	}
	var out []map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if len(out) != 1 || out[0]["id"] != "p1" {
		t.Fatalf("body = %s", rec.Body.String())
	}
}

func TestHandleListBookings(t *testing.T) {
	bookings := &fakeBookingsReader{list: []Booking{
		{ID: "b1", UserID: "user-1", Start: time.Now(), End: time.Now().Add(time.Hour), Status: StatusActive},
	}}
	svc := newTestService(&fakeExecutor{}, bookings, aliceResolver())

	req := httptest.NewRequest(http.MethodGet, "/bookings", nil)
	req = req.WithContext(auth.WithEmail(req.Context(), "alice@example.com"))
	rec := httptest.NewRecorder()

	HandleListBookings(svc)(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	var out []map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if len(out) != 1 || out[0]["id"] != "b1" {
		t.Fatalf("body = %s", rec.Body.String())
	}
}

func TestHandleListBookingsBadRange(t *testing.T) {
	svc := newTestService(&fakeExecutor{}, &fakeBookingsReader{}, aliceResolver())

	req := httptest.NewRequest(http.MethodGet, "/bookings?from=not-a-time", nil)
	req = req.WithContext(auth.WithEmail(req.Context(), "alice@example.com"))
	rec := httptest.NewRecorder()

	HandleListBookings(svc)(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

func TestBookingHTTPStatus(t *testing.T) {
	cases := []struct {
		err  error
		want int
	}{
		{nil, http.StatusOK},
		{ErrInvalidInterval, http.StatusBadRequest},
		{ErrStartInPast, http.StatusBadRequest},
		{ErrNotOwner, http.StatusForbidden},
		{ErrForbidden, http.StatusForbidden},
		{ErrBookingNotFound, http.StatusNotFound},
		{ErrDoubleBooking, http.StatusConflict},
		{ErrAlreadyCancelled, http.StatusConflict},
		{context.Canceled, http.StatusInternalServerError},
	}
	for _, c := range cases {
		if got := bookingHTTPStatus(c.err); got != c.want {
			t.Fatalf("bookingHTTPStatus(%v) = %d, want %d", c.err, got, c.want)
		}
	}
}
