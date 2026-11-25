#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
SCRIPT="$SCRIPT_DIR/../run-ui-audit.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." >/dev/null && pwd)"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }
pass() { PASS=$((PASS+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --help
"$SCRIPT" --help >/dev/null 2>&1 && pass || fail "--help exits 0"

# prod env is rejected
set +e
"$SCRIPT" --env prod --local --dry-run >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] && pass || fail "prod env rejected"

# invalid env name rejected
set +e
"$SCRIPT" --env '../bad' --local --dry-run >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] && pass || fail "invalid env name rejected"

# dry run prepares artifacts and rendered prompt without requiring opencode
deploy_dir="$tmp/deploy"
mkdir -p "$deploy_dir"
artifact_root="$tmp/artifacts"
out="$tmp/dry.out"
if DEPLOY_DIR="$deploy_dir" UI_AUDIT_ARTIFACT_ROOT="$artifact_root" \
    "$SCRIPT" --env qa --local --dry-run --run-id testrun --no-issue-filing >"$out" 2>&1; then
  pass
else
  fail "dry run should succeed"
fi
run_dir="$artifact_root/qa/testrun"
[ -d "$run_dir/evidence" ] && pass || fail "evidence dir created"
[ -f "$run_dir/audit-prompt.md" ] && pass || fail "prompt created"
[ -f "$run_dir/report.md" ] && pass || fail "report created"
[ -f "$run_dir/findings.json" ] && pass || fail "findings created"
[ -f "$run_dir/run.json" ] && pass || fail "run.json created"

grep -q 'Run ID: testrun' "$run_dir/audit-prompt.md" && pass || fail "run id rendered in prompt"
grep -q 'Environment: qa' "$run_dir/audit-prompt.md" && pass || fail "env rendered in prompt"
grep -q 'Base URL: http://127.0.0.1:' "$run_dir/audit-prompt.md" && pass || fail "base URL rendered in prompt"
grep -q 'Issue filing mode: disabled' "$run_dir/audit-prompt.md" && pass || fail "issue filing disabled in prompt"
grep -q 'user1@test.local' "$run_dir/audit-prompt.md" && pass || fail "basic email rendered"
grep -q 'superuser@test.local' "$run_dir/audit-prompt.md" && pass || fail "super email rendered"
grep -q 'admin@test.local' "$run_dir/audit-prompt.md" && pass || fail "admin email rendered"
grep -q "Nielsen's 10 usability heuristics" "$run_dir/audit-prompt.md" && pass || fail "Nielsen heuristics mentioned"
grep -q 'one parent tracking issue for this run' "$run_dir/audit-prompt.md" && pass || fail "parent issue guidance present"
grep -q 'Search and review existing open issues' "$run_dir/audit-prompt.md" && pass || fail "duplicate-check guidance present"
grep -q '\[agent-playwright-audit\]' "$run_dir/audit-prompt.md" && pass || fail "automated title prefix present"
grep -q 'dry run: prepared prompt and artifact skeleton' "$out" && pass || fail "dry run log message"

# issue filing enabled is reflected in prompt and metadata
artifact_root2="$tmp/artifacts2"
DEPLOY_DIR="$deploy_dir" UI_AUDIT_ARTIFACT_ROOT="$artifact_root2" \
  "$SCRIPT" --env qa --local --dry-run --run-id filerun --issue-filing >/dev/null 2>&1
run_dir2="$artifact_root2/qa/filerun"
grep -q 'Issue filing mode: enabled' "$run_dir2/audit-prompt.md" && pass || fail "issue filing enabled in prompt"
grep -q '"issue_filing_mode": "enabled"' "$run_dir2/run.json" && pass || fail "issue filing enabled in run.json"

# custom role emails and prefixes are rendered
artifact_root3="$tmp/artifacts3"
DEPLOY_DIR="$deploy_dir" UI_AUDIT_ARTIFACT_ROOT="$artifact_root3" \
  "$SCRIPT" --env qa --local --dry-run --run-id custom --basic-email basic@x.test --super-email super@x.test --admin-email admin@x.test \
  --title-prefix '[custom-audit]' --parent-title-prefix '[custom-audit][run]' >/dev/null 2>&1
run_dir3="$artifact_root3/qa/custom"
grep -q 'basic@x.test' "$run_dir3/audit-prompt.md" && pass || fail "custom basic email"
grep -q 'super@x.test' "$run_dir3/audit-prompt.md" && pass || fail "custom super email"
grep -q 'admin@x.test' "$run_dir3/audit-prompt.md" && pass || fail "custom admin email"
grep -q '\[custom-audit\]' "$run_dir3/audit-prompt.md" && pass || fail "custom title prefix"
grep -q '\[custom-audit\]\[run\]' "$run_dir3/audit-prompt.md" && pass || fail "custom parent prefix"

# missing agent command fails clearly on non-dry-run
stubs="$tmp/stubs"
mkdir -p "$stubs"
cat > "$stubs/docker" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$stubs/npm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$stubs/docker" "$stubs/npm"
set +e
PATH="$stubs:$PATH" DEPLOY_DIR="$deploy_dir" UI_AUDIT_ARTIFACT_ROOT="$tmp/artifacts4" UI_AUDIT_AGENT_CMD=definitely-missing-opencode \
  "$SCRIPT" --env qa --local --run-id norun --no-issue-filing >"$tmp/noagent.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] && pass || fail "missing agent command fails"
grep -q 'required for agent-driven audit' "$tmp/noagent.out" && pass || fail "missing agent error message"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
