package e2e

import (
	"context"
	"errors"
	"sync"

	"github.com/adamzki99/booking-system/product/backend/internal/email"
)

// captureSender is an in-memory email.Sender used by E2E tests.
type captureSender struct {
	mu       sync.Mutex
	messages []capturedMessage
}

type capturedMessage struct {
	To      string
	Subject string
	Body    string
}

func (c *captureSender) Send(_ context.Context, to, subject, body string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.messages = append(c.messages, capturedMessage{To: to, Subject: subject, Body: body})
	return nil
}

func (c *captureSender) reset() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.messages = nil
}

func (c *captureSender) all() []capturedMessage {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make([]capturedMessage, len(c.messages))
	copy(out, c.messages)
	return out
}

func (c *captureSender) lastSubject(subject string) (capturedMessage, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for i := len(c.messages) - 1; i >= 0; i-- {
		if c.messages[i].Subject == subject {
			return c.messages[i], true
		}
	}
	return capturedMessage{}, false
}

// flakySender wraps the capture sender and fails the next n outbox deliveries,
// simulating transient SMTP failures. Login-code mail uses captureSender
// directly and is unaffected.
type flakySender struct {
	mu            sync.Mutex
	delegate      email.Sender
	failRemaining int
	calls         int
}

func (f *flakySender) Send(ctx context.Context, to, subject, body string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	if f.failRemaining > 0 {
		f.failRemaining--
		return errors.New("transient smtp failure")
	}
	return f.delegate.Send(ctx, to, subject, body)
}

func (f *flakySender) setFailures(n int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.failRemaining = n
}

func (f *flakySender) callCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls
}

var (
	_ email.Sender = (*captureSender)(nil)
	_ email.Sender = (*flakySender)(nil)
)
