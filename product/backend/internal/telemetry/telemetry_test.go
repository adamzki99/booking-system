package telemetry

import (
	"context"
	"errors"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/config"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/log/global"
	"go.opentelemetry.io/otel/sdk/metric"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

func TestBuildResourceIncludesEnvAttributes(t *testing.T) {
	t.Setenv("OTEL_RESOURCE_ATTRIBUTES", "service.version=1.2.3,deployment.environment=test,project=sauna")
	t.Setenv("OTEL_SERVICE_NAME", "")

	res, err := buildResource(context.Background(), config.Config{OTELServiceName: "booking-backend"})
	if err != nil {
		t.Fatalf("buildResource: %v", err)
	}
	attrs := map[string]string{}
	for _, kv := range res.Attributes() {
		attrs[string(kv.Key)] = kv.Value.Emit()
	}
	if attrs["service.name"] != "booking-backend" {
		t.Fatalf("service.name = %q", attrs["service.name"])
	}
	if attrs["service.version"] != "1.2.3" {
		t.Fatalf("service.version = %q", attrs["service.version"])
	}
	if attrs["deployment.environment"] != "test" {
		t.Fatalf("deployment.environment = %q", attrs["deployment.environment"])
	}
	if attrs["project"] != "sauna" {
		t.Fatalf("project = %q", attrs["project"])
	}
}

func TestInitFailureDoesNotInstallGlobals(t *testing.T) {
	origTrace := newTraceExporter
	origMetric := newMetricExporter
	origLog := newLogExporter
	origTP := otel.GetTracerProvider()
	origMP := otel.GetMeterProvider()
	origLP := global.GetLoggerProvider()
	origProp := otel.GetTextMapPropagator()
	t.Cleanup(func() {
		newTraceExporter = origTrace
		newMetricExporter = origMetric
		newLogExporter = origLog
		otel.SetTracerProvider(origTP)
		otel.SetMeterProvider(origMP)
		global.SetLoggerProvider(origLP)
		otel.SetTextMapPropagator(origProp)
	})

	baseTP := otel.GetTracerProvider()
	baseMP := otel.GetMeterProvider()
	baseLP := global.GetLoggerProvider()
	baseProp := otel.GetTextMapPropagator()

	newTraceExporter = func(ctx context.Context, opts ...otlptracehttp.Option) (*otlptrace.Exporter, error) {
		return otlptracehttp.New(ctx, otlptracehttp.WithInsecure(), otlptracehttp.WithEndpoint("127.0.0.1:1"))
	}
	newMetricExporter = func(ctx context.Context, opts ...otlpmetrichttp.Option) (*otlpmetrichttp.Exporter, error) {
		return nil, errors.New("boom")
	}
	newLogExporter = func(ctx context.Context, opts ...otlploghttp.Option) (*otlploghttp.Exporter, error) {
		t.Fatal("log exporter should not be created after metric failure")
		return nil, nil
	}

	shutdown, handler, err := Init(context.Background(), config.Config{
		OTLPEndpoint:    "http://127.0.0.1:1",
		OTELServiceName: "booking-backend",
	})
	if err == nil {
		t.Fatal("expected error")
	}
	if shutdown != nil || handler != nil {
		t.Fatalf("expected nil shutdown/handler, got shutdown=%t handler=%v", shutdown != nil, handler)
	}
	if otel.GetTracerProvider() != baseTP {
		t.Fatalf("tracer provider changed: %T", otel.GetTracerProvider())
	}
	if otel.GetMeterProvider() != baseMP {
		t.Fatalf("meter provider changed: %T", otel.GetMeterProvider())
	}
	if global.GetLoggerProvider() != baseLP {
		t.Fatalf("logger provider changed: %T", global.GetLoggerProvider())
	}
	if otel.GetTextMapPropagator() != baseProp {
		t.Fatalf("propagator changed: %T", otel.GetTextMapPropagator())
	}

	_ = (*sdktrace.TracerProvider)(nil)
	_ = (*metric.MeterProvider)(nil)
}
