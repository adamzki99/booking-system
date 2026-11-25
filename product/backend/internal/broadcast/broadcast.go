// Package broadcast implements super-user broadcast messages: recording the
// message as an event and fanning it out to basic users by email.
package broadcast

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

const (
	// AggregateType is the broadcast event aggregate type.
	AggregateType = "broadcast"

	// MessageBroadcastEventType records a broadcast message.
	MessageBroadcastEventType = "broadcast.message"

	// BroadcastMessageCommandType identifies BroadcastMessage commands.
	BroadcastMessageCommandType = "broadcast.BroadcastMessage"

	subjectLimit = 200
	bodyLimit    = 10_000
)

// Error sentinels.
var (
	// ErrForbidden indicates the caller is not allowed to broadcast.
	ErrForbidden = errors.New("broadcast: forbidden")
	// ErrInvalidSubject indicates the subject is empty or too long.
	ErrInvalidSubject = errors.New("broadcast: invalid subject")
	// ErrInvalidBody indicates the body is empty or too long.
	ErrInvalidBody = errors.New("broadcast: invalid body")
)

// BroadcastMessage sends a plain-text message to all basic users (super users
// only).
type BroadcastMessage struct {
	Subject     string
	Body        string
	RequesterID string
}

// CommandType implements command.Command.
func (BroadcastMessage) CommandType() string { return BroadcastMessageCommandType }

// MessageBroadcastPayload is the payload for broadcast.message events.
type MessageBroadcastPayload struct {
	BroadcastID string    `json:"broadcast_id"`
	Subject     string    `json:"subject"`
	Body        string    `json:"body"`
	ByUserID    string    `json:"by_user_id"`
	BroadcastAt time.Time `json:"broadcast_at"`
}

// Directory resolves users from the user directory read model.
type Directory interface {
	GetByID(ctx context.Context, id string) (user.User, error)
	GetByEmail(ctx context.Context, email string) (user.User, error)
}

// ValidateMessage reports whether the subject and body are acceptable.
func ValidateMessage(subject, body string) error {
	subject = strings.TrimSpace(subject)
	if subject == "" || len(subject) > subjectLimit {
		return ErrInvalidSubject
	}
	body = strings.TrimSpace(body)
	if body == "" || len(body) > bodyLimit {
		return ErrInvalidBody
	}
	return nil
}

// NewID generates a new UUID string for a broadcast.
func NewID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("broadcast-%d", time.Now().UnixNano())
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// Register wires the broadcast command into the registry. users is the user
// directory used for the super-user check.
func Register(r *registry.Registry, users Directory) {
	r.RegisterCommand(BroadcastMessageCommandType, HandleBroadcastMessage(users))
}

// HandleBroadcastMessage returns the command handler recording the broadcast
// event; the email fan-out happens as a side effect of the recorded event.
func HandleBroadcastMessage(users Directory) command.Handler {
	return func(ctx context.Context, cmd command.Command) ([]eventstore.Event, error) {
		var c BroadcastMessage
		switch typed := cmd.(type) {
		case BroadcastMessage:
			c = typed
		case *BroadcastMessage:
			if typed == nil {
				return nil, errors.New("broadcast: command is nil")
			}
			c = *typed
		default:
			return nil, fmt.Errorf("broadcast: expected BroadcastMessage, got %T", cmd)
		}

		if c.RequesterID == "" {
			return nil, errors.New("broadcast: requester id is required")
		}
		u, err := users.GetByID(ctx, c.RequesterID)
		if err != nil || !u.Role.AtLeast(user.RoleSuper) {
			return nil, ErrForbidden
		}
		if err := ValidateMessage(c.Subject, c.Body); err != nil {
			return nil, err
		}

		now := time.Now().UTC()
		id := NewID()
		payload, err := json.Marshal(MessageBroadcastPayload{
			BroadcastID: id,
			Subject:     strings.TrimSpace(c.Subject),
			Body:        c.Body,
			ByUserID:    c.RequesterID,
			BroadcastAt: now,
		})
		if err != nil {
			return nil, fmt.Errorf("broadcast: marshal event: %w", err)
		}
		return []eventstore.Event{{
			AggregateType: AggregateType,
			AggregateID:   id,
			EventType:     MessageBroadcastEventType,
			Payload:       payload,
			OccurredAt:    now,
		}}, nil
	}
}
