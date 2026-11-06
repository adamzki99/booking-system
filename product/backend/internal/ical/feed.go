package ical

import (
	"strings"
	"time"

	"github.com/adamzki99/booking-system/product/backend/internal/booking"
)

// RenderFeed renders bookings into an RFC 5545 iCal document.
func RenderFeed(bookings []booking.Booking, now time.Time) string {
	var b strings.Builder
	writeLine(&b, "BEGIN:VCALENDAR")
	writeLine(&b, "VERSION:2.0")
	writeLine(&b, "PRODID:-//Booking System//EN")
	writeLine(&b, "CALSCALE:GREGORIAN")
	writeLine(&b, "METHOD:PUBLISH")
	for _, bk := range bookings {
		writeLine(&b, "BEGIN:VEVENT")
		writeLine(&b, "UID:"+escapeText(bk.ID))
		writeLine(&b, "DTSTAMP:"+now.UTC().Format("20060102T150405Z"))
		writeLine(&b, "DTSTART:"+bk.Start.UTC().Format("20060102T150405Z"))
		writeLine(&b, "DTEND:"+bk.End.UTC().Format("20060102T150405Z"))
		writeLine(&b, "SUMMARY:"+escapeText("Booking"))
		if bk.Status == booking.StatusCancelled {
			writeLine(&b, "STATUS:CANCELLED")
		} else {
			writeLine(&b, "STATUS:CONFIRMED")
		}
		writeLine(&b, "END:VEVENT")
	}
	writeLine(&b, "END:VCALENDAR")
	return b.String()
}

// Aliases.
func Render(bookings []booking.Booking, now time.Time) string { return RenderFeed(bookings, now) }
func RenderICal(bookings []booking.Booking, now time.Time) string { return RenderFeed(bookings, now) }

func escapeText(v string) string {
	v = strings.ReplaceAll(v, "\\", "\\\\")
	v = strings.ReplaceAll(v, ";", "\\;")
	v = strings.ReplaceAll(v, ",", "\\,")
	v = strings.ReplaceAll(v, "\n", "\\n")
	v = strings.ReplaceAll(v, "\r", "")
	return v
}

func writeLine(b *strings.Builder, line string) {
	// fold at 75 octets
	folded := foldLine(line, 75)
	b.WriteString(folded)
	b.WriteString("\r\n")
}

func foldLine(line string, limit int) string {
	if len(line) <= limit {
		return line
	}
	var out strings.Builder
	remaining := line
	first := true
	curLimit := limit
	for len(remaining) > curLimit {
		out.WriteString(remaining[:curLimit])
		out.WriteString("\r\n")
		if first {
			// subsequent lines start with a space; account for it
			first = false
		}
		remaining = " " + remaining[curLimit:]
		curLimit = limit - 1
		if curLimit < 1 {
			curLimit = 1
		}
	}
	out.WriteString(remaining)
	return out.String()
}