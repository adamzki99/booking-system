#!/usr/bin/env bash
#
# check-acceptance-criteria.sh — verify that an issue body (or issue) contains
# an "Acceptance Criteria" section with at least one measurable checkbox.
#
# Usage:
#   check-acceptance-criteria.sh --issue <number>
#   check-acceptance-criteria.sh --body-file <path>
#   check-acceptance-criteria.sh <number|path>   (auto-detect)
#   ... | check-acceptance-criteria.sh --stdin
#
# Exit codes: 0 = present, 1 = missing/invalid, 2 = usage error.
set -euo pipefail

mode=""
target=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) mode="issue"; target="$2"; shift 2 ;;
    --body-file) mode="file"; target="$2"; shift 2 ;;
    --stdin) mode="stdin"; shift ;;
    -h|--help) echo "Usage: $0 [--issue N|--body-file F|--stdin|N|F]"; exit 0 ;;
    *)
      if [[ -z "$mode" ]]; then
        if [[ -f "$1" ]]; then mode="file"; else mode="issue"; fi
        target="$1"; shift
      else
        echo "Unexpected argument: $1" >&2; exit 2
      fi
      ;;
  esac
done

case "$mode" in
  issue)
    [[ -n "$target" ]] || { echo "Usage: $0 --issue <number>" >&2; exit 2; }
    body="$(gh issue view "$target" --json body --jq '.body // empty' 2>/dev/null)" || {
      echo "Failed to fetch issue #$target" >&2; exit 2; }
    ;;
  file)
    [[ -n "$target" && -f "$target" ]] || { echo "Body file not found: ${target:-}" >&2; exit 2; }
    body="$(cat "$target")"
    ;;
  stdin)
    body="$(cat)"
    ;;
  *)
    echo "Usage: $0 [--issue N|--body-file F|--stdin|N|F]" >&2; exit 2
    ;;
esac

python3 - "$body" <<'PY'
import re, sys
body = sys.argv[1] if len(sys.argv) > 1 else ""
lines = body.splitlines()
# Find an "Acceptance Criteria" heading (## or deeper).
start = None
for i, line in enumerate(lines):
    if re.match(r'^#{1,6}\s+.*acceptance criteria\b', line, re.IGNORECASE):
        start = i + 1
        break
if start is None:
    print("Missing '## Acceptance Criteria' section", file=sys.stderr)
    sys.exit(1)
# Collect until next heading of same or higher level.
end = len(lines)
for j in range(start, len(lines)):
    if re.match(r'^#{1,6}\s+', lines[j]):
        end = j
        break
section = "\n".join(lines[start:end])
if not re.search(r'^\s*[-*]\s*\[[ xX]\]\s*.+', section, re.MULTILINE):
    print("Acceptance Criteria must contain at least one '- [ ] ...' checkbox", file=sys.stderr)
    sys.exit(1)
print("OK: acceptance criteria present")
PY