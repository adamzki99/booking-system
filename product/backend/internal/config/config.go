package config

import (
	"os"
	"strconv"
	"strings"
	"time"
)

// Config holds runtime configuration populated from environment variables.
type Config struct {
	Port          int
	DatabaseURL   string
	SidecarURL    string
	PublicBaseURL string

	EmailMode          string
	SMTPHost           string
	SMTPPort           int
	SMTPUsername       string
	SMTPPassword       string
	SMTPFrom           string
	EmailMaxAttempts   int
	EmailRetryBase     time.Duration
	EmailRetryInterval time.Duration

	OTLPEndpoint    string
	OTELServiceName string

	DevMode       bool
	SeedUsersFile string
	QAMode        bool
}

// Load reads configuration from the environment.
func Load() Config {
	port := 8080
	if v := os.Getenv("PORT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			port = n
		}
	}
	smtpPort := 587
	if v := os.Getenv("SMTP_PORT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			smtpPort = n
		}
	}
	emailMode := os.Getenv("EMAIL_MODE")
	if emailMode == "" {
		emailMode = "log"
	}
	emailMaxAttempts := envInt("EMAIL_MAX_ATTEMPTS", 5)
	emailRetryBase := time.Duration(envInt("EMAIL_RETRY_BASE_SECONDS", 1)) * time.Second
	emailRetryInterval := time.Duration(envInt("EMAIL_RETRY_INTERVAL_SECONDS", 5)) * time.Second
	serviceName := os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = "booking-backend"
	}
	devMode := false
	if v := os.Getenv("DEV_MODE"); v != "" {
		b, err := strconv.ParseBool(v)
		if err == nil {
			devMode = b
		} else {
			// accept "true"/"1" loosely? test uses "true"
			devMode = (v == "true" || v == "1" || v == "yes")
		}
	}
	qaMode := parseBoolEnv("QA_MODE")
	return Config{
		Port:          port,
		DatabaseURL:   os.Getenv("DATABASE_URL"),
		SidecarURL:    os.Getenv("SIDECAR_URL"),
		PublicBaseURL: os.Getenv("PUBLIC_BASE_URL"),

		EmailMode:          emailMode,
		SMTPHost:           os.Getenv("SMTP_HOST"),
		SMTPPort:           smtpPort,
		SMTPUsername:       os.Getenv("SMTP_USERNAME"),
		SMTPPassword:       os.Getenv("SMTP_PASSWORD"),
		SMTPFrom:           os.Getenv("SMTP_FROM"),
		EmailMaxAttempts:   emailMaxAttempts,
		EmailRetryBase:     emailRetryBase,
		EmailRetryInterval: emailRetryInterval,

		OTLPEndpoint:    os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"),
		OTELServiceName: serviceName,

		DevMode:       devMode,
		SeedUsersFile: os.Getenv("SEED_USERS_FILE"),
		QAMode:        qaMode,
	}
}

// envInt reads a positive integer from the environment, falling back to the
// default for absent or invalid values.
func envInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil || n <= 0 {
		return fallback
	}
	return n
}

// parseBoolEnv returns true for common truthy environment variable values.
func parseBoolEnv(key string) bool {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return false
	}
	b, err := strconv.ParseBool(v)
	if err == nil {
		return b
	}
	switch strings.ToLower(v) {
	case "yes", "y", "on":
		return true
	default:
		return false
	}
}
