package user

import (
	"context"
	"sync"

	"github.com/adamzki99/booking-system/product/backend/internal/command"
)

// commandExecutor runs commands against the event store.
type commandExecutor interface {
	Execute(context.Context, command.Command) error
}

// UserService orchestrates user commands, bootstrap, and role lookups.
type UserService struct {
	commands commandExecutor
	users    *UsersProjection
	mu       sync.Mutex
}

// NewService creates a user service.
func NewService(commands commandExecutor, users *UsersProjection) *UserService {
	return &UserService{commands: commands, users: users}
}

// NewUserService is an alias for NewService.
func NewUserService(commands commandExecutor, users *UsersProjection) *UserService {
	return NewService(commands, users)
}

// Users returns the underlying projection.
func (s *UserService) Users() *UsersProjection { return s.users }

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

// ChangeOwnEmail changes a user's email.
func (s *UserService) ChangeOwnEmail(ctx context.Context, userID, newEmail, requesterEmail string) (User, error) {
	normalized, err := NormalizeEmail(newEmail)
	if err != nil {
		return User{}, err
	}
	if err := s.commands.Execute(ctx, ChangeOwnEmail{
		UserID:         userID,
		NewEmail:       normalized,
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

// ChangeEmail is an alias for ChangeOwnEmail.
func (s *UserService) ChangeEmail(ctx context.Context, userID, newEmail, requesterEmail string) (User, error) {
	return s.ChangeOwnEmail(ctx, userID, newEmail, requesterEmail)
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
