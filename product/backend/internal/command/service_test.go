package command_test

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
)

type testCommand string

func (c testCommand) CommandType() string { return string(c) }

func TestExecuteRejectsUnknownCommand(t *testing.T) {
	service := command.NewService(nil, nil)

	err := service.Execute(context.Background(), testCommand("Unknown"))
	if !errors.Is(err, command.ErrUnknownCommand) {
		t.Fatalf("expected ErrUnknownCommand, got %v", err)
	}
}

func TestExecuteStopsWhenValidationFails(t *testing.T) {
	validationErr := errors.New("invalid sample")
	service := command.NewService(nil, nil)
	service.Register("CreateSample", func(context.Context, command.Command) ([]eventstore.Event, error) {
		return nil, validationErr
	})

	err := service.Execute(context.Background(), testCommand("CreateSample"))
	if !errors.Is(err, validationErr) {
		t.Fatalf("expected validation error, got %v", err)
	}
}

func TestExecuteAppendsBeforePublishingRecordedEvents(t *testing.T) {
	var calls []string
	recorded := []eventstore.Event{{ID: 42, EventType: "SampleCreated"}}
	store := &recordingStore{calls: &calls, recorded: recorded}
	publisher := &recordingPublisher{calls: &calls}
	service := command.NewService(store, publisher)
	service.Register("CreateSample", func(context.Context, command.Command) ([]eventstore.Event, error) {
		return []eventstore.Event{{EventType: "SampleCreated"}}, nil
	})

	if err := service.Execute(context.Background(), testCommand("CreateSample")); err != nil {
		t.Fatal(err)
	}
	if want := []string{"append", "publish"}; !reflect.DeepEqual(calls, want) {
		t.Fatalf("expected calls %v, got %v", want, calls)
	}
	if !reflect.DeepEqual(publisher.events, recorded) {
		t.Fatalf("expected recorded events %v, got %v", recorded, publisher.events)
	}
}

func TestExecuteStopsWhenAppendFails(t *testing.T) {
	appendErr := errors.New("append failed")
	var calls []string
	store := &recordingStore{calls: &calls, err: appendErr}
	service := command.NewService(store, &recordingPublisher{calls: &calls})
	service.Register("CreateSample", func(context.Context, command.Command) ([]eventstore.Event, error) {
		return []eventstore.Event{{EventType: "SampleCreated"}}, nil
	})

	err := service.Execute(context.Background(), testCommand("CreateSample"))
	if !errors.Is(err, appendErr) {
		t.Fatalf("expected append error, got %v", err)
	}
	if want := []string{"append"}; !reflect.DeepEqual(calls, want) {
		t.Fatalf("expected calls %v, got %v", want, calls)
	}
}

func TestExecutePropagatesPublishError(t *testing.T) {
	publishErr := errors.New("publish failed")
	var calls []string
	store := &recordingStore{calls: &calls, recorded: []eventstore.Event{{ID: 1}}}
	service := command.NewService(store, &recordingPublisher{calls: &calls, err: publishErr})
	service.Register("CreateSample", func(context.Context, command.Command) ([]eventstore.Event, error) {
		return []eventstore.Event{{EventType: "SampleCreated"}}, nil
	})

	err := service.Execute(context.Background(), testCommand("CreateSample"))
	if !errors.Is(err, publishErr) {
		t.Fatalf("expected publish error, got %v", err)
	}
	if want := []string{"append", "publish"}; !reflect.DeepEqual(calls, want) {
		t.Fatalf("expected calls %v, got %v", want, calls)
	}
}

type recordingStore struct {
	calls    *[]string
	recorded []eventstore.Event
	err      error
}

func (s *recordingStore) Append(_ context.Context, _ ...eventstore.Event) ([]eventstore.Event, error) {
	*s.calls = append(*s.calls, "append")
	return s.recorded, s.err
}

type recordingPublisher struct {
	calls  *[]string
	events []eventstore.Event
	err    error
}

func (p *recordingPublisher) Publish(_ context.Context, events []eventstore.Event) error {
	*p.calls = append(*p.calls, "publish")
	p.events = events
	return p.err
}
