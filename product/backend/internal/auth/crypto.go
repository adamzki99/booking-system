package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"math/big"

	"golang.org/x/crypto/bcrypt"
)

// GenerateCode returns a random CodeLength code drawn from CodeCharset.
func GenerateCode() (string, error) {
	b := make([]byte, CodeLength)
	max := big.NewInt(int64(len(CodeCharset)))
	for i := range b {
		n, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}
		b[i] = CodeCharset[n.Int64()]
	}
	return string(b), nil
}

// HashCode bcrypt-hashes a plaintext login code for storage.
func HashCode(code string) (string, error) {
	hashed, err := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hashed), nil
}

// VerifyCodeHash reports whether a plaintext code matches a stored bcrypt hash.
func VerifyCodeHash(code, hash string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(code)) == nil
}

// GenerateToken returns a high-entropy session token and its SHA-256 hash.
func GenerateToken() (token, hash string, err error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", "", err
	}
	token = base64.RawURLEncoding.EncodeToString(raw)
	return token, HashToken(token), nil
}

// HashToken returns the SHA-256 hex digest of a session token.
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
