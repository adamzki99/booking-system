package user_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

func writeSeedFile(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "users.yaml")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoadSeedUsersNormalizesEntries(t *testing.T) {
	path := writeSeedFile(t, `
users:
  - email: "  Alice@Example.COM "
    role: admin
  - email: bob@example.com
    role: " super "
  - email: carol@example.com
    role: basic
`)

	seeds, err := user.LoadSeedUsers(path)
	if err != nil {
		t.Fatal(err)
	}
	want := []user.SeedUser{
		{Email: "alice@example.com", Role: user.RoleAdmin},
		{Email: "bob@example.com", Role: user.RoleSuper},
		{Email: "carol@example.com", Role: user.RoleBasic},
	}
	if len(seeds) != len(want) {
		t.Fatalf("got %d seeds, want %d", len(seeds), len(want))
	}
	for i := range want {
		if seeds[i] != want[i] {
			t.Errorf("seed %d = %+v, want %+v", i, seeds[i], want[i])
		}
	}
}

func TestLoadSeedUsersEmptyFileYieldsNoSeeds(t *testing.T) {
	path := writeSeedFile(t, "users: []\n")
	seeds, err := user.LoadSeedUsers(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(seeds) != 0 {
		t.Fatalf("got %d seeds, want 0", len(seeds))
	}
}

func TestLoadSeedUsersRejectsInvalidEmail(t *testing.T) {
	path := writeSeedFile(t, `
users:
  - email: not-an-email
    role: basic
`)
	if _, err := user.LoadSeedUsers(path); !errors.Is(err, user.ErrInvalidEmail) {
		t.Fatalf("expected ErrInvalidEmail, got %v", err)
	}
}

func TestLoadSeedUsersRejectsInvalidRole(t *testing.T) {
	path := writeSeedFile(t, `
users:
  - email: alice@example.com
    role: wizard
`)
	if _, err := user.LoadSeedUsers(path); !errors.Is(err, user.ErrInvalidRole) {
		t.Fatalf("expected ErrInvalidRole, got %v", err)
	}
}

func TestLoadSeedUsersRejectsMissingFile(t *testing.T) {
	if _, err := user.LoadSeedUsers(filepath.Join(t.TempDir(), "absent.yaml")); err == nil {
		t.Fatal("expected an error for a missing seed file")
	}
}

func TestLoadSeedUsersRejectsMalformedYAML(t *testing.T) {
	path := writeSeedFile(t, "users: [unclosed\n")
	if _, err := user.LoadSeedUsers(path); err == nil {
		t.Fatal("expected an error for malformed YAML")
	}
}

func TestSeedDevUsersCreatesUsersWhenEnabled(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	path := writeSeedFile(t, `
users:
  - email: admin@example.com
    role: admin
  - email: super@example.com
    role: super
  - email: basic@example.com
    role: basic
`)

	n, err := user.SeedDevUsers(ctx, ta.service, true, path)
	if err != nil {
		t.Fatal(err)
	}
	if n != 3 {
		t.Fatalf("seeded %d users, want 3", n)
	}

	for email, wantRole := range map[string]user.Role{
		"admin@example.com": user.RoleAdmin,
		"super@example.com": user.RoleSuper,
		"basic@example.com": user.RoleBasic,
	} {
		u, err := ta.users.GetByEmail(ctx, email)
		if err != nil {
			t.Fatalf("seeded user %s missing: %v", email, err)
		}
		if u.Role != wantRole {
			t.Errorf("%s role = %q, want %q", email, u.Role, wantRole)
		}
		if !u.Active {
			t.Errorf("%s should be active", email)
		}
	}

	// Seeding again is idempotent.
	n, err = user.SeedDevUsers(ctx, ta.service, true, path)
	if err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("second seed created %d users, want 0", n)
	}
}

func TestSeedDevUsersNoOpWhenDisabled(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	path := writeSeedFile(t, `
users:
  - email: admin@example.com
    role: admin
`)

	n, err := user.SeedDevUsers(ctx, ta.service, false, path)
	if err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("seeded %d users with devMode disabled, want 0", n)
	}
	count, err := ta.users.Count(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Fatalf("user count = %d, want 0", count)
	}
}

func TestSeedDevUsersNoOpOnEmptyPath(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()

	n, err := user.SeedDevUsers(ctx, ta.service, true, "   ")
	if err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("seeded %d users with empty path, want 0", n)
	}
}

func TestSeedDevUsersNoOpWithNilService(t *testing.T) {
	ctx := context.Background()
	path := writeSeedFile(t, `
users:
  - email: admin@example.com
    role: admin
`)

	n, err := user.SeedDevUsers(ctx, nil, true, path)
	if err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("seeded %d users with nil service, want 0", n)
	}
}

func TestSeedDevUsersPropagatesFileErrors(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()

	_, err := user.SeedDevUsers(ctx, ta.service, true, filepath.Join(t.TempDir(), "absent.yaml"))
	if err == nil {
		t.Fatal("expected an error for a missing seed file")
	}
}

func TestSeedUsersRejectsInvalidSeedRole(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()

	_, err := ta.service.SeedUsers(ctx, []user.SeedUser{{Email: "alice@example.com", Role: "wizard"}})
	if !errors.Is(err, user.ErrInvalidRole) {
		t.Fatalf("expected ErrInvalidRole, got %v", err)
	}
}
