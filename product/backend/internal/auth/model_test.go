package auth_test

import (
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/auth"
)

func TestValidateEmail(t *testing.T) {
	for _, e := range []string{"alice@example.com", "bob@sub.example.com", "a@b.co"} {
		if err := auth.ValidateEmail(e); err != nil {
			t.Errorf("ValidateEmail(%q) = %v, want nil", e, err)
		}
	}
	for _, e := range []string{
		"", "alice", "alice@", "@example.com", "alice example.com",
		"alice@example.com extra", "Alice <alice@example.com>",
	} {
		if err := auth.ValidateEmail(e); err == nil {
			t.Errorf("ValidateEmail(%q) = nil, want error", e)
		}
	}
}

func TestNormalizeEmailLowercases(t *testing.T) {
	got, err := auth.NormalizeEmail("Alice@Example.COM")
	if err != nil {
		t.Fatal(err)
	}
	if want := "alice@example.com"; got != want {
		t.Fatalf("NormalizeEmail = %q, want %q", got, want)
	}
}

func TestValidateCode(t *testing.T) {
	if err := auth.ValidateCode("ABC123"); err != nil {
		t.Fatalf("ValidateCode(ABC123) = %v, want nil", err)
	}
	for _, c := range []string{"", "ABC12", "ABC1234", "abc123", "ABC12!", "ABC 12"} {
		if err := auth.ValidateCode(c); err == nil {
			t.Errorf("ValidateCode(%q) = nil, want error", c)
		}
	}
}
