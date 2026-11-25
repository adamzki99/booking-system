package eventstore

import (
	"testing"
	"time"
)

func TestEventValidate(t *testing.T) {
	valid := Event{
		AggregateType: "sauna",
		AggregateID:   "1",
		EventType:     "Booked",
		Payload:       []byte(`{"x":1}`),
		OccurredAt:    time.Now(),
	}
	if err := valid.Validate(); err != nil {
		t.Fatalf("valid event: %v", err)
	}
	if err := ValidateEvent(valid); err != nil {
		t.Fatalf("ValidateEvent: %v", err)
	}

	cases := []struct {
		name   string
		mutate func(*Event)
	}{
		{"missing aggregate type", func(e *Event) { e.AggregateType = "" }},
		{"missing aggregate id", func(e *Event) { e.AggregateID = "" }},
		{"missing event type", func(e *Event) { e.EventType = "" }},
		{"missing payload", func(e *Event) { e.Payload = nil }},
		{"missing occurred at", func(e *Event) { e.OccurredAt = time.Time{} }},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			e := valid
			c.mutate(&e)
			if err := e.Validate(); err == nil {
				t.Fatal("expected error")
			}
		})
	}
}
