package config

import (
	"os"
	"strconv"
)

// Config holds runtime configuration populated from environment variables.
type Config struct {
	Port        int
	DatabaseURL string
	SidecarURL  string
}

// Load reads configuration from the environment.
func Load() Config {
	port := 8080
	if v := os.Getenv("PORT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			port = n
		}
	}
	return Config{
		Port:        port,
		DatabaseURL: os.Getenv("DATABASE_URL"),
		SidecarURL:  os.Getenv("SIDECAR_URL"),
	}
}
