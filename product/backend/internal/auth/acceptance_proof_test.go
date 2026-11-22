package auth_test

import "testing"

// Temporary acceptance proof for #172: this skip must fail the backend job.
func TestAcceptanceProofSkip(t *testing.T) {
	t.Skip("temporary acceptance proof for #172")
}
