package email

import (
	"context"
	"errors"
	"net/smtp"
	"strconv"
	"strings"

	"github.com/adamzki99/booking-system/product/backend/internal/config"
)

var errMissingSMTPConfig = errors.New("smtp mode requires SMTP_HOST and SMTP_FROM")

// SMTPSender delivers email through an SMTP server.
type SMTPSender struct {
	host     string
	port     int
	username string
	password string
	from     string
	sendMail func(addr string, a smtp.Auth, from string, to []string, msg []byte) error
}

// NewSMTPSender returns a Sender that delivers mail via the configured SMTP server.
func NewSMTPSender(cfg config.Config) (*SMTPSender, error) {
	if cfg.SMTPHost == "" || cfg.SMTPFrom == "" {
		return nil, errMissingSMTPConfig
	}
	return &SMTPSender{
		host:     cfg.SMTPHost,
		port:     cfg.SMTPPort,
		username: cfg.SMTPUsername,
		password: cfg.SMTPPassword,
		from:     cfg.SMTPFrom,
		sendMail: smtp.SendMail,
	}, nil
}

// Send renders a plain-text message and hands it to the SMTP server.
// net/smtp has no context support, so ctx is not used for cancellation.
func (s *SMTPSender) Send(_ context.Context, to, subject, body string) error {
	var auth smtp.Auth
	if s.username != "" {
		auth = smtp.PlainAuth("", s.username, s.password, s.host)
	}
	addr := s.host + ":" + strconv.Itoa(s.port)
	msg := renderMessage(s.from, to, subject, body)
	return s.sendMail(addr, auth, s.from, []string{to}, msg)
}

func renderMessage(from, to, subject, body string) []byte {
	var b strings.Builder
	b.WriteString("From: " + from + "\r\n")
	b.WriteString("To: " + to + "\r\n")
	b.WriteString("Subject: " + subject + "\r\n")
	b.WriteString("MIME-Version: 1.0\r\n")
	b.WriteString("Content-Type: text/plain; charset=utf-8\r\n")
	b.WriteString("\r\n")
	b.WriteString(toCRLF(body))
	return []byte(b.String())
}

func toCRLF(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(s, "\r\n", "\n"), "\n", "\r\n")
}
