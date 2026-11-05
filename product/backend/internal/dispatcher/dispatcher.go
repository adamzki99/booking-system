// Package dispatcher provides synchronous in-process event delivery.
package dispatcher

import (
	"context"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
)

// Subscriber handles a batch of recorded events.
type Subscriber func(context.Context, []eventstore.Event) error

// Dispatcher delivers events to subscribers in registration order.
type Dispatcher struct {
	subscribers []Subscriber
}

// New creates an empty dispatcher.
func New() *Dispatcher {
	return &Dispatcher{}
}

// Subscribe registers a subscriber for recorded events.
func (d *Dispatcher) Subscribe(subscriber Subscriber) {
	d.subscribers = append(d.subscribers, subscriber)
}

// Publish synchronously delivers events until all subscribers succeed or one fails.
func (d *Dispatcher) Publish(ctx context.Context, events []eventstore.Event) error {
	for _, subscriber := range d.subscribers {
		if err := subscriber(ctx, events); err != nil {
			return err
		}
	}
	return nil
}
