// Package telemetry configures OpenTelemetry export to an OTLP collector.
package telemetry

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

	"github.com/adamzki99/booking-system/product/backend/internal/config"

	"go.opentelemetry.io/contrib/bridges/otelslog"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/log/global"
	"go.opentelemetry.io/otel/propagation"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// Init installs global OpenTelemetry providers. When no OTLP endpoint is
// configured it leaves the default no-op providers in place and returns a
// no-op shutdown function after logging a warning. The returned slog.Handler
// exports log records through OTLP when telemetry is enabled; callers can
// combine it with a local stdout handler.
func Init(ctx context.Context, cfg config.Config) (func(context.Context) error, slog.Handler, error) {
	if cfg.OTLPEndpoint == "" {
		slog.Warn("no OTLP endpoint configured; telemetry export disabled")
		return func(context.Context) error { return nil }, nil, nil
	}

	serviceName := cfg.OTELServiceName
	if serviceName == "" {
		serviceName = "booking-backend"
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(semconv.ServiceName(serviceName)),
	)
	if err != nil {
		return nil, nil, fmt.Errorf("telemetry: resource: %w", err)
	}

	endpoint := strings.TrimRight(cfg.OTLPEndpoint, "/")

	traceExp, err := otlptracehttp.New(ctx, otlptracehttp.WithEndpointURL(endpoint+"/v1/traces"))
	if err != nil {
		return nil, nil, fmt.Errorf("telemetry: trace exporter: %w", err)
	}
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExp),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)

	metricExp, err := otlpmetrichttp.New(ctx, otlpmetrichttp.WithEndpointURL(endpoint+"/v1/metrics"))
	if err != nil {
		_ = tp.Shutdown(ctx)
		return nil, nil, fmt.Errorf("telemetry: metric exporter: %w", err)
	}
	mp := metric.NewMeterProvider(
		metric.WithReader(metric.NewPeriodicReader(metricExp)),
		metric.WithResource(res),
	)
	otel.SetMeterProvider(mp)

	logExp, err := otlploghttp.New(ctx, otlploghttp.WithEndpointURL(endpoint+"/v1/logs"))
	if err != nil {
		_ = mp.Shutdown(ctx)
		_ = tp.Shutdown(ctx)
		return nil, nil, fmt.Errorf("telemetry: log exporter: %w", err)
	}
	lp := sdklog.NewLoggerProvider(
		sdklog.WithProcessor(sdklog.NewBatchProcessor(logExp)),
		sdklog.WithResource(res),
	)
	global.SetLoggerProvider(lp)

	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	shutdown := func(ctx context.Context) error {
		var firstErr error
		if err := lp.Shutdown(ctx); err != nil && firstErr == nil {
			firstErr = err
		}
		if err := tp.Shutdown(ctx); err != nil && firstErr == nil {
			firstErr = err
		}
		if err := mp.Shutdown(ctx); err != nil && firstErr == nil {
			firstErr = err
		}
		return firstErr
	}
	return shutdown, otelslog.NewHandler(serviceName), nil
}
