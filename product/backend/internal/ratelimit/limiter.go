// Package ratelimit provides an in-memory fixed-window rate limiter.
package ratelimit

import (
	"sync"
	"time"
)

// Limiter tracks per-key request counts in fixed time windows. It is safe for
// concurrent use. Windows reset lazily once their duration has elapsed.
type Limiter struct {
	mu      sync.Mutex
	now     func() time.Time
	windows map[string]window
}

type window struct {
	start time.Time
	count int
}

// NewLimiter creates an empty limiter using the wall clock.
func NewLimiter() *Limiter {
	return &Limiter{
		now:     time.Now,
		windows: make(map[string]window),
	}
}

// Allow reports whether a request under key may proceed, given a limit of
// requests per fixed window of the supplied duration. An allowed request is
// counted; a denied request leaves the count unchanged.
func (l *Limiter) Allow(key string, limit int, windowSize time.Duration) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	if limit <= 0 {
		return false
	}
	now := l.now()
	w, ok := l.windows[key]
	if !ok || !now.Before(w.start.Add(windowSize)) {
		l.windows[key] = window{start: now, count: 1}
		return true
	}
	if w.count >= limit {
		return false
	}
	w.count++
	l.windows[key] = w
	return true
}
