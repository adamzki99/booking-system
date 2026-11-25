package e2e

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/booking"
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

func doJSON(t *testing.T, method, url string, body any, token string) *http.Response {
	t.Helper()
	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, url, reader)
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

	app.DrainNotifications(t)
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

func TestEmailChangeKeepsSessionValid(t *testing.T) {
	app := newE2EApp(t)
	const newEmail = "moved@example.com"
	token := login(t, app, basicEmail)

	// Step 1: request the change; the account keeps its old login address.
	resp := doJSON(t, http.MethodPatch, app.Server.URL+"/users/me/email",
		map[string]string{"email": newEmail}, token)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("request email change status = %d, want 202 (body %s)", resp.StatusCode, body)
	}
	var pending struct {
		PendingEmail string `json:"pendingEmail"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&pending); err != nil {
		t.Fatal(err)
	}
	if pending.PendingEmail != newEmail {
		t.Fatalf("pendingEmail = %q, want %q", pending.PendingEmail, newEmail)
	}

	// Step 2: confirm with the code emailed to the new address.
	msg, ok := app.Sender.lastSubject("Confirm your new email")
	if !ok {
		t.Fatal("no email change verification email captured")
	}
	if msg.To != newEmail {
		t.Fatalf("verification code sent to %q, want %q", msg.To, newEmail)
	}
	resp = postJSON(t, app.Server.URL+"/users/me/email/confirm",
		map[string]string{"code": msg.Body}, token)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("confirm email change status = %d, want 200 (body %s)", resp.StatusCode, body)
	}

	// The same session token still identifies the account, now under the new
	// email, without re-authentication.
	resp = doJSON(t, http.MethodGet, app.Server.URL+"/users/me", nil, token)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("GET /users/me after change status = %d, want 200", resp.StatusCode)
	}
	var me map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&me); err != nil {
		t.Fatal(err)
	}
	if me["email"] != newEmail {
		t.Fatalf("/users/me email = %v, want %v", me["email"], newEmail)
	}

	// A protected account action still works with the re-keyed session.
	resp = postJSON(t, app.Server.URL+"/bookings", map[string]any{
		"start": futureTime().Format(timeRFC3339()),
		"end":   futureTime().Add(timeHour()).Format(timeRFC3339()),
	}, token)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("create booking after email change status = %d, want 201 (body %s)", resp.StatusCode, body)
	}

	// A reload (fresh request with the stored token) still resolves the new
	// identity; the old address is gone.
	resp = doJSON(t, http.MethodGet, app.Server.URL+"/users/me", nil, token)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("GET /users/me after reload status = %d, want 200", resp.StatusCode)
	}
	var again map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&again); err != nil {
		t.Fatal(err)
	}
	if again["email"] != newEmail {
		t.Fatalf("email after reload = %v, want %v", again["email"], newEmail)
	}
}

func TestEmailChangeDuplicateRejectedAndAccountUnchanged(t *testing.T) {
	app := newE2EApp(t)
	token := login(t, app, superEmail)

	// super@example.com cannot take basic@example.com.
	resp := doJSON(t, http.MethodPatch, app.Server.URL+"/users/me/email",
		map[string]string{"email": basicEmail}, token)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusConflict {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("duplicate email change status = %d, want 409 (body %s)", resp.StatusCode, body)
	}

	// The account is unchanged and no verification email was sent.
	me := doJSON(t, http.MethodGet, app.Server.URL+"/users/me", nil, token)
	defer me.Body.Close()
	var m map[string]any
	if err := json.NewDecoder(me.Body).Decode(&m); err != nil {
		t.Fatal(err)
	}
	if m["email"] != superEmail {
		t.Fatalf("email after duplicate request = %v, want %v", m["email"], superEmail)
	}
	if _, ok := app.Sender.lastSubject("Confirm your new email"); ok {
		t.Fatal("no verification email should be sent for a duplicate request")
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
	app.DrainNotifications(t)
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

func TestTransientSenderFailureRecoversBookingAndBroadcastEmail(t *testing.T) {
	app := newE2EApp(t)
	basicToken := login(t, app, basicEmail)
	superToken := login(t, app, superEmail)

	// Booking confirmation: two transient failures, then delivery.
	app.DeliverySender.setFailures(2)
	start := futureTime().Add(24 * timeHour())
	end := start.Add(timeHour())
	resp := postJSON(t, app.Server.URL+"/bookings", map[string]any{
		"start": start.Format(timeRFC3339()),
		"end":   end.Format(timeRFC3339()),
	}, basicToken)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("create booking status = %d, want 201", resp.StatusCode)
	}
	var created map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&created); err != nil {
		t.Fatal(err)
	}
	bookingID, _ := created["id"].(string)
	if bookingID == "" {
		t.Fatal("missing booking id")
	}
	if _, ok := app.Sender.lastSubject("Booking confirmed"); ok {
		t.Fatal("confirmation delivered before the worker ran")
	}
	app.DrainNotifications(t)
	if msg, ok := app.Sender.lastSubject("Booking confirmed"); !ok || msg.To != basicEmail {
		t.Fatalf("confirmation = %+v, ok = %v", msg, ok)
	}
	if got := app.DeliverySender.callCount(); got != 3 {
		t.Fatalf("delivery calls = %d, want 3 (two failures + success)", got)
	}

	// Cancellation notice to the owner also recovers, and the booking event
	// is untouched by delivery failures.
	app.DeliverySender.setFailures(2)
	resp = postJSON(t, app.Server.URL+"/bookings/"+bookingID+"/cancel", nil, superToken)
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("cancel status = %d, want 204", resp.StatusCode)
	}
	app.DrainNotifications(t)
	if msg, ok := app.Sender.lastSubject("Booking cancelled"); !ok || msg.To != basicEmail {
		t.Fatalf("cancellation = %+v, ok = %v", msg, ok)
	}
	stored, err := app.Bookings.GetByID(context.Background(), bookingID)
	if err != nil {
		t.Fatal(err)
	}
	if stored.Status != booking.StatusCancelled {
		t.Fatalf("booking status = %q, want %q", stored.Status, booking.StatusCancelled)
	}

	// Broadcast fan-out recovers through the same outbox.
	app.DeliverySender.setFailures(2)
	resp = postJSON(t, app.Server.URL+"/broadcast", map[string]string{
		"subject": "Sauna closed",
		"body":    "Maintenance tonight.",
	}, superToken)
	resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("broadcast status = %d, want 202", resp.StatusCode)
	}
	app.DrainNotifications(t)
	if msg, ok := app.Sender.lastSubject("Sauna closed"); !ok || msg.To != basicEmail {
		t.Fatalf("broadcast = %+v, ok = %v", msg, ok)
	}
}
