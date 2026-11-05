package eventstore

import (
	"os"
	"strings"
	"testing"
)

func TestNoUpdateOrDeleteAgainstEvents(t *testing.T) {
	b, err := os.ReadFile("eventstore.go")
	if err != nil {
		t.Fatal(err)
	}
	s := strings.ToUpper(string(b))
	if strings.Contains(s, "UPDATE EVENTS") || strings.Contains(s, "DELETE FROM EVENTS") || strings.Contains(s, "DELETE EVENTS") {
		t.Fatal("event store must not update or delete events")
	}
}
