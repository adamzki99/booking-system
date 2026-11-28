#!/usr/bin/env bash
# Issue #178: sandbox is the default, missing runtime fails closed, and the
# sandbox mounts only the worktree, a disposable home, a read-only OpenCode
# config, and a masked Docker socket. Sessions get egress through an allowlist.
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
mkdir -p "$stubs" "$tmp/home/.config/opencode" "$tmp/home/.opencode/bin"
printf '{"model":"fixture"}\n' > "$tmp/home/.config/opencode/opencode.jsonc"
opencode_log="$tmp/opencode.log"
bwrap_log="$tmp/bwrap.log"
: > "$opencode_log"; : > "$bwrap_log"

cat > "$stubs/gh" <<'SH'
#!/usr/bin/env bash
args="$*"
if [[ "$1 $2" == "repo view" ]]; then
  printf 'owner/repo\n'
elif [[ "$1" == "api" && "$args" == *"issues?"* ]]; then
  printf '[[{"number":1,"created_at":"2026-01-01T00:00:00Z","author":{"login":"owner"},"labels":[],"body":"## Acceptance Criteria\\n- [ ] Works\\n","comments":[]}]]\n'
elif [[ "$1 $2" == "issue view" ]]; then
  if [[ "$args" == *"body,comments"* ]]; then
    printf '{"body":"## Acceptance Criteria\\n- [ ] Works\\n","comments":[]}\n'
  elif [[ "$args" == *"--json body"* ]]; then
    printf '## Acceptance Criteria\n- [ ] Works\n'
  else
    printf '{"comments":[]}\n'
  fi
else
  printf '[]\n'
fi
SH

cat > "$stubs/opencode" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" != "--version" ]]; then
  printf 'token=%s proxy=%s\n' "${GH_TOKEN:-}" "${HTTPS_PROXY:-}" >> "$OPENCODE_LOG"
fi
exit 0
SH

# Stub sandbox runtime: log the arguments it received, then run the agent.
cat > "$stubs/fake-bwrap" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BWRAP_LOG"
while [[ $# -gt 0 && "$1" != opencode ]]; do shift; done
shift || true
exec opencode "$@"
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

run_tick() {
  env -u GH_TOKEN -u GITHUB_TOKEN \
    -u FACTORY_GITHUB_APP_ID -u FACTORY_GITHUB_APP_PRIVATE_KEY_FILE \
    -u FACTORY_GITHUB_APP_PRIVATE_KEY -u FACTORY_GITHUB_INSTALLATION_ID \
    GH_TOKEN="fixture-installation-token" GITHUB_TOKEN="fixture-installation-token" \
    HOME="$tmp/home" \
    PATH="$stubs:$PATH" \
    REAL_PYTHON="$real_python" \
    OPENCODE_LOG="$opencode_log" \
    BWRAP_LOG="$bwrap_log" \
    FACTORY_WORKTREE="$worktree" \
    FACTORY_CONTAINER_MODE=1 \
    FACTORY_OPENCODE_CONFIG_DIR="$tmp/home/.config/opencode" \
    FACTORY_LOG_FILE="$1" \
    FACTORY_METRICS_DIR="$tmp/metrics" \
    FACTORY_SESSION_LOG_DIR="$tmp/sessions" \
    FACTORY_CLAIM_DIR="$tmp/claims" \
    FACTORY_LOGIN="factory-bot" \
    FACTORY_TRUSTED_LOGINS="owner" \
    FACTORY_GH_RETRIES=1 \
    FACTORY_SESSION_TIMEOUT=30 \
    FACTORY_PRESERVE_SESSION_LOGS=never \
    FACTORY_LOG_SESSION_OUTPUT=metadata \
    FACTORY_OTLP_TRACES_ENDPOINT="" \
    "${@:2}"
}

# 1. Default must be sandbox mode.
grep -Fq 'FACTORY_CONTAINER_MODE="${FACTORY_CONTAINER_MODE:-1}"' "$TICK" \
  && pass "FACTORY_CONTAINER_MODE defaults to 1" || fail "sandbox is not the default"

# 2. Missing runtime: non-zero exit, sandbox_unavailable event, no session.
events="$tmp/missing-events.jsonl"; : > "$events"
set +e
run_tick "$events" FACTORY_SANDBOX_RUNTIME=definitely-missing-bwrap bash "$TICK" \
  > "$tmp/missing.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] \
  && pass "missing sandbox runtime fails the tick" || fail "missing runtime accepted"
grep -Fq '"event": "sandbox_unavailable"' "$events" \
  && pass "sandbox_unavailable event emitted" || fail "sandbox_unavailable event missing"
grep -Fq '"reason": "runtime-missing"' "$events" \
  && pass "sandbox_unavailable reason is runtime-missing" || fail "missing reason"
[[ ! -s "$opencode_log" ]] \
  && pass "no session started when sandbox is unavailable" || fail "session started without sandbox"

# 3. Sandbox construction: no host home, masked socket, read-only config,
#    disposable tmpfs home, and egress proxy injected into the session.
events="$tmp/sandbox-events.jsonl"; : > "$events"
if run_tick "$events" FACTORY_SANDBOX_RUNTIME=fake-bwrap bash "$TICK" \
  > "$tmp/sandbox.log" 2>&1; then
  pass "sandboxed tick completes"
else
  fail "sandboxed tick failed"
  cat "$tmp/sandbox.log" >&2
fi
args="$(cat "$bwrap_log")"
[[ "$args" != *"--bind $tmp/home $tmp/home"* ]] \
  && pass "host HOME is not bound into the sandbox" || fail "host HOME leaked into sandbox"
grep -Fq -- '--ro-bind /dev/null /run/docker.sock' "$bwrap_log" \
  && pass "Docker socket is masked" || fail "Docker socket not masked"
grep -Fq -- '--tmpfs /tmp' "$bwrap_log" \
  && pass "disposable tmpfs mounted" || fail "no disposable tmpfs"
grep -Fq -- '--setenv HOME /tmp/factory-sandbox-home' "$bwrap_log" \
  && pass "sandbox HOME is disposable" || fail "sandbox HOME not isolated"
grep -Fq -- "--ro-bind $tmp/home/.config/opencode /tmp/factory-sandbox-home/.config/opencode" "$bwrap_log" \
  && pass "OpenCode config mounted read-only" || fail "read-only OpenCode config bind missing"
grep -Fq '"reason": "sandbox"' "$events" \
  && pass "container_mode=sandbox event emitted" || fail "sandbox mode event missing"
grep -Eq 'proxy=http://127\.0\.0\.1:[0-9]+' "$opencode_log" \
  && pass "allowlist proxy injected into session" || fail "egress proxy not injected"
grep -Eq 'token=[^[:space:]]+' "$opencode_log" \
  && pass "token passed into session environment" || fail "token missing from session"

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
