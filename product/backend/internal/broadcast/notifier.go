package broadcast

import (
	"context"
	"encoding/json"
	"log/slog"
	"strings"

	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/email"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

// lister reads the user directory read model.
type lister interface {
	List(ctx context.Context) ([]user.User, error)
}

// executor executes commands against the event store.
type executor interface {
	Execute(ctx context.Context, cmd command.Command) error
}

// BroadcastService orchestrates broadcast commands.
type BroadcastService struct {
	commands executor
	users    Directory
}

// NewService creates a broadcast service.
func NewService(commands executor, users Directory) *BroadcastService {
	return &BroadcastService{commands: commands, users: users}
}

// Broadcast records a broadcast message (super users only). The email fan-out
// to basic users happens as a side effect of the recorded event.
func (s *BroadcastService) Broadcast(ctx context.Context, email, subject, body string) error {
	u, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		return ErrForbidden
	}
	if !u.Role.AtLeast(user.RoleSuper) {
		return ErrForbidden
	}
	if err := ValidateMessage(subject, body); err != nil {
		return err
	}
	return s.commands.Execute(ctx, BroadcastMessage{
		Subject:     subject,
		Body:        body,
		RequesterID: u.ID,
	})
}

// Notifier fans out broadcast messages to basic users as a side effect of
// recorded broadcast events. Delivery is best-effort: errors are logged and
// never surfaced, so a failed email cannot roll back an accepted broadcast.
type Notifier struct {
	sender email.Sender
	users  lister
	logger *slog.Logger
}

// NewNotifier creates a broadcast notifier.
func NewNotifier(sender email.Sender, users lister, logger *slog.Logger) *Notifier {
	return &Notifier{sender: sender, users: users, logger: logger}
}

// RegisterNotify subscribes the broadcast notifier to the dispatcher.
func RegisterNotify(r *registry.Registry, sender email.Sender, users lister, logger *slog.Logger) {
	r.Dispatcher.Subscribe(NewNotifier(sender, users, logger).Handle)
}

// Handle processes a batch of recorded events, sending broadcast messages to
// active basic users and always returning nil so downstream subscribers are
// unaffected.
func (n *Notifier) Handle(ctx context.Context, events []eventstore.Event) error {
	for _, event := range events {
		if event.EventType != MessageBroadcastEventType {
			continue
		}
		var payload MessageBroadcastPayload
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			n.logger.Error("broadcast notify: decode event", "event", event.ID, "err", err)
			continue
		}
		users, err := n.users.List(ctx)
		if err != nil {
			n.logger.Error("broadcast notify: list users", "event", event.ID, "err", err)
			continue
		}
		for _, u := range users {
			if u.Role != user.RoleBasic || !u.Active || strings.TrimSpace(u.Email) == "" {
				continue
			}
			if err := n.sender.Send(ctx, u.Email, payload.Subject, payload.Body); err != nil {
				n.logger.Error("broadcast notify: send", "event", event.ID, "to", u.Email, "err", err)
			}
		}
	}
	return nil
}
