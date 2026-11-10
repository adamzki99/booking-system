#!/usr/bin/env bash
# Advisory issue-triage helper backed by Strands Decider (Pilot 1).
# Usage: triage.sh <issue-number>
# Fail-open: prints documented fallback object and exits 0 on service failure.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." >/dev/null && pwd)"
exec python3 "$REPO_ROOT/dev-ops/scripts/decider-triage.py" "$@"
