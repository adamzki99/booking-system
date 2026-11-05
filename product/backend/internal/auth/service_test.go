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

func TestRequestCodeEmailsGeneratedCode(t *testing.T) {
	exec := &fakeExecutor{}
	sender := &fakeSender{}
	svc := auth.NewService(exec, sender, &fakeLimiter{allow: true})

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
	svc := auth.NewService(exec, &fakeSender{}, &fakeLimiter{allow: true})

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
	svc := auth.NewService(exec, &fakeSender{}, &fakeLimiter{allow: false})

	err := svc.RequestCode(context.Background(), "alice@example.com", "1.2.3.4")
	if !errors.Is(err, auth.ErrRateLimited) {
		t.Fatalf("expected ErrRateLimited, got %v", err)
	}
	if exec.last != nil {
		t.Fatal("command should not execute when rate limited")
	}
}
