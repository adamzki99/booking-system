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
	"github.com/exaring/otelpgx"
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
	Append(ctx context.Context, events ...Event) ([]Event, error)
	LoadAll(ctx context.Context) ([]Event, error)
	LoadByAggregate(ctx context.Context, aggregateType, aggregateID string) ([]Event, error)
}

// Locker serializes command execution across backend replicas with a
// database-level advisory lock. Callers must invoke the returned release
// function on every path.
type Locker interface {
	Lock(ctx context.Context, key int64) (release func() error, err error)
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

// Append inserts events in a single transaction and returns their database IDs and timestamps.
func (s *PostgresStore) Append(ctx context.Context, events ...Event) ([]Event, error) {
	if len(events) == 0 {
		return []Event{}, nil
	}
	for _, e := range events {
		if err := e.Validate(); err != nil {
			return nil, err
		}
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("eventstore: begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	batch := &pgx.Batch{}
	for _, e := range events {
		batch.Queue(
			`INSERT INTO events (aggregate_type, aggregate_id, event_type, payload, occurred_at)
			 VALUES ($1, $2, $3, $4, $5)
			 RETURNING id, recorded_at`,
			e.AggregateType, e.AggregateID, e.EventType, []byte(e.Payload), e.OccurredAt,
		)
	}
	recorded := make([]Event, len(events))
	copy(recorded, events)
	br := tx.SendBatch(ctx, batch)
	for i := range recorded {
		if err := br.QueryRow().Scan(&recorded[i].ID, &recorded[i].RecordedAt); err != nil {
			_ = br.Close()
			return nil, fmt.Errorf("eventstore: insert: %w", err)
		}
	}
	if err := br.Close(); err != nil {
		return nil, fmt.Errorf("eventstore: batch close: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("eventstore: commit: %w", err)
	}
	return recorded, nil
}

// Lock acquires a session-level PostgreSQL advisory lock identified by key on a
// dedicated pooled connection. Calls with the same key serialize across all
// backend replicas. Session scope (rather than transaction scope) is required
// so the lock covers the caller's read-model validation, the event append, and
// the synchronous projection update, not just the append transaction.
//
// Locks are held on a connection borrowed from the store's pool, so the pool
// must keep at least one connection available while a lock is held for the
// queries and append performed under it. Concurrent create-booking requests
// serialize for the same key; see product/backend/README.md.
//
// The returned release function unlocks the connection and returns it to the
// pool. If unlocking fails, the connection is destroyed so the session close
// releases the lock instead of leaking it.
func (s *PostgresStore) Lock(ctx context.Context, key int64) (func() error, error) {
	conn, err := s.pool.Acquire(ctx)
	if err != nil {
		return nil, fmt.Errorf("eventstore: acquire lock connection: %w", err)
	}
	if _, err := conn.Exec(ctx, `SELECT pg_advisory_lock($1)`, key); err != nil {
		conn.Release()
		return nil, fmt.Errorf("eventstore: acquire advisory lock %d: %w", key, err)
	}
	return func() error {
		// The command's context is often cancelled by the time the deferred
		// release runs, so unlocking uses an independent, bounded context.
		unlockCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if _, err := conn.Exec(unlockCtx, `SELECT pg_advisory_unlock($1)`, key); err != nil {
			if raw := conn.Hijack(); raw != nil {
				_ = raw.Close(context.Background())
			}
			return fmt.Errorf("eventstore: release advisory lock %d: %w", key, err)
		}
		conn.Release()
		return nil
	}, nil
}

// Head returns the highest recorded event ID, or 0 when the store is empty.
func (s *PostgresStore) Head(ctx context.Context) (int64, error) {
	var id int64
	if err := s.pool.QueryRow(ctx, `SELECT COALESCE(MAX(id), 0) FROM events`).Scan(&id); err != nil {
		return 0, fmt.Errorf("eventstore: head: %w", err)
	}
	return id, nil
}

// LoadAll returns all events in recorded order.
func (s *PostgresStore) LoadAll(ctx context.Context) ([]Event, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id, aggregate_type, aggregate_id, event_type, payload, occurred_at, recorded_at
		 FROM events ORDER BY id`)
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
		 FROM events WHERE aggregate_type = $1 AND aggregate_id = $2 ORDER BY id`,
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
	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("eventstore: parse database url: %w", err)
	}
	cfg.ConnConfig.Tracer = otelpgx.NewTracer()
	return pgxpool.NewWithConfig(ctx, cfg)
}
