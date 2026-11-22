package auth_test

import "testing"

// Temporary acceptance proof for #172: must trigger WARNING: DATA RACE under -race.
func TestAcceptanceProofDataRace(t *testing.T) {
	m := map[int]int{}
	done := make(chan struct{})
	go func() {
		for i := 0; i < 1000; i++ {
			m[i] = i
		}
		close(done)
	}()
	for i := 0; i < 1000; i++ {
		_ = m[i]
	}
	<-done
}
