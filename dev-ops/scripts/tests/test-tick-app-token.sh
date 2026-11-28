#!/usr/bin/env bash
# GitHub App token lifetime and worktree isolation for tick.sh.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
TICK="$SCRIPT_DIR/../../factory/tick.sh"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { PASS=$((PASS + 1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
real_python="$(command -v python3)"
git_bin="$(command -v git)"
stubs="$tmp/bin"
mkdir -p "$stubs" "$tmp/home/.opencode/bin"
gh_log="$tmp/gh.log"
mint_counter="$tmp/mint-counter"
opencode_token="$tmp/opencode-token"
: > "$gh_log"
printf '0\n' > "$mint_counter"

cat > "$stubs/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == *mint_github_app_token.py ]]; then
  count="$(cat "$MINT_COUNTER")"
  count=$((count + 1))
  printf '%s\n' "$count" > "$MINT_COUNTER"
  if [[ "$count" == "${FAIL_MINT_AT:-0}" ]]; then
    printf 'mint fixture failure\n' >&2
    exit 1
  fi
  printf 'app-token-%s\n' "$count"
  exit 0
fi
exec "$REAL_PYTHON" "$@"
SH

cat > "$stubs/gh" <<'SH'
#!/usr/bin/env bash
printf '%s|%s\n' "${GH_TOKEN:-}" "$*" >> "$GH_LOG"
args="$*"
if [[ "$1 $2" == "repo view" ]]; then
  if [[ "$args" == *"owner,nameWithOwner"* ]]; then
    printf '{"nameWithOwner":"owner/repo","owner":{"login":"owner"}}\n'
  elif [[ "$args" == *"--json owner"* ]]; then
    printf '{"owner":{"login":"owner"}}\n'
  else
    printf 'owner/repo\n'
  fi
elif [[ "$1 $2" == "issue list" ]]; then
  printf '[]\n'
elif [[ "$1 $2" == "issue view" ]]; then
  if [[ "$args" == *"body,comments"* ]]; then
    printf '{"body":"## Acceptance Criteria\\n- [ ] Works\\n","comments":[]}\n'
  elif [[ "$args" == *"--json body"* ]]; then
    printf '## Acceptance Criteria\n- [ ] Works\n'
  else
    printf '{"comments":[]}\n'
  fi
elif [[ "$1 $2" == "pr list" || "$1 $2" == "pr view" ]]; then
  printf '[]\n'
elif [[ "$1" == "api" && "$args" == *"issues?"* ]]; then
  printf '[[{"number":1,"created_at":"2026-01-01T00:00:00Z","author":{"login":"owner"},"labels":[],"body":"## Acceptance Criteria\\n- [ ] Works\\n","comments":[]}]]\n'
elif [[ "$1 $2" == "api graphql" ]]; then
  printf '{"data":{"user":{"projectsV2":{"nodes":[]}},"organization":{"projectsV2":{"nodes":[]}}}}\n'
else
  printf '[]\n'
fi
SH

cat > "$stubs/opencode" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" != "--version" ]]; then
  printf '%s\n' "${GH_TOKEN:-}" > "$OPENCODE_TOKEN_FILE"
fi
exit 0
SH
chmod +x "$stubs"/*

origin="$tmp/origin.git"
seed="$tmp/seed"
worktree="$tmp/runtime"
"$git_bin" init -q --bare "$origin"
"$git_bin" -C "$origin" symbolic-ref HEAD refs/heads/main
"$git_bin" init -q "$seed"
"$git_bin" -C "$seed" config user.email "fixture@example.invalid"
"$git_bin" -C "$seed" config user.name "fixture"
mkdir -p "$seed/.opencode/agents" "$seed/dev-ops/scripts"
printf '# planner\n' > "$seed/.opencode/agents/planner.md"
printf '{}\n' > "$seed/opencode.jsonc"
printf '# rules\n' > "$seed/AGENTS.md"
cp "$SCRIPT_DIR/../check-acceptance-criteria.sh" "$seed/dev-ops/scripts/check-acceptance-criteria.sh"
"$git_bin" -C "$seed" add -A
"$git_bin" -C "$seed" commit -qm fixture
"$git_bin" -C "$seed" branch -M main
"$git_bin" -C "$seed" remote add origin "$origin"
"$git_bin" -C "$seed" push -q origin main
python3 "$SCRIPT_DIR/../../factory/lib/factory.py" guardrail-manifest "$seed" HEAD > "$tmp/guardrail-manifest.json"
"$git_bin" -C "$seed" checkout -q -b factory-guardrail-approved
cp "$tmp/guardrail-manifest.json" "$seed/guardrail-manifest.json"
"$git_bin" -C "$seed" add guardrail-manifest.json
"$git_bin" -C "$seed" commit -qm "guardrail manifest"
"$git_bin" -C "$seed" push -q origin factory-guardrail-approved
"$git_bin" -C "$seed" checkout -q main
"$git_bin" clone -q "$origin" "$worktree"

key="$tmp/app.pem"
printf '%s\n' '-----BEGIN RSA PRIVATE KEY-----' 'fixture' '-----END RSA PRIVATE KEY-----' > "$key"
chmod 600 "$key"

run_tick() {
  env -u GH_TOKEN -u GITHUB_TOKEN \
    HOME="$tmp/home" \
    PATH="$stubs:$PATH" \
    REAL_PYTHON="$real_python" \
    MINT_COUNTER="$mint_counter" \
    FAIL_MINT_AT="${FAIL_MINT_AT:-0}" \
    GH_LOG="$gh_log" \
    OPENCODE_TOKEN_FILE="$opencode_token" \
    FACTORY_WORKTREE="$worktree" \
    FACTORY_CONTAINER_MODE=0 \
    FACTORY_LOG_FILE="$tmp/events.jsonl" \
    FACTORY_METRICS_DIR="$tmp/metrics" \
    FACTORY_SESSION_LOG_DIR="$tmp/sessions" \
    FACTORY_CLAIM_DIR="$tmp/claims" \
    FACTORY_LOGIN="factory-bot" \
    FACTORY_TRUSTED_LOGINS="owner" \
    FACTORY_GITHUB_APP_ID="123" \
    FACTORY_GITHUB_APP_PRIVATE_KEY_FILE="$key" \
    FACTORY_GH_RETRIES=1 \
    FACTORY_SESSION_TIMEOUT=30 \
    FACTORY_PRESERVE_SESSION_LOGS=never \
    FACTORY_LOG_SESSION_OUTPUT=metadata \
    FACTORY_OTLP_TRACES_ENDPOINT="" \
    "$@"
}

if run_tick bash "$TICK" > "$tmp/tick.log" 2>&1; then
  pass "live tick with one planning session succeeds"
else
  fail "live tick failed"
  cat "$tmp/tick.log" >&2
fi
if [[ "$(cat "$opencode_token" 2>/dev/null || true)" == "app-token-2" ]]; then
  pass "agent receives token refreshed in parent shell"
else
  fail "agent did not receive refreshed token"
  cat "$tmp/tick.log" >&2
  cat "$gh_log" >&2
  cat "$tmp/events.jsonl" >&2
fi
[[ "$(cat "$mint_counter")" == 2 ]] \
  && pass "token minted once at startup and once before the session" || fail "unexpected token mint count"
last_gh_token="$(tail -n 1 "$gh_log" | cut -d'|' -f1)"
[[ "$last_gh_token" == "app-token-2" ]] \
  && pass "parent shell keeps refreshed token for later GitHub operations" || fail "parent shell reused stale token"

printf '0\n' > "$mint_counter"
: > "$gh_log"
rm -f "$opencode_token"
rm -rf "$tmp/claims"
set +e
run_tick FAIL_MINT_AT=2 bash "$TICK" > "$tmp/mint-failure.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "session token refresh failure fails the tick" || fail "session token refresh failure accepted"
[[ ! -e "$tmp/claims/plan-1.claim" ]] \
  && pass "session token refresh failure releases the claim" || fail "claim leaked after token refresh failure"
grep -Fq '"failure_reason": "auth"' "$tmp/events.jsonl" \
  && pass "session token refresh failure is recorded" || fail "token refresh failure event missing"

set +e
run_tick FACTORY_WORKTREE="$REPO_ROOT/nested-worktree" bash "$TICK" --dry-run \
  > "$tmp/nested.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "nested factory worktree fails closed" || fail "nested worktree accepted"
grep -Fq 'FACTORY_WORKTREE must be outside the primary checkout' "$tmp/nested.log" \
  && pass "nested worktree reports isolation error" || fail "nested worktree error missing"

blocked="$tmp/not-a-directory"
printf 'blocked\n' > "$blocked"
set +e
run_tick FACTORY_WORKTREE="$blocked" bash "$TICK" --dry-run \
  > "$tmp/blocked.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "uncreatable factory worktree fails closed" || fail "uncreatable worktree accepted"
grep -Fq 'could not create isolated factory worktree' "$tmp/blocked.log" \
  && pass "uncreatable worktree reports isolation error" || fail "worktree creation error missing"

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
