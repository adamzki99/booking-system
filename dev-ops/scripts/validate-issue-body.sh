#!/usr/bin/env bash
# Validate that a Markdown issue body follows the agentic issue template.
# Usage: validate-issue-body.sh <path-to-body.md>
# Exits 0 when all required sections are present and acceptance criteria
# contain at least one measurable checkbox; nonzero otherwise.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <path-to-body.md>" >&2
  exit 2
fi

file="$1"
if [[ ! -f "$file" ]]; then
  echo "File not found: $file" >&2
  exit 2
fi

required=(
  "## Problem Statement"
  "## Motivation"
  "## Relevant Repository Context"
  "## Functional Requirements"
  "## Acceptance Criteria"
  "## Implementation Tasks"
  "## Testing and Validation"
  "## Constraints and Considerations"
)

missing=0
for heading in "${required[@]}"; do
  if ! grep -qF "$heading" "$file"; then
    echo "Missing required section: $heading" >&2
    missing=1
  fi
done

# Acceptance criteria must contain at least one checkbox.
if ! grep -Eq '^- \[ \] .+' "$file"; then
  echo "Acceptance Criteria must contain at least one '- [ ] ...' checkbox" >&2
  missing=1
fi

# Each required section should have non-empty content after its heading.
python3 - "$file" "${required[@]}" <<'PY' 2>/dev/null || true
import sys
path = sys.argv[1]
headings = sys.argv[2:]
text = open(path).read().splitlines()
for h in headings:
    try:
        i = text.index(h)
    except ValueError:
        continue
    # find next heading or EOF
    j = i + 1
    while j < len(text) and not text[j].startswith("## "):
        j += 1
    body = [l for l in text[i+1:j] if l.strip()]
    if not body:
        print(f"Empty section: {h}", file=sys.stderr)
        sys.exit(1)
PY
# The python check is advisory; treat its failure as a warning, not fatal,
# to keep the script dependency-light. Re-run as fatal below if python exists.
if command -v python3 >/dev/null 2>&1; then
  if ! python3 - "$file" "${required[@]}" >/dev/null 2>&1 <<'PY'
import sys
path = sys.argv[1]
headings = sys.argv[2:]
text = open(path).read().splitlines()
for h in headings:
    try:
        i = text.index(h)
    except ValueError:
        continue
    j = i + 1
    while j < len(text) and not text[j].startswith("## "):
        j += 1
    body = [l for l in text[i+1:j] if l.strip()]
    if not body:
        sys.exit(1)
PY
  then
    echo "One or more required sections are empty" >&2
    missing=1
  fi
fi

if [[ $missing -ne 0 ]]; then
  echo "Validation FAILED" >&2
  exit 1
fi

echo "Validation OK: all required sections present and acceptance criteria defined."
exit 0