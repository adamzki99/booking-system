// Package email sends transactional email (login codes, booking notices).
package email

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/adamzki99/booking-system/product/backend/internal/config"
)

// Sender delivers a plain-text email.
type Sender interface {
	Send(ctx context.Context, to, subject, body string) error
}

// New selects a Sender implementation from configuration.
func New(cfg config.Config, logger *slog.Logger) (Sender, error) {
	switch cfg.EmailMode {
	case "log":
		return NewLogSender(logger), nil
	case "smtp":
		return NewSMTPSender(cfg)
	default:
		return nil, fmt.Errorf("unknown EMAIL_MODE %q", cfg.EmailMode)
	}
}
