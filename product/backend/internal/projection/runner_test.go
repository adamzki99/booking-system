package projection_test

import (
	"context"
	"reflect"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/projection"
)

func TestHandleSkipsEventsAtOrBeforeCheckpoint(t *testing.T) {
	checkpoints := &memoryCheckpoints{values: map[string]int64{"samples": 5}}
	readModel := &recordingProjection{name: "samples"}
	runner := projection.NewRunner(nil, checkpoints)
	runner.Register(readModel)

	err := runner.Handle(context.Background(), []eventstore.Event{{ID: 4}, {ID: 5}, {ID: 6}})
	if err != nil {
		t.Fatal(err)
	}
	if want := []int64{6}; !reflect.DeepEqual(readModel.applied, want) {
		t.Fatalf("expected applied events %v, got %v", want, readModel.applied)
	}
	if got := checkpoints.values["samples"]; got != 6 {
		t.Fatalf("expected checkpoint 6, got %d", got)
	}
}

func TestCatchUpResumesAfterCheckpoint(t *testing.T) {
	store := &staticStore{events: []eventstore.Event{{ID: 1}, {ID: 2}, {ID: 3}}}
	checkpoints := &memoryCheckpoints{values: map[string]int64{"samples": 1}}
	readModel := &recordingProjection{name: "samples"}
	runner := projection.NewRunner(store, checkpoints)
	runner.Register(readModel)

	if err := runner.CatchUp(context.Background()); err != nil {
		t.Fatal(err)
	}
	if want := []int64{2, 3}; !reflect.DeepEqual(readModel.applied, want) {
		t.Fatalf("expected applied events %v, got %v", want, readModel.applied)
	}
	if got := checkpoints.values["samples"]; got != 3 {
		t.Fatalf("expected checkpoint 3, got %d", got)
	}
}

func TestRebuildAllResetsAndReplaysEventHistory(t *testing.T) {
	store := &staticStore{events: []eventstore.Event{{ID: 1}, {ID: 2}}}
	checkpoints := &memoryCheckpoints{values: map[string]int64{"samples": 2}}
	readModel := &recordingProjection{name: "samples", applied: []int64{2}}
	runner := projection.NewRunner(store, checkpoints)
	runner.Register(readModel)

	if err := runner.RebuildAll(context.Background()); err != nil {
		t.Fatal(err)
	}
	if readModel.resets != 1 {
		t.Fatalf("expected one reset, got %d", readModel.resets)
	}
	if want := []int64{1, 2}; !reflect.DeepEqual(readModel.applied, want) {
		t.Fatalf("expected replayed events %v, got %v", want, readModel.applied)
	}
	if got := checkpoints.values["samples"]; got != 2 {
		t.Fatalf("expected checkpoint 2, got %d", got)
	}
}

type staticStore struct {
	events []eventstore.Event
}

func (s *staticStore) Append(_ context.Context, events ...eventstore.Event) ([]eventstore.Event, error) {
	return events, nil
}

func (s *staticStore) LoadAll(context.Context) ([]eventstore.Event, error) {
	return s.events, nil
}

func (s *staticStore) LoadByAggregate(context.Context, string, string) ([]eventstore.Event, error) {
	return nil, nil
}

type recordingProjection struct {
	name    string
	applied []int64
	resets  int
}

func (p *recordingProjection) Name() string { return p.name }

func (p *recordingProjection) Apply(_ context.Context, event eventstore.Event) error {
	p.applied = append(p.applied, event.ID)
	return nil
}

func (p *recordingProjection) Reset(context.Context) error {
	p.resets++
	p.applied = nil
	return nil
}

type memoryCheckpoints struct {
	values map[string]int64
}

func (s *memoryCheckpoints) Get(_ context.Context, name string) (int64, error) {
	return s.values[name], nil
}

func (s *memoryCheckpoints) Set(_ context.Context, name string, id int64) error {
	s.values[name] = id
	return nil
}

func (s *memoryCheckpoints) Reset(_ context.Context, name string) error {
	s.values[name] = 0
	return nil
}
