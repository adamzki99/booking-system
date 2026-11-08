package server_test

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/ratelimit"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
	"github.com/adamzki99/booking-system/product/backend/internal/server"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

type captureSender struct {
	mu   sync.Mutex
	body string
}

func (s *captureSender) Send(_ context.Context, _, _ string, body string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.body = body
	return nil
}

func newTestServer(t *testing.T) (*httptest.Server, *captureSender) {
	t.Helper()
	ctx := context.Background()
	pool := newServerTestPool(t)
	store := eventstore.NewPostgresStore(pool)
	app, err := registry.New(ctx, store, pool)
	if err != nil {
		t.Fatal(err)
	}
	projections := auth.Register(app)

	sender := &captureSender{}
	svc := auth.NewService(app.Commands, sender, ratelimit.NewLimiter())
	mw := auth.NewSessionMiddleware(projections.Sessions)
	deps := server.Deps{Auth: svc, Middleware: mw}

	ts := httptest.NewServer(server.NewMux(deps))
	t.Cleanup(ts.Close)
	return ts, sender
}

func TestAuthFlow(t *testing.T) {
	ts, sender := newTestServer(t)

	resp, _ := request(t, ts, http.MethodPost, "/auth/request-code", `{"email":"alice@example.com"}`, nil)
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("request-code status = %d, want %d", resp.StatusCode, http.StatusNoContent)
	}
	code := sender.body
	if code == "" {
		t.Fatal("no code emailed")
	}

	resp, body := request(t, ts, http.MethodPost, "/auth/verify", `{"email":"alice@example.com","code":"`+code+`"}`, nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("verify status = %d, want %d (body %s)", resp.StatusCode, http.StatusOK, body)
	}
	var verify struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(body, &verify); err != nil {
		t.Fatal(err)
	}
	if verify.Token == "" {
		t.Fatal("verify response missing token")
	}

	header := http.Header{"Authorization": []string{"Bearer " + verify.Token}}
	resp, body = request(t, ts, http.MethodGet, "/auth/me", "", header)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("me status = %d, want %d", resp.StatusCode, http.StatusOK)
	}
	var me struct {
		Email string `json:"email"`
	}
	if err := json.Unmarshal(body, &me); err != nil {
		t.Fatal(err)
	}
	if me.Email != "alice@example.com" {
		t.Fatalf("me email = %q, want alice@example.com", me.Email)
	}
}

func TestRequestCodeRejectsInvalidEmail(t *testing.T) {
	ts, _ := newTestServer(t)
	resp, _ := request(t, ts, http.MethodPost, "/auth/request-code", `{"email":"not-an-email"}`, nil)
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", resp.StatusCode, http.StatusBadRequest)
	}
}

func TestVerifyRejectsWrongCode(t *testing.T) {
	ts, _ := newTestServer(t)
	if resp, _ := request(t, ts, http.MethodPost, "/auth/request-code", `{"email":"alice@example.com"}`, nil); resp.StatusCode != http.StatusNoContent {
		t.Fatalf("request-code status = %d", resp.StatusCode)
	}
	resp, _ := request(t, ts, http.MethodPost, "/auth/verify", `{"email":"alice@example.com","code":"AAAAAA"}`, nil)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", resp.StatusCode, http.StatusUnauthorized)
	}
}

func TestMeWithoutToken(t *testing.T) {
	ts, _ := newTestServer(t)
	resp, _ := request(t, ts, http.MethodGet, "/auth/me", "", nil)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", resp.StatusCode, http.StatusUnauthorized)
	}
}

func TestRequestCodeRateLimited(t *testing.T) {
	ts, _ := newTestServer(t)
	for i := 0; i < 5; i++ {
		if resp, _ := request(t, ts, http.MethodPost, "/auth/request-code", `{"email":"alice@example.com"}`, nil); resp.StatusCode != http.StatusNoContent {
			t.Fatalf("request %d status = %d", i+1, resp.StatusCode)
		}
	}
	resp, _ := request(t, ts, http.MethodPost, "/auth/request-code", `{"email":"alice@example.com"}`, nil)
	if resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want %d", resp.StatusCode, http.StatusTooManyRequests)
	}
}

func TestCalendarFeedRateLimited(t *testing.T) {
	ts, _ := newTestServer(t)
	for i := 0; i < 30; i++ {
		if resp, _ := request(t, ts, http.MethodGet, fmt.Sprintf("/calendar/unknown-token-%d.ics", i), "", nil); resp.StatusCode != http.StatusServiceUnavailable {
			t.Fatalf("request %d status = %d, want %d", i+1, resp.StatusCode, http.StatusServiceUnavailable)
		}
	}
	resp, _ := request(t, ts, http.MethodGet, "/calendar/unknown-token-30.ics", "", nil)
	if resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want %d", resp.StatusCode, http.StatusTooManyRequests)
	}
}

func request(t *testing.T, ts *httptest.Server, method, path, body string, header http.Header) (*http.Response, []byte) {
	t.Helper()
	var rd io.Reader
	if body != "" {
		rd = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, ts.URL+path, rd)
	if err != nil {
		t.Fatal(err)
	}
	for k, vs := range header {
		for _, v := range vs {
			req.Header.Add(k, v)
		}
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return resp, data
}

func newServerTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	ctx := context.Background()

	if url := os.Getenv("DATABASE_URL"); url != "" {
		pool, err := pgxpool.New(ctx, url)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(pool.Close)
		return pool
	}

	container, err := postgres.Run(ctx, "postgres:16",
		postgres.WithDatabase("test"),
		postgres.WithUsername("test"),
		postgres.WithPassword("test"),
		testcontainers.WithWaitStrategy(wait.ForLog("database system is ready to accept connections").WithOccurrence(2)),
	)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = container.Terminate(ctx) })

	url, err := container.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	return pool
}
