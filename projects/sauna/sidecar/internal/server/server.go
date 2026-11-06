// Package server wires the sidecar HTTP API.
package server

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/adamzki99/booking-system/projects/sauna/sidecar/internal/config"
)

// Deps holds the dependencies required by the HTTP server. The sidecar is
// stateless, so this is intentionally empty for now.
type Deps struct{}

// NewMux builds the HTTP router.
func NewMux(_ ...Deps) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", handleHealthz)
	mux.HandleFunc("POST /functions/echo", handleEcho)
	return mux
}

// New creates an *http.Server wired with sensible timeouts.
func New(cfg config.Config, logger *slog.Logger, _ ...Deps) *http.Server {
	return &http.Server{
		Addr:         ":" + strconv.Itoa(cfg.Port),
		Handler:      NewMux(),
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
		ErrorLog:     slog.NewLogLogger(logger.Handler(), slog.LevelError),
	}
}

func handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type echoRequest struct {
	Input string `json:"input"`
}

type echoResponse struct {
	Result string `json:"result"`
}

func handleEcho(w http.ResponseWriter, r *http.Request) {
	var req echoRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Input == "" {
		writeError(w, http.StatusBadRequest, "input is required")
		return
	}
	writeJSON(w, http.StatusOK, echoResponse{Result: req.Input})
}

func decodeJSON(r *http.Request, dst any) error {
	dec := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	if err := dec.Decode(dst); err != nil {
		return err
	}
	if err := dec.Decode(&struct{}{}); err != io.EOF {
		return errors.New("request body must contain a single JSON object")
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}
