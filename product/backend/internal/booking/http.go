package booking

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
)

func writeBookingJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeBookingError(w http.ResponseWriter, status int, msg string) {
	writeBookingJSON(w, status, map[string]string{"error": msg})
}

func bookingHTTPStatus(err error) int {
	switch {
	case err == nil:
		return http.StatusOK
	case errors.Is(err, ErrInvalidInterval), errors.Is(err, ErrStartInPast):
		return http.StatusBadRequest
	case errors.Is(err, ErrNotOwner), errors.Is(err, ErrForbidden):
		return http.StatusForbidden
	case errors.Is(err, ErrBookingNotFound):
		return http.StatusNotFound
	case errors.Is(err, ErrDoubleBooking), errors.Is(err, ErrAlreadyCancelled):
		return http.StatusConflict
	default:
		return http.StatusInternalServerError
	}
}

// HandleListBookings returns active bookings in the optional range.
func HandleListBookings(svc *BookingService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeBookingError(w, http.StatusServiceUnavailable, "booking unavailable")
			return
		}
		from, to, err := parseRange(r)
		if err != nil {
			writeBookingError(w, http.StatusBadRequest, err.Error())
			return
		}
		bookings, err := svc.ListBookings(r.Context(), from, to)
		if err != nil {
			writeBookingError(w, bookingHTTPStatus(err), err.Error())
			return
		}
		out := make([]map[string]any, 0, len(bookings))
		for _, b := range bookings {
			out = append(out, bookingToMap(b))
		}
		writeBookingJSON(w, http.StatusOK, out)
	}
}

// HandleCreateBooking creates a booking for the authenticated user.
func HandleCreateBooking(svc *BookingService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeBookingError(w, http.StatusServiceUnavailable, "booking unavailable")
			return
		}
		email, ok := auth.FromContext(r.Context())
		if !ok {
			writeBookingError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		var body struct {
			Start time.Time `json:"start"`
			End   time.Time `json:"end"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeBookingError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		b, err := svc.CreateBooking(r.Context(), email, body.Start, body.End)
		if err != nil {
			writeBookingError(w, bookingHTTPStatus(err), err.Error())
			return
		}
		writeBookingJSON(w, http.StatusCreated, bookingToMap(b))
	}
}

// HandleCancelOwnBooking cancels the authenticated user's own booking.
func HandleCancelOwnBooking(svc *BookingService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeBookingError(w, http.StatusServiceUnavailable, "booking unavailable")
			return
		}
		email, ok := auth.FromContext(r.Context())
		if !ok {
			writeBookingError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		id := r.PathValue("id")
		if err := svc.CancelOwnBooking(r.Context(), email, id); err != nil {
			writeBookingError(w, bookingHTTPStatus(err), err.Error())
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func parseRange(r *http.Request) (*time.Time, *time.Time, error) {
	var from, to *time.Time
	if v := r.URL.Query().Get("from"); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err != nil {
			return nil, nil, errors.New("invalid from parameter")
		}
		from = &t
	}
	if v := r.URL.Query().Get("to"); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err != nil {
			return nil, nil, errors.New("invalid to parameter")
		}
		to = &t
	}
	return from, to, nil
}

func bookingToMap(b Booking) map[string]any {
	m := map[string]any{
		"id":         b.ID,
		"user_id":    b.UserID,
		"userId":     b.UserID,
		"start":      b.Start,
		"end":        b.End,
		"status":     string(b.Status),
		"created_at": b.CreatedAt,
		"createdAt":  b.CreatedAt,
	}
	if b.CancelledBy != nil {
		m["cancelled_by"] = *b.CancelledBy
		m["cancelledBy"] = *b.CancelledBy
	}
	if b.CancelledAt != nil {
		m["cancelled_at"] = *b.CancelledAt
		m["cancelledAt"] = *b.CancelledAt
	}
	return m
}
