// Package config holds runtime configuration for the sidecar.
package config

import (
	"os"
	"strconv"
)

// Config holds runtime configuration populated from environment variables.
type Config struct {
	Port int
}

// Load reads configuration from the environment.
func Load() Config {
	port := 8081
	if v := os.Getenv("PORT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			port = n
		}
	}
	return Config{Port: port}
}
