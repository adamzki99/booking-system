#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." >/dev/null && pwd)"
PASS=0; FAIL=0
pass(){ PASS=$((PASS+1)); }
fail(){ echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Mock reconcile_outcomes.py that fails
cat > "$tmp/reconcile_outcomes.py" <<'PY'
import sys
sys.exit(1)
PY

# Simulate the tick.sh pattern
DRY_RUN=0
RECONCILE_IN_DRY_RUN=0
SCRIPT_DIR="$tmp"
EMITTED=""
emit_event(){ EMITTED="$EMITTED $1"; }
run_factory_reconcile() {
  if [[ "$DRY_RUN" == 1 && "$RECONCILE_IN_DRY_RUN" != 1 ]]; then
    return 0
  fi
  local args=()
  if [[ "$DRY_RUN" == 1 && "$RECONCILE_IN_DRY_RUN" == 1 ]]; then
    args+=(--dry-run)
  fi
  if ! python3 "$SCRIPT_DIR/reconcile_outcomes.py" "${args[@]}" >/dev/null 2>&1; then
    emit_event reconcile_failed error="reconcile_outcomes.py failed"
  fi
}

set +e
run_factory_reconcile
rc=$?
set -e
[[ $rc -eq 0 ]] && pass || fail "reconcile failure changed exit code (rc=$rc)"
[[ "$EMITTED" == *"reconcile_failed"* ]] && pass || fail "reconcile_failed not emitted"

# Dry-run without flag should not run reconciler
DRY_RUN=1
RECONCILE_IN_DRY_RUN=0
EMITTED=""
cat > "$tmp/reconcile_outcomes.py" <<'PY'
import sys
sys.exit(1)
PY
run_factory_reconcile
rc=$?
[[ $rc -eq 0 ]] && pass || fail "dry-run reconcile changed exit code"
[[ "$EMITTED" != *"reconcile_failed"* ]] && pass || fail "reconciler ran in dry-run without flag"

# Dry-run with flag runs (read-only) - still best-effort
DRY_RUN=1
RECONCILE_IN_DRY_RUN=1
EMITTED=""
run_factory_reconcile
rc=$?
[[ $rc -eq 0 ]] && pass || fail "dry-run+flag reconcile changed exit code"
[[ "$EMITTED" == *"reconcile_failed"* ]] && pass || fail "reconcile_failed not emitted in dry-run+flag failure"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
