package notification

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresStore stores pending deliveries in PostgreSQL so they survive a
// process restart. Construction mirrors projection.PostgresCheckpointStore.
type PostgresStore struct {
	pool *pgxpool.Pool
}

// NewPostgresStore creates a PostgreSQL-backed outbox.
func NewPostgresStore(pool *pgxpool.Pool) *PostgresStore {
	return &PostgresStore{pool: pool}
}

// Enqueue stores an intended delivery. The unique key on
// (event_id, kind, recipient_email) makes replaying an event idempotent.
func (s *PostgresStore) Enqueue(ctx context.Context, item Item) error {
	result, err := s.pool.Exec(ctx, `
		INSERT INTO notification_outbox (event_id, kind, recipient_email, subject, body)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (event_id, kind, recipient_email) DO NOTHING`,
		item.EventID, item.Kind, item.RecipientEmail, item.Subject, item.Body)
	if err != nil {
		return fmt.Errorf("notification enqueue: %w", err)
	}
	if result.RowsAffected() > 0 {
		recordEnqueued(ctx)
	}
	return nil
}

// Due claims up to limit due rows in one statement. The lease written to
// next_attempt_at prevents a second worker or tick from sending the same row
// twice; a crashed worker's claim expires and the row is retried. Attempts is
// incremented on claim (not only on a sender error) so repeated crashes cannot
// retry a row forever without recording progress.
func (s *PostgresStore) Due(ctx context.Context, now time.Time, limit int) ([]Item, error) {
	if limit <= 0 {
		limit = 50
	}
	rows, err := s.pool.Query(ctx, `
		UPDATE notification_outbox
		SET attempts = attempts + 1,
		    next_attempt_at = $2
		WHERE id IN (
		    SELECT id FROM notification_outbox
		    WHERE status = 'pending' AND next_attempt_at <= $1
		    ORDER BY next_attempt_at, id
		    LIMIT $3
		    FOR UPDATE SKIP LOCKED
		)
		RETURNING id, event_id, kind, recipient_email, subject, body, attempts,
		          status, next_attempt_at, COALESCE(last_error, ''), created_at`,
		now, now.Add(claimLease), limit)
	if err != nil {
		return nil, fmt.Errorf("notification due: %w", err)
	}
	defer rows.Close()

	var out []Item
	for rows.Next() {
		var item Item
		if err := rows.Scan(
			&item.ID, &item.EventID, &item.Kind, &item.RecipientEmail, &item.Subject,
			&item.Body, &item.Attempts, &item.Status, &item.NextAttemptAt,
			&item.LastError, &item.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("notification due scan: %w", err)
		}
		out = append(out, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("notification due rows: %w", err)
	}
	return out, nil
}

// MarkSent records a successful delivery.
func (s *PostgresStore) MarkSent(ctx context.Context, id int64, at time.Time) error {
	if _, err := s.pool.Exec(ctx, `
		UPDATE notification_outbox
		SET status = 'sent', sent_at = $2, last_error = NULL
		WHERE id = $1`, id, at); err != nil {
		return fmt.Errorf("notification mark sent: %w", err)
	}
	recordSent(ctx)
	return nil
}

// Retry schedules another attempt and records the cause of this failure.
func (s *PostgresStore) Retry(ctx context.Context, id int64, nextAt time.Time, cause string) error {
	if _, err := s.pool.Exec(ctx, `
		UPDATE notification_outbox
		SET status = 'pending', next_attempt_at = $2, last_error = $3
		WHERE id = $1`, id, nextAt, cause); err != nil {
		return fmt.Errorf("notification retry: %w", err)
	}
	recordRetried(ctx)
	return nil
}

// Fail permanently fails a row. The row is kept for operator inspection.
func (s *PostgresStore) Fail(ctx context.Context, id int64, cause string) error {
	if _, err := s.pool.Exec(ctx, `
		UPDATE notification_outbox
		SET status = 'failed', last_error = $2
		WHERE id = $1`, id, cause); err != nil {
		return fmt.Errorf("notification fail: %w", err)
	}
	recordFailed(ctx)
	return nil
}

// PendingCount returns the number of deliveries currently awaiting delivery.
func (s *PostgresStore) PendingCount(ctx context.Context) (int64, error) {
	var n int64
	if err := s.pool.QueryRow(ctx, `SELECT COUNT(*) FROM notification_outbox WHERE status = 'pending'`).Scan(&n); err != nil {
		return 0, fmt.Errorf("notification pending count: %w", err)
	}
	return n, nil
}

// List returns rows with the given status, or all rows when status is empty.
func (s *PostgresStore) List(ctx context.Context, status string) ([]Item, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, event_id, kind, recipient_email, subject, body, status,
		       attempts, next_attempt_at, COALESCE(last_error, ''), created_at,
		       COALESCE(sent_at, to_timestamp(0))
		FROM notification_outbox
		WHERE $1 = '' OR status = $1
		ORDER BY id`, status)
	if err != nil {
		return nil, fmt.Errorf("notification list: %w", err)
	}
	defer rows.Close()

	var out []Item
	for rows.Next() {
		var item Item
		if err := rows.Scan(
			&item.ID, &item.EventID, &item.Kind, &item.RecipientEmail, &item.Subject,
			&item.Body, &item.Status, &item.Attempts, &item.NextAttemptAt,
			&item.LastError, &item.CreatedAt, &item.SentAt,
		); err != nil {
			return nil, fmt.Errorf("notification list scan: %w", err)
		}
		out = append(out, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("notification list rows: %w", err)
	}
	return out, nil
}
