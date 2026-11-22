#!/usr/bin/env bash
# Tests for dev-ops/scripts/go-test-report.sh.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
SCRIPT="$SCRIPT_DIR/../go-test-report.sh"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }
pass() { PASS=$((PASS+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

summary="$tmp/summary.md"
export GITHUB_STEP_SUMMARY="$summary"

run_report() {
  local jsonl="$1"; shift
  set +e
  "$SCRIPT" "$jsonl" "$@" >"$tmp/out" 2>"$tmp/err"
  RC=$?
  set -e
}

# A clean stream with two passing packages.
cat > "$tmp/all-pass.jsonl" <<'EOF'
{"Action":"run","Package":"example.com/mod/internal/auth","Test":"TestA"}
{"Action":"output","Package":"example.com/mod/internal/auth","Test":"TestA","Output":"=== RUN   TestA\n"}
{"Action":"pass","Package":"example.com/mod/internal/auth","Test":"TestA","Elapsed":0}
{"Action":"output","Package":"example.com/mod/internal/auth","Output":"ok  \texample.com/mod/internal/auth\t0.01s\n"}
{"Action":"pass","Package":"example.com/mod/internal/auth","Elapsed":0.01}
{"Action":"run","Package":"example.com/mod/internal/booking","Test":"TestB"}
{"Action":"pass","Package":"example.com/mod/internal/booking","Test":"TestB","Elapsed":0}
{"Action":"pass","Package":"example.com/mod/internal/booking","Elapsed":0.01}
EOF

# All pass, requirements satisfied.
: > "$summary"
run_report "$tmp/all-pass.jsonl" --require-package auth --require-package booking
[ "$RC" -eq 0 ] && pass || fail "all-pass rc=$RC err=$(cat "$tmp/err")"
grep -qF '| example.com/mod/internal/auth | 1 | 0 | 0 |' "$summary" && pass || fail "summary auth row"
grep -qF '| example.com/mod/internal/booking | 1 | 0 | 0 |' "$summary" && pass || fail "summary booking row"
grep -qF '| example.com/mod/internal/auth | 1 | 0 | 0 |' "$tmp/out" && pass || fail "stdout table"

# A test-level skip fails and prints the test name plus captured output.
cat > "$tmp/skip.jsonl" <<'EOF'
{"Action":"run","Package":"example.com/mod/internal/auth","Test":"TestSkip"}
{"Action":"output","Package":"example.com/mod/internal/auth","Test":"TestSkip","Output":"=== RUN   TestSkip\n"}
{"Action":"output","Package":"example.com/mod/internal/auth","Test":"TestSkip","Output":"    auth_test.go:7: deliberately skipped\n"}
{"Action":"skip","Package":"example.com/mod/internal/auth","Test":"TestSkip","Elapsed":0}
{"Action":"pass","Package":"example.com/mod/internal/auth","Elapsed":0.01}
EOF
run_report "$tmp/skip.jsonl" --require-package auth
[ "$RC" -eq 1 ] && pass || fail "skip rc=$RC"
grep -qF 'TestSkip' "$tmp/err" && pass || fail "skip test name in stderr"
grep -qF 'deliberately skipped' "$tmp/err" && pass || fail "skip output in stderr"

# A package-level skip (no Test field, emitted for packages with no test files) is fine.
cat > "$tmp/pkg-skip.jsonl" <<'EOF'
{"Action":"skip","Package":"example.com/mod/cmd/tool","Output":"?   \texample.com/mod/cmd/tool\t[no test files]\n"}
{"Action":"pass","Package":"example.com/mod/internal/auth","Test":"TestA","Elapsed":0}
EOF
run_report "$tmp/pkg-skip.jsonl" --require-package auth
[ "$RC" -eq 0 ] && pass || fail "package-level skip rc=$RC err=$(cat "$tmp/err")"

# A required package that is absent fails.
run_report "$tmp/all-pass.jsonl" --require-package auth --require-package eventstore
[ "$RC" -eq 1 ] && pass || fail "missing required package rc=$RC"
grep -qF 'eventstore' "$tmp/err" && pass || fail "missing package name in stderr"

# A required package present only as a package-level pass (zero test passes) fails.
cat > "$tmp/no-test-pass.jsonl" <<'EOF'
{"Action":"pass","Package":"example.com/mod/internal/eventstore","Elapsed":0.01}
{"Action":"pass","Package":"example.com/mod/internal/auth","Test":"TestA","Elapsed":0}
EOF
run_report "$tmp/no-test-pass.jsonl" --require-package eventstore --require-package auth
[ "$RC" -eq 1 ] && pass || fail "zero-pass required package rc=$RC"

# Non-JSON lines (build failures from go test) are ignored, not fatal.
cat > "$tmp/non-json.jsonl" <<'EOF'
FAIL	example.com/mod/broken	[build failed]
not json at all
{"Action":"pass","Package":"example.com/mod/internal/auth","Test":"TestA","Elapsed":0}
EOF
run_report "$tmp/non-json.jsonl" --require-package auth
[ "$RC" -eq 0 ] && pass || fail "non-json rc=$RC err=$(cat "$tmp/err")"

# A failing test's output and a race warning are surfaced on stderr.
cat > "$tmp/race.jsonl" <<'EOF'
{"Action":"run","Package":"example.com/mod/internal/projection","Test":"TestRace"}
{"Action":"output","Package":"example.com/mod/internal/projection","Test":"TestRace","Output":"=== RUN   TestRace\n"}
{"Action":"output","Package":"example.com/mod/internal/projection","Output":"WARNING: DATA RACE\n"}
{"Action":"fail","Package":"example.com/mod/internal/projection","Test":"TestRace","Elapsed":0}
{"Action":"pass","Package":"example.com/mod/internal/projection","Test":"TestOther","Elapsed":0}
{"Action":"pass","Package":"example.com/mod/internal/projection","Elapsed":0.02}
EOF
run_report "$tmp/race.jsonl" --require-package projection
[ "$RC" -eq 0 ] && pass || fail "race report rc=$RC err=$(cat "$tmp/err")"
grep -qF 'WARNING: DATA RACE' "$tmp/err" && pass || fail "race warning in stderr"
grep -qF 'TestRace' "$tmp/err" && pass || fail "failed test name in stderr"

# Usage errors exit 2.
set +e
"$SCRIPT" >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -eq 2 ] && pass || fail "no-args rc=$rc"
set +e
"$SCRIPT" "$tmp/all-pass.jsonl" --bogus >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -eq 2 ] && pass || fail "unknown-flag rc=$rc"
set +e
"$SCRIPT" "$tmp/does-not-exist.jsonl" >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -eq 2 ] && pass || fail "missing-file rc=$rc"

# No GITHUB_STEP_SUMMARY: still succeeds without writing a summary.
set +e
env -u GITHUB_STEP_SUMMARY "$SCRIPT" "$tmp/all-pass.jsonl" --require-package auth >"$tmp/out" 2>"$tmp/err"
rc=$?
set -e
[ "$rc" -eq 0 ] && pass || fail "no-summary rc=$rc err=$(cat "$tmp/err")"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
