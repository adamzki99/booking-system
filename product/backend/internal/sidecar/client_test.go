package sidecar

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/booking"
)

func TestValidateBookingHappyPath(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("method = %s", r.Method)
		}
		if r.URL.Path != "/functions/validate-booking" {
			t.Errorf("path = %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer ts.Close()

	c := NewRulesClient(ts.URL, nil)
	start := time.Now().Add(time.Hour)
	end := start.Add(time.Hour)
	if err := c.ValidateBooking(context.Background(), booking.Booking{Start: start, End: end}, nil); err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
}

func TestValidateBookingRuleViolation(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"multi-day"}`))
	}))
	defer ts.Close()

	c := NewRulesClient(ts.URL, nil)
	start := time.Now().Add(time.Hour)
	end := start.Add(time.Hour)
	err := c.ValidateBooking(context.Background(), booking.Booking{Start: start, End: end}, nil)
	if !errors.Is(err, booking.ErrBookingRuleViolation) {
		t.Fatalf("expected ErrBookingRuleViolation, got %v", err)
	}
}

func TestValidateBookingUnavailable(t *testing.T) {
	// 500
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer ts.Close()

	c := NewRulesClient(ts.URL, nil)
	start := time.Now().Add(time.Hour)
	end := start.Add(time.Hour)
	err := c.ValidateBooking(context.Background(), booking.Booking{Start: start, End: end}, nil)
	if !errors.Is(err, booking.ErrBookingRulesUnavailable) {
		t.Fatalf("expected ErrBookingRulesUnavailable, got %v", err)
	}

	// connection refused
	c2 := NewRulesClient("http://127.0.0.1:1", nil)
	err2 := c2.ValidateBooking(context.Background(), booking.Booking{Start: start, End: end}, nil)
	if !errors.Is(err2, booking.ErrBookingRulesUnavailable) {
		t.Fatalf("expected ErrBookingRulesUnavailable, got %v", err2)
	}
}
