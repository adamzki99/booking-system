package auth_test

import (
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
)

func TestGenerateCodeLengthAndCharset(t *testing.T) {
	for i := 0; i < 100; i++ {
		code, err := auth.GenerateCode()
		if err != nil {
			t.Fatal(err)
		}
		if len(code) != auth.CodeLength {
			t.Fatalf("code %q has length %d, want %d", code, len(code), auth.CodeLength)
		}
		if err := auth.ValidateCode(code); err != nil {
			t.Fatalf("code %q should be valid: %v", code, err)
		}
	}
}

func TestHashCodeRoundTrip(t *testing.T) {
	hash, err := auth.HashCode("ABC123")
	if err != nil {
		t.Fatal(err)
	}
	if !auth.VerifyCodeHash("ABC123", hash) {
		t.Fatal("VerifyCodeHash should accept the matching code")
	}
	if auth.VerifyCodeHash("ABC124", hash) {
		t.Fatal("VerifyCodeHash should reject a non-matching code")
	}
}

func TestGenerateTokenUniquenessAndHash(t *testing.T) {
	token, hash, err := auth.GenerateToken()
	if err != nil {
		t.Fatal(err)
	}
	if token == "" || hash == "" {
		t.Fatal("token and hash should be non-empty")
	}
	if got := auth.HashToken(token); got != hash {
		t.Fatalf("HashToken(%q) = %q, want %q", token, got, hash)
	}
	other, _, _ := auth.GenerateToken()
	if other == token {
		t.Fatal("two generated tokens should differ")
	}
}
