package e2e

import (
	"context"
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

var _ email.Sender = (*captureSender)(nil)
