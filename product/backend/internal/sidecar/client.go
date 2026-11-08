// Package sidecar provides a thin HTTP client for the deployment sidecar's
// stateless functions (booking rules, etc.).
package sidecar

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/booking"
)

// Client calls the sidecar's booking-rule validation endpoint.
type Client struct {
	baseURL string
	http    *http.Client
	logger  *slog.Logger
}

// NewClient constructs a client targeting baseURL.
func NewClient(baseURL string, opts ...any) *Client {
	c := &Client{
		baseURL: baseURL,
		http:    &http.Client{Timeout: 2 * time.Second},
	}
	for _, o := range opts {
		switch v := o.(type) {
		case *slog.Logger:
			c.logger = v
		case *http.Client:
			c.http = v
		}
	}
	return c
}

// NewRulesClient is kept for backwards compatibility.
func NewRulesClient(baseURL string, logger *slog.Logger) *Client {
	return NewClient(baseURL, logger)
}

type sidecarExisting struct {
	ID    string `json:"id"`
	Start string `json:"start"`
	End   string `json:"end"`
}

// ValidateBooking asks the sidecar to validate a candidate booking against
// existing bookings (overlap + capacity).
func (c *Client) ValidateBooking(ctx context.Context, candidate booking.Booking, existing []booking.Booking) error {
	ex := make([]sidecarExisting, 0, len(existing))
	for _, b := range existing {
		ex = append(ex, sidecarExisting{
			ID:    b.ID,
			Start: b.Start.Format(time.RFC3339),
			End:   b.End.Format(time.RFC3339),
		})
	}
	body := map[string]any{
		"start":    candidate.Start.Format(time.RFC3339),
		"end":      candidate.End.Format(time.RFC3339),
		"existing": ex,
	}
	b, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("%w: %v", booking.ErrSidecarUnavailable, err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/functions/validate-booking", bytes.NewReader(b))
	if err != nil {
		return fmt.Errorf("%w: %v", booking.ErrSidecarUnavailable, err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("%w: %v", booking.ErrSidecarUnavailable, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		data, _ := io.ReadAll(resp.Body)
		if len(data) == 0 {
			return nil
		}
		var out struct {
			Allowed bool   `json:"allowed"`
			Code    string `json:"code"`
			Message string `json:"message"`
		}
		if err := json.Unmarshal(data, &out); err != nil {
			return fmt.Errorf("%w: %v", booking.ErrSidecarUnavailable, err)
		}
		if out.Allowed {
			return nil
		}
		msg := out.Code
		if out.Message != "" {
			if msg != "" {
				msg += ": "
			}
			msg += out.Message
		}
		if msg == "" {
			msg = "booking rejected"
		}
		return fmt.Errorf("%w: %s", booking.ErrBookingRejected, msg)
		// wrap code? errors.Is enough; message includes code maybe
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
		return fmt.Errorf("%w: %s", booking.ErrBookingRejected, msg)
	}
	return fmt.Errorf("%w: unexpected status %d", booking.ErrSidecarUnavailable, resp.StatusCode)
}
