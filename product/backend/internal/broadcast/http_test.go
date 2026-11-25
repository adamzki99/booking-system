package broadcast

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"github.com/adamzki99/booking-system/product/backend/internal/command"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
)

type fakeExecutor struct {
	last command.Command
	err  error
}

func (f *fakeExecutor) Execute(_ context.Context, cmd command.Command) error {
	f.last = cmd
	return f.err
}

type fakeDirectory struct {
	byEmail map[string]user.User
	byIDErr error
}

func (f *fakeDirectory) GetByID(_ context.Context, id string) (user.User, error) {
	if f.byIDErr != nil {
		return user.User{}, f.byIDErr
	}
	for _, u := range f.byEmail {
		if u.ID == id {
			return u, nil
		}
	}
	return user.User{}, user.ErrUserNotFound
}

func (f *fakeDirectory) GetByEmail(_ context.Context, email string) (user.User, error) {
	u, ok := f.byEmail[email]
	if !ok {
		return user.User{}, user.ErrUserNotFound
	}
	return u, nil
}

func newTestService(exec *fakeExecutor, directory Directory) *BroadcastService {
	return NewService(exec, directory)
}

func broadcastDirectory() *fakeDirectory {
	return &fakeDirectory{byEmail: map[string]user.User{
		"super@example.com": {ID: "super-1", Email: "super@example.com", Role: user.RoleSuper},
		"alice@example.com": {ID: "user-1", Email: "alice@example.com", Role: user.RoleBasic},
	}}
}

func TestHandleBroadcastAccepted(t *testing.T) {
	exec := &fakeExecutor{}
	svc := newTestService(exec, broadcastDirectory())

	body := `{"subject":"Sauna closed","body":"The sauna is closed for maintenance."}`
	req := httptest.NewRequest(http.MethodPost, "/broadcast", strings.NewReader(body))
	req = req.WithContext(auth.WithEmail(req.Context(), "super@example.com"))
	rec := httptest.NewRecorder()

	HandleBroadcast(svc)(rec, req)

	if rec.Code != http.StatusAccepted {
		t.Fatalf("status = %d, want %d (body %s)", rec.Code, http.StatusAccepted, rec.Body.String())
	}
	cmd, ok := exec.last.(BroadcastMessage)
	if !ok {
		t.Fatalf("expected BroadcastMessage command, got %T", exec.last)
	}
	if cmd.RequesterID != "super-1" {
		t.Fatalf("command = %+v", cmd)
	}
}

func TestHandleBroadcastForbidden(t *testing.T) {
	svc := newTestService(&fakeExecutor{}, broadcastDirectory())

	body := `{"subject":"Sauna closed","body":"The sauna is closed for maintenance."}`
	req := httptest.NewRequest(http.MethodPost, "/broadcast", strings.NewReader(body))
	req = req.WithContext(auth.WithEmail(req.Context(), "alice@example.com"))
	rec := httptest.NewRecorder()

	HandleBroadcast(svc)(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want %d (body %s)", rec.Code, http.StatusForbidden, rec.Body.String())
	}
}

func TestHandleBroadcastBadRequestBody(t *testing.T) {
	svc := newTestService(&fakeExecutor{}, broadcastDirectory())

	req := httptest.NewRequest(http.MethodPost, "/broadcast", strings.NewReader(`not json`))
	req = req.WithContext(auth.WithEmail(req.Context(), "super@example.com"))
	rec := httptest.NewRecorder()

	HandleBroadcast(svc)(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

func TestHandleBroadcastInvalidMessage(t *testing.T) {
	svc := newTestService(&fakeExecutor{}, broadcastDirectory())

	body := `{"subject":" ","body":"The sauna is closed for maintenance."}`
	req := httptest.NewRequest(http.MethodPost, "/broadcast", strings.NewReader(body))
	req = req.WithContext(auth.WithEmail(req.Context(), "super@example.com"))
	rec := httptest.NewRecorder()

	HandleBroadcast(svc)(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d (body %s)", rec.Code, http.StatusBadRequest, rec.Body.String())
	}
}

func TestBroadcastHTTPStatus(t *testing.T) {
	cases := []struct {
		err  error
		want int
	}{
		{nil, http.StatusOK},
		{ErrInvalidSubject, http.StatusBadRequest},
		{ErrInvalidBody, http.StatusBadRequest},
		{ErrForbidden, http.StatusForbidden},
		{context.Canceled, http.StatusInternalServerError},
	}
	for _, c := range cases {
		if got := broadcastHTTPStatus(c.err); got != c.want {
			t.Fatalf("broadcastHTTPStatus(%v) = %d, want %d", c.err, got, c.want)
		}
	}
}
