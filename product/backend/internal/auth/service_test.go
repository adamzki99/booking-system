package auth_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/command"
)

type fakeExecutor struct {
	last command.Command
	err  error
}

func (f *fakeExecutor) Execute(_ context.Context, cmd command.Command) error {
	f.last = cmd
	return f.err
}

type fakeSender struct {
	to, subject, body string
}

func (f *fakeSender) Send(_ context.Context, to, subject, body string) error {
	f.to, f.subject, f.body = to, subject, body
	return nil
}

type fakeLimiter struct {
	allow bool
}

func (f *fakeLimiter) Allow(string, int, time.Duration) bool { return f.allow }

// fakeUsers is a read-only user directory for login-gating tests.
type fakeUsers struct {
	active map[string]bool
	count  int
}

func (f *fakeUsers) ActiveByEmail(_ context.Context, email string) (bool, error) {
	return f.active[email], nil
}

func (f *fakeUsers) Count(context.Context) (int, error) { return f.count, nil }

func activeDirectory(emails ...string) *fakeUsers {
	active := make(map[string]bool, len(emails))
	for _, email := range emails {
		active[email] = true
	}
	return &fakeUsers{active: active, count: len(emails)}
}

func TestRequestCodeEmailsGeneratedCode(t *testing.T) {
	exec := &fakeExecutor{}
	sender := &fakeSender{}
	svc := auth.NewService(exec, sender, &fakeLimiter{allow: true}, activeDirectory("alice@example.com"))

	if err := svc.RequestCode(context.Background(), "Alice@Example.com", "1.2.3.4"); err != nil {
		t.Fatal(err)
	}

	cmd, ok := exec.last.(auth.RequestLoginCode)
	if !ok {
		t.Fatalf("expected RequestLoginCode, got %T", exec.last)
	}
	if cmd.Email != "alice@example.com" {
		t.Fatalf("command email = %q, want normalized", cmd.Email)
	}
	if cmd.CodeHash == "" {
		t.Fatal("code hash should be set")
	}
	if !cmd.ExpiresAt.After(time.Now()) {
		t.Fatal("expiry should be in the future")
	}
	if sender.to != "alice@example.com" {
		t.Fatalf("to = %q", sender.to)
	}
	if sender.subject != "Your login code" {
		t.Fatalf("subject = %q", sender.subject)
	}
	if !auth.VerifyCodeHash(sender.body, cmd.CodeHash) {
		t.Fatal("emailed code should match the stored hash")
	}
}

func TestVerifyReturnsToken(t *testing.T) {
	exec := &fakeExecutor{}
	svc := auth.NewService(exec, &fakeSender{}, &fakeLimiter{allow: true}, activeDirectory("alice@example.com"))

	token, err := svc.Verify(context.Background(), "alice@example.com", "ABC123", "1.2.3.4")
	if err != nil {
		t.Fatal(err)
	}
	if token == "" {
		t.Fatal("token should be non-empty")
	}
	cmd, ok := exec.last.(auth.VerifyLoginCode)
	if !ok {
		t.Fatalf("expected VerifyLoginCode, got %T", exec.last)
	}
	if cmd.TokenHash != auth.HashToken(token) {
		t.Fatal("command token hash should match the returned token")
	}
}

func TestRequestCodeRateLimitedDoesNotExecute(t *testing.T) {
	exec := &fakeExecutor{}
	svc := auth.NewService(exec, &fakeSender{}, &fakeLimiter{allow: false}, activeDirectory("alice@example.com"))

	err := svc.RequestCode(context.Background(), "alice@example.com", "1.2.3.4")
	if !errors.Is(err, auth.ErrRateLimited) {
		t.Fatalf("expected ErrRateLimited, got %v", err)
	}
	if exec.last != nil {
		t.Fatal("command should not execute when rate limited")
	}
}

func TestRequestCodeUnknownEmailSendsNoCode(t *testing.T) {
	exec := &fakeExecutor{}
	sender := &fakeSender{}
	// One registered user exists, but it is not the requested address.
	svc := auth.NewService(exec, sender, &fakeLimiter{allow: true}, activeDirectory("someone@example.com"))

	if err := svc.RequestCode(context.Background(), "ghost@example.com", "1.2.3.4"); err != nil {
		t.Fatalf("RequestCode should not disclose unknown email, got %v", err)
	}
	if exec.last != nil {
		t.Fatal("no login-code command should execute for an unknown email")
	}
	if sender.to != "" {
		t.Fatalf("no email should be sent for an unknown email, got %q", sender.to)
	}
}

func TestVerifyUnknownEmailRejected(t *testing.T) {
	exec := &fakeExecutor{}
	svc := auth.NewService(exec, &fakeSender{}, &fakeLimiter{allow: true}, activeDirectory("someone@example.com"))

	token, err := svc.Verify(context.Background(), "ghost@example.com", "ABC123", "1.2.3.4")
	if !errors.Is(err, auth.ErrInvalidOrExpiredCode) {
		t.Fatalf("expected ErrInvalidOrExpiredCode, got %v", err)
	}
	if token != "" {
		t.Fatal("unknown email must not obtain a session token")
	}
	if exec.last != nil {
		t.Fatal("no verify command should execute for an unknown email")
	}
}

func TestVerifyDeactivatedUserRejected(t *testing.T) {
	exec := &fakeExecutor{}
	// The user exists but is inactive; Count is non-zero, so bootstrap is off.
	users := &fakeUsers{active: map[string]bool{"alice@example.com": false}, count: 1}
	svc := auth.NewService(exec, &fakeSender{}, &fakeLimiter{allow: true}, users)

	token, err := svc.Verify(context.Background(), "alice@example.com", "ABC123", "1.2.3.4")
	if !errors.Is(err, auth.ErrInvalidOrExpiredCode) {
		t.Fatalf("expected ErrInvalidOrExpiredCode, got %v", err)
	}
	if token != "" {
		t.Fatal("deactivated user must not obtain a session token")
	}
	if exec.last != nil {
		t.Fatal("no verify command should execute for a deactivated user")
	}
}

func TestNilDirectoryFailsClosed(t *testing.T) {
	exec := &fakeExecutor{}
	sender := &fakeSender{}
	svc := auth.NewService(exec, sender, &fakeLimiter{allow: true}, nil)

	if err := svc.RequestCode(context.Background(), "alice@example.com", "1.2.3.4"); err != nil {
		t.Fatal(err)
	}
	if sender.to != "" || exec.last != nil {
		t.Fatal("no code should be issued without a user directory")
	}
	if _, err := svc.Verify(context.Background(), "alice@example.com", "ABC123", "1.2.3.4"); !errors.Is(err, auth.ErrInvalidOrExpiredCode) {
		t.Fatalf("expected ErrInvalidOrExpiredCode without a directory, got %v", err)
	}
}

func TestFirstUserBootstrapsWhenNoUsersExist(t *testing.T) {
	exec := &fakeExecutor{}
	sender := &fakeSender{}
	svc := auth.NewService(exec, sender, &fakeLimiter{allow: true}, &fakeUsers{active: map[string]bool{}, count: 0})
	bootstrapped := ""
	svc.BootstrapAdmin = func(_ context.Context, email string) error {
		bootstrapped = email
		return nil
	}

	if err := svc.RequestCode(context.Background(), "first@example.com", "1.2.3.4"); err != nil {
		t.Fatal(err)
	}
	if sender.to != "first@example.com" {
		t.Fatalf("bootstrap email should be sent, got %q", sender.to)
	}
	token, err := svc.Verify(context.Background(), "first@example.com", sender.body, "1.2.3.4")
	if err != nil {
		t.Fatal(err)
	}
	if token == "" {
		t.Fatal("bootstrap user should obtain a session token")
	}
	if bootstrapped != "first@example.com" {
		t.Fatalf("BootstrapAdmin called with %q, want first@example.com", bootstrapped)
	}
}
