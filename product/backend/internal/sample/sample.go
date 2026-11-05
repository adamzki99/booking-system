// Package sample demonstrates declarative command and projection registration.
package sample

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
	// CreateCommandType identifies CreateSample commands.
	CreateCommandType = "CreateSample"
	// CreatedEventType identifies SampleCreated events.
	CreatedEventType = "SampleCreated"
	// AggregateType is the sample event aggregate type.
	AggregateType = "Sample"
)

type createdPayload struct {
	Name string `json:"name"`
}

// CreateSample creates one sample read-model item through an event.
type CreateSample struct {
	ID         string
	Name       string
	OccurredAt time.Time
}

// CommandType implements command.Command.
func (CreateSample) CommandType() string { return CreateCommandType }

// Register adds the sample command handler and projection to an application.
func Register(r *registry.Registry) *Projection {
	r.RegisterCommand(CreateCommandType, handleCreateSample)
	readModel := NewProjection(r.DB())
	r.RegisterProjection(readModel)
	return readModel
}

func handleCreateSample(_ context.Context, cmd command.Command) ([]eventstore.Event, error) {
	var create CreateSample
	switch typed := cmd.(type) {
	case CreateSample:
		create = typed
	case *CreateSample:
		if typed == nil {
			return nil, errors.New("sample: command is nil")
		}
		create = *typed
	default:
		return nil, fmt.Errorf("sample: expected CreateSample, got %T", cmd)
	}
	if create.ID == "" {
		return nil, errors.New("sample: id is required")
	}
	if create.Name == "" {
		return nil, errors.New("sample: name is required")
	}
	if create.OccurredAt.IsZero() {
		create.OccurredAt = time.Now().UTC()
	}
	payload, err := json.Marshal(createdPayload{Name: create.Name})
	if err != nil {
		return nil, fmt.Errorf("sample: marshal event: %w", err)
	}
	return []eventstore.Event{{
		AggregateType: AggregateType,
		AggregateID:   create.ID,
		EventType:     CreatedEventType,
		Payload:       payload,
		OccurredAt:    create.OccurredAt,
	}}, nil
}
