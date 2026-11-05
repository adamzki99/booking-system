package auth

import (
	"context"
	"net/http"
	"strings"
	"time"
)

// sessionReader is the part of the sessions read model the middleware needs.
type sessionReader interface {
	Find(ctx context.Context, tokenHash string) (Session, error)
}

// SessionMiddleware protects handlers behind session authentication.
type SessionMiddleware struct {
	sessions sessionReader
}

// NewSessionMiddleware creates session middleware backed by a sessions read model.
func NewSessionMiddleware(sessions sessionReader) *SessionMiddleware {
	return &SessionMiddleware{sessions: sessions}
}

// Middleware validates the session and stores the email in the request context.
func (m *SessionMiddleware) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := extractToken(r)
		if !ok {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		session, err := m.sessions.Find(r.Context(), HashToken(token))
		if err != nil || session.Revoked || !session.ExpiresAt.After(time.Now()) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r.WithContext(WithEmail(r.Context(), session.Email)))
	})
}

// Require wraps a handler function with session authentication.
func (m *SessionMiddleware) Require(next http.HandlerFunc) http.Handler {
	return m.Middleware(next)
}

func extractToken(r *http.Request) (string, bool) {
	if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
		token := strings.TrimSpace(strings.TrimPrefix(h, "Bearer "))
		if token != "" {
			return token, true
		}
	}
	if c, err := r.Cookie("session"); err == nil && c.Value != "" {
		return c.Value, true
	}
	return "", false
}

type emailContextKey struct{}

// WithEmail stores an email in the request context.
func WithEmail(ctx context.Context, email string) context.Context {
	return context.WithValue(ctx, emailContextKey{}, email)
}

// FromContext returns the authenticated email, if present.
func FromContext(ctx context.Context) (string, bool) {
	email, ok := ctx.Value(emailContextKey{}).(string)
	return email, ok
}
