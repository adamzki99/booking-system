package booking

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"

	"github.com/adamzki99/booking-system/product/backend/internal/email"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
)

const (
	createdSubject   = "Booking confirmed"
	cancelledSubject = "Booking cancelled"
)

// Notifier sends booking confirmation and cancellation emails as a side effect
// of recorded booking events. Delivery is best-effort: errors are logged and
// never surfaced, so a failed email cannot roll back an accepted booking.
type Notifier struct {
	sender email.Sender
	users  userResolver
	logger *slog.Logger
}

// RegisterNotify subscribes the booking notifier to the dispatcher.
func RegisterNotify(r *registry.Registry, sender email.Sender, users userResolver, logger *slog.Logger) {
	n := &Notifier{sender: sender, users: users, logger: logger}
	r.Dispatcher.Subscribe(n.Handle)
}

// Handle processes a batch of recorded events, ignoring non-booking events and
// always returning nil so downstream subscribers are unaffected.
func (n *Notifier) Handle(ctx context.Context, events []eventstore.Event) error {
	for _, event := range events {
		switch event.EventType {
		case BookingCreatedEventType:
			n.sendCreated(ctx, event)
		case BookingCancelledEventType:
			n.sendCancelled(ctx, event)
		}
	}
	return nil
}

func (n *Notifier) sendCreated(ctx context.Context, event eventstore.Event) {
	var payload BookingCreatedPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		n.logger.Error("booking notify: decode created event", "event", event.ID, "err", err)
		return
	}
	u, err := n.users.GetByID(ctx, payload.UserID)
	if err != nil {
		n.logger.Error("booking notify: resolve user", "event", event.ID, "user_id", payload.UserID, "err", err)
		return
	}
	body := fmt.Sprintf("Your booking %s is confirmed from %s to %s.",
		payload.BookingID, payload.Start.Format("2006-01-02 15:04"), payload.End.Format("2006-01-02 15:04"))
	if err := n.sender.Send(ctx, u.Email, createdSubject, body); err != nil {
		n.logger.Error("booking notify: send confirmation", "event", event.ID, "to", u.Email, "err", err)
	}
}

func (n *Notifier) sendCancelled(ctx context.Context, event eventstore.Event) {
	var payload BookingCancelledPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		n.logger.Error("booking notify: decode cancelled event", "event", event.ID, "err", err)
		return
	}
	u, err := n.users.GetByID(ctx, payload.CancelledBy)
	if err != nil {
		n.logger.Error("booking notify: resolve user", "event", event.ID, "user_id", payload.CancelledBy, "err", err)
		return
	}
	body := fmt.Sprintf("Your booking %s has been cancelled.", payload.BookingID)
	if err := n.sender.Send(ctx, u.Email, cancelledSubject, body); err != nil {
		n.logger.Error("booking notify: send cancellation", "event", event.ID, "to", u.Email, "err", err)
	}
}
