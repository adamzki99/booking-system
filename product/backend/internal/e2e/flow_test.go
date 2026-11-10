package e2e

import (
	"bytes"
	"encoding/json"
	"net/http"
	"testing"
)

func postJSON(t *testing.T, url string, body any, token string) *http.Response {
	t.Helper()
	b, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(b))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func login(t *testing.T, app *e2eApp, email string) string {
	t.Helper()
	resp := postJSON(t, app.Server.URL+"/auth/request-code", map[string]string{"email": email}, "")
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("request-code status = %d, want 204", resp.StatusCode)
	}
	msg, ok := app.Sender.lastSubject("Your login code")
	if !ok {
		t.Fatal("no login code email captured")
	}
	if msg.To != email {
		t.Fatalf("login code sent to %q, want %q", msg.To, email)
	}
	resp = postJSON(t, app.Server.URL+"/auth/verify", map[string]string{"email": email, "code": msg.Body}, "")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("verify status = %d, want 200", resp.StatusCode)
	}
	var out map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatal(err)
	}
	if out["token"] == "" {
		t.Fatal("verify returned empty token")
	}
	return out["token"]
}

func TestHappyFlowBookingConfirmationEmail(t *testing.T) {
	app := newE2EApp(t)
	token := login(t, app, basicEmail)

	start := futureTime()
	end := start.Add(timeHour())
	resp := postJSON(t, app.Server.URL+"/bookings", map[string]any{
		"start": start.Format(timeRFC3339()),
		"end":   end.Format(timeRFC3339()),
	}, token)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("create booking status = %d, want 201", resp.StatusCode)
	}
	var booking map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&booking); err != nil {
		t.Fatal(err)
	}
	if booking["id"] == nil || booking["id"] == "" {
		t.Fatal("created booking missing id")
	}

	msg, ok := app.Sender.lastSubject("Booking confirmed")
	if !ok {
		t.Fatal("no booking confirmation email captured")
	}
	if msg.To != basicEmail {
		t.Fatalf("confirmation sent to %q, want %q", msg.To, basicEmail)
	}

	// Unauthenticated create returns 401.
	resp2 := postJSON(t, app.Server.URL+"/bookings", map[string]any{
		"start": start.Add(2 * timeHour()).Format(timeRFC3339()),
		"end":   start.Add(3 * timeHour()).Format(timeRFC3339()),
	}, "")
	defer resp2.Body.Close()
	if resp2.StatusCode != http.StatusUnauthorized {
		t.Fatalf("unauthenticated create status = %d, want 401", resp2.StatusCode)
	}
}

func TestSuperUserCancellationSendsNoticeEmail(t *testing.T) {
	app := newE2EApp(t)
	basicToken := login(t, app, basicEmail)
	superToken := login(t, app, superEmail)

	start := futureTime().Add(timeHour() * 5)
	end := start.Add(timeHour())
	resp := postJSON(t, app.Server.URL+"/bookings", map[string]any{
		"start": start.Format(timeRFC3339()),
		"end":   end.Format(timeRFC3339()),
	}, basicToken)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("create booking status = %d, want 201", resp.StatusCode)
	}
	var b map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&b); err != nil {
		t.Fatal(err)
	}
	bookingID, _ := b["id"].(string)
	if bookingID == "" {
		t.Fatal("missing booking id")
	}

	app.Sender.reset()
	resp = postJSON(t, app.Server.URL+"/bookings/"+bookingID+"/cancel", nil, superToken)
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("cancel status = %d, want 204", resp.StatusCode)
	}
	msg, ok := app.Sender.lastSubject("Booking cancelled")
	if !ok {
		t.Fatal("no cancellation email captured")
	}
	if msg.To != basicEmail {
		t.Fatalf("cancellation sent to %q, want %q", msg.To, basicEmail)
	}

	// Non-super cancellation of another user's booking returns 403.
	// Create another booking owned by super? Instead test basic cancelling nonexistent/other? We'll create booking as super then basic cancels.
	start2 := start.Add(10 * timeHour())
	end2 := start2.Add(timeHour())
	resp = postJSON(t, app.Server.URL+"/bookings", map[string]any{
		"start": start2.Format(timeRFC3339()),
		"end":   end2.Format(timeRFC3339()),
	}, superToken)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("create booking status = %d, want 201", resp.StatusCode)
	}
	var b2 map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&b2)
	id2, _ := b2["id"].(string)
	resp = postJSON(t, app.Server.URL+"/bookings/"+id2+"/cancel", nil, basicToken)
	resp.Body.Close()
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("non-super cancel status = %d, want 403", resp.StatusCode)
	}
}
