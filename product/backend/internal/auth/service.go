package auth

import (
	"context"
	"fmt"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/email"
)

const (
	// CodeTTL is how long a login code remains valid.
	CodeTTL = 10 * time.Minute
	// SessionTTL is how long a session remains valid.
	SessionTTL = 7 * 24 * time.Hour

	loginCodeSubject = "Your login code"

	requestCodeEmailLimit  = 5
	requestCodeEmailWindow = 15 * time.Minute
	requestCodeIPLimit     = 20
	requestCodeIPWindow    = time.Hour

	verifyEmailLimit  = 10
	verifyEmailWindow = 15 * time.Minute
	verifyIPLimit     = 30
	verifyIPWindow    = time.Hour
)

// commandExecutor runs commands against the event store.
type commandExecutor interface {
	Execute(context.Context, command.Command) error
}

// rateLimiter guards request rates per key.
type rateLimiter interface {
	Allow(key string, limit int, window time.Duration) bool
}

// AuthService orchestrates passwordless login.
type AuthService struct {
	commands       commandExecutor
	sender         email.Sender
	limiter        rateLimiter
	BootstrapAdmin func(context.Context, string) error
}

// NewService creates an auth service.
func NewService(commands commandExecutor, sender email.Sender, limiter rateLimiter) *AuthService {
	return &AuthService{
		commands: commands,
		sender:   sender,
		limiter:  limiter,
	}
}

// RequestCode issues and emails a one-time login code.
func (s *AuthService) RequestCode(ctx context.Context, emailAddr, clientIP string) error {
	normalized, err := NormalizeEmail(emailAddr)
	if err != nil {
		return err
	}
	emailOK := s.limiter.Allow(requestCodeEmailKey(normalized), requestCodeEmailLimit, requestCodeEmailWindow)
	ipOK := s.limiter.Allow(requestCodeIPKey(clientIP), requestCodeIPLimit, requestCodeIPWindow)
	if !emailOK || !ipOK {
		return ErrRateLimited
	}

	code, err := GenerateCode()
	if err != nil {
		return fmt.Errorf("auth: generate code: %w", err)
	}
	hash, err := HashCode(code)
	if err != nil {
		return fmt.Errorf("auth: hash code: %w", err)
	}

	now := time.Now().UTC()
	cmd := RequestLoginCode{
		Email:      normalized,
		CodeHash:   hash,
		ExpiresAt:  now.Add(CodeTTL),
		OccurredAt: now,
	}
	if err := s.commands.Execute(ctx, cmd); err != nil {
		return err
	}
	if err := s.sender.Send(ctx, normalized, loginCodeSubject, code); err != nil {
		return fmt.Errorf("auth: send login code: %w", err)
	}
	return nil
}

// Verify checks a submitted code and returns a session token.
func (s *AuthService) Verify(ctx context.Context, emailAddr, code, clientIP string) (string, error) {
	normalized, err := NormalizeEmail(emailAddr)
	if err != nil {
		return "", err
	}
	if err := ValidateCode(code); err != nil {
		return "", err
	}
	emailOK := s.limiter.Allow(verifyEmailKey(normalized), verifyEmailLimit, verifyEmailWindow)
	ipOK := s.limiter.Allow(verifyIPKey(clientIP), verifyIPLimit, verifyIPWindow)
	if !emailOK || !ipOK {
		return "", ErrRateLimited
	}

	token, tokenHash, err := GenerateToken()
	if err != nil {
		return "", fmt.Errorf("auth: generate token: %w", err)
	}

	now := time.Now().UTC()
	cmd := VerifyLoginCode{
		Email:            normalized,
		Code:             code,
		TokenHash:        tokenHash,
		SessionExpiresAt: now.Add(SessionTTL),
		OccurredAt:       now,
	}
	if err := s.commands.Execute(ctx, cmd); err != nil {
		return "", err
	}
	if s.BootstrapAdmin != nil {
		if err := s.BootstrapAdmin(ctx, normalized); err != nil {
			return token, err
		}
	}
	return token, nil
}

func requestCodeEmailKey(email string) string { return "request-code:email:" + email }
func requestCodeIPKey(ip string) string       { return "request-code:ip:" + ip }
func verifyEmailKey(email string) string      { return "verify:email:" + email }
func verifyIPKey(ip string) string            { return "verify:ip:" + ip }
