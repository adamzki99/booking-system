// Package server wires the sidecar HTTP API.
package server

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/adamzki99/booking-system/projects/sauna/sidecar/internal/config"
	"github.com/adamzki99/booking-system/projects/sauna/sidecar/internal/rules"
)

// Deps holds the dependencies required by the HTTP server. The sidecar is
// stateless, so this is intentionally small.
type Deps struct {
	// Timezone is the IANA timezone name used for the single-day rule.
	Timezone string
	// Capacity is the max concurrent overlapping bookings.
	Capacity int
}

// NewMux builds the HTTP router.
func NewMux(deps ...Deps) *http.ServeMux {
	loc := bookingLocation(deps...)
	capacity := 1
	if len(deps) > 0 && deps[0].Capacity != 0 {
		capacity = deps[0].Capacity
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", handleHealthz)
	mux.HandleFunc("GET /functions/chrome", handleChrome)
	mux.HandleFunc("POST /functions/echo", handleEcho)
	mux.HandleFunc("POST /functions/validate-booking", handleValidateBooking(loc, capacity))
	return mux
}

// New creates an *http.Server wired with sensible timeouts.
func New(cfg config.Config, logger *slog.Logger, deps ...Deps) *http.Server {
	if len(deps) == 0 {
		deps = []Deps{{Timezone: cfg.BookingTimezone, Capacity: cfg.Capacity}}
	} else if deps[0].Timezone == "" {
		deps[0].Timezone = cfg.BookingTimezone
	}
	if len(deps) > 0 && deps[0].Capacity == 0 {
		deps[0].Capacity = cfg.Capacity
		if deps[0].Capacity == 0 {
			deps[0].Capacity = 1
		}
	}
	return &http.Server{
		Addr:         ":" + strconv.Itoa(cfg.Port),
		Handler:      NewMux(deps...),
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
		ErrorLog:     slog.NewLogLogger(logger.Handler(), slog.LevelError),
	}
}

func handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type echoRequest struct {
	Input string `json:"input"`
}

type echoResponse struct {
	Result string `json:"result"`
}

func handleEcho(w http.ResponseWriter, r *http.Request) {
	var req echoRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Input == "" {
		writeError(w, http.StatusBadRequest, "input is required")
		return
	}
	writeJSON(w, http.StatusOK, echoResponse{Result: req.Input})
}

type validateBookingExisting struct {
	ID    string `json:"id"`
	Start string `json:"start"`
	End   string `json:"end"`
}

type validateBookingRequest struct {
	Start    string                    `json:"start"`
	End      string                    `json:"end"`
	Capacity int                       `json:"capacity"`
	Existing []validateBookingExisting `json:"existing"`
}

type validateBookingResponse struct {
	Allowed bool   `json:"allowed"`
	Code    string `json:"code,omitempty"`
	Message string `json:"message,omitempty"`
}

func handleValidateBooking(loc *time.Location, defaultCapacity int) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req validateBookingRequest
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		if req.Start == "" || req.End == "" {
			writeError(w, http.StatusBadRequest, "start and end are required")
			return
		}
		start, err1 := time.Parse(time.RFC3339, req.Start)
		end, err2 := time.Parse(time.RFC3339, req.End)
		if err1 != nil || err2 != nil {
			writeError(w, http.StatusBadRequest, "invalid start or end time")
			return
		}
		if !start.Before(end) {
			writeError(w, http.StatusBadRequest, "start must be before end")
			return
		}
		if start.In(loc).Format("2006-01-02") != end.In(loc).Format("2006-01-02") {
			writeError(w, http.StatusBadRequest, "booking must be within a single day")
			return
		}

		capacity := defaultCapacity
		if req.Capacity != 0 {
			capacity = req.Capacity
		}

		candidate := rules.Interval{Start: start, End: end}
		existing := make([]rules.Interval, 0, len(req.Existing))
		for _, e := range req.Existing {
			es, err1 := time.Parse(time.RFC3339, e.Start)
			ee, err2 := time.Parse(time.RFC3339, e.End)
			if err1 != nil || err2 != nil {
				writeError(w, http.StatusBadRequest, "invalid existing time")
				return
			}
			existing = append(existing, rules.Interval{ID: e.ID, Start: es, End: ee})
		}

		if err := rules.Validate(candidate, existing, capacity); err != nil {
			code := "overlap"
			if errors.Is(err, rules.ErrCapacity) {
				code = "capacity"
			}
			writeJSON(w, http.StatusOK, validateBookingResponse{
				Allowed: false,
				Code:    code,
				Message: err.Error(),
			})
			return
		}
		writeJSON(w, http.StatusOK, validateBookingResponse{Allowed: true})
	}
}

func bookingLocation(deps ...Deps) *time.Location {
	tz := "Europe/Stockholm"
	if len(deps) > 0 && deps[0].Timezone != "" {
		tz = deps[0].Timezone
	} else if v := os.Getenv("BOOKING_TIMEZONE"); v != "" {
		tz = v
	}
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return time.UTC
	}
	return loc
}

type chromeResponse struct {
	Header string `json:"header"`
	Footer string `json:"footer"`
}

func handleChrome(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, chromeResponse{
		Header: "Sauna booking system",
		Footer: "Homeowner association sauna",
	})
}

func decodeJSON(r *http.Request, dst any) error {
	dec := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	if err := dec.Decode(dst); err != nil {
		return err
	}
	if err := dec.Decode(&struct{}{}); err != io.EOF {
		return errors.New("request body must contain a single JSON object")
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}
