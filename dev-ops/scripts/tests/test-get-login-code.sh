#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
SCRIPT="$SCRIPT_DIR/../get-login-code.sh"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }
pass() { PASS=$((PASS+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Fixture: two emails interleaved
cat > "$tmp/two.log" <<'EOF'
{"time":"t1","level":"INFO","msg":"email (log mode, not sent)","to":"a@x.com","subject":"Login code","body":"AAAAAA"}
{"time":"t2","level":"INFO","msg":"email (log mode, not sent)","to":"b@x.com","subject":"Login code","body":"BBBBBB"}
EOF
got="$("$SCRIPT" a@x.com --from-file "$tmp/two.log")" && [ "$got" = "AAAAAA" ] && pass || fail "two-emails a"
got="$("$SCRIPT" b@x.com --from-file "$tmp/two.log")" && [ "$got" = "BBBBBB" ] && pass || fail "two-emails b"

# Same email twice -> latest wins
cat > "$tmp/twice.log" <<'EOF'
{"time":"t1","level":"INFO","msg":"email (log mode, not sent)","to":"a@x.com","subject":"Login code","body":"FIRST1"}
{"time":"t2","level":"INFO","msg":"email (log mode, not sent)","to":"a@x.com","subject":"Login code","body":"SECOND"}
EOF
got="$("$SCRIPT" a@x.com --from-file "$tmp/twice.log")" && [ "$got" = "SECOND" ] && pass || fail "latest-wins"

# Text handler fallback
cat > "$tmp/text.log" <<'EOF'
time=t1 level=INFO msg="email (log mode, not sent)" to=c@x.com subject="Login code" body=CCCCCC
EOF
got="$("$SCRIPT" c@x.com --from-file "$tmp/text.log")" && [ "$got" = "CCCCCC" ] && pass || fail "text-fallback"

# Stdin
got="$(cat "$tmp/two.log" | "$SCRIPT" b@x.com --from-file -)" && [ "$got" = "BBBBBB" ] && pass || fail "stdin"

# No match -> exit 2 + stderr
set +e
out="$("$SCRIPT" z@x.com --from-file "$tmp/two.log" 2>"$tmp/err")"
rc=$?
set -e
[ "$rc" -eq 2 ] && [ -s "$tmp/err" ] && pass || fail "no-match exit/rc"

# Prod guard
set +e
"$SCRIPT" a@x.com --env prod --from-file "$tmp/two.log" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] && pass || fail "prod-guard"

# Unknown env guard
set +e
"$SCRIPT" a@x.com --env nope --from-file "$tmp/two.log" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] && pass || fail "unknown-env-guard"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
