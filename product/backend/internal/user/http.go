package user

import (
	"encoding/json"

	"errors"
	"github.com/adamzki99/booking-system/product/backend/internal/auth"
	"net/http"
)

// NewHTTPHandlers is a small container for user HTTP handlers.
type HTTPHandlers struct {
	Service *UserService
}

// NewHTTPHandlers creates a handler container.
func NewHTTPHandlers(svc *UserService) *HTTPHandlers {
	return &HTTPHandlers{Service: svc}
}

func writeUserJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeUserError(w http.ResponseWriter, status int, msg string) {
	writeUserJSON(w, status, map[string]string{"error": msg})
}

func userHTTPStatus(err error) int {
	switch {
	case err == nil:
		return http.StatusOK
	case errors.Is(err, ErrInvalidEmail), errors.Is(err, ErrInvalidAddress), errors.Is(err, ErrInvalidRole):
		return http.StatusBadRequest
	case errors.Is(err, ErrForbidden), errors.Is(err, ErrPermissionDenied), errors.Is(err, ErrNotAuthorized), errors.Is(err, ErrAccessDenied):
		return http.StatusForbidden
	case errors.Is(err, ErrUserNotFound), errors.Is(err, ErrNotFound):
		return http.StatusNotFound
	case errors.Is(err, ErrDuplicateEmail), errors.Is(err, ErrEmailTaken), errors.Is(err, ErrEmailAlreadyExists), errors.Is(err, ErrConflict),
		errors.Is(err, ErrNotRemovable), errors.Is(err, ErrCannotRemove), errors.Is(err, ErrUserNotRemovable), errors.Is(err, ErrNotRemovableUser),
		errors.Is(err, ErrSelfRemoval), errors.Is(err, ErrCannotRemoveSelf),
		errors.Is(err, ErrTargetNotBasic), errors.Is(err, ErrNotBasicUser),
		errors.Is(err, ErrBootstrapNotAllowed):
		// not removable / conflict cases -> 409 for remove/not removable; duplicate -> 409
		return http.StatusConflict
	default:
		return http.StatusInternalServerError
	}
}

// HandleListUsers returns all users.
func HandleListUsers(svc *UserService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeUserError(w, http.StatusServiceUnavailable, "user unavailable")
			return
		}
		users, err := svc.ListUsers(r.Context())
		if err != nil {
			writeUserError(w, userHTTPStatus(err), err.Error())
			return
		}
		out := make([]map[string]any, 0, len(users))
		for _, u := range users {
			out = append(out, userToMap(u))
		}
		writeUserJSON(w, http.StatusOK, out)
	}
}

// HandleMe returns the caller's user record.
func HandleMe(svc *UserService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeUserError(w, http.StatusServiceUnavailable, "user unavailable")
			return
		}
		email, ok := auth.FromContext(r.Context())
		if !ok {
			writeUserError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		u, err := svc.GetByEmail(r.Context(), email)
		if err != nil {
			writeUserError(w, userHTTPStatus(err), err.Error())
			return
		}
		writeUserJSON(w, http.StatusOK, userToMap(u))
	}
}

// HandleCreateUser creates a user (super).
func HandleCreateUser(svc *UserService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeUserError(w, http.StatusServiceUnavailable, "user unavailable")
			return
		}
		caller, ok := auth.FromContext(r.Context())
		if !ok {
			writeUserError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		var body struct {
			Email   string `json:"email"`
			Address string `json:"address"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeUserError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		// role check
		role, ok2 := svc.RoleOf(r.Context(), caller)
		if !ok2 || !role.AtLeast(RoleSuper) {
			writeUserError(w, http.StatusForbidden, "forbidden")
			return
		}
		u, err := svc.AddUser(r.Context(), body.Email, body.Address, caller)
		if err != nil {
			writeUserError(w, userHTTPStatus(err), err.Error())
			return
		}
		writeUserJSON(w, http.StatusCreated, userToMap(u))
	}
}

// HandleRemoveUser removes (deactivates) a user.
func HandleRemoveUser(svc *UserService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeUserError(w, http.StatusServiceUnavailable, "user unavailable")
			return
		}
		caller, ok := auth.FromContext(r.Context())
		if !ok {
			writeUserError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		id := r.PathValue("id")
		role, ok2 := svc.RoleOf(r.Context(), caller)
		if !ok2 || !role.AtLeast(RoleSuper) {
			writeUserError(w, http.StatusForbidden, "forbidden")
			return
		}
		if err := svc.RemoveUser(r.Context(), id, caller); err != nil {
			writeUserError(w, userHTTPStatus(err), err.Error())
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// HandleChangeOwnEmail changes caller's email (or admin acting).
func HandleChangeOwnEmail(svc *UserService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeUserError(w, http.StatusServiceUnavailable, "user unavailable")
			return
		}
		caller, ok := auth.FromContext(r.Context())
		if !ok {
			writeUserError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		var body struct {
			Email string `json:"email"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeUserError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		// resolve target user by session email
		u, err := svc.GetByEmail(r.Context(), caller)
		if err != nil {
			writeUserError(w, userHTTPStatus(err), err.Error())
			return
		}
		updated, err := svc.ChangeOwnEmail(r.Context(), u.ID, body.Email, caller)
		if err != nil {
			writeUserError(w, userHTTPStatus(err), err.Error())
			return
		}
		writeUserJSON(w, http.StatusOK, userToMap(updated))
	}
}

// HandleChangeUserAddress changes a basic user's address (super).
func HandleChangeUserAddress(svc *UserService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeUserError(w, http.StatusServiceUnavailable, "user unavailable")
			return
		}
		caller, ok := auth.FromContext(r.Context())
		if !ok {
			writeUserError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		id := r.PathValue("id")
		role, ok2 := svc.RoleOf(r.Context(), caller)
		if !ok2 || !role.AtLeast(RoleSuper) {
			writeUserError(w, http.StatusForbidden, "forbidden")
			return
		}
		var body struct {
			Address string `json:"address"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeUserError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		updated, err := svc.ChangeUserAddress(r.Context(), id, body.Address, caller)
		if err != nil {
			writeUserError(w, userHTTPStatus(err), err.Error())
			return
		}
		writeUserJSON(w, http.StatusOK, userToMap(updated))
	}
}

// HandleChangeUserRole changes a user's role (admin only).
func HandleChangeUserRole(svc *UserService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeUserError(w, http.StatusServiceUnavailable, "user unavailable")
			return
		}
		caller, ok := auth.FromContext(r.Context())
		if !ok {
			writeUserError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		id := r.PathValue("id")
		role, ok2 := svc.RoleOf(r.Context(), caller)
		if !ok2 || !role.AtLeast(RoleAdmin) {
			writeUserError(w, http.StatusForbidden, "forbidden")
			return
		}
		var body struct {
			Role    string `json:"role"`
			NewRole string `json:"newRole"`
			Newrole string `json:"new_role"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeUserError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		targetRole := body.Role
		if targetRole == "" {
			targetRole = body.NewRole
		}
		if targetRole == "" {
			targetRole = body.Newrole
		}
		updated, err := svc.ChangeUserRole(r.Context(), id, targetRole, caller)
		if err != nil {
			writeUserError(w, userHTTPStatus(err), err.Error())
			return
		}
		writeUserJSON(w, http.StatusOK, userToMap(updated))
	}
}

func userToMap(u User) map[string]any {
	m := map[string]any{
		"id":         u.ID,
		"email":      u.Email,
		"role":       string(u.Role),
		"address":    u.Address,
		"active":     u.Active,
		"createdAt":  u.CreatedAt,
		"created_at": u.CreatedAt,
		"updatedAt":  u.UpdatedAt,
		"updated_at": u.UpdatedAt,
	}
	if u.DeactivatedAt != nil {
		m["deactivatedAt"] = *u.DeactivatedAt
		m["deactivated_at"] = *u.DeactivatedAt
	}
	return m
}
