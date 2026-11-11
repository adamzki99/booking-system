package user_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

func TestValidateRoleAcceptsKnownRoles(t *testing.T) {
	for _, r := range []user.Role{user.RoleBasic, user.RoleSuper, user.RoleAdmin} {
		if err := user.ValidateRole(r); err != nil {
			t.Errorf("ValidateRole(%q) = %v, want nil", r, err)
		}
	}
}

func TestValidateRoleRejectsUnknownRoles(t *testing.T) {
	for _, r := range []user.Role{"", "unknown", "ADMIN", "Basic", " super"} {
		if err := user.ValidateRole(r); !errors.Is(err, user.ErrInvalidRole) {
			t.Errorf("ValidateRole(%q) = %v, want ErrInvalidRole", r, err)
		}
	}
}

func TestRoleAliasesMatchConstants(t *testing.T) {
	if user.Basic != user.RoleBasic || user.Super != user.RoleSuper || user.Admin != user.RoleAdmin {
		t.Fatalf("role aliases do not match: %q/%q/%q", user.Basic, user.Super, user.Admin)
	}
}

func TestRoleAtLeastOrdersBasicSuperAdmin(t *testing.T) {
	tests := []struct {
		role user.Role
		min  user.Role
		want bool
	}{
		{user.RoleBasic, user.RoleBasic, true},
		{user.RoleBasic, user.RoleSuper, false},
		{user.RoleBasic, user.RoleAdmin, false},
		{user.RoleSuper, user.RoleBasic, true},
		{user.RoleSuper, user.RoleSuper, true},
		{user.RoleSuper, user.RoleAdmin, false},
		{user.RoleAdmin, user.RoleBasic, true},
		{user.RoleAdmin, user.RoleSuper, true},
		{user.RoleAdmin, user.RoleAdmin, true},
	}
	for _, tc := range tests {
		if got := tc.role.AtLeast(tc.min); got != tc.want {
			t.Errorf("(%q).AtLeast(%q) = %v, want %v", tc.role, tc.min, got, tc.want)
		}
	}
}

func TestRoleAtLeastRejectsUnknownRoles(t *testing.T) {
	unknown := user.Role("unknown")
	for _, min := range []user.Role{user.RoleBasic, user.RoleSuper, user.RoleAdmin} {
		if unknown.AtLeast(min) {
			t.Errorf("unknown role must not satisfy AtLeast(%q)", min)
		}
	}
	for _, r := range []user.Role{user.RoleBasic, user.RoleSuper, user.RoleAdmin} {
		if r.AtLeast(unknown) {
			t.Errorf("%q.AtLeast(unknown) = true, want false", r)
		}
	}
	if unknown.AtLeast(unknown) {
		t.Error("unknown role must not satisfy AtLeast(unknown)")
	}
}

func TestRoleString(t *testing.T) {
	if got := user.RoleAdmin.String(); got != "admin" {
		t.Fatalf("RoleAdmin.String() = %q, want admin", got)
	}
}

func TestNormalizeEmailLowercasesAndTrims(t *testing.T) {
	got, err := user.NormalizeEmail("  Alice@Example.COM  ")
	if err != nil {
		t.Fatal(err)
	}
	if want := "alice@example.com"; got != want {
		t.Fatalf("NormalizeEmail = %q, want %q", got, want)
	}
}

func TestNormalizeEmailRejectsInvalid(t *testing.T) {
	for _, e := range []string{"", "alice", "alice@", "@example.com", "alice example.com"} {
		if _, err := user.NormalizeEmail(e); !errors.Is(err, user.ErrInvalidEmail) {
			t.Errorf("NormalizeEmail(%q) error = %v, want ErrInvalidEmail", e, err)
		}
	}
}

func TestValidateEmail(t *testing.T) {
	for _, e := range []string{"alice@example.com", "Bob@Sub.Example.com"} {
		if err := user.ValidateEmail(e); err != nil {
			t.Errorf("ValidateEmail(%q) = %v, want nil", e, err)
		}
	}
	for _, e := range []string{"", "alice", "alice@example.com extra"} {
		if err := user.ValidateEmail(e); !errors.Is(err, user.ErrInvalidEmail) {
			t.Errorf("ValidateEmail(%q) = %v, want ErrInvalidEmail", e, err)
		}
	}
}

func TestNormalizeAddressTrims(t *testing.T) {
	if got := user.NormalizeAddress("  Saunatie 4  "); got != "Saunatie 4" {
		t.Fatalf("NormalizeAddress = %q, want %q", got, "Saunatie 4")
	}
}

func TestValidateAddressLength(t *testing.T) {
	if err := user.ValidateAddress("Saunatie 4"); err != nil {
		t.Fatalf("ValidateAddress(short) = %v, want nil", err)
	}
	limit := strings.Repeat("a", 1000)
	if err := user.ValidateAddress(limit); err != nil {
		t.Fatalf("ValidateAddress(1000 chars) = %v, want nil", err)
	}
	tooLong := strings.Repeat("a", 1001)
	if err := user.ValidateAddress(tooLong); !errors.Is(err, user.ErrInvalidAddress) {
		t.Fatalf("ValidateAddress(1001 chars) = %v, want ErrInvalidAddress", err)
	}
}

func TestNewIDReturnsUniqueNonEmptyIDs(t *testing.T) {
	seen := make(map[string]bool)
	for i := 0; i < 100; i++ {
		id := user.NewID()
		if id == "" {
			t.Fatal("NewID returned an empty string")
		}
		if seen[id] {
			t.Fatalf("NewID returned duplicate id %q", id)
		}
		seen[id] = true
	}
}
