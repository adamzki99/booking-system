package broadcast

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
)

func broadcastHTTPStatus(err error) int {
	switch {
	case err == nil:
		return http.StatusOK
	case errors.Is(err, ErrInvalidSubject), errors.Is(err, ErrInvalidBody):
		return http.StatusBadRequest
	case errors.Is(err, ErrForbidden):
		return http.StatusForbidden
	default:
		return http.StatusInternalServerError
	}
}

// HandleBroadcast records a broadcast message to all basic users
// (super users only).
func HandleBroadcast(svc *BroadcastService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if svc == nil {
			writeError(w, http.StatusServiceUnavailable, "broadcast unavailable")
			return
		}
		email, ok := auth.FromContext(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		var body struct {
			Subject string `json:"subject"`
			Body    string `json:"body"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeError(w, http.StatusBadRequest, "invalid request body")
			return
		}
		if err := svc.Broadcast(r.Context(), email, body.Subject, body.Body); err != nil {
			writeError(w, broadcastHTTPStatus(err), err.Error())
			return
		}
		w.WriteHeader(http.StatusAccepted)
	}
}

func writeError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": msg})
}
