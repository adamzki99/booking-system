package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/adamzki99/booking-system/projects/sauna/sidecar/internal/config"
	"github.com/adamzki99/booking-system/projects/sauna/sidecar/internal/server"
	"github.com/adamzki99/booking-system/projects/sauna/sidecar/internal/telemetry"
)

func main() {
	cfg := config.Load()

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	telShutdown, err := telemetry.Init(context.Background(), cfg)
	if err != nil {
		logger.Error("configure telemetry", "err", err)
		os.Exit(1)
	}

	srv := server.New(cfg, logger)
	logger.Info("starting server", "port", cfg.Port)

	go func() {
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server error", "err", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		logger.Error("shutdown error", "err", err)
	}
	shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelShutdown()
	if err := telShutdown(shutdownCtx); err != nil {
		logger.Error("telemetry shutdown", "err", err)
	}
	logger.Info("server stopped")
}
