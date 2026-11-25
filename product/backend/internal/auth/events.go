package auth

import "time"

const (
	// AggregateType is the auth event aggregate type.
	AggregateType = "auth"

	// LoginCodeIssuedEventType records an issued login code.
	LoginCodeIssuedEventType = "auth.login_code_issued"
	// SessionCreatedEventType records a session created from a verified code.
	SessionCreatedEventType = "auth.session_created"
	// SessionIdentityChangedEventType records the re-keying of open sessions
	// after a verified account email change.
	SessionIdentityChangedEventType = "auth.session_identity_changed"
)

type loginCodeIssuedPayload struct {
	Email     string    `json:"email"`
	CodeHash  string    `json:"code_hash"`
	ExpiresAt time.Time `json:"expires_at"`
}

type sessionCreatedPayload struct {
	Email     string    `json:"email"`
	CodeHash  string    `json:"code_hash"`
	TokenHash string    `json:"token_hash"`
	ExpiresAt time.Time `json:"expires_at"`
}

// sessionIdentityChangedPayload is the payload for auth.session_identity_changed
// events: open sessions are moved from the old account email to the new one.
type SessionIdentityChangedPayload struct {
	OldEmail  string    `json:"old_email"`
	NewEmail  string    `json:"new_email"`
	ChangedAt time.Time `json:"changed_at"`
}
