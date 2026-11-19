package user

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/email"
)

// commandExecutor runs commands against the event store.
type commandExecutor interface {
	Execute(context.Context, command.Command) error
}

// rateLimiter guards request rates per key.
type rateLimiter interface {
	Allow(key string, limit int, window time.Duration) bool
}

const (
	// emailChangeCodeTTL is how long an email-change verification code remains valid.
	emailChangeCodeTTL = 15 * time.Minute

	// emailChangeEmailSubject is the subject of the verification email.
	emailChangeEmailSubject = "Confirm your new email"

	requestEmailChangeLimit    = 5
	requestEmailChangeWindow   = 15 * time.Minute
	requestEmailChangeIPLimit  = 20
	requestEmailChangeIPWindow = time.Hour
)

// UserService orchestrates user commands, bootstrap, and role lookups.
type UserService struct {
	commands commandExecutor
	users    *UsersProjection
	changes  *EmailChangesProjection
	sender   email.Sender
	limiter  rateLimiter
	mu       sync.Mutex
}

// NewService creates a user service. The sender delivers the verification
// email for email changes and the limiter (nil disables rate limiting) guards
// verification emails against abuse. The email-changes projection may be nil
// when pending email-change reads are not needed.
func NewService(commands commandExecutor, users *UsersProjection, changes *EmailChangesProjection, sender email.Sender, limiter rateLimiter) *UserService {
	return &UserService{commands: commands, users: users, changes: changes, sender: sender, limiter: limiter}
}

// NewUserService is an alias for NewService.
func NewUserService(commands commandExecutor, users *UsersProjection, changes *EmailChangesProjection, sender email.Sender, limiter rateLimiter) *UserService {
	return NewService(commands, users, changes, sender, limiter)
}

// Users returns the underlying projection.
func (s *UserService) Users() *UsersProjection { return s.users }

// EmailChanges returns the email-change read model projection.
func (s *UserService) EmailChanges() *EmailChangesProjection { return s.changes }

// BootstrapAdmin creates the first admin user if none exist.
func (s *UserService) BootstrapAdmin(ctx context.Context, email string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	normalized, err := NormalizeEmail(email)
	if err != nil {
		return err
	}
	count, err := s.users.Count(ctx)
	if err != nil {
		return err
	}
	if count > 0 {
		return nil
	}
	return s.commands.Execute(ctx, BootstrapAdmin{Email: normalized})
}

// RoleOf returns the role for an email, if the user exists.
func (s *UserService) RoleOf(ctx context.Context, email string) (Role, bool) {
	if s.users == nil {
		return "", false
	}
	return s.users.RoleOf(ctx, email)
}

// Package-level RoleOf reads the registered users projection.
func RoleOf(ctx context.Context, email string) (Role, bool) {
	if defaultUsers == nil {
		return "", false
	}
	return defaultUsers.RoleOf(ctx, email)
}

// ListUsers returns all users.
func (s *UserService) ListUsers(ctx context.Context) ([]User, error) {
	return s.users.List(ctx)
}

// List is an alias for ListUsers.
func (s *UserService) List(ctx context.Context) ([]User, error) { return s.ListUsers(ctx) }

// GetUser returns a user by id.
func (s *UserService) GetUser(ctx context.Context, id string) (User, error) {
	return s.users.GetByID(ctx, id)
}

// GetByID is an alias for GetUser.
func (s *UserService) GetByID(ctx context.Context, id string) (User, error) {
	return s.GetUser(ctx, id)
}

// GetByEmail returns a user by email.
func (s *UserService) GetByEmail(ctx context.Context, email string) (User, error) {
	normalized, err := NormalizeEmail(email)
	if err != nil {
		return User{}, err
	}
	return s.users.GetByEmail(ctx, normalized)
}

// AddUser creates a basic user.
func (s *UserService) AddUser(ctx context.Context, email, address, requesterEmail string) (User, error) {
	normalizedEmail, err := NormalizeEmail(email)
	if err != nil {
		return User{}, err
	}
	if err := ValidateAddress(address); err != nil {
		return User{}, err
	}
	if err := s.commands.Execute(ctx, AddUser{
		Email:          normalizedEmail,
		Address:        address,
		RequesterEmail: requesterEmail,
	}); err != nil {
		return User{}, err
	}
	// read back
	u, err := s.users.GetByEmail(ctx, normalizedEmail)
	if err != nil {
		return User{}, err
	}
	return u, nil
}

// CreateUser is an alias for AddUser.
func (s *UserService) CreateUser(ctx context.Context, email, address, requesterEmail string) (User, error) {
	return s.AddUser(ctx, email, address, requesterEmail)
}

// RemoveUser deactivates a user.
func (s *UserService) RemoveUser(ctx context.Context, userID, requesterEmail string) error {
	return s.commands.Execute(ctx, RemoveUser{
		UserID:         userID,
		RequesterEmail: requesterEmail,
	})
}

// PendingEmailChange describes an unconfirmed email change request.
type PendingEmailChange struct {
	NewEmail  string    `json:"newEmail"`
	ExpiresAt time.Time `json:"expiresAt"`
}

// GetPendingEmailChange returns the pending email change for a user, if any.
func (s *UserService) GetPendingEmailChange(ctx context.Context, userID string) (*PendingEmailChange, error) {
	if s.changes == nil {
		return nil, nil
	}
	pending, err := s.changes.Pending(ctx, userID)
	if err != nil {
		if errors.Is(err, ErrNoPendingEmailChange) {
			return nil, nil
		}
		return nil, err
	}
	return &PendingEmailChange{NewEmail: pending.NewEmail, ExpiresAt: pending.ExpiresAt}, nil
}

// RequestEmailChange records a pending email change and emails the
// verification code to the new address. The account's login address is
// unchanged until the code is confirmed. Requesting again replaces any
// existing pending change, which can be used to resend a code or correct the
// target address.
func (s *UserService) RequestEmailChange(ctx context.Context, userID, newEmail, requesterEmail, clientIP string) (PendingEmailChange, error) {
	normalized, err := NormalizeEmail(newEmail)
	if err != nil {
		return PendingEmailChange{}, err
	}
	if s.limiter != nil {
		emailOK := s.limiter.Allow("email-change:email:"+normalized, requestEmailChangeLimit, requestEmailChangeWindow)
		ipOK := s.limiter.Allow("email-change:ip:"+clientIP, requestEmailChangeIPLimit, requestEmailChangeIPWindow)
		if !emailOK || !ipOK {
			return PendingEmailChange{}, ErrEmailChangeRateLimit
		}
	}
	if s.sender == nil {
		return PendingEmailChange{}, fmt.Errorf("user: no email sender configured")
	}
	code, err := auth.GenerateCode()
	if err != nil {
		return PendingEmailChange{}, fmt.Errorf("user: generate code: %w", err)
	}
	hash, err := auth.HashCode(code)
	if err != nil {
		return PendingEmailChange{}, fmt.Errorf("user: hash code: %w", err)
	}
	now := time.Now().UTC()
	expiresAt := now.Add(emailChangeCodeTTL)
	if err := s.commands.Execute(ctx, ChangeOwnEmail{
		UserID:         userID,
		NewEmail:       normalized,
		RequesterEmail: requesterEmail,
		CodeHash:       hash,
		ExpiresAt:      expiresAt,
	}); err != nil {
		return PendingEmailChange{}, err
	}
	if err := s.sender.Send(ctx, normalized, emailChangeEmailSubject, code); err != nil {
		return PendingEmailChange{}, fmt.Errorf("user: send verification code: %w", err)
	}
	return PendingEmailChange{NewEmail: normalized, ExpiresAt: expiresAt}, nil
}

// ConfirmEmailChange verifies the code sent to the new address, commits the
// change, and returns the updated user.
func (s *UserService) ConfirmEmailChange(ctx context.Context, userID, code, requesterEmail string) (User, error) {
	if err := auth.ValidateCode(code); err != nil {
		return User{}, err
	}
	if err := s.commands.Execute(ctx, ConfirmOwnEmailChange{
		UserID:         userID,
		Code:           code,
		RequesterEmail: requesterEmail,
	}); err != nil {
		return User{}, err
	}
	u, err := s.users.GetByID(ctx, userID)
	if err != nil {
		return User{}, err
	}
	return u, nil
}

// CancelEmailChange cancels any pending email change for the user.
func (s *UserService) CancelEmailChange(ctx context.Context, userID, requesterEmail string) error {
	return s.commands.Execute(ctx, CancelOwnEmailChange{
		UserID:         userID,
		RequesterEmail: requesterEmail,
	})
}

// ChangeUserAddress changes a basic user's address.
func (s *UserService) ChangeUserAddress(ctx context.Context, userID, address, requesterEmail string) (User, error) {
	if err := ValidateAddress(address); err != nil {
		return User{}, err
	}
	if err := s.commands.Execute(ctx, ChangeUserAddress{
		UserID:         userID,
		Address:        address,
		RequesterEmail: requesterEmail,
	}); err != nil {
		return User{}, err
	}
	u, err := s.users.GetByID(ctx, userID)
	if err != nil {
		return User{}, err
	}
	return u, nil
}

// ChangeAddress is an alias for ChangeUserAddress.
func (s *UserService) ChangeAddress(ctx context.Context, userID, address, requesterEmail string) (User, error) {
	return s.ChangeUserAddress(ctx, userID, address, requesterEmail)
}

// ChangeUserRole changes a user's role (admin only).
func (s *UserService) ChangeUserRole(ctx context.Context, userID string, role any, requesterEmail string) (User, error) {
	r, err := toRole(role)
	if err != nil {
		return User{}, err
	}
	if err := ValidateRole(r); err != nil {
		return User{}, err
	}
	if err := s.commands.Execute(ctx, ChangeUserRole{
		UserID:         userID,
		Role:           r,
		NewRole:        r,
		RequesterEmail: requesterEmail,
	}); err != nil {
		return User{}, err
	}
	u, err := s.users.GetByID(ctx, userID)
	if err != nil {
		return User{}, err
	}
	return u, nil
}

// toRole converts a role-like value to Role.
func toRole(v any) (Role, error) {
	switch t := v.(type) {
	case Role:
		return t, nil
	case string:
		return Role(t), nil
	case *Role:
		if t == nil {
			return "", ErrInvalidRole
		}
		return *t, nil
	default:
		return "", ErrInvalidRole
	}
}

// ChangeRole is an alias for ChangeUserRole.
func (s *UserService) ChangeRole(ctx context.Context, userID string, role any, requesterEmail string) (User, error) {
	return s.ChangeUserRole(ctx, userID, role, requesterEmail)
}

// UpdateUserRole is an alias for ChangeUserRole.
func (s *UserService) UpdateUserRole(ctx context.Context, userID string, role any, requesterEmail string) (User, error) {
	return s.ChangeUserRole(ctx, userID, role, requesterEmail)
}

// SetUserRole is an alias for ChangeUserRole.
func (s *UserService) SetUserRole(ctx context.Context, userID string, role any, requesterEmail string) (User, error) {
	return s.ChangeUserRole(ctx, userID, role, requesterEmail)
}
