package ratelimit

import (
	"testing"
	"time"
)

func TestAllowUpToLimit(t *testing.T) {
	l := NewLimiter()
	for i := 0; i < 5; i++ {
		if !l.Allow("k", 5, time.Minute) {
			t.Fatalf("request %d should be allowed", i+1)
		}
	}
	if l.Allow("k", 5, time.Minute) {
		t.Fatal("6th request within the window should be denied")
	}
}

func TestAllowResetsAfterWindow(t *testing.T) {
	l := NewLimiter()
	now := time.Unix(1000, 0)
	l.now = func() time.Time { return now }

	if !l.Allow("k", 1, time.Minute) {
		t.Fatal("first request should be allowed")
	}
	if l.Allow("k", 1, time.Minute) {
		t.Fatal("second request within the window should be denied")
	}

	now = now.Add(time.Minute)
	if !l.Allow("k", 1, time.Minute) {
		t.Fatal("request after the window should be allowed")
	}
}

func TestAllowSeparatesKeys(t *testing.T) {
	l := NewLimiter()
	if !l.Allow("a", 1, time.Minute) {
		t.Fatal("a should be allowed")
	}
	if !l.Allow("b", 1, time.Minute) {
		t.Fatal("b should be allowed independently")
	}
	if l.Allow("a", 1, time.Minute) {
		t.Fatal("a should now be denied")
	}
}
