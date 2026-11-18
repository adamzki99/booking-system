package booking

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/notification"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
)

const (
	createdSubject   = "Booking confirmed"
	cancelledSubject = "Booking cancelled"
)

// Notifier records booking confirmation and cancellation deliveries as durable
// outbox work. Delivery is a side effect of recorded events: an enqueue error
// is logged and never surfaced, so a failed email cannot roll back a booking.
type Notifier struct {
	enqueuer notification.Enqueuer
	users    Directory
	bookings bookingsReader
	logger   *slog.Logger
}

// RegisterNotify subscribes the booking notifier to the dispatcher.
func RegisterNotify(r *registry.Registry, enqueuer notification.Enqueuer, users Directory, bookings bookingsReader, logger *slog.Logger) {
	n := &Notifier{enqueuer: enqueuer, users: users, bookings: bookings, logger: logger}
	r.Dispatcher.Subscribe(n.Handle)
}

// Handle processes a batch of recorded events, ignoring non-booking events and
// always returning nil so downstream subscribers are unaffected.
func (n *Notifier) Handle(ctx context.Context, events []eventstore.Event) error {
	for _, event := range events {
		switch event.EventType {
		case BookingCreatedEventType:
			n.enqueueCreated(ctx, event)
		case BookingCancelledEventType:
			n.enqueueCancelled(ctx, event)
		}
	}
	return nil
}

func (n *Notifier) enqueueCreated(ctx context.Context, event eventstore.Event) {
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
	n.enqueue(ctx, notification.Item{
		EventID:        event.ID,
		Kind:           notification.KindBookingCreated,
		RecipientEmail: u.Email,
		Subject:        createdSubject,
		Body:           body,
	}, "confirmation", event.ID)
}

func (n *Notifier) enqueueCancelled(ctx context.Context, event eventstore.Event) {
	var payload BookingCancelledPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		n.logger.Error("booking notify: decode cancelled event", "event", event.ID, "err", err)
		return
	}
	// The cancellation notice goes to the user that made the booking — the
	// owner — whether they cancelled it themselves or a super user did.
	var ownerID string
	if n.bookings != nil {
		b, err := n.bookings.GetByID(ctx, payload.BookingID)
		if err != nil {
			n.logger.Error("booking notify: resolve booking", "event", event.ID, "booking_id", payload.BookingID, "err", err)
			return
		}
		ownerID = b.UserID
	} else {
		ownerID = payload.CancelledBy
	}
	u, err := n.users.GetByID(ctx, ownerID)
	if err != nil {
		n.logger.Error("booking notify: resolve user", "event", event.ID, "user_id", ownerID, "err", err)
		return
	}
	body := fmt.Sprintf("Your booking %s has been cancelled.", payload.BookingID)
	n.enqueue(ctx, notification.Item{
		EventID:        event.ID,
		Kind:           notification.KindBookingCancelled,
		RecipientEmail: u.Email,
		Subject:        cancelledSubject,
		Body:           body,
	}, "cancellation", event.ID)
}

// enqueue stores one intended delivery. Failures are observable but do not
// propagate to the command path.
func (n *Notifier) enqueue(ctx context.Context, item notification.Item, label string, eventID int64) {
	if err := n.enqueuer.Enqueue(ctx, item); err != nil {
		notification.ReportEnqueueFailure(ctx)
		n.logger.Error("booking notify: enqueue "+label,
			"event", eventID,
			"kind", item.Kind,
			"to", notification.MaskRecipient(item.RecipientEmail),
			"err", err)
	}
}
