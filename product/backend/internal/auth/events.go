package auth

import "time"

const (
	// AggregateType is the auth event aggregate type.
	AggregateType = "auth"

	// LoginCodeIssuedEventType records an issued login code.
	LoginCodeIssuedEventType = "auth.login_code_issued"
	// SessionCreatedEventType records a session created from a verified code.
	SessionCreatedEventType = "auth.session_created"
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
