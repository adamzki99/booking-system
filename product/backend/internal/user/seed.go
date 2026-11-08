package user

import (
	"context"
	"errors"
	"os"
	"strings"
	"time"

	"go.yaml.in/yaml/v3"
)

// SeedUser is a declarative user fixture entry (email + role).
type SeedUser struct {
	Email string `yaml:"email"`
	Role  Role   `yaml:"role"`
}

// seedFile is the on-disk YAML shape.
type seedFile struct {
	Users []SeedUser `yaml:"users"`
}

// LoadSeedUsers parses a YAML file into validated seed users.
func LoadSeedUsers(path string) ([]SeedUser, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var f seedFile
	if err := yaml.Unmarshal(data, &f); err != nil {
		return nil, err
	}
	out := make([]SeedUser, 0, len(f.Users))
	for _, s := range f.Users {
		email, err := NormalizeEmail(s.Email)
		if err != nil {
			return nil, ErrInvalidEmail
		}
		role := Role(strings.TrimSpace(string(s.Role)))
		if err := ValidateRole(role); err != nil {
			return nil, ErrInvalidRole
		}
		out = append(out, SeedUser{Email: email, Role: role})
	}
	return out, nil
}

// SeedDevUsers seeds users from a YAML file when devMode is true.
// Prod (devMode false) never reads the file. Empty path is a no-op.
func SeedDevUsers(ctx context.Context, svc *UserService, devMode bool, file string) (int, error) {
	if !devMode {
		return 0, nil
	}
	if strings.TrimSpace(file) == "" {
		return 0, nil
	}
	seeds, err := LoadSeedUsers(file)
	if err != nil {
		return 0, err
	}
	if svc == nil {
		return 0, nil
	}
	return svc.SeedUsers(ctx, seeds)
}

// SeedUsers on UserService.
func (s *UserService) SeedUsers(ctx context.Context, seeds []SeedUser) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	n := 0
	for _, seed := range seeds {
		email, err := NormalizeEmail(seed.Email)
		if err != nil {
			return n, err
		}
		if err := ValidateRole(seed.Role); err != nil {
			return n, err
		}
		if _, err := s.users.GetByEmail(ctx, email); err == nil {
			continue
		} else if !errors.Is(err, ErrUserNotFound) {
			return n, err
		}

		now := time.Now().UTC()
		id := NewID()
		if err := s.commands.Execute(ctx, SeedUserCommand{
			Email: email,
			Role:  seed.Role,
		}); err != nil {
			// command handler creates event; id unused but okay
			_ = id
			_ = now
			return n, err
		}
		n++
	}
	return n, nil
}
