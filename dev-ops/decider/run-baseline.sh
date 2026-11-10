#!/usr/bin/env bash
# Baseline runner for Strands Decider triage (Pilot 1).
# Scores released models + majority-class baseline; writes results file.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." >/dev/null && pwd)"
exec python3 "$REPO_ROOT/dev-ops/scripts/run-decider-baseline.py" "$@"
