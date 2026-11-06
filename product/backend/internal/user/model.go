package user

import (
	"crypto/rand"

	"errors"
	"fmt"
	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"strings"
	"time"
)

// Role is a user's authorization level.
type Role string

const (
	// RoleBasic is the default role for created users.
	RoleBasic Role = "basic"
	// RoleSuper is a superset of basic capabilities.
	RoleSuper Role = "super"
	// RoleAdmin is the highest privilege level.
	RoleAdmin Role = "admin"

	// Aliases matching the bare role names.
	Basic Role = "basic"
	Super Role = "super"
	Admin Role = "admin"
)

// rank returns the ordering of a role; unknown roles rank below basic.
func rank(r Role) int {
	switch r {
	case RoleBasic:
		return 0
	case RoleSuper:
		return 1
	case RoleAdmin:
		return 2
	default:
		return -1
	}
}

// AtLeast reports whether r is at least as privileged as min.
func (r Role) AtLeast(min Role) bool {
	return rank(r) >= rank(min) && rank(r) >= 0 && rank(min) >= 0
}

// String returns the textual form of the role.
func (r Role) String() string { return string(r) }

// ValidateRole reports whether r is a known role.
func ValidateRole(r Role) error {
	if rank(r) < 0 {
		return ErrInvalidRole
	}
	return nil
}

// User is a row in the users read model.
type User struct {
	ID            string     `json:"id"`
	Email         string     `json:"email"`
	Role          Role       `json:"role"`
	Address       string     `json:"address"`
	Active        bool       `json:"active"`
	DeactivatedAt *time.Time `json:"deactivatedAt"`
	CreatedAt     time.Time  `json:"createdAt"`
	UpdatedAt     time.Time  `json:"updatedAt"`
}

// Error sentinels. Aliases are provided so callers using either naming
// convention can match errors with errors.Is.
var (
	ErrInvalidEmail   = auth.ErrInvalidEmail
	ErrInvalidRole    = errors.New("user: invalid role")
	ErrInvalidAddress = errors.New("user: invalid address")

	ErrForbidden        = errors.New("user: forbidden")
	ErrPermissionDenied = ErrForbidden
	ErrNotAuthorized    = ErrForbidden
	ErrAccessDenied     = ErrForbidden

	ErrDuplicateEmail     = errors.New("user: duplicate email")
	ErrEmailTaken         = ErrDuplicateEmail
	ErrEmailAlreadyExists = ErrDuplicateEmail
	ErrConflict           = ErrDuplicateEmail

	ErrUserNotFound = errors.New("user: user not found")
	ErrNotFound     = ErrUserNotFound

	ErrNotRemovable     = errors.New("user: user not removable")
	ErrCannotRemove     = ErrNotRemovable
	ErrUserNotRemovable = ErrNotRemovable
	ErrNotRemovableUser = ErrNotRemovable

	ErrSelfRemoval      = errors.New("user: cannot remove self")
	ErrCannotRemoveSelf = ErrSelfRemoval

	ErrTargetNotBasic = errors.New("user: target is not a basic user")
	ErrNotBasicUser   = ErrTargetNotBasic

	ErrBootstrapNotAllowed = errors.New("user: bootstrap not allowed")
	ErrUsersExist          = ErrBootstrapNotAllowed
	ErrAlreadyBootstrapped = ErrBootstrapNotAllowed
	ErrNotEmpty            = ErrBootstrapNotAllowed
)

// NormalizeEmail trims, lowercases, and validates an email address.
func NormalizeEmail(email string) (string, error) {
	normalized, err := auth.NormalizeEmail(email)
	if err != nil {
		return "", ErrInvalidEmail
	}
	return normalized, nil
}

// ValidateEmail reports whether an email address is acceptable.
func ValidateEmail(email string) error {
	_, err := NormalizeEmail(email)
	return err
}

// NormalizeAddress trims surrounding whitespace from an address.
func NormalizeAddress(address string) string {
	return strings.TrimSpace(address)
}

// ValidateAddress reports whether an address is acceptable.
func ValidateAddress(address string) error {
	if len(strings.TrimSpace(address)) > 1000 {
		return ErrInvalidAddress
	}
	return nil
}

// NewID generates a new UUID string for a user.
func NewID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("user-%d", time.Now().UnixNano())
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
