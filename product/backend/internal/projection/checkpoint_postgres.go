package projection

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresCheckpointStore stores projection checkpoints in PostgreSQL.
type PostgresCheckpointStore struct {
	pool *pgxpool.Pool
}

// NewPostgresCheckpointStore creates a PostgreSQL-backed checkpoint store.
func NewPostgresCheckpointStore(pool *pgxpool.Pool) *PostgresCheckpointStore {
	return &PostgresCheckpointStore{pool: pool}
}

// Get returns the last applied event ID, or zero for a new projection.
func (s *PostgresCheckpointStore) Get(ctx context.Context, name string) (int64, error) {
	var id int64
	err := s.pool.QueryRow(ctx,
		`SELECT last_event_id FROM projection_checkpoints WHERE projection_name = $1`, name,
	).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	if err != nil {
		return 0, fmt.Errorf("projection checkpoint %s: %w", name, err)
	}
	return id, nil
}

// Set advances a projection checkpoint.
func (s *PostgresCheckpointStore) Set(ctx context.Context, name string, lastEventID int64) error {
	_, err := s.pool.Exec(ctx,
		`INSERT INTO projection_checkpoints (projection_name, last_event_id)
		 VALUES ($1, $2)
		 ON CONFLICT (projection_name) DO UPDATE
		 SET last_event_id = EXCLUDED.last_event_id, updated_at = now()`,
		name, lastEventID,
	)
	if err != nil {
		return fmt.Errorf("projection checkpoint %s: %w", name, err)
	}
	return nil
}

// Reset returns a projection checkpoint to the start of the event history.
func (s *PostgresCheckpointStore) Reset(ctx context.Context, name string) error {
	return s.Set(ctx, name, 0)
}
