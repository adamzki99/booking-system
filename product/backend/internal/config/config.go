package config

import (
	"os"
	"strconv"
)

// Config holds runtime configuration populated from environment variables.
type Config struct {
	Port          int
	DatabaseURL   string
	SidecarURL    string
	PublicBaseURL string

	EmailMode    string
	SMTPHost     string
	SMTPPort     int
	SMTPUsername string
	SMTPPassword string
	SMTPFrom     string

	OTLPEndpoint    string
	OTELServiceName string

	DevMode       bool
	SeedUsersFile string
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
	return Config{
		Port:          port,
		DatabaseURL:   os.Getenv("DATABASE_URL"),
		SidecarURL:    os.Getenv("SIDECAR_URL"),
		PublicBaseURL: os.Getenv("PUBLIC_BASE_URL"),

		EmailMode:    emailMode,
		SMTPHost:     os.Getenv("SMTP_HOST"),
		SMTPPort:     smtpPort,
		SMTPUsername: os.Getenv("SMTP_USERNAME"),
		SMTPPassword: os.Getenv("SMTP_PASSWORD"),
		SMTPFrom:     os.Getenv("SMTP_FROM"),

		OTLPEndpoint:    os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"),
		OTELServiceName: serviceName,

		DevMode:       devMode,
		SeedUsersFile: os.Getenv("SEED_USERS_FILE"),
	}
}
