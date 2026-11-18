package config

import (
	"testing"
	"time"
)

func TestLoadEmailRetryDefaults(t *testing.T) {
	t.Setenv("EMAIL_MAX_ATTEMPTS", "")
	t.Setenv("EMAIL_RETRY_BASE_SECONDS", "")
	t.Setenv("EMAIL_RETRY_INTERVAL_SECONDS", "")

	cfg := Load()
	if cfg.EmailMaxAttempts != 5 {
		t.Fatalf("EmailMaxAttempts = %d, want 5", cfg.EmailMaxAttempts)
	}
	if cfg.EmailRetryBase != time.Second {
		t.Fatalf("EmailRetryBase = %v, want 1s", cfg.EmailRetryBase)
	}
	if cfg.EmailRetryInterval != 5*time.Second {
		t.Fatalf("EmailRetryInterval = %v, want 5s", cfg.EmailRetryInterval)
	}
}

func TestLoadEmailRetryOverrides(t *testing.T) {
	t.Setenv("EMAIL_MAX_ATTEMPTS", "9")
	t.Setenv("EMAIL_RETRY_BASE_SECONDS", "2")
	t.Setenv("EMAIL_RETRY_INTERVAL_SECONDS", "11")

	cfg := Load()
	if cfg.EmailMaxAttempts != 9 || cfg.EmailRetryBase != 2*time.Second ||
		cfg.EmailRetryInterval != 11*time.Second {
		t.Fatalf("retry policy = %+v", cfg)
	}
}

func TestLoadEmailRetryIgnoresInvalidValues(t *testing.T) {
	t.Setenv("EMAIL_MAX_ATTEMPTS", "nope")
	t.Setenv("EMAIL_RETRY_BASE_SECONDS", "0")
	t.Setenv("EMAIL_RETRY_INTERVAL_SECONDS", "-3")

	cfg := Load()
	if cfg.EmailMaxAttempts != 5 || cfg.EmailRetryBase != time.Second ||
		cfg.EmailRetryInterval != 5*time.Second {
		t.Fatalf("retry policy = %+v, want defaults", cfg)
	}
}
