package notification

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/email"
)

// Retry policy defaults. Deployment tuning lives in config.Config.
const (
	DefaultMaxAttempts = 5
	DefaultBaseDelay   = time.Second
	DefaultMaxDelay    = time.Minute
	DefaultInterval    = 5 * time.Second
	DefaultBatchSize   = 50
)

// Policy bounds retries. Zero values are replaced by defaults.
type Policy struct {
	MaxAttempts int
	BaseDelay   time.Duration
	MaxDelay    time.Duration
}

func (p Policy) withDefaults() Policy {
	if p.MaxAttempts <= 0 {
		p.MaxAttempts = DefaultMaxAttempts
	}
	if p.BaseDelay <= 0 {
		p.BaseDelay = DefaultBaseDelay
	}
	if p.MaxDelay <= 0 {
		p.MaxDelay = DefaultMaxDelay
	}
	return p
}

// Delay returns the backoff before the next attempt, where attempts is the
// number of send attempts already made (1-based). It grows exponentially and
// is capped at MaxDelay.
func (p Policy) Delay(attempts int) time.Duration {
	p = p.withDefaults()
	if attempts < 1 {
		attempts = 1
	}
	delay := p.BaseDelay
	for i := 1; i < attempts; i++ {
		if delay >= p.MaxDelay {
			return p.MaxDelay
		}
		delay *= 2
	}
	if delay > p.MaxDelay {
		delay = p.MaxDelay
	}
	return delay
}

// Stats reports what one drain pass did.
type Stats struct {
	Claimed int
	Sent    int
	Retried int
	Failed  int
}

// Worker drains due outbox rows and delivers them through a Sender.
type Worker struct {
	store     Store
	sender    email.Sender
	logger    *slog.Logger
	policy    Policy
	interval  time.Duration
	batchSize int
	now       func() time.Time
}

// NewWorker creates a worker. A nil logger uses the default logger.
func NewWorker(store Store, sender email.Sender, logger *slog.Logger, policy Policy) *Worker {
	if logger == nil {
		logger = slog.Default()
	}
	return &Worker{
		store:     store,
		sender:    sender,
		logger:    logger,
		policy:    policy.withDefaults(),
		interval:  DefaultInterval,
		batchSize: DefaultBatchSize,
		now:       time.Now,
	}
}

// ProcessOnce performs one drain pass over due rows. It is the seam used by
// tests and by Run.
func (w *Worker) ProcessOnce(ctx context.Context) (Stats, error) {
	var stats Stats
	items, err := w.store.Due(ctx, w.now(), w.batchSize)
	if err != nil {
		return stats, err
	}
	stats.Claimed = len(items)

	for _, item := range items {
		if err := ctx.Err(); err != nil {
			return stats, err
		}
		attrs := []any{
			"id", item.ID,
			"event_id", item.EventID,
			"kind", item.Kind,
			"attempts", item.Attempts,
			"to", MaskRecipient(item.RecipientEmail),
		}
		sendErr := w.sender.Send(ctx, item.RecipientEmail, item.Subject, item.Body)
		if sendErr == nil {
			if err := w.store.MarkSent(ctx, item.ID, w.now()); err != nil {
				return stats, fmt.Errorf("notification mark sent: %w", err)
			}
			stats.Sent++
			w.logger.Info("notification delivered", attrs...)
			continue
		}
		attrs = append(attrs, "err", sendErr)
		if item.Attempts >= w.policy.MaxAttempts {
			if err := w.store.Fail(ctx, item.ID, sendErr.Error()); err != nil {
				return stats, fmt.Errorf("notification fail: %w", err)
			}
			stats.Failed++
			w.logger.Error("notification permanently failed", attrs...)
			continue
		}
		next := w.now().Add(w.policy.Delay(item.Attempts))
		if err := w.store.Retry(ctx, item.ID, next, sendErr.Error()); err != nil {
			return stats, fmt.Errorf("notification retry: %w", err)
		}
		stats.Retried++
		attrs = append(attrs, "next_attempt_at", next)
		w.logger.Warn("notification retry scheduled", attrs...)
	}
	return stats, nil
}

// Run drains due rows on every tick until the context is cancelled. An
// interval <= 0 uses the worker default.
func (w *Worker) Run(ctx context.Context, interval time.Duration) error {
	if interval <= 0 {
		interval = w.interval
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		if _, err := w.ProcessOnce(ctx); err != nil && ctx.Err() == nil {
			w.logger.Error("notification worker pass", "err", err)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}
