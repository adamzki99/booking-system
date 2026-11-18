package ical

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

// activeFeedUsers is a user directory whose users are always active. It keeps
// token-focused feed tests independent of the users table.
type activeFeedUsers struct{}

func (activeFeedUsers) GetByID(context.Context, string) (user.User, error) {
	return user.User{Active: true}, nil
}

// TestHandleFeedRejectsDeactivatedUsersToken proves a previously valid
// calendar token stops working once its user is deactivated.
func TestHandleFeedRejectsDeactivatedUsersToken(t *testing.T) {
	pool := newHTTPTestPool(t)
	ctx := context.Background()
	if err := eventstore.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `TRUNCATE users, calendar_tokens`); err != nil {
		t.Fatal(err)
	}

	var userID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (id, email, role, address, active)
		 VALUES (gen_random_uuid(), 'feed@example.com', 'basic', '', true) RETURNING id`,
	).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	token, hash, err := GenerateToken()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO calendar_tokens (user_id, token_hash) VALUES ($1, $2)`, userID, hash,
	); err != nil {
		t.Fatal(err)
	}

	h := HandleFeed(NewCalendarTokenProjection(pool), nil, nil, user.NewUsersProjection(pool))
	if rec := getFeed(h, "/calendar/"+token+".ics"); rec.Code != http.StatusOK {
		t.Fatalf("active user feed status = %d, want %d", rec.Code, http.StatusOK)
	}

	if _, err := pool.Exec(ctx, `UPDATE users SET active = false WHERE id = $1`, userID); err != nil {
		t.Fatal(err)
	}
	rec := getFeed(h, "/calendar/"+token+".ics")
	if rec.Code != http.StatusNotFound {
		t.Fatalf("deactivated user feed status = %d, want %d", rec.Code, http.StatusNotFound)
	}
}

// fakeTokenUserResolver implements the regenerate handler's user seam.
type fakeTokenUserResolver struct {
	users map[string]user.User
}

func (f *fakeTokenUserResolver) GetByEmail(_ context.Context, email string) (user.User, error) {
	u, ok := f.users[email]
	if !ok {
		return user.User{}, user.ErrUserNotFound
	}
	return u, nil
}

func TestHandleRegenerateTokenRejectsInactiveUser(t *testing.T) {
	resolver := &fakeTokenUserResolver{users: map[string]user.User{
		"alice@example.com": {ID: "user-1", Email: "alice@example.com", Active: false},
	}}
	req := httptest.NewRequest(http.MethodPost, "/account/calendar-token", nil)
	req = req.WithContext(auth.WithEmail(req.Context(), "alice@example.com"))
	rec := httptest.NewRecorder()

	HandleRegenerateToken(&Service{}, resolver)(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d (body %s)", rec.Code, http.StatusUnauthorized, rec.Body.String())
	}
}
