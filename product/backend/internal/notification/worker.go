package notification

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/email"
)

// Policy bounds delivery retries.
type Policy struct {
	MaxAttempts int
	BaseDelay   time.Duration
	MaxDelay    time.Duration
}

// DefaultPolicy is the fallback when no deployment policy is supplied.
func DefaultPolicy() Policy {
	return Policy{MaxAttempts: 5, BaseDelay: time.Second, MaxDelay: time.Minute}
}

func (p Policy) normalized() Policy {
	defaults := DefaultPolicy()
	if p.MaxAttempts <= 0 {
		p.MaxAttempts = defaults.MaxAttempts
	}
	if p.BaseDelay <= 0 {
		p.BaseDelay = defaults.BaseDelay
	}
	if p.MaxDelay <= 0 {
		p.MaxDelay = defaults.MaxDelay
	}
	return p
}

// backoffFor returns base * 2^attempts, capped at the configured maximum.
func backoffFor(attempts int, p Policy) time.Duration {
	p = p.normalized()
	delay := p.BaseDelay
	for i := 0; i < attempts; i++ {
		if delay >= p.MaxDelay || delay > p.MaxDelay/2 {
			return p.MaxDelay
		}
		delay *= 2
	}
	if delay > p.MaxDelay {
		return p.MaxDelay
	}
	return delay
}

// Stats summarizes one drain pass.
type Stats struct {
	Due     int
	Sent    int
	Retried int
	Failed  int
}

// Worker drains due outbox rows through an email sender.
type Worker struct {
	store  Store
	sender email.Sender
	logger *slog.Logger
	policy Policy
	limit  int
}

// NewWorker creates a worker. A zero policy uses DefaultPolicy.
func NewWorker(store Store, sender email.Sender, logger *slog.Logger, policy Policy) *Worker {
	if logger == nil {
		logger = slog.Default()
	}
	return &Worker{
		store:  store,
		sender: sender,
		logger: logger,
		policy: policy.normalized(),
		limit:  100,
	}
}

// ProcessOnce performs one drain pass over due rows. It is used both by the
// runtime loop and by tests that need deterministic delivery.
func (w *Worker) ProcessOnce(ctx context.Context) (Stats, error) {
	var stats Stats
	now := time.Now().UTC()
	items, err := w.store.Due(ctx, now, w.limit)
	if err != nil {
		return stats, fmt.Errorf("notification: due: %w", err)
	}
	stats.Due = len(items)

	for _, item := range items {
		fields := []any{
			"id", item.ID,
			"event_id", item.EventID,
			"kind", item.Kind,
			"attempts", item.Attempts,
			"recipient", MaskRecipient(item.RecipientEmail),
		}
		sendErr := w.sender.Send(ctx, item.RecipientEmail, item.Subject, item.Body)
		if sendErr == nil {
			if err := w.store.MarkSent(ctx, item.ID, time.Now().UTC()); err != nil {
				w.logger.Error("notification: mark sent", append(fields, "err", err)...)
				continue
			}
			stats.Sent++
			w.logger.Info("notification delivered", fields...)
			continue
		}

		cause := sendErr.Error()
		// item.Attempts counts completed sends; this failure is the next one.
		if item.Attempts+1 >= w.policy.MaxAttempts {
			if err := w.store.Fail(ctx, item.ID, cause); err != nil {
				w.logger.Error("notification: mark failed", append(fields, "err", err)...)
			}
			stats.Failed++
			w.logger.Error("notification permanently failed",
				append(fields, "err", sendErr)...)
			continue
		}

		nextAt := now.Add(backoffFor(item.Attempts+1, w.policy))
		if err := w.store.Retry(ctx, item.ID, nextAt, cause); err != nil {
			w.logger.Error("notification: schedule retry", append(fields, "err", err)...)
		}
		stats.Retried++
		w.logger.Warn("notification delivery retried",
			append(fields, "next_attempt_at", nextAt, "err", sendErr)...)
	}
	return stats, nil
}

// Run drains due rows immediately and then on each tick until ctx is
// cancelled. Drain errors are logged; a failed pass never stops the loop.
func (w *Worker) Run(ctx context.Context, interval time.Duration) {
	if interval <= 0 {
		interval = time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	w.drain(ctx)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			w.drain(ctx)
		}
	}
}

func (w *Worker) drain(ctx context.Context) {
	if _, err := w.ProcessOnce(ctx); err != nil {
		w.logger.Error("notification drain", "err", err)
	}
}
