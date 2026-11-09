// Package config holds runtime configuration for the sidecar.
package config

import (
	"os"
	"strconv"
	"strings"
)

// Config holds runtime configuration populated from environment variables.
type Config struct {
	Port            int
	BookingTimezone string
	Capacity        int
	// RedeployTimes lists daily redeploy times in "HH:MM" form. Empty means no
	// schedule is exposed (e.g. production).
	RedeployTimes []string
}

// Load reads configuration from the environment.
func Load() Config {
	port := 8081
	if v := os.Getenv("PORT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			port = n
		}
	}
	tz := os.Getenv("BOOKING_TIMEZONE")
	if tz == "" {
		tz = "Europe/Stockholm"
	}
	capacity := 1
	if v := os.Getenv("SAUNA_CAPACITY"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			capacity = n
		}
	}
	var redeployTimes []string
	for _, part := range strings.Split(os.Getenv("REDEPLOY_TIMES"), ",") {
		if t := strings.TrimSpace(part); t != "" {
			redeployTimes = append(redeployTimes, t)
		}
	}
	return Config{Port: port, BookingTimezone: tz, Capacity: capacity, RedeployTimes: redeployTimes}
}
