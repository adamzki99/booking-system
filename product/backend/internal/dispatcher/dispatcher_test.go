package dispatcher_test

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/dispatcher"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
)

func TestPublishDeliversInOrderAndStopsOnSubscriberError(t *testing.T) {
	d := dispatcher.New()
	subscriberErr := errors.New("projection failed")
	events := []eventstore.Event{{ID: 1}, {ID: 2}}
	var calls []string

	d.Subscribe(func(_ context.Context, got []eventstore.Event) error {
		calls = append(calls, "first")
		if !reflect.DeepEqual(got, events) {
			t.Fatalf("expected events %v, got %v", events, got)
		}
		return nil
	})
	d.Subscribe(func(context.Context, []eventstore.Event) error {
		calls = append(calls, "second")
		return subscriberErr
	})
	d.Subscribe(func(context.Context, []eventstore.Event) error {
		calls = append(calls, "third")
		return nil
	})

	err := d.Publish(context.Background(), events)
	if !errors.Is(err, subscriberErr) {
		t.Fatalf("expected subscriber error, got %v", err)
	}
	if want := []string{"first", "second"}; !reflect.DeepEqual(calls, want) {
		t.Fatalf("expected calls %v, got %v", want, calls)
	}
}
