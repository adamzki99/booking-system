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
	"github.com/adamzki99/booking-system/product/backend/internal/notification"
	"github.com/adamzki99/booking-system/product/backend/internal/ratelimit"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
	"github.com/adamzki99/booking-system/product/backend/internal/sample"
	"github.com/adamzki99/booking-system/product/backend/internal/server"
	"github.com/adamzki99/booking-system/product/backend/internal/sidecar"
	"github.com/adamzki99/booking-system/product/backend/internal/telemetry"
	"github.com/adamzki99/booking-system/product/backend/internal/user"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	cfg := config.Load()

	stdoutHandler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})
	logger := slog.New(stdoutHandler)
	slog.SetDefault(logger)

	telShutdown, otelHandler, err := telemetry.Init(context.Background(), cfg)
	if err != nil {
		logger.Error("configure telemetry", "err", err)
		os.Exit(1)
	}
	if otelHandler != nil {
		logger = slog.New(newMultiHandler(stdoutHandler, otelHandler))
		slog.SetDefault(logger)
	}

	mailer, err := email.New(cfg, logger)
	if err != nil {
		logger.Error("configure email", "err", err)
		os.Exit(1)
	}

	var deps server.Deps
	var pool *pgxpool.Pool
	var workerDone <-chan struct{}
	stopNotifications := func() {}
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
		userProjections := user.RegisterWithProjections(app)
		var validator booking.BookingValidator
		if cfg.SidecarURL != "" {
			validator = sidecar.NewClient(cfg.SidecarURL, logger)
		}
		bookings, blocked := booking.Register(app, userProjections.Users, validator)
		outbox := notification.NewPostgresStore(pool)
		booking.RegisterNotify(app, outbox, userProjections.Users, bookings, logger)
		broadcast.Register(app, userProjections.Users)
		broadcast.RegisterNotify(app, outbox, userProjections.Users, logger)
		icalProjections := ical.Register(app)
		if err := app.Projections.CatchUp(context.Background()); err != nil {
			pool.Close()
			logger.Error("catch up projections", "err", err)
			os.Exit(1)
		}

		workerCtx, cancelWorker := context.WithCancel(context.Background())
		stopNotifications = cancelWorker
		done := make(chan struct{})
		workerDone = done
		worker := notification.NewWorker(outbox, mailer, logger, notification.Policy{
			MaxAttempts: cfg.EmailMaxAttempts,
			BaseDelay:   cfg.EmailRetryBase,
		})
		go func() {
			defer close(done)
			if err := worker.Run(workerCtx, cfg.EmailRetryInterval); err != nil {
				logger.Error("notification worker stopped", "err", err)
			}
		}()

		userService := user.NewService(app.Commands, userProjections.Users, userProjections.EmailChanges, mailer, ratelimit.NewLimiter())
		if n, err := user.SeedDevUsers(context.Background(), userService, cfg.DevMode, cfg.SeedUsersFile); err != nil {
			pool.Close()
			logger.Error("seed dev users", "err", err)
			os.Exit(1)
		} else if n > 0 {
			logger.Info("seeded dev users", "count", n)
		}
		if cfg.QAMode {
			if n, err := userService.SeedQAUsers(context.Background()); err != nil {
				pool.Close()
				logger.Error("seed qa users", "err", err)
				os.Exit(1)
			} else if n > 0 {
				logger.Info("seeded qa users", "count", n)
			}
		}
		bookingService := booking.NewService(app.Commands, bookings, userProjections.Users, blocked)
		broadcastService := broadcast.NewService(app.Commands, userProjections.Users)
		icalService := ical.NewService(app.Commands, icalProjections)
		authService := auth.NewService(app.Commands, mailer, ratelimit.NewLimiter(), userProjections.Users)
		authService.QAMode = cfg.QAMode
		authService.BootstrapAdmin = func(ctx context.Context, email string) error {
			return userService.BootstrapAdmin(ctx, email)
		}
		deps.Auth = authService
		deps.Middleware = auth.NewSessionMiddleware(projections.Sessions, userProjections.Users)
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

	deps.SidecarURL = cfg.SidecarURL
	deps.PublicBaseURL = cfg.PublicBaseURL

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
	// Stop the worker before telemetry and the database pool go away so an
	// in-flight delivery cannot emit metrics through a shut-down provider or
	// query a closed pool.
	stopNotifications()
	if workerDone != nil {
		select {
		case <-workerDone:
		case <-time.After(5 * time.Second):
			logger.Warn("notification worker did not stop before shutdown")
		}
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

type multiHandler struct {
	handlers []slog.Handler
}

func newMultiHandler(handlers ...slog.Handler) slog.Handler {
	filtered := make([]slog.Handler, 0, len(handlers))
	for _, h := range handlers {
		if h != nil {
			filtered = append(filtered, h)
		}
	}
	return &multiHandler{handlers: filtered}
}

func (h *multiHandler) Enabled(ctx context.Context, level slog.Level) bool {
	for _, handler := range h.handlers {
		if handler.Enabled(ctx, level) {
			return true
		}
	}
	return false
}

func (h *multiHandler) Handle(ctx context.Context, record slog.Record) error {
	var firstErr error
	for _, handler := range h.handlers {
		if !handler.Enabled(ctx, record.Level) {
			continue
		}
		if err := handler.Handle(ctx, record.Clone()); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

func (h *multiHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	handlers := make([]slog.Handler, len(h.handlers))
	for i, handler := range h.handlers {
		handlers[i] = handler.WithAttrs(attrs)
	}
	return &multiHandler{handlers: handlers}
}

func (h *multiHandler) WithGroup(name string) slog.Handler {
	handlers := make([]slog.Handler, len(h.handlers))
	for i, handler := range h.handlers {
		handlers[i] = handler.WithGroup(name)
	}
	return &multiHandler{handlers: handlers}
}
