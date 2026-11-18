package user

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
)

const (
	// BootstrapAdminCommandType identifies BootstrapAdmin commands.
	BootstrapAdminCommandType = "user.BootstrapAdmin"
	// AddUserCommandType identifies AddUser commands.
	AddUserCommandType = "user.AddUser"
	// RemoveUserCommandType identifies RemoveUser commands.
	RemoveUserCommandType = "user.RemoveUser"
	// ChangeOwnEmailCommandType identifies ChangeOwnEmail commands.
	ChangeOwnEmailCommandType = "user.ChangeOwnEmail"
	// ChangeUserAddressCommandType identifies ChangeUserAddress commands.
	ChangeUserAddressCommandType = "user.ChangeUserAddress"
	// ChangeUserRoleCommandType identifies ChangeUserRole commands.
	ChangeUserRoleCommandType = "user.ChangeUserRole"
	// SeedUserCommandType identifies SeedUser commands.
	SeedUserCommandType = "user.SeedUser"
)

// BootstrapAdmin creates the first admin user.
type BootstrapAdmin struct {
	Email string
}

// CommandType implements command.Command.
func (BootstrapAdmin) CommandType() string { return BootstrapAdminCommandType }

// AddUser creates a basic user (super/admin only).
type AddUser struct {
	Email          string
	Address        string
	RequesterEmail string
}

// CommandType implements command.Command.
func (AddUser) CommandType() string { return AddUserCommandType }

// RemoveUser deactivates a basic user (super/admin only).
type RemoveUser struct {
	UserID         string
	RequesterEmail string
}

// CommandType implements command.Command.
func (RemoveUser) CommandType() string { return RemoveUserCommandType }

// ChangeOwnEmail requests an email change: it records a pending change with a
// verification code hash but does not commit the new address.
type ChangeOwnEmail struct {
	UserID         string
	NewEmail       string
	RequesterEmail string
	// CodeHash stores the bcrypt hash of the verification code emailed to the
	// new address; empty is rejected.
	CodeHash  string
	ExpiresAt time.Time
}

// CommandType implements command.Command.
func (ChangeOwnEmail) CommandType() string { return ChangeOwnEmailCommandType }

// ConfirmOwnEmailChangeCommandType identifies ConfirmOwnEmailChange commands.
const ConfirmOwnEmailChangeCommandType = "user.ConfirmOwnEmailChange"

// ConfirmOwnEmailChange verifies the code emailed to the new address and
// commits the email change together with the session re-keying event.
type ConfirmOwnEmailChange struct {
	UserID         string
	Code           string
	RequesterEmail string
}

// CommandType implements command.Command.
func (ConfirmOwnEmailChange) CommandType() string { return ConfirmOwnEmailChangeCommandType }

// ChangeUserAddress changes a basic user's address (super/admin only).
type ChangeUserAddress struct {
	UserID         string
	Address        string
	RequesterEmail string
}

// CommandType implements command.Command.
func (ChangeUserAddress) CommandType() string { return ChangeUserAddressCommandType }

// ChangeUserRole changes a user's role (admin only).
type ChangeUserRole struct {
	UserID         string
	Role           Role
	NewRole        Role
	RequesterEmail string
}

// CommandType implements command.Command.
func (ChangeUserRole) CommandType() string { return ChangeUserRoleCommandType }

// SeedUserCommand creates a user with a given role (dev seeding only).
type SeedUserCommand struct {
	Email string
	Role  Role
}

// CommandType implements command.Command.
func (SeedUserCommand) CommandType() string { return SeedUserCommandType }

// defaultUsers is the projection registered by Register; used by package-level helpers.
var defaultUsers *UsersProjection

// defaultChanges is the email-change projection registered by Register.
var defaultChanges *EmailChangesProjection

// Register wires the user commands and projection into the registry.
func Register(r *registry.Registry) *UsersProjection {
	users := NewUsersProjection(r.DB())
	changes := NewEmailChangesProjection(r.DB())
	defaultUsers = users
	defaultChanges = changes
	r.RegisterCommand(BootstrapAdminCommandType, handleBootstrapAdmin(users))
	r.RegisterCommand(AddUserCommandType, handleAddUser(users))
	r.RegisterCommand(RemoveUserCommandType, handleRemoveUser(users))
	r.RegisterCommand(ChangeOwnEmailCommandType, handleChangeOwnEmail(users))
	r.RegisterCommand(ConfirmOwnEmailChangeCommandType, handleConfirmOwnEmail(users, changes))
	r.RegisterCommand(ChangeUserAddressCommandType, handleChangeUserAddress(users))
	r.RegisterCommand(ChangeUserRoleCommandType, handleChangeUserRole(users))
	r.RegisterCommand(SeedUserCommandType, handleSeedUser(users))
	r.RegisterProjection(users)
	r.RegisterProjection(changes)
	return users
}

// Projections bundles user read models (for parity with auth).
type Projections struct {
	Users        *UsersProjection
	EmailChanges *EmailChangesProjection
}

// RegisterWithProjections is an alias returning a Projections wrapper.
func RegisterWithProjections(r *registry.Registry) *Projections {
	_ = Register(r)
	return &Projections{Users: defaultUsers, EmailChanges: defaultChanges}
}

func handleBootstrapAdmin(users *UsersProjection) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var b BootstrapAdmin
		switch typed := cmd.(type) {
		case BootstrapAdmin:
			b = typed
		case *BootstrapAdmin:
			if typed == nil {
				return nil, errors.New("user: command is nil")
			}
			b = *typed
		default:
			return nil, fmt.Errorf("user: expected BootstrapAdmin, got %T", cmd)
		}

		email, err := NormalizeEmail(b.Email)
		if err != nil {
			return nil, err
		}

		count, err := users.Count(ctx)
		if err != nil {
			return nil, err
		}
		if count > 0 {
			return nil, ErrBootstrapNotAllowed
		}

		now := time.Now().UTC()
		id := NewID()
		payload, err := json.Marshal(UserCreatedPayload{
			UserID:    id,
			Email:     email,
			Role:      RoleAdmin,
			Address:   "",
			CreatedBy: "system",
			CreatedAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("user: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: AggregateType,
			AggregateID:   id,
			EventType:     UserCreatedEventType,
			Payload:       payload,
			OccurredAt:    now,
		}}, nil
	}
}

func handleAddUser(users *UsersProjection) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var a AddUser
		switch typed := cmd.(type) {
		case AddUser:
			a = typed
		case *AddUser:
			if typed == nil {
				return nil, errors.New("user: command is nil")
			}
			a = *typed
		default:
			return nil, fmt.Errorf("user: expected AddUser, got %T", cmd)
		}

		requesterEmail, err := NormalizeEmail(a.RequesterEmail)
		if err != nil {
			return nil, ErrForbidden
		}
		reqUser, err := users.GetByEmail(ctx, requesterEmail)
		if err != nil || !reqUser.Role.AtLeast(RoleSuper) {
			return nil, ErrForbidden
		}

		email, err := NormalizeEmail(a.Email)
		if err != nil {
			return nil, err
		}
		if err := ValidateAddress(a.Address); err != nil {
			return nil, err
		}
		if _, err := users.GetByEmail(ctx, email); err == nil {
			return nil, ErrDuplicateEmail
		} else if !errors.Is(err, ErrUserNotFound) {
			return nil, err
		}

		now := time.Now().UTC()
		address := NormalizeAddress(a.Address)
		id := NewID()
		payload, err := json.Marshal(UserCreatedPayload{
			UserID:    id,
			Email:     email,
			Role:      RoleBasic,
			Address:   address,
			CreatedBy: requesterEmail,
			CreatedAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("user: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: AggregateType,
			AggregateID:   id,
			EventType:     UserCreatedEventType,
			Payload:       payload,
			OccurredAt:    now,
		}}, nil
	}
}

func handleRemoveUser(users *UsersProjection) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var r RemoveUser
		switch typed := cmd.(type) {
		case RemoveUser:
			r = typed
		case *RemoveUser:
			if typed == nil {
				return nil, errors.New("user: command is nil")
			}
			r = *typed
		default:
			return nil, fmt.Errorf("user: expected RemoveUser, got %T", cmd)
		}

		requesterEmail, err := NormalizeEmail(r.RequesterEmail)
		if err != nil {
			return nil, ErrForbidden
		}
		reqUser, err := users.GetByEmail(ctx, requesterEmail)
		if err != nil || !reqUser.Role.AtLeast(RoleSuper) {
			return nil, ErrForbidden
		}

		target, err := users.GetByID(ctx, r.UserID)
		if err != nil {
			if errors.Is(err, ErrUserNotFound) {
				return nil, ErrUserNotFound
			}
			return nil, err
		}
		if target.Email == requesterEmail {
			return nil, ErrSelfRemoval
		}
		if !target.Active {
			return nil, ErrNotRemovable
		}
		if reqUser.Role.AtLeast(RoleAdmin) {
			if target.Role == RoleAdmin {
				return nil, ErrNotRemovable
			}
		} else {
			if target.Role != RoleBasic {
				return nil, ErrTargetNotBasic
			}
		}

		now := time.Now().UTC()
		payload, err := json.Marshal(UserRemovedPayload{
			UserID:    target.ID,
			RemovedBy: requesterEmail,
			RemovedAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("user: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: AggregateType,
			AggregateID:   target.ID,
			EventType:     UserRemovedEventType,
			Payload:       payload,
			OccurredAt:    now,
		}}, nil
	}
}

func handleChangeOwnEmail(users *UsersProjection) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var c ChangeOwnEmail
		switch typed := cmd.(type) {
		case ChangeOwnEmail:
			c = typed
		case *ChangeOwnEmail:
			if typed == nil {
				return nil, errors.New("user: command is nil")
			}
			c = *typed
		default:
			return nil, fmt.Errorf("user: expected ChangeOwnEmail, got %T", cmd)
		}

		target, err := users.GetByID(ctx, c.UserID)
		if err != nil {
			if errors.Is(err, ErrUserNotFound) {
				return nil, ErrUserNotFound
			}
			return nil, err
		}

		requesterEmail, err := NormalizeEmail(c.RequesterEmail)
		if err != nil {
			return nil, ErrForbidden
		}
		reqUser, rerr := users.GetByEmail(ctx, requesterEmail)
		allowed := false
		if rerr == nil {
			if requesterEmail == target.Email {
				allowed = true
			}
			if reqUser.Role.AtLeast(RoleAdmin) {
				allowed = true
			}
		}
		if !allowed {
			return nil, ErrForbidden
		}

		newEmail, err := NormalizeEmail(c.NewEmail)
		if err != nil {
			return nil, err
		}
		if newEmail == target.Email {
			return nil, ErrUnchangedEmail
		}
		if existing, err := users.GetByEmail(ctx, newEmail); err == nil {
			if existing.ID != target.ID {
				return nil, ErrDuplicateEmail
			}
		} else if !errors.Is(err, ErrUserNotFound) {
			return nil, err
		}
		if c.CodeHash == "" {
			return nil, ErrInvalidEmail
		}
		if c.ExpiresAt.IsZero() || !c.ExpiresAt.After(time.Now().UTC()) {
			return nil, ErrEmailChangeExpired
		}

		now := time.Now().UTC()
		payload, err := json.Marshal(UserEmailChangeRequestedPayload{
			UserID:      target.ID,
			OldEmail:    target.Email,
			NewEmail:    newEmail,
			CodeHash:    c.CodeHash,
			ExpiresAt:   c.ExpiresAt,
			RequestedAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("user: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: AggregateType,
			AggregateID:   target.ID,
			EventType:     UserEmailChangeRequestedEventType,
			Payload:       payload,
			OccurredAt:    now,
		}}, nil
	}
}

func handleConfirmOwnEmail(users *UsersProjection, changes *EmailChangesProjection) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var c ConfirmOwnEmailChange
		switch typed := cmd.(type) {
		case ConfirmOwnEmailChange:
			c = typed
		case *ConfirmOwnEmailChange:
			if typed == nil {
				return nil, errors.New("user: command is nil")
			}
			c = *typed
		default:
			return nil, fmt.Errorf("user: expected ConfirmOwnEmailChange, got %T", cmd)
		}

		target, err := users.GetByID(ctx, c.UserID)
		if err != nil {
			if errors.Is(err, ErrUserNotFound) {
				return nil, ErrUserNotFound
			}
			return nil, err
		}

		requesterEmail, err := NormalizeEmail(c.RequesterEmail)
		if err != nil {
			return nil, ErrForbidden
		}
		reqUser, rerr := users.GetByEmail(ctx, requesterEmail)
		allowed := false
		if rerr == nil {
			if requesterEmail == target.Email {
				allowed = true
			}
			if reqUser.Role.AtLeast(RoleAdmin) {
				allowed = true
			}
		}
		if !allowed {
			return nil, ErrForbidden
		}

		pending, err := changes.Pending(ctx, target.ID)
		if err != nil {
			return nil, err
		}
		if time.Now().UTC().After(pending.ExpiresAt) {
			return nil, ErrEmailChangeExpired
		}
		if !auth.VerifyCodeHash(c.Code, pending.CodeHash) {
			return nil, ErrInvalidChangeCode
		}
		// The new address may have been claimed after the request was made;
		// the first confirmed change wins.
		if existing, err := users.GetByEmail(ctx, pending.NewEmail); err == nil {
			if existing.ID != target.ID {
				return nil, ErrDuplicateEmail
			}
		} else if !errors.Is(err, ErrUserNotFound) {
			return nil, err
		}

		now := time.Now().UTC()
		changedPayload, err := json.Marshal(UserEmailChangedPayload{
			UserID:    target.ID,
			OldEmail:  target.Email,
			NewEmail:  pending.NewEmail,
			ChangedAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("user: marshal event: %w", err)
		}
		// Keep open sessions valid: they are re-keyed to the new address in the
		// same transaction as the account change.
		sessionPayload, err := json.Marshal(auth.SessionIdentityChangedPayload{
			OldEmail:  target.Email,
			NewEmail:  pending.NewEmail,
			ChangedAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("user: marshal event: %w", err)
		}
		return []eventstore.Event{
			{
				AggregateType: AggregateType,
				AggregateID:   target.ID,
				EventType:     UserEmailChangedEventType,
				Payload:       changedPayload,
				OccurredAt:    now,
			},
			{
				AggregateType: auth.AggregateType,
				AggregateID:   target.ID,
				EventType:     auth.SessionIdentityChangedEventType,
				Payload:       sessionPayload,
				OccurredAt:    now,
			},
		}, nil
	}
}

func handleChangeUserAddress(users *UsersProjection) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var c ChangeUserAddress
		switch typed := cmd.(type) {
		case ChangeUserAddress:
			c = typed
		case *ChangeUserAddress:
			if typed == nil {
				return nil, errors.New("user: command is nil")
			}
			c = *typed
		default:
			return nil, fmt.Errorf("user: expected ChangeUserAddress, got %T", cmd)
		}

		requesterEmail, err := NormalizeEmail(c.RequesterEmail)
		if err != nil {
			return nil, ErrForbidden
		}
		reqUser, err := users.GetByEmail(ctx, requesterEmail)
		if err != nil || !reqUser.Role.AtLeast(RoleSuper) {
			return nil, ErrForbidden
		}

		target, err := users.GetByID(ctx, c.UserID)
		if err != nil {
			if errors.Is(err, ErrUserNotFound) {
				return nil, ErrUserNotFound
			}
			return nil, err
		}
		if target.Role != RoleBasic {
			return nil, ErrTargetNotBasic
		}
		if err := ValidateAddress(c.Address); err != nil {
			return nil, err
		}

		now := time.Now().UTC()
		address := NormalizeAddress(c.Address)
		payload, err := json.Marshal(UserAddressChangedPayload{
			UserID:    target.ID,
			Address:   address,
			ChangedBy: requesterEmail,
			ChangedAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("user: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: AggregateType,
			AggregateID:   target.ID,
			EventType:     UserAddressChangedEventType,
			Payload:       payload,
			OccurredAt:    now,
		}}, nil
	}
}

func handleChangeUserRole(users *UsersProjection) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var c ChangeUserRole
		switch typed := cmd.(type) {
		case ChangeUserRole:
			c = typed
		case *ChangeUserRole:
			if typed == nil {
				return nil, errors.New("user: command is nil")
			}
			c = *typed
		default:
			return nil, fmt.Errorf("user: expected ChangeUserRole, got %T", cmd)
		}

		requesterEmail, err := NormalizeEmail(c.RequesterEmail)
		if err != nil {
			return nil, ErrForbidden
		}
		reqUser, err := users.GetByEmail(ctx, requesterEmail)
		if err != nil || !reqUser.Role.AtLeast(RoleAdmin) {
			return nil, ErrForbidden
		}

		target, err := users.GetByID(ctx, c.UserID)
		if err != nil {
			if errors.Is(err, ErrUserNotFound) {
				return nil, ErrUserNotFound
			}
			return nil, err
		}

		newRole := c.Role
		if newRole == "" {
			newRole = c.NewRole
		}
		if err := ValidateRole(newRole); err != nil {
			return nil, err
		}

		now := time.Now().UTC()
		payload, err := json.Marshal(UserRoleChangedPayload{
			UserID:    target.ID,
			OldRole:   target.Role,
			NewRole:   newRole,
			Role:      newRole,
			ChangedBy: requesterEmail,
			ChangedAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("user: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: AggregateType,
			AggregateID:   target.ID,
			EventType:     UserRoleChangedEventType,
			Payload:       payload,
			OccurredAt:    now,
		}}, nil
	}
}

func handleSeedUser(users *UsersProjection) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var su SeedUserCommand
		switch typed := cmd.(type) {
		case SeedUserCommand:
			su = typed
		case *SeedUserCommand:
			if typed == nil {
				return nil, errors.New("user: command is nil")
			}
			su = *typed
		default:
			return nil, fmt.Errorf("user: expected SeedUserCommand, got %T", cmd)
		}

		email, err := NormalizeEmail(su.Email)
		if err != nil {
			return nil, err
		}
		if err := ValidateRole(su.Role); err != nil {
			return nil, err
		}

		if existing, err := users.GetByEmail(ctx, email); err == nil {
			// already exists; do not overwrite
			_ = existing
			return nil, nil
		} else if !errors.Is(err, ErrUserNotFound) {
			return nil, err
		}

		now := time.Now().UTC()
		id := NewID()
		payload, err := json.Marshal(UserCreatedPayload{
			UserID:    id,
			Email:     email,
			Role:      su.Role,
			Address:   "",
			CreatedBy: "system-seed",
			CreatedAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("user: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: AggregateType,
			AggregateID:   id,
			EventType:     UserCreatedEventType,
			Payload:       payload,
			OccurredAt:    now,
		}}, nil
	}
}
