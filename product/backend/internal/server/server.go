package server

import (
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/config"
)

// NewMux builds the HTTP router.
func NewMux() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	return mux
}

// New creates an *http.Server wired with sensible timeouts.
func New(cfg config.Config, logger *slog.Logger) *http.Server {
	return &http.Server{
		Addr:         ":" + strconv.Itoa(cfg.Port),
		Handler:      NewMux(),
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
		ErrorLog:     slog.NewLogLogger(logger.Handler(), slog.LevelError),
	}
}
