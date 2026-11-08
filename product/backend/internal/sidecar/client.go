// Package sidecar provides a thin HTTP client for the deployment sidecar's
// stateless functions (booking rules, etc.).
package sidecar

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/booking"
)

// RulesClient calls the sidecar's booking-rule validation endpoint.
type RulesClient struct {
	baseURL string
	http    *http.Client
	logger  *slog.Logger
}

// NewRulesClient constructs a client targeting baseURL.
func NewRulesClient(baseURL string, logger *slog.Logger) *RulesClient {
	return &RulesClient{
		baseURL: baseURL,
		http:    &http.Client{Timeout: 2 * time.Second},
		logger:  logger,
	}
}

// ValidateBooking asks the sidecar to validate/normalize a booking interval.
func (c *RulesClient) ValidateBooking(ctx context.Context, start, end time.Time) error {
	body := map[string]string{
		"start": start.Format(time.RFC3339),
		"end":   end.Format(time.RFC3339),
	}
	b, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("%w: %v", booking.ErrBookingRulesUnavailable, err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/functions/validate-booking", bytes.NewReader(b))
	if err != nil {
		return fmt.Errorf("%w: %v", booking.ErrBookingRulesUnavailable, err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("%w: %v", booking.ErrBookingRulesUnavailable, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		return nil
	}
	if resp.StatusCode == http.StatusBadRequest {
		var e struct {
			Error string `json:"error"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&e)
		msg := e.Error
		if msg == "" {
			msg = "booking rule violation"
		}
		return fmt.Errorf("%w: %s", booking.ErrBookingRuleViolation, msg)
	}
	return fmt.Errorf("%w: unexpected status %d", booking.ErrBookingRulesUnavailable, resp.StatusCode)
}
