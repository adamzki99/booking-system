package ical

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/booking"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

// BookingsReader is the part of the bookings read model the feed needs.
type BookingsReader interface {
	ListByUser(ctx context.Context, userID string) ([]booking.Booking, error)
}

// HandleFeed serves the iCal feed for a token.
func HandleFeed(tokens *CalendarTokenProjection, bookings BookingsReader) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if tokens == nil {
			http.Error(w, "ical unavailable", http.StatusServiceUnavailable)
			return
		}
		token := r.PathValue("token")
		if token == "" {
			token = strings.TrimPrefix(r.URL.Path, "/calendar/")
			token = strings.TrimSuffix(token, ".ics")
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

// Aliases for handler name.
func HandleCalendarFeed(tokens *CalendarTokenProjection, bookings BookingsReader) http.HandlerFunc {
	return HandleFeed(tokens, bookings)
}
func HandleICalFeed(tokens *CalendarTokenProjection, bookings BookingsReader) http.HandlerFunc {
	return HandleFeed(tokens, bookings)
}
func HandleCalendar(tokens *CalendarTokenProjection, bookings BookingsReader) http.HandlerFunc {
	return HandleFeed(tokens, bookings)
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