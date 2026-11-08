package user

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

// UsersProjection maintains the users read model.
type UsersProjection struct {
	pool  *pgxpool.Pool
	Users *UsersProjection
}

// NewUsersProjection creates a users read-model projection.
func NewUsersProjection(pool *pgxpool.Pool) *UsersProjection {
	p := &UsersProjection{pool: pool}
	p.Users = p
	return p
}

// Name identifies this projection in checkpoint bookkeeping.
func (p *UsersProjection) Name() string { return "users" }

// Apply applies user events to the users read model.
func (p *UsersProjection) Apply(ctx context.Context, event eventstore.Event) error {
	switch event.EventType {
	case UserCreatedEventType:
		var payload UserCreatedPayload
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			return fmt.Errorf("user projection: decode event %d: %w", event.ID, err)
		}
		_, err := p.pool.Exec(ctx,
			`INSERT INTO users (id, email, role, address, active, created_at, updated_at)
			 VALUES ($1, $2, $3, $4, true, $5, $5)
			 ON CONFLICT (id) DO UPDATE
			 SET email = EXCLUDED.email,
			     role = EXCLUDED.role,
			     address = EXCLUDED.address,
			     active = true,
			     updated_at = EXCLUDED.updated_at`,
			payload.UserID, payload.Email, string(payload.Role), payload.Address, payload.CreatedAt,
		)
		if err != nil {
			return fmt.Errorf("user projection: apply create event %d: %w", event.ID, err)
		}
	case UserRemovedEventType:
		var payload UserRemovedPayload
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			return fmt.Errorf("user projection: decode event %d: %w", event.ID, err)
		}
		_, err := p.pool.Exec(ctx,
			`UPDATE users SET active = false, deactivated_at = $2, updated_at = $2 WHERE id = $1`,
			payload.UserID, payload.RemovedAt,
		)
		if err != nil {
			return fmt.Errorf("user projection: apply remove event %d: %w", event.ID, err)
		}
	case UserEmailChangedEventType:
		var payload UserEmailChangedPayload
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			return fmt.Errorf("user projection: decode event %d: %w", event.ID, err)
		}
		_, err := p.pool.Exec(ctx,
			`UPDATE users SET email = $2, updated_at = $3 WHERE id = $1`,
			payload.UserID, payload.NewEmail, payload.ChangedAt,
		)
		if err != nil {
			return fmt.Errorf("user projection: apply email change event %d: %w", event.ID, err)
		}
	case UserAddressChangedEventType:
		var payload UserAddressChangedPayload
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			return fmt.Errorf("user projection: decode event %d: %w", event.ID, err)
		}
		_, err := p.pool.Exec(ctx,
			`UPDATE users SET address = $2, updated_at = $3 WHERE id = $1`,
			payload.UserID, payload.Address, payload.ChangedAt,
		)
		if err != nil {
			return fmt.Errorf("user projection: apply address change event %d: %w", event.ID, err)
		}
	case UserRoleChangedEventType:
		var payload UserRoleChangedPayload
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			return fmt.Errorf("user projection: decode event %d: %w", event.ID, err)
		}
		role := payload.NewRole
		if role == "" {
			role = payload.Role
		}
		_, err := p.pool.Exec(ctx,
			`UPDATE users SET role = $2, updated_at = $3 WHERE id = $1`,
			payload.UserID, string(role), payload.ChangedAt,
		)
		if err != nil {
			return fmt.Errorf("user projection: apply role change event %d: %w", event.ID, err)
		}
	}
	return nil
}

// Reset clears the derived users read model.
func (p *UsersProjection) Reset(ctx context.Context) error {
	if _, err := p.pool.Exec(ctx, `TRUNCATE users`); err != nil {
		return fmt.Errorf("user projection: reset: %w", err)
	}
	return nil
}

// Count returns the number of user rows.
func (p *UsersProjection) Count(ctx context.Context) (int, error) {
	var n int
	if err := p.pool.QueryRow(ctx, `SELECT count(*) FROM users`).Scan(&n); err != nil {
		return 0, fmt.Errorf("user projection: count: %w", err)
	}
	return n, nil
}

// CountUsers is an alias for Count.
func (p *UsersProjection) CountUsers(ctx context.Context) (int, error) { return p.Count(ctx) }

// List returns all users ordered by created_at then id.
func (p *UsersProjection) List(ctx context.Context) ([]User, error) {
	rows, err := p.pool.Query(ctx,
		`SELECT id, email, role, address, active, deactivated_at, created_at, updated_at
		 FROM users ORDER BY created_at, id`)
	if err != nil {
		return nil, fmt.Errorf("user projection: list: %w", err)
	}
	defer rows.Close()
	var out []User
	for rows.Next() {
		u, err := scanUserRows(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("user projection: rows: %w", err)
	}
	if out == nil {
		out = []User{}
	}
	return out, nil
}

// ListUsers is an alias for List.
func (p *UsersProjection) ListUsers(ctx context.Context) ([]User, error) { return p.List(ctx) }

// All is an alias for List.
func (p *UsersProjection) All(ctx context.Context) ([]User, error) { return p.List(ctx) }

// GetByID returns a user by id.
func (p *UsersProjection) GetByID(ctx context.Context, id string) (User, error) {
	row := p.pool.QueryRow(ctx,
		`SELECT id, email, role, address, active, deactivated_at, created_at, updated_at
		 FROM users WHERE id = $1`, id)
	u, err := scanUserRow(row)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return User{}, ErrUserNotFound
		}
		return User{}, err
	}
	return u, nil
}

// ByID is an alias for GetByID.
func (p *UsersProjection) ByID(ctx context.Context, id string) (User, error) {
	return p.GetByID(ctx, id)
}

// Find is an alias for GetByID.
func (p *UsersProjection) Find(ctx context.Context, id string) (User, error) {
	return p.GetByID(ctx, id)
}

// Get is an alias for GetByID.
func (p *UsersProjection) Get(ctx context.Context, id string) (User, error) {
	return p.GetByID(ctx, id)
}

// GetByEmail returns a user by email.
func (p *UsersProjection) GetByEmail(ctx context.Context, email string) (User, error) {
	row := p.pool.QueryRow(ctx,
		`SELECT id, email, role, address, active, deactivated_at, created_at, updated_at
		 FROM users WHERE email = $1`, email)
	u, err := scanUserRow(row)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return User{}, ErrUserNotFound
		}
		return User{}, err
	}
	return u, nil
}

// ByEmail is an alias for GetByEmail.
func (p *UsersProjection) ByEmail(ctx context.Context, email string) (User, error) {
	return p.GetByEmail(ctx, email)
}

// FindByEmail is an alias for GetByEmail.
func (p *UsersProjection) FindByEmail(ctx context.Context, email string) (User, error) {
	return p.GetByEmail(ctx, email)
}

// RoleOf returns the role for an email, if the user exists.
func (p *UsersProjection) RoleOf(ctx context.Context, email string) (Role, bool) {
	u, err := p.GetByEmail(ctx, email)
	if err != nil {
		return "", false
	}
	return u.Role, true
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanUserRows(rows rowScanner) (User, error) {
	var u User
	var role string
	var deactivated *time.Time
	if err := rows.Scan(&u.ID, &u.Email, &role, &u.Address, &u.Active, &deactivated, &u.CreatedAt, &u.UpdatedAt); err != nil {
		return User{}, fmt.Errorf("user projection: scan: %w", err)
	}
	u.Role = Role(role)
	u.DeactivatedAt = deactivated
	return u, nil
}

func scanUserRow(row pgx.Row) (User, error) {
	var u User
	var role string
	var deactivated *time.Time
	if err := row.Scan(&u.ID, &u.Email, &role, &u.Address, &u.Active, &deactivated, &u.CreatedAt, &u.UpdatedAt); err != nil {
		return User{}, err
	}
	u.Role = Role(role)
	u.DeactivatedAt = deactivated
	return u, nil
}
