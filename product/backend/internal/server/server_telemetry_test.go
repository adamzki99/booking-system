package server

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/config"
	"go.opentelemetry.io/otel"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
)

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func withSpanRecorder(t *testing.T) *tracetest.InMemoryExporter {
	t.Helper()
	exp := tracetest.NewInMemoryExporter()
	tp := sdktrace.NewTracerProvider(sdktrace.WithSyncer(exp))
	orig := otel.GetTracerProvider()
	otel.SetTracerProvider(tp)
	t.Cleanup(func() {
		_ = tp.Shutdown(t.Context())
		otel.SetTracerProvider(orig)
	})
	return exp
}

func TestServerSpanNameUsesRoutePattern(t *testing.T) {
	exp := withSpanRecorder(t)
	srv := New(config.Config{Port: 8080}, testLogger(), Deps{})

	req := httptest.NewRequest(http.MethodGet, "/auth/config", nil)
	rec := httptest.NewRecorder()
	srv.Handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	spans := exp.GetSpans()
	if len(spans) == 0 {
		t.Fatal("expected spans")
	}
	var found bool
	for _, s := range spans {
		if s.Name == "GET /auth/config" {
			found = true
			for _, kv := range s.Attributes {
				if string(kv.Key) == "http.route" && kv.Value.AsString() != "/auth/config" {
					t.Fatalf("http.route = %q", kv.Value.AsString())
				}
			}
		}
	}
	if !found {
		names := make([]string, 0, len(spans))
		for _, s := range spans {
			names = append(names, s.Name)
		}
		t.Fatalf("span names = %v", names)
	}
}

func TestHealthzExcludedFromTracing(t *testing.T) {
	exp := withSpanRecorder(t)
	srv := New(config.Config{Port: 8080}, testLogger(), Deps{})

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()
	srv.Handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	if spans := exp.GetSpans(); len(spans) != 0 {
		names := make([]string, 0, len(spans))
		for _, s := range spans {
			names = append(names, s.Name)
		}
		t.Fatalf("expected no spans, got %v", names)
	}
}

func TestCalendarFeedSpanDoesNotLeakToken(t *testing.T) {
	exp := withSpanRecorder(t)
	srv := New(config.Config{Port: 8080}, testLogger(), Deps{})

	const secret = "super-secret-token-value"
	req := httptest.NewRequest(http.MethodGet, "/calendar/"+secret+".ics", nil)
	rec := httptest.NewRecorder()
	srv.Handler.ServeHTTP(rec, req)

	if rec.Code == 0 {
		t.Fatal("no response")
	}
	spans := exp.GetSpans()
	if len(spans) == 0 {
		t.Fatal("expected spans")
	}
	for _, s := range spans {
		if strings.Contains(s.Name, secret) {
			t.Fatalf("span name leaked token: %q", s.Name)
		}
		for _, kv := range s.Attributes {
			if strings.Contains(kv.Value.Emit(), secret) {
				t.Fatalf("span attribute %s leaked token: %q", kv.Key, kv.Value.Emit())
			}
		}
	}
}
