#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
SCRIPT="$SCRIPT_DIR/../check-acceptance-criteria.sh"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }
pass() { PASS=$((PASS+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Present
cat > "$tmp/ok.md" <<'EOF'
## Problem Statement
x

## Acceptance Criteria

- [ ] measurable outcome
EOF
"$SCRIPT" "$tmp/ok.md" >/dev/null 2>&1 && pass || fail "present"

# Missing section
cat > "$tmp/missing.md" <<'EOF'
## Problem Statement
x
EOF
set +e
"$SCRIPT" "$tmp/missing.md" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ] && pass || fail "missing rc"

# Section present but no checkbox
cat > "$tmp/nocheck.md" <<'EOF'
## Acceptance Criteria

some text
EOF
set +e
"$SCRIPT" "$tmp/nocheck.md" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ] && pass || fail "no-checkbox"

# stdin
cat "$tmp/ok.md" | "$SCRIPT" --stdin >/dev/null 2>&1 && pass || fail "stdin"

# body-file flag
"$SCRIPT" --body-file "$tmp/ok.md" >/dev/null 2>&1 && pass || fail "body-file flag"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]