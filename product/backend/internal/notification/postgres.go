package notification

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresStore stores durable notification work in PostgreSQL.
type PostgresStore struct {
	pool *pgxpool.Pool
}

// NewPostgresStore creates a PostgreSQL-backed outbox over an existing pool.
func NewPostgresStore(pool *pgxpool.Pool) *PostgresStore {
	return &PostgresStore{pool: pool}
}

// Enqueue inserts a delivery, or does nothing when the same event, kind and
// recipient is already present.
func (s *PostgresStore) Enqueue(ctx context.Context, item Item) error {
	tag, err := s.pool.Exec(ctx, `
		INSERT INTO notification_outbox (event_id, kind, recipient_email, subject, body)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (event_id, kind, recipient_email) DO NOTHING`,
		item.EventID, item.Kind, item.RecipientEmail, item.Subject, item.Body,
	)
	if err != nil {
		return fmt.Errorf("notification enqueue: %w", err)
	}
	if tag.RowsAffected() > 0 {
		enqueuedCounter.Add(ctx, 1)
	}
	return nil
}

// Due claims up to limit due rows. The CTE locks candidate rows with SKIP
// LOCKED and the conditional UPDATE takes the claim; a second worker or tick
// cannot send the same row twice.
func (s *PostgresStore) Due(ctx context.Context, now time.Time, limit int) ([]Item, error) {
	if limit <= 0 {
		return nil, nil
	}
	rows, err := s.pool.Query(ctx, `
		WITH due AS (
			SELECT id FROM notification_outbox
			WHERE status = 'pending' AND next_attempt_at <= $1
			ORDER BY next_attempt_at, id
			LIMIT $3
			FOR UPDATE SKIP LOCKED
		)
		UPDATE notification_outbox o
		SET next_attempt_at = $2
		FROM due
		WHERE o.id = due.id AND o.status = 'pending'
		RETURNING o.id, o.event_id, o.kind, o.recipient_email, o.subject, o.body,
		          o.status, o.attempts, o.next_attempt_at, o.last_error,
		          o.created_at, o.sent_at`,
		now, now.Add(claimLease), limit,
	)
	if err != nil {
		return nil, fmt.Errorf("notification due: %w", err)
	}
	defer rows.Close()

	var out []Item
	for rows.Next() {
		var item Item
		var lastError *string
		if err := rows.Scan(
			&item.ID, &item.EventID, &item.Kind, &item.RecipientEmail,
			&item.Subject, &item.Body, &item.Status, &item.Attempts,
			&item.NextAttemptAt, &lastError, &item.CreatedAt, &item.SentAt,
		); err != nil {
			return nil, fmt.Errorf("notification due: scan: %w", err)
		}
		if lastError != nil {
			item.LastError = *lastError
		}
		out = append(out, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("notification due: rows: %w", err)
	}
	return out, nil
}

// MarkSent records a successful delivery.
func (s *PostgresStore) MarkSent(ctx context.Context, id int64, at time.Time) error {
	tag, err := s.pool.Exec(ctx, `
		UPDATE notification_outbox
		SET status = 'sent', sent_at = $2, last_error = NULL, attempts = attempts + 1
		WHERE id = $1 AND status = 'pending'`, id, at)
	if err != nil {
		return fmt.Errorf("notification mark sent %d: %w", id, err)
	}
	if tag.RowsAffected() > 0 {
		sentCounter.Add(ctx, 1)
	}
	return nil
}

// Retry reschedules a transiently failed delivery.
func (s *PostgresStore) Retry(ctx context.Context, id int64, nextAt time.Time, cause string) error {
	tag, err := s.pool.Exec(ctx, `
		UPDATE notification_outbox
		SET status = 'pending', next_attempt_at = $2, last_error = $3, attempts = attempts + 1
		WHERE id = $1 AND status = 'pending'`, id, nextAt, cause)
	if err != nil {
		return fmt.Errorf("notification retry %d: %w", id, err)
	}
	if tag.RowsAffected() > 0 {
		retriedCounter.Add(ctx, 1)
	}
	return nil
}

// Fail permanently fails a delivery. The row is retained for inspection.
func (s *PostgresStore) Fail(ctx context.Context, id int64, cause string) error {
	tag, err := s.pool.Exec(ctx, `
		UPDATE notification_outbox
		SET status = 'failed', last_error = $2, attempts = attempts + 1
		WHERE id = $1 AND status = 'pending'`, id, cause)
	if err != nil {
		return fmt.Errorf("notification fail %d: %w", id, err)
	}
	if tag.RowsAffected() > 0 {
		failedCounter.Add(ctx, 1)
	}
	return nil
}
