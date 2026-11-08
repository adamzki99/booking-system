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

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/booking"
	"github.com/adamzki99/booking-system/product/backend/internal/broadcast"
	"github.com/adamzki99/booking-system/product/backend/internal/config"
	"github.com/adamzki99/booking-system/product/backend/internal/email"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/ical"
	"github.com/adamzki99/booking-system/product/backend/internal/ratelimit"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
	"github.com/adamzki99/booking-system/product/backend/internal/sample"
	"github.com/adamzki99/booking-system/product/backend/internal/server"
	"github.com/adamzki99/booking-system/product/backend/internal/telemetry"
	"github.com/adamzki99/booking-system/product/backend/internal/user"

	"github.com/jackc/pgx/v5/pgxpool"
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

	mailer, err := email.New(cfg, logger)
	if err != nil {
		logger.Error("configure email", "err", err)
		os.Exit(1)
	}

	var deps server.Deps
	var pool *pgxpool.Pool
	if cfg.DatabaseURL != "" {
		p, err := eventstore.OpenPool(context.Background(), cfg.DatabaseURL)
		if err != nil {
			logger.Error("open db pool", "err", err)
			os.Exit(1)
		}
		pool = p
		store := eventstore.NewPostgresStore(pool)
		app, err := registry.New(context.Background(), store, pool)
		if err != nil {
			pool.Close()
			logger.Error("initialize application", "err", err)
			os.Exit(1)
		}
		sample.Register(app)
		projections := auth.Register(app)
		userProjections := user.Register(app)
		bookings, blocked := booking.Register(app, userProjections)
		booking.RegisterNotify(app, mailer, userProjections, bookings, logger)
		broadcast.Register(app, userProjections)
		broadcast.RegisterNotify(app, mailer, userProjections, logger)
		icalProjections := ical.Register(app)
		if err := app.Projections.CatchUp(context.Background()); err != nil {
			pool.Close()
			logger.Error("catch up projections", "err", err)
			os.Exit(1)
		}

		userService := user.NewService(app.Commands, userProjections)
		if n, err := user.SeedDevUsers(context.Background(), userService, cfg.DevMode, cfg.SeedUsersFile); err != nil {
			pool.Close()
			logger.Error("seed dev users", "err", err)
			os.Exit(1)
		} else if n > 0 {
			logger.Info("seeded dev users", "count", n)
		}
		bookingService := booking.NewService(app.Commands, bookings, userProjections, blocked)
		broadcastService := broadcast.NewService(app.Commands, userProjections)
		icalService := ical.NewService(app.Commands, icalProjections)
		authService := auth.NewService(app.Commands, mailer, ratelimit.NewLimiter())
		authService.BootstrapAdmin = func(ctx context.Context, email string) error {
			return userService.BootstrapAdmin(ctx, email)
		}
		deps.Auth = authService
		deps.Middleware = auth.NewSessionMiddleware(projections.Sessions)
		deps.UserService = userService
		deps.BookingService = bookingService
		deps.BroadcastService = broadcastService
		deps.ICal = icalService
		deps.ICalService = icalService
		deps.CalendarTokenService = icalService
		deps.CalendarTokens = icalProjections
		deps.Bookings = bookings
		logger.Info("event store and projections ready")
	}

	srv := server.New(cfg, logger, deps)
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
	if telShutdown != nil {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := telShutdown(shutdownCtx); err != nil {
			slog.Error("telemetry shutdown", "err", err)
		}
	}
	if pool != nil {
		pool.Close()
	}
	logger.Info("server stopped")
}
