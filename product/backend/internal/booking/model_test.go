package booking

import (
	"errors"
	"testing"
	"time"
)

func TestValidateInterval(t *testing.T) {
	now := time.Date(2026, time.November, 6, 12, 0, 0, 0, time.UTC)

	cases := []struct {
		name       string
		start, end time.Time
		wantErr    error
	}{
		{
			name:    "valid interval",
			start:   now.Add(time.Hour),
			end:     now.Add(2 * time.Hour),
			wantErr: nil,
		},
		{
			name:    "start equals end",
			start:   now.Add(time.Hour),
			end:     now.Add(time.Hour),
			wantErr: ErrInvalidInterval,
		},
		{
			name:    "start after end",
			start:   now.Add(2 * time.Hour),
			end:     now.Add(time.Hour),
			wantErr: ErrInvalidInterval,
		},
		{
			name:    "start in the past",
			start:   now.Add(-time.Hour),
			end:     now.Add(time.Hour),
			wantErr: ErrStartInPast,
		},
		{
			name:    "start equals now",
			start:   now,
			end:     now.Add(time.Hour),
			wantErr: ErrStartInPast,
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := ValidateInterval(c.start, c.end, now)
			if !errors.Is(err, c.wantErr) {
				t.Fatalf("ValidateInterval() error = %v, want %v", err, c.wantErr)
			}
		})
	}
}

func TestNewID(t *testing.T) {
	a := NewID()
	b := NewID()
	if a == "" || b == "" {
		t.Fatal("NewID returned empty id")
	}
	if a == b {
		t.Fatal("NewID should return distinct ids")
	}
}
