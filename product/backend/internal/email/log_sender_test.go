package email

import (
	"bytes"
	"context"
	"log/slog"
	"strings"
	"testing"
)

func TestLogSenderLogsInsteadOfSending(t *testing.T) {
	var buf bytes.Buffer
	logger := slog.New(slog.NewTextHandler(&buf, nil))

	s := NewLogSender(logger)
	if err := s.Send(context.Background(), "alice@example.com", "Login code", "Your code is 123456"); err != nil {
		t.Fatalf("Send: %v", err)
	}

	out := buf.String()
	for _, want := range []string{"alice@example.com", "Login code", "Your code is 123456"} {
		if !strings.Contains(out, want) {
			t.Errorf("log output %q does not contain %q", out, want)
		}
	}
}
