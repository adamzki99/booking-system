#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

fail=0
run() {
  echo "+ $*"
  if ! "$@"; then
    echo "[factory-validate] FAILED: $*" >&2
    fail=1
  fi
}

# Shell syntax and lint
run bash -n dev-ops/factory/tick.sh
run bash -n dev-ops/factory/nightly-cleanup.sh
if command -v shellcheck >/dev/null 2>&1; then
  run shellcheck -x dev-ops/factory/tick.sh dev-ops/factory/nightly-cleanup.sh
else
  echo "[factory-validate] WARN: shellcheck not installed; skipped"
fi

# Python syntax/validation
run python3 -m py_compile dev-ops/factory/lib/factory.py dev-ops/factory/discover_fix_candidates.py dev-ops/factory/discover_build_candidates.py dev-ops/factory/reconcile_outcomes.py dev-ops/factory/queue_snapshot.py
run python3 dev-ops/factory/lib/factory.py validate-models dev-ops/factory/models.yaml
# minimal event schema smoke check (v2)
run python3 - <<'PY'
import sys
sys.path.insert(0, 'dev-ops/factory/lib')
import factory
e = factory.make_event('validate_smoke', 'tick0', False, 'backup', 'dev', 'host', attempt=3, exit_code='0')
factory.validate_event(e)
assert e['schema_version'] == 2 and e['event_id'] and e['exit_code'] == 0
# run the opencode stream parser against the fixture (malformed stream tolerated)
fixture = 'dev-ops/scripts/tests/fixtures/opencode-stream-v2.3.2.jsonl'
with open(fixture, 'r', encoding='utf-8') as f:
    d = factory.parse_opencode_stream(f.read())
assert d.get('session_id') and d.get('steps') == 2 and d.get('tool_calls') == 1
assert factory.parse_opencode_stream('garbage\n{not json\n') == {}
print('OK: v2 schema/event smoke checks and opencode stream parser')
PY

# Unit tests (factory lib)
if command -v pytest >/dev/null 2>&1; then
  run pytest -q dev-ops/scripts/tests/test-factory-lib.py dev-ops/scripts/tests/test-reconcile-outcomes.py
elif python3 -m pytest --version >/dev/null 2>&1; then
  run python3 -m pytest -q dev-ops/scripts/tests/test-factory-lib.py dev-ops/scripts/tests/test-reconcile-outcomes.py
else
  echo "[factory-validate] WARN: pytest not installed; skipped factory unit tests"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "[factory-validate] FAIL" >&2
  exit 1
fi
echo "[factory-validate] OK"
