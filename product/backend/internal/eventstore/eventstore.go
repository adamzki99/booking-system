package eventstore

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"sort"
	"strings"
	"time"

	"github.com/adamzki99/booking-system/product/backend/migrations"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Migrations is the embedded filesystem containing the SQL migrations.
var Migrations embed.FS = migrations.FS

// MigrationFS is an alias for Migrations.
var MigrationFS = Migrations

// Event is a single recorded domain event. Events are append-only.
type Event struct {
	ID            int64           `json:"id"`
	AggregateType string          `json:"aggregate_type"`
	AggregateID   string          `json:"aggregate_id"`
	EventType     string          `json:"event_type"`
	Payload       json.RawMessage `json:"payload"`
	OccurredAt    time.Time       `json:"occurred_at"`
	RecordedAt    time.Time       `json:"recorded_at"`
}

// Valid reports whether the event passes validation.
func (e Event) Valid() bool { return e.Validate() == nil }

// Validate checks that required fields are non-empty.
func (e Event) Validate() error {
	if e.AggregateType == "" {
		return errors.New("eventstore: aggregate_type is required")
	}
	if e.AggregateID == "" {
		return errors.New("eventstore: aggregate_id is required")
	}
	if e.EventType == "" {
		return errors.New("eventstore: event_type is required")
	}
	if len(e.Payload) == 0 {
		return errors.New("eventstore: payload is required")
	}
	if e.OccurredAt.IsZero() {
		return errors.New("eventstore: occurred_at is required")
	}
	return nil
}

// ValidateEvent is a functional form of Event.Validate.
func ValidateEvent(e Event) error { return e.Validate() }

// Store is the append-only event store interface.
type Store interface {
	Append(ctx context.Context, events ...Event) error
	LoadAll(ctx context.Context) ([]Event, error)
	LoadByAggregate(ctx context.Context, aggregateType, aggregateID string) ([]Event, error)
}

// PostgresStore is a Store backed by a pgx pool.
type PostgresStore struct {
	pool *pgxpool.Pool
}

// NewPostgresStore wraps an existing pool.
func NewPostgresStore(pool *pgxpool.Pool) *PostgresStore {
	return &PostgresStore{pool: pool}
}

// New is an alias for NewPostgresStore.
func New(pool *pgxpool.Pool) *PostgresStore {
	return NewPostgresStore(pool)
}

// Append inserts events in a single transaction. recorded_at comes from DB default.
func (s *PostgresStore) Append(ctx context.Context, events ...Event) error {
	if len(events) == 0 {
		return nil
	}
	for _, e := range events {
		if err := e.Validate(); err != nil {
			return err
		}
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("eventstore: begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	batch := &pgx.Batch{}
	for _, e := range events {
		batch.Queue(
			`INSERT INTO events (aggregate_type, aggregate_id, event_type, payload, occurred_at)
			 VALUES ($1, $2, $3, $4, $5)`,
			e.AggregateType, e.AggregateID, e.EventType, []byte(e.Payload), e.OccurredAt,
		)
	}
	br := tx.SendBatch(ctx, batch)
	for range events {
		if _, err := br.Exec(); err != nil {
			_ = br.Close()
			return fmt.Errorf("eventstore: insert: %w", err)
		}
	}
	if err := br.Close(); err != nil {
		return fmt.Errorf("eventstore: batch close: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("eventstore: commit: %w", err)
	}
	return nil
}

// LoadAll returns all events ordered by (recorded_at, id).
func (s *PostgresStore) LoadAll(ctx context.Context) ([]Event, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id, aggregate_type, aggregate_id, event_type, payload, occurred_at, recorded_at
		 FROM events ORDER BY recorded_at, id`)
	if err != nil {
		return nil, fmt.Errorf("eventstore: query: %w", err)
	}
	defer rows.Close()
	return scanEvents(rows)
}

// LoadByAggregate filters by aggregate.
func (s *PostgresStore) LoadByAggregate(ctx context.Context, aggregateType, aggregateID string) ([]Event, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id, aggregate_type, aggregate_id, event_type, payload, occurred_at, recorded_at
		 FROM events WHERE aggregate_type = $1 AND aggregate_id = $2 ORDER BY recorded_at, id`,
		aggregateType, aggregateID)
	if err != nil {
		return nil, fmt.Errorf("eventstore: query: %w", err)
	}
	defer rows.Close()
	return scanEvents(rows)
}

func scanEvents(rows pgx.Rows) ([]Event, error) {
	var out []Event
	for rows.Next() {
		var e Event
		var payload []byte
		if err := rows.Scan(&e.ID, &e.AggregateType, &e.AggregateID, &e.EventType, &payload, &e.OccurredAt, &e.RecordedAt); err != nil {
			return nil, fmt.Errorf("eventstore: scan: %w", err)
		}
		e.Payload = json.RawMessage(payload)
		out = append(out, e)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("eventstore: rows: %w", err)
	}
	if out == nil {
		out = []Event{}
	}
	return out, nil
}

// Migrate applies all embedded migrations idempotently.
func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	return runMigrations(ctx, pool, Migrations)
}

func runMigrations(ctx context.Context, pool *pgxpool.Pool, fsys embed.FS) error {
	// collect sql files
	var files []string
	err := fs.WalkDir(fsys, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if strings.HasSuffix(path, ".sql") {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("eventstore: walk migrations: %w", err)
	}
	sort.Strings(files)
	for _, f := range files {
		b, err := fs.ReadFile(fsys, f)
		if err != nil {
			return fmt.Errorf("eventstore: read migration %s: %w", f, err)
		}
		if _, err := pool.Exec(ctx, string(b)); err != nil {
			return fmt.Errorf("eventstore: apply migration %s: %w", f, err)
		}
	}
	return nil
}

// OpenPool opens a pgx pool from a database URL.
func OpenPool(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	return pgxpool.New(ctx, databaseURL)
}
