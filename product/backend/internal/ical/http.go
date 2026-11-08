package ical

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/booking"
	"github.com/adamzki99/booking-system/product/backend/internal/ratelimit"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

// Feed rate limits mirror the auth verify limits: 30 requests per client IP
// per hour, and 10 requests per token per 15-minute window.
const (
	feedIPLimit     = 30
	feedIPWindow    = time.Hour
	feedTokenLimit  = 10
	feedTokenWindow = 15 * time.Minute
)

// BookingsReader is the part of the bookings read model the feed needs.
type BookingsReader interface {
	ListByUser(ctx context.Context, userID string) ([]booking.Booking, error)
}

// HandleFeed serves the iCal feed for a token. A non-nil limiter rate limits
// requests by client IP and token hash and responds 429 when exceeded; a nil
// limiter disables rate limiting.
func HandleFeed(tokens *CalendarTokenProjection, bookings BookingsReader, limiter *ratelimit.Limiter) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := r.PathValue("token")
		if token == "" {
			token = strings.TrimPrefix(r.URL.Path, "/calendar/")
			token = strings.TrimSuffix(token, ".ics")
		}
		if limiter != nil {
			if !feedAllows(r, token, limiter) {
				http.Error(w, "rate limited", http.StatusTooManyRequests)
				return
			}
		}
		if tokens == nil {
			http.Error(w, "ical unavailable", http.StatusServiceUnavailable)
			return
		}
		userID, err := tokens.UserIDByTokenHash(r.Context(), HashToken(token))
		if err != nil {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		var bs []booking.Booking
		if bookings != nil {
			bs, err = bookings.ListByUser(r.Context(), userID)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
		}
		body := RenderFeed(bs, time.Now().UTC())
		w.Header().Set("Content-Type", "text/calendar; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(body))
	}
}

// feedAllows reports whether the request under the client's IP and the given
// token may proceed. Denied requests are left uncounted for that key.
func feedAllows(r *http.Request, token string, limiter *ratelimit.Limiter) bool {
	if !limiter.Allow(feedIPKey(clientIP(r)), feedIPLimit, feedIPWindow) {
		return false
	}
	if !limiter.Allow(feedTokenKey(HashToken(token)), feedTokenLimit, feedTokenWindow) {
		return false
	}
	return true
}

func feedIPKey(ip string) string      { return "ical:ip:" + ip }
func feedTokenKey(hash string) string { return "ical:token:" + hash }

// clientIP extracts the host of the request's remote address.
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// Aliases for handler name.
func HandleCalendarFeed(tokens *CalendarTokenProjection, bookings BookingsReader, limiter *ratelimit.Limiter) http.HandlerFunc {
	return HandleFeed(tokens, bookings, limiter)
}
func HandleICalFeed(tokens *CalendarTokenProjection, bookings BookingsReader, limiter *ratelimit.Limiter) http.HandlerFunc {
	return HandleFeed(tokens, bookings, limiter)
}
func HandleCalendar(tokens *CalendarTokenProjection, bookings BookingsReader, limiter *ratelimit.Limiter) http.HandlerFunc {
	return HandleFeed(tokens, bookings, limiter)
}

// userResolver resolves a user from an email.
type userResolver interface {
	GetByEmail(ctx context.Context, email string) (user.User, error)
}

// HandleRegenerateToken regenerates a user's calendar token.
func HandleRegenerateToken(svc *Service, users userResolver) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeICalError(w, http.StatusServiceUnavailable, "ical unavailable")
			return
		}
		email, ok := auth.FromContext(r.Context())
		if !ok {
			writeICalError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		var u user.User
		var err error
		if users != nil {
			u, err = users.GetByEmail(r.Context(), email)
		} else {
			err = errors.New("user service unavailable")
		}
		if err != nil {
			writeICalError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		token, err := svc.Generate(r.Context(), u.ID)
		if err != nil {
			writeICalError(w, http.StatusInternalServerError, err.Error())
			return
		}
		base := baseURL(r)
		writeICalJSON(w, http.StatusOK, map[string]string{
			"url": base + "/calendar/" + token + ".ics",
		})
	}
}

// Aliases.
func HandleRegenerateCalendarToken(svc *Service, users userResolver) http.HandlerFunc {
	return HandleRegenerateToken(svc, users)
}
func HandleCreateCalendarToken(svc *Service, users userResolver) http.HandlerFunc {
	return HandleRegenerateToken(svc, users)
}

func writeICalJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeICalError(w http.ResponseWriter, status int, msg string) {
	writeICalJSON(w, status, map[string]string{"error": msg})
}

func baseURL(r *http.Request) string {
	if v := os.Getenv("PUBLIC_BASE_URL"); v != "" {
		return strings.TrimRight(v, "/")
	}
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}
	if p := r.Header.Get("X-Forwarded-Proto"); p != "" {
		scheme = p
	}
	host := r.Host
	if h := r.Header.Get("X-Forwarded-Host"); h != "" {
		host = h
	}
	return scheme + "://" + host
}
