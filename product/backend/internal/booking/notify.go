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

// Notifier enqueues booking confirmation and cancellation deliveries as a side
// effect of recorded booking events. Enqueue failures are logged and never
// surfaced, so a failed notification cannot roll back an accepted booking.
type Notifier struct {
	outbox   notification.Enqueuer
	users    Directory
	bookings bookingsReader
	logger   *slog.Logger
}

// RegisterNotify subscribes the booking notifier to the dispatcher.
func RegisterNotify(r *registry.Registry, outbox notification.Enqueuer, users Directory, bookings bookingsReader, logger *slog.Logger) {
	n := &Notifier{outbox: outbox, users: users, bookings: bookings, logger: logger}
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
	item := notification.Item{
		EventID:        event.ID,
		Kind:           notification.KindBookingCreated,
		RecipientEmail: u.Email,
		Subject:        createdSubject,
		Body:           body,
	}
	notification.EnqueueDelivery(ctx, n.outbox, item, n.logger, event.ID, "booking confirmation")
}

func (n *Notifier) sendCancelled(ctx context.Context, event eventstore.Event) {
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
	item := notification.Item{
		EventID:        event.ID,
		Kind:           notification.KindBookingCancelled,
		RecipientEmail: u.Email,
		Subject:        cancelledSubject,
		Body:           body,
	}
	notification.EnqueueDelivery(ctx, n.outbox, item, n.logger, event.ID, "booking cancellation")
}
