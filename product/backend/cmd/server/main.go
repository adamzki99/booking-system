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

	"github.com/adamzki99/booking-system/product/backend/internal/config"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/server"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	cfg := config.Load()

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	var pool *pgxpool.Pool
	var store eventstore.Store
	if cfg.DatabaseURL != "" {
		p, err := eventstore.OpenPool(context.Background(), cfg.DatabaseURL)
		if err != nil {
			logger.Error("open db pool", "err", err)
			os.Exit(1)
		}
		pool = p
		if err := eventstore.Migrate(context.Background(), pool); err != nil {
			pool.Close()
			logger.Error("migrate db", "err", err)
			os.Exit(1)
		}
		store = eventstore.NewPostgresStore(pool)
		logger.Info("event store ready")
	}

	srv := server.New(cfg, logger, store)
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
	if pool != nil {
		pool.Close()
	}
	logger.Info("server stopped")
}
