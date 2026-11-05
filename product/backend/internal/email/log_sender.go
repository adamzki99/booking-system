package email

import (
	"context"
	"log/slog"
)

// LogSender is the dev-mode Sender: it logs emails instead of sending them.
type LogSender struct {
	logger *slog.Logger
}

// NewLogSender returns a Sender that logs each message via logger.
func NewLogSender(logger *slog.Logger) *LogSender {
	if logger == nil {
		logger = slog.Default()
	}
	return &LogSender{logger: logger}
}

// Send logs the email; it never touches the network.
func (s *LogSender) Send(_ context.Context, to, subject, body string) error {
	s.logger.Info("email (log mode, not sent)", "to", to, "subject", subject, "body", body)
	return nil
}
