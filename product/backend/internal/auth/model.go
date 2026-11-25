package auth

import (
	"errors"
	"net/mail"
	"strings"
)

const (
	// CodeLength is the number of characters in a login code.
	CodeLength = 6
	// CodeCharset is the alphabet login codes are drawn from.
	CodeCharset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
)

var (
	// ErrInvalidEmail indicates an email address failed validation.
	ErrInvalidEmail = errors.New("auth: invalid email")
	// ErrInvalidCode indicates a login code has the wrong length or charset.
	ErrInvalidCode = errors.New("auth: invalid code")
	// ErrRateLimited indicates a client exceeded a rate limit.
	ErrRateLimited = errors.New("auth: rate limited")
	// ErrInvalidOrExpiredCode indicates a submitted code was not accepted.
	ErrInvalidOrExpiredCode = errors.New("auth: invalid or expired code")
)

// NormalizeEmail lowercases and validates an email address, returning the
// normalized form. The parsed address must equal the input, rejecting display
// names and surrounding whitespace.
func NormalizeEmail(email string) (string, error) {
	normalized := strings.ToLower(strings.TrimSpace(email))
	if normalized == "" {
		return "", ErrInvalidEmail
	}
	addr, err := mail.ParseAddress(normalized)
	if err != nil {
		return "", ErrInvalidEmail
	}
	if addr.Address != normalized {
		return "", ErrInvalidEmail
	}
	return normalized, nil
}

// ValidateEmail reports whether an email address is acceptable.
func ValidateEmail(email string) error {
	_, err := NormalizeEmail(email)
	return err
}

// ValidateCode reports whether a login code has the expected length and charset.
func ValidateCode(code string) error {
	if len(code) != CodeLength {
		return ErrInvalidCode
	}
	for i := 0; i < len(code); i++ {
		if !strings.ContainsRune(CodeCharset, rune(code[i])) {
			return ErrInvalidCode
		}
	}
	return nil
}
