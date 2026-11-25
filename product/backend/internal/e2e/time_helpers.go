package e2e

import "time"

func timeHour() time.Duration { return time.Hour }
func timeRFC3339() string     { return time.RFC3339 }

func futureTime() time.Time {
	return time.Now().Add(24 * time.Hour).Truncate(time.Second)
}
