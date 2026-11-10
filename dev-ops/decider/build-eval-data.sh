#!/usr/bin/env bash
# Eval-data builder for Strands Decider triage (Pilot 1).
# Mines closed issues/PRs via gh into a labeled JSONL dataset + SHA256SUMS.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." >/dev/null && pwd)"
exec python3 "$REPO_ROOT/dev-ops/scripts/build-decider-eval.py" "$@"
