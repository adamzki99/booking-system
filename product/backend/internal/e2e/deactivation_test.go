package e2e

import (
	"context"
	"net/http"
	"testing"
)

// TestDeactivatedUserLosesAccess proves that deactivating an account revokes
// its live session and prevents it from booking or logging in again.
func TestDeactivatedUserLosesAccess(t *testing.T) {
	app := newE2EApp(t)
	token := login(t, app, basicEmail)

	resp := doJSON(t, http.MethodGet, app.Server.URL+"/users/me", nil, token)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("pre-deactivation /users/me = %d, want %d", resp.StatusCode, http.StatusOK)
	}

	if _, err := app.Pool.Exec(context.Background(),
		`UPDATE users SET active = false WHERE email = $1`, basicEmail,
	); err != nil {
		t.Fatal(err)
	}

	resp = doJSON(t, http.MethodGet, app.Server.URL+"/users/me", nil, token)
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("post-deactivation /users/me = %d, want %d", resp.StatusCode, http.StatusUnauthorized)
	}

	resp = postJSON(t, app.Server.URL+"/bookings", map[string]any{
		"start": futureTime().Format(timeRFC3339()),
		"end":   futureTime().Add(timeHour()).Format(timeRFC3339()),
	}, token)
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("post-deactivation create booking = %d, want %d", resp.StatusCode, http.StatusUnauthorized)
	}

	// A fresh login cannot restore access for the deactivated account.
	var before int
	if err := app.Pool.QueryRow(context.Background(),
		`SELECT count(*) FROM login_codes WHERE email = $1`, basicEmail,
	).Scan(&before); err != nil {
		t.Fatal(err)
	}
	resp = postJSON(t, app.Server.URL+"/auth/request-code", map[string]string{"email": basicEmail}, "")
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("request-code status = %d, want 204", resp.StatusCode)
	}
	var after int
	if err := app.Pool.QueryRow(context.Background(),
		`SELECT count(*) FROM login_codes WHERE email = $1`, basicEmail,
	).Scan(&after); err != nil {
		t.Fatal(err)
	}
	if after != before {
		t.Fatal("no new login code should be recorded for a deactivated user")
	}
	resp = postJSON(t, app.Server.URL+"/auth/verify", map[string]string{"email": basicEmail, "code": "ABC123"}, "")
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("re-login verify = %d, want %d", resp.StatusCode, http.StatusUnauthorized)
	}
}
