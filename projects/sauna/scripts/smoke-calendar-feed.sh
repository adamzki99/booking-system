#!/usr/bin/env bash
# QA smoke check for the public iCal feed through the sauna Caddy ingress.
# No Authorization header is sent: the high-entropy token in the URL is the
# only credential. Pass the URL returned by POST /api/account/calendar-token.
set -euo pipefail

url="${1:-${CALENDAR_URL:-}}"
if [ -z "$url" ]; then
  echo "Usage: CALENDAR_URL=https://host/calendar/<token>.ics $0" >&2
  echo "   or: $0 https://host/calendar/<token>.ics" >&2
  exit 2
fi

body="$(mktemp)"
headers="$(mktemp)"
trap 'rm -f "$body" "$headers"' EXIT

status="$(curl -sS --max-time 15 -o "$body" -D "$headers" -w '%{http_code}' "$url")"
if [ "$status" != "200" ]; then
  echo "FAIL: HTTP $status, want 200" >&2
  exit 1
fi

content_type="$(awk 'tolower($1)=="content-type:" {print tolower($2)}' "$headers" | tr -d '\r')"
case "$content_type" in
  text/calendar*) ;;
  *)
    echo "FAIL: Content-Type '$content_type', want text/calendar" >&2
    exit 1
    ;;
esac

if ! grep -q 'BEGIN:VCALENDAR' "$body" || ! grep -q 'END:VCALENDAR' "$body"; then
  echo "FAIL: response is not a VCALENDAR document" >&2
  exit 1
fi

echo "PASS: public feed returned a VCALENDAR document as text/calendar without an auth header"
