package ical

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
	// GenerateCalendarTokenCommandType identifies GenerateCalendarToken commands.
	GenerateCalendarTokenCommandType = "ical.GenerateCalendarToken"

	// Alias.
	GenerateTokenCommandType = GenerateCalendarTokenCommandType
)

// GenerateCalendarToken (re)generates a user's calendar token (records event).
type GenerateCalendarToken struct {
	UserID    string
	TokenHash string
}

// CommandType implements command.Command.
func (GenerateCalendarToken) CommandType() string { return GenerateCalendarTokenCommandType }

// defaultTokens is the projection registered by Register.
var defaultTokens *CalendarTokenProjection

// Register wires the ical commands and projection into the registry.
func Register(r *registry.Registry) *CalendarTokenProjection {
	tokens := NewCalendarTokenProjection(r.DB())
	defaultTokens = tokens
	r.RegisterCommand(GenerateCalendarTokenCommandType, handleGenerateCalendarToken(tokens))
	r.RegisterProjection(tokens)
	return tokens
}

// handleGenerateCalendarToken validates fields and emits the event.
func handleGenerateCalendarToken(tokens *CalendarTokenProjection) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var g GenerateCalendarToken
		switch typed := cmd.(type) {
		case GenerateCalendarToken:
			g = typed
		case *GenerateCalendarToken:
			if typed == nil {
				return nil, errors.New("ical: command is nil")
			}
			g = *typed
		default:
			return nil, fmt.Errorf("ical: expected GenerateCalendarToken, got %T", cmd)
		}
		if g.UserID == "" {
			return nil, errors.New("ical: user id required")
		}
		if g.TokenHash == "" {
			return nil, errors.New("ical: token hash required")
		}
		now := time.Now().UTC()
		payload, err := json.Marshal(CalendarTokenGeneratedPayload{
			UserID:      g.UserID,
			TokenHash:   g.TokenHash,
			GeneratedAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("ical: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: AggregateType,
			AggregateID:   g.UserID,
			EventType:     CalendarTokenGeneratedEventType,
			Payload:       payload,
			OccurredAt:    now,
		}}, nil
	}
}