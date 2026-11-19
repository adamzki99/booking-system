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

type fakeMiddlewareUsers struct {
	active map[string]bool
	err    error
}

func (f *fakeMiddlewareUsers) ActiveByEmail(_ context.Context, email string) (bool, error) {
	return f.active[email], f.err
}

func (f *fakeMiddlewareUsers) Count(context.Context) (int, error) { return len(f.active), nil }

func activeMiddlewareUsers() *fakeMiddlewareUsers {
	return &fakeMiddlewareUsers{active: map[string]bool{
		"alice@example.com": true,
		"bob@example.com":   true,
	}}
}

func TestSessionMiddlewarePopulatesContext(t *testing.T) {
	reader := &fakeSessionReader{find: func(_ context.Context, tokenHash string) (auth.Session, error) {
		if want := auth.HashToken("secret-token"); tokenHash != want {
			t.Fatalf("token hash = %q, want %q", tokenHash, want)
		}
		return auth.Session{Email: "alice@example.com", ExpiresAt: time.Now().Add(time.Hour)}, nil
	}}
	mw := auth.NewSessionMiddleware(reader, activeMiddlewareUsers())

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
	mw := auth.NewSessionMiddleware(reader, activeMiddlewareUsers())

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
			mw := auth.NewSessionMiddleware(reader, activeMiddlewareUsers())
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

func TestSessionMiddlewareExpiryBoundary(t *testing.T) {
	cases := []struct {
		name      string
		expiresAt time.Time
		want      int
	}{
		{"before expiry", time.Now().Add(time.Hour), http.StatusOK},
		{"at expiry", time.Now(), http.StatusUnauthorized},
		{"after expiry", time.Now().Add(-time.Hour), http.StatusUnauthorized},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			reader := &fakeSessionReader{find: func(context.Context, string) (auth.Session, error) {
				return auth.Session{Email: "alice@example.com", ExpiresAt: c.expiresAt}, nil
			}}
			mw := auth.NewSessionMiddleware(reader, activeMiddlewareUsers())
			var called bool
			handler := mw.Require(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { called = true }))

			req := httptest.NewRequest(http.MethodGet, "/", nil)
			req.Header.Set("Authorization", "Bearer secret-token")
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)

			if rec.Code != c.want {
				t.Fatalf("status = %d, want %d", rec.Code, c.want)
			}
			if called != (c.want == http.StatusOK) {
				t.Fatalf("handler called = %v, want %v", called, c.want == http.StatusOK)
			}
		})
	}
}

func TestSessionMiddlewareActiveUserCheck(t *testing.T) {
	reader := &fakeSessionReader{find: func(context.Context, string) (auth.Session, error) {
		return auth.Session{Email: "alice@example.com", ExpiresAt: time.Now().Add(time.Hour)}, nil
	}}

	cases := []struct {
		name  string
		users *fakeMiddlewareUsers
		want  int
	}{
		{"active user", &fakeMiddlewareUsers{active: map[string]bool{"alice@example.com": true}}, http.StatusOK},
		{"deactivated user", &fakeMiddlewareUsers{active: map[string]bool{"alice@example.com": false}}, http.StatusUnauthorized},
		{"unknown user", &fakeMiddlewareUsers{active: map[string]bool{}}, http.StatusUnauthorized},
		{"directory error", &fakeMiddlewareUsers{err: context.Canceled}, http.StatusUnauthorized},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			mw := auth.NewSessionMiddleware(reader, c.users)
			var called bool
			handler := mw.Require(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { called = true }))
			req := httptest.NewRequest(http.MethodGet, "/", nil)
			req.Header.Set("Authorization", "Bearer secret-token")
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)
			if rec.Code != c.want {
				t.Fatalf("status = %d, want %d", rec.Code, c.want)
			}
			if called != (c.want == http.StatusOK) {
				t.Fatalf("handler called = %v, want %v", called, c.want == http.StatusOK)
			}
		})
	}
}

func TestSessionMiddlewareWithoutDirectoryRejects(t *testing.T) {
	reader := &fakeSessionReader{find: func(context.Context, string) (auth.Session, error) {
		return auth.Session{Email: "alice@example.com", ExpiresAt: time.Now().Add(time.Hour)}, nil
	}}
	mw := auth.NewSessionMiddleware(reader, nil)
	var called bool
	handler := mw.Require(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { called = true }))
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("Authorization", "Bearer secret-token")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized || called {
		t.Fatalf("status = %d, called = %v, want 401 and not called", rec.Code, called)
	}
}

func TestFromContextMissing(t *testing.T) {
	if _, ok := auth.FromContext(context.Background()); ok {
		t.Fatal("FromContext should report missing email")
	}
}
