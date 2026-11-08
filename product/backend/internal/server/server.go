// Package server wires the HTTP API to the application services.
package server

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strconv"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/booking"
	"github.com/adamzki99/booking-system/product/backend/internal/broadcast"
	"github.com/adamzki99/booking-system/product/backend/internal/config"
	"github.com/adamzki99/booking-system/product/backend/internal/ical"
	"github.com/adamzki99/booking-system/product/backend/internal/ratelimit"
	"github.com/adamzki99/booking-system/product/backend/internal/user"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// Deps holds the dependencies required by the HTTP server.
type Deps struct {
	Auth             *auth.AuthService
	Middleware       *auth.SessionMiddleware
	UserService      *user.UserService
	BookingService   *booking.BookingService
	BroadcastService *broadcast.BroadcastService

	ICal                 *ical.Service
	ICalService          *ical.Service
	CalendarTokenService *ical.Service
	CalendarTokens       *ical.CalendarTokenProjection
	Bookings             *booking.BookingsProjection
}

// NewMux builds the HTTP router.
func NewMux(deps Deps) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", handleHealthz)
	mux.HandleFunc("POST /auth/request-code", handleRequestCode(deps.Auth))
	mux.HandleFunc("POST /auth/verify", handleVerify(deps.Auth))
	mux.Handle("GET /auth/me", protect(deps.Middleware, handleMe))

	// User endpoints (all require a valid session).
	mux.Handle("GET /users", protect(deps.Middleware, user.HandleListUsers(deps.UserService)))
	mux.Handle("GET /users/me", protect(deps.Middleware, user.HandleMe(deps.UserService)))
	mux.Handle("POST /users", protect(deps.Middleware, user.HandleCreateUser(deps.UserService)))
	mux.Handle("POST /users/{id}/remove", protect(deps.Middleware, user.HandleRemoveUser(deps.UserService)))
	mux.Handle("PATCH /users/me/email", protect(deps.Middleware, user.HandleChangeOwnEmail(deps.UserService)))
	mux.Handle("PATCH /users/{id}/address", protect(deps.Middleware, user.HandleChangeUserAddress(deps.UserService)))

	// Booking endpoints (all require a valid session).
	mux.Handle("GET /bookings", protect(deps.Middleware, booking.HandleListBookings(deps.BookingService)))
	mux.Handle("POST /bookings", protect(deps.Middleware, booking.HandleCreateBooking(deps.BookingService)))
	mux.Handle("POST /bookings/{id}/cancel", protect(deps.Middleware, booking.HandleCancelBooking(deps.BookingService)))
	mux.Handle("GET /blocked-periods", protect(deps.Middleware, booking.HandleListBlockedPeriods(deps.BookingService)))
	mux.Handle("POST /blocked-periods", protect(deps.Middleware, booking.HandleBlockTimePeriod(deps.BookingService)))

	// Broadcast endpoint (super users only; requires a valid session).
	mux.Handle("POST /broadcast", protect(deps.Middleware, broadcast.HandleBroadcast(deps.BroadcastService)))

	// iCal feed (unauthenticated; token is the credential; rate limited by IP and token).
	mux.HandleFunc("GET /calendar/", ical.HandleFeed(deps.CalendarTokens, deps.Bookings, ratelimit.NewLimiter()))

	// Regenerate calendar token (authenticated).
	mux.Handle("POST /account/calendar-token", protect(deps.Middleware, ical.HandleRegenerateToken(icalServiceFromDeps(deps), deps.UserService)))
	return mux
}

// New creates an *http.Server wired with sensible timeouts.
func New(cfg config.Config, logger *slog.Logger, deps Deps) *http.Server {
	return &http.Server{
		Addr:         ":" + strconv.Itoa(cfg.Port),
		Handler:      otelhttp.NewHandler(NewMux(deps), "http"),
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
		ErrorLog:     slog.NewLogLogger(logger.Handler(), slog.LevelError),
	}
}

func icalServiceFromDeps(deps Deps) *ical.Service {
	if deps.ICalService != nil {
		return deps.ICalService
	}
	if deps.ICal != nil {
		return deps.ICal
	}
	return deps.CalendarTokenService
}

func handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type requestCodeRequest struct {
	Email string `json:"email"`
}

func handleRequestCode(svc *auth.AuthService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeError(w, http.StatusServiceUnavailable, "auth unavailable")
			return
		}
		var req requestCodeRequest
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		if err := svc.RequestCode(r.Context(), req.Email, clientIP(r)); err != nil {
			writeAuthError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

type verifyRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

func handleVerify(svc *auth.AuthService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeError(w, http.StatusServiceUnavailable, "auth unavailable")
			return
		}
		var req verifyRequest
		if err := decodeJSON(r, &req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		token, err := svc.Verify(r.Context(), req.Email, req.Code, clientIP(r))
		if err != nil {
			writeAuthError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"token": token})
	}
}

func handleMe(w http.ResponseWriter, r *http.Request) {
	email, ok := auth.FromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"email": email})
}

func protect(mw *auth.SessionMiddleware, next http.HandlerFunc) http.Handler {
	if mw == nil {
		return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			writeError(w, http.StatusServiceUnavailable, "auth unavailable")
		})
	}
	return mw.Require(next)
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

func writeAuthError(w http.ResponseWriter, err error) {
	writeError(w, authStatus(err), err.Error())
}

func authStatus(err error) int {
	switch {
	case errors.Is(err, auth.ErrInvalidEmail), errors.Is(err, auth.ErrInvalidCode):
		return http.StatusBadRequest
	case errors.Is(err, auth.ErrInvalidOrExpiredCode):
		return http.StatusUnauthorized
	case errors.Is(err, auth.ErrRateLimited):
		return http.StatusTooManyRequests
	default:
		return http.StatusInternalServerError
	}
}

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
