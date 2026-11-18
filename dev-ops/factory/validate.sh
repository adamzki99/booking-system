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
run python3 -m py_compile dev-ops/factory/lib/factory.py dev-ops/factory/discover_fix_candidates.py dev-ops/factory/discover_build_candidates.py
run python3 dev-ops/factory/lib/factory.py validate-models dev-ops/factory/models.yaml
run python3 - <<'PY'
import yaml, json
with open('dev-ops/factory/models.yaml', 'r', encoding='utf-8') as f:
    yaml.safe_load(f)
# minimal event schema smoke check
import sys
sys.path.insert(0, 'dev-ops/factory/lib')
import factory
e=factory.make_event('validate_smoke','tick0',False,'backup','dev','host')
factory.validate_event(e)
print('OK: schema/event smoke checks')
PY

# Unit tests (factory lib)
if command -v pytest >/dev/null 2>&1; then
  run pytest -q dev-ops/scripts/tests/test-factory-lib.py
elif python3 -m pytest --version >/dev/null 2>&1; then
  run python3 -m pytest -q dev-ops/scripts/tests/test-factory-lib.py
else
  echo "[factory-validate] WARN: pytest not installed; skipped factory unit tests"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "[factory-validate] FAIL" >&2
  exit 1
fi
echo "[factory-validate] OK"
