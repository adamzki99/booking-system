// Package rules holds the sauna-specific booking validation rules.
package rules

import (
	"errors"
	"time"
)

// ErrOverlap indicates the candidate overlaps an existing booking beyond capacity.
var ErrOverlap = errors.New("overlap")

// ErrCapacity indicates the candidate exceeds capacity.
var ErrCapacity = errors.New("capacity")

// Interval is a booking time range (half-open [Start, End)).
type Interval struct {
	ID    string
	Start time.Time
	End   time.Time
}

// Overlaps reports whether two intervals overlap (half-open).
func Overlaps(a, b Interval) bool {
	return a.Start.Before(b.End) && a.End.After(b.Start)
}

// Validate reports why a candidate interval violates the deployment rules.
// Existing intervals are supplied by the caller; the sidecar keeps no state.
func Validate(candidate Interval, existing []Interval, capacity int) error {
	if capacity <= 0 {
		return ErrCapacity
	}
	count := 0
	for _, other := range existing {
		if candidate.Start.Before(other.End) && candidate.End.After(other.Start) {
			count++
		}
	}
	if count >= capacity {
		if capacity == 1 {
			return ErrOverlap
		}
		return ErrCapacity
	}
	return nil
}
