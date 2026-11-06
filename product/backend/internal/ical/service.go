package ical

import (
	"context"

	"github.com/adamzki99/booking-system/product/backend/internal/command"
)

// commandExecutor runs commands against the event store.
type commandExecutor interface {
	Execute(context.Context, command.Command) error
}

// Service orchestrates calendar token generation.
type Service struct {
	commands commandExecutor
	tokens   *CalendarTokenProjection
}

// NewService creates an ical service.
func NewService(commands commandExecutor, tokens *CalendarTokenProjection) *Service {
	return &Service{commands: commands, tokens: tokens}
}

// NewICalService is an alias.
func NewICalService(commands commandExecutor, tokens *CalendarTokenProjection) *Service {
	return NewService(commands, tokens)
}

// Tokens returns the underlying projection.
func (s *Service) Tokens() *CalendarTokenProjection { return s.tokens }

// Generate creates a new token, records the event, and returns the plaintext token.
func (s *Service) Generate(ctx context.Context, userID string) (string, error) {
	token, hash, err := GenerateToken()
	if err != nil {
		return "", err
	}
	if err := s.commands.Execute(ctx, GenerateCalendarToken{
		UserID:    userID,
		TokenHash: hash,
	}); err != nil {
		return "", err
	}
	return token, nil
}

// Aliases.
func (s *Service) GenerateToken(ctx context.Context, userID string) (string, error) {
	return s.Generate(ctx, userID)
}
func (s *Service) GenerateCalendarToken(ctx context.Context, userID string) (string, error) {
	return s.Generate(ctx, userID)
}
func (s *Service) Regenerate(ctx context.Context, userID string) (string, error) {
	return s.Generate(ctx, userID)
}
