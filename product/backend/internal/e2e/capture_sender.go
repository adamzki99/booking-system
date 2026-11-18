package e2e

import (
	"context"
	"errors"
	"sync"

	"github.com/adamzki99/booking-system/product/backend/internal/email"
)

// captureSender is an in-memory email.Sender used by E2E tests. failNext
// simulates a transient sender failure for a subject a fixed number of times.
type captureSender struct {
	mu       sync.Mutex
	messages []capturedMessage
	failNext map[string]int
}

type capturedMessage struct {
	To      string
	Subject string
	Body    string
}

func (c *captureSender) Send(_ context.Context, to, subject, body string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.failNext[subject] > 0 {
		c.failNext[subject]--
		return errors.New("transient sender failure")
	}
	c.messages = append(c.messages, capturedMessage{To: to, Subject: subject, Body: body})
	return nil
}

// failFor schedules count transient failures for a subject.
func (c *captureSender) failFor(subject string, count int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.failNext == nil {
		c.failNext = make(map[string]int)
	}
	c.failNext[subject] = count
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
