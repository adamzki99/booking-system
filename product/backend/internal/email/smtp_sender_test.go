package email

import (
	"context"
	"net/smtp"
	"strings"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/config"
)

type sentMail struct {
	addr string
	auth smtp.Auth
	from string
	to   []string
	msg  string
}

func TestSMTPSenderSendsConfiguredMessage(t *testing.T) {
	var got sentMail
	s := &SMTPSender{
		host:     "smtp.example.com",
		port:     587,
		username: "",
		password: "",
		from:     "noreply@example.com",
		sendMail: func(addr string, a smtp.Auth, from string, to []string, msg []byte) error {
			got = sentMail{addr: addr, auth: a, from: from, to: to, msg: string(msg)}
			return nil
		},
	}

	if err := s.Send(context.Background(), "alice@example.com", "Login code", "Your code is 123456"); err != nil {
		t.Fatalf("Send: %v", err)
	}

	if got.addr != "smtp.example.com:587" {
		t.Errorf("addr = %q, want %q", got.addr, "smtp.example.com:587")
	}
	if got.auth != nil {
		t.Errorf("auth = %v, want nil when no username is configured", got.auth)
	}
	if got.from != "noreply@example.com" {
		t.Errorf("envelope from = %q, want %q", got.from, "noreply@example.com")
	}
	if len(got.to) != 1 || got.to[0] != "alice@example.com" {
		t.Errorf("envelope to = %v, want [alice@example.com]", got.to)
	}

	for _, want := range []string{
		"From: noreply@example.com\r\n",
		"To: alice@example.com\r\n",
		"Subject: Login code\r\n",
		"MIME-Version: 1.0\r\n",
		"Content-Type: text/plain; charset=utf-8\r\n",
		"\r\n\r\nYour code is 123456",
	} {
		if !strings.Contains(got.msg, want) {
			t.Errorf("message %q does not contain %q", got.msg, want)
		}
	}
}

func TestSMTPSenderUsesAuthWhenUsernameSet(t *testing.T) {
	var got smtp.Auth
	s := &SMTPSender{
		host:     "smtp.example.com",
		port:     587,
		username: "mailer",
		password: "secret",
		from:     "noreply@example.com",
		sendMail: func(addr string, a smtp.Auth, from string, to []string, msg []byte) error {
			got = a
			return nil
		},
	}

	if err := s.Send(context.Background(), "alice@example.com", "s", "b"); err != nil {
		t.Fatalf("Send: %v", err)
	}
	if got == nil {
		t.Fatal("auth = nil, want PlainAuth when username is configured")
	}
}

func TestNewSelectsSenderFromConfig(t *testing.T) {
	if _, err := New(config.Config{EmailMode: "log"}, nil); err != nil {
		t.Errorf("log mode: %v", err)
	}
	if _, err := New(config.Config{EmailMode: "smtp", SMTPHost: "smtp.example.com", SMTPPort: 587, SMTPFrom: "noreply@example.com"}, nil); err != nil {
		t.Errorf("smtp mode: %v", err)
	}
}

func TestNewRejectsInvalidEmailConfig(t *testing.T) {
	cases := []struct {
		name string
		cfg  config.Config
	}{
		{"unknown mode", config.Config{EmailMode: "carrier-pigeon"}},
		{"smtp without host", config.Config{EmailMode: "smtp", SMTPPort: 587, SMTPFrom: "noreply@example.com"}},
		{"smtp without from", config.Config{EmailMode: "smtp", SMTPHost: "smtp.example.com", SMTPPort: 587}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if _, err := New(c.cfg, nil); err == nil {
				t.Fatal("expected error")
			}
		})
	}
}
