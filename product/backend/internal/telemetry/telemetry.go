// Package telemetry configures OpenTelemetry export to an OTLP collector.
package telemetry

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

	"github.com/adamzki99/booking-system/product/backend/internal/config"

	"go.opentelemetry.io/contrib/bridges/otelslog"
	"go.opentelemetry.io/contrib/instrumentation/runtime"
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

var (
	newTraceExporter  = otlptracehttp.New
	newMetricExporter = otlpmetrichttp.New
	newLogExporter    = otlploghttp.New
)

// Init installs global OpenTelemetry providers. When no OTLP endpoint is
// configured it leaves the default no-op providers in place and returns a
// no-op shutdown function after logging a warning. The returned slog.Handler
// exports log records through OTLP when telemetry is enabled; callers can
// combine it with a local stdout handler.
func buildResource(ctx context.Context, cfg config.Config) (*resource.Resource, error) {
	serviceName := cfg.OTELServiceName
	if serviceName == "" {
		serviceName = "booking-backend"
	}

	// Service name from config/env has precedence over defaults, while
	// OTEL_RESOURCE_ATTRIBUTES and other env-sourced attributes remain visible
	// through WithFromEnv().
	return resource.New(ctx,
		resource.WithAttributes(semconv.ServiceName(serviceName)),
		resource.WithFromEnv(),
		resource.WithTelemetrySDK(),
		resource.WithHost(),
		resource.WithProcessRuntimeName(),
		resource.WithProcessRuntimeVersion(),
		resource.WithProcessRuntimeDescription(),
	)
}

func Init(ctx context.Context, cfg config.Config) (func(context.Context) error, slog.Handler, error) {
	if cfg.OTLPEndpoint == "" {
		slog.Warn("no OTLP endpoint configured; telemetry export disabled")
		return func(context.Context) error { return nil }, nil, nil
	}

	serviceName := cfg.OTELServiceName
	if serviceName == "" {
		serviceName = "booking-backend"
	}

	res, err := buildResource(ctx, cfg)
	if err != nil {
		return nil, nil, fmt.Errorf("telemetry: resource: %w", err)
	}

	endpoint := strings.TrimRight(cfg.OTLPEndpoint, "/")

	traceExp, err := newTraceExporter(ctx, otlptracehttp.WithEndpointURL(endpoint+"/v1/traces"))
	if err != nil {
		return nil, nil, fmt.Errorf("telemetry: trace exporter: %w", err)
	}

	metricExp, err := newMetricExporter(ctx, otlpmetrichttp.WithEndpointURL(endpoint+"/v1/metrics"))
	if err != nil {
		_ = traceExp.Shutdown(ctx)
		return nil, nil, fmt.Errorf("telemetry: metric exporter: %w", err)
	}

	logExp, err := newLogExporter(ctx, otlploghttp.WithEndpointURL(endpoint+"/v1/logs"))
	if err != nil {
		_ = metricExp.Shutdown(ctx)
		_ = traceExp.Shutdown(ctx)
		return nil, nil, fmt.Errorf("telemetry: log exporter: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExp),
		sdktrace.WithResource(res),
	)
	mp := metric.NewMeterProvider(
		metric.WithReader(metric.NewPeriodicReader(metricExp)),
		metric.WithResource(res),
	)
	lp := sdklog.NewLoggerProvider(
		sdklog.WithProcessor(sdklog.NewBatchProcessor(logExp)),
		sdklog.WithResource(res),
	)

	// Install globals only after all providers are created successfully.
	otel.SetTracerProvider(tp)
	otel.SetMeterProvider(mp)
	global.SetLoggerProvider(lp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	if err := runtime.Start(); err != nil {
		slog.Warn("telemetry: runtime metrics disabled", "err", err)
	}

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
	return shutdown, otelslog.NewHandler(serviceName, otelslog.WithLoggerProvider(lp)), nil
}
