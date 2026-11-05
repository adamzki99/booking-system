package auth

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
)

const (
	// RequestLoginCodeCommandType identifies RequestLoginCode commands.
	RequestLoginCodeCommandType = "auth.RequestLoginCode"
	// VerifyLoginCodeCommandType identifies VerifyLoginCode commands.
	VerifyLoginCodeCommandType = "auth.VerifyLoginCode"
)

// RequestLoginCode issues a login code for an email address.
type RequestLoginCode struct {
	Email      string
	CodeHash   string
	ExpiresAt  time.Time
	OccurredAt time.Time
}

// CommandType implements command.Command.
func (RequestLoginCode) CommandType() string { return RequestLoginCodeCommandType }

// VerifyLoginCode verifies a submitted code and creates a session.
type VerifyLoginCode struct {
	Email            string
	Code             string
	TokenHash        string
	SessionExpiresAt time.Time
	OccurredAt       time.Time
}

// CommandType implements command.Command.
func (VerifyLoginCode) CommandType() string { return VerifyLoginCodeCommandType }

// Register wires the auth commands and projections into the registry.
func Register(r *registry.Registry) *Projections {
	codes := NewLoginCodeProjection(r.DB())
	sessions := NewSessionProjection(r.DB())
	r.RegisterCommand(RequestLoginCodeCommandType, handleRequestLoginCode)
	r.RegisterCommand(VerifyLoginCodeCommandType, handleVerifyLoginCode(codes))
	r.RegisterProjection(codes)
	r.RegisterProjection(sessions)
	return &Projections{LoginCodes: codes, Sessions: sessions}
}

func handleRequestLoginCode(_ context.Context, cmd command.Command) ([]eventstore.Event, error) {
	var req RequestLoginCode
	switch typed := cmd.(type) {
	case RequestLoginCode:
		req = typed
	case *RequestLoginCode:
		if typed == nil {
			return nil, errors.New("auth: command is nil")
		}
		req = *typed
	default:
		return nil, fmt.Errorf("auth: expected RequestLoginCode, got %T", cmd)
	}

	email, err := NormalizeEmail(req.Email)
	if err != nil {
		return nil, err
	}
	if req.CodeHash == "" {
		return nil, errors.New("auth: code hash is required")
	}
	if req.ExpiresAt.IsZero() {
		return nil, errors.New("auth: expiry is required")
	}
	occurredAt := req.OccurredAt
	if occurredAt.IsZero() {
		occurredAt = time.Now().UTC()
	}

	payload, err := json.Marshal(loginCodeIssuedPayload{
		Email:     email,
		CodeHash:  req.CodeHash,
		ExpiresAt: req.ExpiresAt,
	})
	if err != nil {
		return nil, fmt.Errorf("auth: marshal event: %w", err)
	}
	return []eventstore.Event{{
		AggregateType: AggregateType,
		AggregateID:   email,
		EventType:     LoginCodeIssuedEventType,
		Payload:       payload,
		OccurredAt:    occurredAt,
	}}, nil
}

func handleVerifyLoginCode(codes *LoginCodeProjection) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var v VerifyLoginCode
		switch typed := cmd.(type) {
		case VerifyLoginCode:
			v = typed
		case *VerifyLoginCode:
			if typed == nil {
				return nil, errors.New("auth: command is nil")
			}
			v = *typed
		default:
			return nil, fmt.Errorf("auth: expected VerifyLoginCode, got %T", cmd)
		}

		email, err := NormalizeEmail(v.Email)
		if err != nil {
			return nil, err
		}
		if err := ValidateCode(v.Code); err != nil {
			return nil, err
		}
		if v.TokenHash == "" {
			return nil, errors.New("auth: token hash is required")
		}
		if v.SessionExpiresAt.IsZero() {
			return nil, errors.New("auth: session expiry is required")
		}

		stored, err := codes.LatestUnconsumed(ctx, email)
		if err != nil {
			if errors.Is(err, ErrNoLoginCode) {
				return nil, ErrInvalidOrExpiredCode
			}
			return nil, err
		}
		if !stored.ExpiresAt.After(time.Now()) {
			return nil, ErrInvalidOrExpiredCode
		}
		if !VerifyCodeHash(v.Code, stored.CodeHash) {
			return nil, ErrInvalidOrExpiredCode
		}

		occurredAt := v.OccurredAt
		if occurredAt.IsZero() {
			occurredAt = time.Now().UTC()
		}
		payload, err := json.Marshal(sessionCreatedPayload{
			Email:     email,
			CodeHash:  stored.CodeHash,
			TokenHash: v.TokenHash,
			ExpiresAt: v.SessionExpiresAt,
		})
		if err != nil {
			return nil, fmt.Errorf("auth: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: AggregateType,
			AggregateID:   email,
			EventType:     SessionCreatedEventType,
			Payload:       payload,
			OccurredAt:    occurredAt,
		}}, nil
	}
}
