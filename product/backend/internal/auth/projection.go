package auth

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNoLoginCode indicates no unconsumed login code exists for an email.
var ErrNoLoginCode = errors.New("auth: no login code")

// ErrNoSession indicates no session exists for a token hash.
var ErrNoSession = errors.New("auth: no session")

// Projections bundles the auth read models.
type Projections struct {
	LoginCodes *LoginCodeProjection
	Sessions   *SessionProjection
}

// LoginCode is a row in the login_codes read model.
type LoginCode struct {
	CodeHash  string
	ExpiresAt time.Time
}

// LoginCodeProjection maintains the login_codes read model.
type LoginCodeProjection struct {
	pool *pgxpool.Pool
}

// NewLoginCodeProjection creates a login-code read-model projection.
func NewLoginCodeProjection(pool *pgxpool.Pool) *LoginCodeProjection {
	return &LoginCodeProjection{pool: pool}
}

// Name identifies this projection in checkpoint bookkeeping.
func (p *LoginCodeProjection) Name() string { return "login_codes" }

// Apply applies auth events to the login_codes read model.
func (p *LoginCodeProjection) Apply(ctx context.Context, event eventstore.Event) error {
	switch event.EventType {
	case LoginCodeIssuedEventType:
		var payload loginCodeIssuedPayload
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			return fmt.Errorf("auth login_codes projection: decode event %d: %w", event.ID, err)
		}
		_, err := p.pool.Exec(ctx,
			`INSERT INTO login_codes (email, code_hash, expires_at, created_at)
			 VALUES ($1, $2, $3, $4)
			 ON CONFLICT (code_hash) DO NOTHING`,
			payload.Email, payload.CodeHash, payload.ExpiresAt, event.OccurredAt,
		)
		if err != nil {
			return fmt.Errorf("auth login_codes projection: apply event %d: %w", event.ID, err)
		}
	case SessionCreatedEventType:
		var payload sessionCreatedPayload
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			return fmt.Errorf("auth login_codes projection: decode event %d: %w", event.ID, err)
		}
		_, err := p.pool.Exec(ctx,
			`UPDATE login_codes SET consumed_at = $1 WHERE code_hash = $2 AND consumed_at IS NULL`,
			event.OccurredAt, payload.CodeHash,
		)
		if err != nil {
			return fmt.Errorf("auth login_codes projection: apply event %d: %w", event.ID, err)
		}
	}
	return nil
}

// Reset clears the derived login_codes read model.
func (p *LoginCodeProjection) Reset(ctx context.Context) error {
	if _, err := p.pool.Exec(ctx, `TRUNCATE login_codes`); err != nil {
		return fmt.Errorf("auth login_codes projection: reset: %w", err)
	}
	return nil
}

// LatestUnconsumed returns the most recently issued unconsumed login code.
func (p *LoginCodeProjection) LatestUnconsumed(ctx context.Context, email string) (LoginCode, error) {
	var c LoginCode
	err := p.pool.QueryRow(ctx,
		`SELECT code_hash, expires_at FROM login_codes
		 WHERE email = $1 AND consumed_at IS NULL
		 ORDER BY id DESC
		 LIMIT 1`,
		email,
	).Scan(&c.CodeHash, &c.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return LoginCode{}, ErrNoLoginCode
	}
	if err != nil {
		return LoginCode{}, fmt.Errorf("auth login_codes projection: latest: %w", err)
	}
	return c, nil
}

// Session is a row in the sessions read model.
type Session struct {
	Email     string
	ExpiresAt time.Time
	Revoked   bool
}

// SessionProjection maintains the sessions read model.
type SessionProjection struct {
	pool *pgxpool.Pool
}

// NewSessionProjection creates a session read-model projection.
func NewSessionProjection(pool *pgxpool.Pool) *SessionProjection {
	return &SessionProjection{pool: pool}
}

// Name identifies this projection in checkpoint bookkeeping.
func (p *SessionProjection) Name() string { return "sessions" }

// Apply applies auth events to the sessions read model.
func (p *SessionProjection) Apply(ctx context.Context, event eventstore.Event) error {
	if event.EventType != SessionCreatedEventType {
		return nil
	}
	var payload sessionCreatedPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("auth sessions projection: decode event %d: %w", event.ID, err)
	}
	_, err := p.pool.Exec(ctx,
		`INSERT INTO sessions (token_hash, email, expires_at, created_at)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (token_hash) DO NOTHING`,
		payload.TokenHash, payload.Email, payload.ExpiresAt, event.OccurredAt,
	)
	if err != nil {
		return fmt.Errorf("auth sessions projection: apply event %d: %w", event.ID, err)
	}
	return nil
}

// Reset clears the derived sessions read model.
func (p *SessionProjection) Reset(ctx context.Context) error {
	if _, err := p.pool.Exec(ctx, `TRUNCATE sessions`); err != nil {
		return fmt.Errorf("auth sessions projection: reset: %w", err)
	}
	return nil
}

// Find returns the session for a token hash, or ErrNoSession if none exists.
func (p *SessionProjection) Find(ctx context.Context, tokenHash string) (Session, error) {
	var s Session
	err := p.pool.QueryRow(ctx,
		`SELECT email, expires_at, (revoked_at IS NOT NULL) FROM sessions WHERE token_hash = $1`,
		tokenHash,
	).Scan(&s.Email, &s.ExpiresAt, &s.Revoked)
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, ErrNoSession
	}
	if err != nil {
		return Session{}, fmt.Errorf("auth sessions projection: find: %w", err)
	}
	return s, nil
}
