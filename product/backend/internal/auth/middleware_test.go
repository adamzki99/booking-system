package auth_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
)

type fakeSessionReader struct {
	find func(ctx context.Context, tokenHash string) (auth.Session, error)
}

func (f *fakeSessionReader) Find(ctx context.Context, tokenHash string) (auth.Session, error) {
	return f.find(ctx, tokenHash)
}

func TestSessionMiddlewarePopulatesContext(t *testing.T) {
	reader := &fakeSessionReader{find: func(_ context.Context, tokenHash string) (auth.Session, error) {
		if want := auth.HashToken("secret-token"); tokenHash != want {
			t.Fatalf("token hash = %q, want %q", tokenHash, want)
		}
		return auth.Session{Email: "alice@example.com", ExpiresAt: time.Now().Add(time.Hour)}, nil
	}}
	mw := auth.NewSessionMiddleware(reader)

	var got string
	handler := mw.Require(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		got, _ = auth.FromContext(r.Context())
	}))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got != "alice@example.com" {
		t.Fatalf("email = %q, want alice@example.com", got)
	}
}

func TestSessionMiddlewareAcceptsCookie(t *testing.T) {
	reader := &fakeSessionReader{find: func(context.Context, string) (auth.Session, error) {
		return auth.Session{Email: "bob@example.com", ExpiresAt: time.Now().Add(time.Hour)}, nil
	}}
	mw := auth.NewSessionMiddleware(reader)

	var got string
	handler := mw.Require(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		got, _ = auth.FromContext(r.Context())
	}))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.AddCookie(&http.Cookie{Name: "session", Value: "cookie-token"})
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK || got != "bob@example.com" {
		t.Fatalf("status=%d email=%q, want 200 bob@example.com", rec.Code, got)
	}
}

func TestSessionMiddlewareRejects(t *testing.T) {
	valid := auth.Session{Email: "alice@example.com", ExpiresAt: time.Now().Add(time.Hour)}
	cases := []struct {
		name  string
		token string
		find  func(string) (auth.Session, error)
	}{
		{
			name: "missing token",
			find: func(string) (auth.Session, error) { return valid, nil },
		},
		{
			name:  "unknown token",
			token: "Bearer nope",
			find:  func(string) (auth.Session, error) { return auth.Session{}, auth.ErrNoSession },
		},
		{
			name:  "expired session",
			token: "Bearer expired",
			find: func(string) (auth.Session, error) {
				return auth.Session{Email: "alice@example.com", ExpiresAt: time.Now().Add(-time.Hour)}, nil
			},
		},
		{
			name:  "revoked session",
			token: "Bearer revoked",
			find: func(string) (auth.Session, error) {
				return auth.Session{Email: "alice@example.com", ExpiresAt: time.Now().Add(time.Hour), Revoked: true}, nil
			},
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			reader := &fakeSessionReader{find: func(_ context.Context, tokenHash string) (auth.Session, error) {
				return c.find(tokenHash)
			}}
			mw := auth.NewSessionMiddleware(reader)
			called := false
			handler := mw.Middleware(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
				called = true
			}))

			req := httptest.NewRequest(http.MethodGet, "/", nil)
			if c.token != "" {
				req.Header.Set("Authorization", c.token)
			}
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)

			if rec.Code != http.StatusUnauthorized {
				t.Fatalf("status = %d, want %d", rec.Code, http.StatusUnauthorized)
			}
			if called {
				t.Fatal("protected handler should not be called")
			}
		})
	}
}

func TestFromContextMissing(t *testing.T) {
	if _, ok := auth.FromContext(context.Background()); ok {
		t.Fatal("FromContext should report missing email")
	}
}
