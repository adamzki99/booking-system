#!/usr/bin/env bash
# Guardrail-drift gate for tick.sh (issue #164 / FAC-05).
#
# Verifies that tick.sh refuses to start any session when the agent/config
# guardrail files in origin/main differ from the owner-moved factory-config
# tag, and that it fails closed when the tag is missing. Uses a throwaway bare
# origin plus a checkout and stubs so no network, gh or opencode is required.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
TICK="$SCRIPT_DIR/../../factory/tick.sh"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }
pass() { PASS=$((PASS+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git_bin="$(command -v git)"

# Stubs: record every invocation so the test can prove no session started.
stubs="$tmp/bin"; mkdir -p "$stubs"
gh_log="$tmp/gh.log"; opencode_log="$tmp/opencode.log"
: > "$gh_log"; : > "$opencode_log"
cat > "$stubs/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case " $* " in
  *" issue list "*) printf '[]\n' ;;
  *" pr list "*)    printf '[]\n' ;;
  *)                printf '[]\n' ;;
esac
exit 0
EOF
cat > "$stubs/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$OPENCODE_LOG"
if [[ "${1:-}" == "--version" ]]; then printf 'test\n'; fi
exit 0
EOF
chmod +x "$stubs/gh" "$stubs/opencode"

# Build a bare origin with guardrail files. When with_tag=1 the approved
# snapshot is tagged factory-config; when with_drift=1 opencode.jsonc is then
# changed on main so origin/main drifts from the tag.
setup_origin() {
  local origin="$1" seed="$2" with_tag="$3" with_drift="$4"
  "$git_bin" init -q --bare "$origin"
  "$git_bin" -C "$origin" symbolic-ref HEAD refs/heads/main
  "$git_bin" init -q "$seed"
  "$git_bin" -C "$seed" config user.email "guardrail-test@example.invalid"
  "$git_bin" -C "$seed" config user.name "guardrail-test"
  mkdir -p "$seed/.opencode/agents"
  printf '# builder\n' > "$seed/.opencode/agents/builder.md"
  printf '{"approved": true}\n' > "$seed/opencode.jsonc"
  printf '# repo rules\n' > "$seed/AGENTS.md"
  "$git_bin" -C "$seed" add -A
  "$git_bin" -C "$seed" commit -qm "guardrail baseline"
  "$git_bin" -C "$seed" branch -M main
  "$git_bin" -C "$seed" remote add origin "$origin"
  "$git_bin" -C "$seed" push -q origin main
  if [[ "$with_tag" == 1 ]]; then
    "$git_bin" -C "$seed" tag factory-config
    "$git_bin" -C "$seed" push -q origin factory-config
  fi
  if [[ "$with_drift" == 1 ]]; then
    printf '{"approved": false}\n' > "$seed/opencode.jsonc"
    "$git_bin" -C "$seed" commit -qam "drift opencode.jsonc"
    "$git_bin" -C "$seed" push -q origin main
  fi
}

# Run tick.sh against a checkout of origin and return its exit code via RC.
run_tick() {
  local origin="$1" worktree="$2" log="$3"
  : > "$log"; : > "$gh_log"; : > "$opencode_log"
  "$git_bin" clone -q "$origin" "$worktree"
  set +e
  PATH="$stubs:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    FACTORY_WORKTREE="$worktree" \
    FACTORY_LOG_FILE="$log" \
    GH_LOG="$gh_log" OPENCODE_LOG="$opencode_log" \
    bash "$TICK" >/dev/null 2>&1
  RC=$?
  set -e
}

has_event() { grep -q "\"$2\"" "$1"; }
session_started() { grep -q " run " "$1"; }

# A: drift from the tag emits guardrail_drift, exits non-zero, starts no session.
setup_origin "$tmp/origin-drift.git" "$tmp/seed-drift" 1 1
run_tick "$tmp/origin-drift.git" "$tmp/wt-drift" "$tmp/events-drift.jsonl"
[[ "$RC" -ne 0 ]] && pass || fail "drift: expected non-zero exit, got $RC"
has_event "$tmp/events-drift.jsonl" guardrail_drift && pass || fail "drift: guardrail_drift event missing"
if session_started "$opencode_log"; then fail "drift: a session was started"; else pass; fi
if has_event "$tmp/events-drift.jsonl" session_start; then fail "drift: session_start event present"; else pass; fi

# B: no drift must not trip the gate (tick completes its normal empty run).
setup_origin "$tmp/origin-ok.git" "$tmp/seed-ok" 1 0
run_tick "$tmp/origin-ok.git" "$tmp/wt-ok" "$tmp/events-ok.jsonl"
[[ "$RC" -eq 0 ]] && pass || fail "no-drift: expected zero exit, got $RC"
if has_event "$tmp/events-ok.jsonl" guardrail_drift; then fail "no-drift: false guardrail_drift"; else pass; fi

# C: missing tag fails closed with guardrail_drift and no session.
setup_origin "$tmp/origin-notag.git" "$tmp/seed-notag" 0 0
run_tick "$tmp/origin-notag.git" "$tmp/wt-notag" "$tmp/events-notag.jsonl"
[[ "$RC" -ne 0 ]] && pass || fail "no-tag: expected non-zero exit, got $RC"
has_event "$tmp/events-notag.jsonl" guardrail_drift && pass || fail "no-tag: guardrail_drift event missing"
if session_started "$opencode_log"; then fail "no-tag: a session was started"; else pass; fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
