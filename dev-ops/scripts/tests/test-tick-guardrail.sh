#!/usr/bin/env bash
# Guardrail attestation gate for tick.sh (FAC-05).
#
# Verifies that tick.sh refuses to start any session when the agent/config
# guardrail files in origin/main do not match the owner-approved manifest on
# factory-guardrail-approved, and that it fails closed when the approved ref or
# manifest is missing/unreadable. Uses a throwaway bare origin plus a checkout
# and stubs so no network, gh or opencode is required.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
TICK="$SCRIPT_DIR/../../factory/tick.sh"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." >/dev/null && pwd)"
FACTORY_PY="$ROOT/dev-ops/factory/lib/factory.py"
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

# Build a bare origin with guardrail files. When with_manifest=1 the approved
# manifest branch is created from the current baseline; when with_drift=1
# opencode.jsonc is then changed on main so origin/main drifts from the
# approved manifest.
setup_origin() {
  local origin="$1" seed="$2" with_manifest="$3" with_drift="$4"
  "$git_bin" init -q --bare "$origin"
  "$git_bin" -C "$origin" symbolic-ref HEAD refs/heads/main
  "$git_bin" init -q "$seed"
  "$git_bin" -C "$seed" config user.email "guardrail-test@example.invalid"
  "$git_bin" -C "$seed" config user.name "guardrail-test"
  mkdir -p "$seed/.opencode/agents" "$seed/.opencode/commands" "$seed/.opencode/skills/demo"
  printf '# builder\n' > "$seed/.opencode/agents/builder.md"
  printf '# lint\n' > "$seed/.opencode/commands/lint.md"
  printf '# skill\n' > "$seed/.opencode/skills/demo/SKILL.md"
  printf '{"approved": true}\n' > "$seed/opencode.jsonc"
  printf '# repo rules\n' > "$seed/AGENTS.md"
  "$git_bin" -C "$seed" add -A
  "$git_bin" -C "$seed" commit -qm "guardrail baseline"
  "$git_bin" -C "$seed" branch -M main
  "$git_bin" -C "$seed" remote add origin "$origin"
  "$git_bin" -C "$seed" push -q origin main
  if [[ "$with_manifest" == 1 ]]; then
    python3 "$FACTORY_PY" guardrail-manifest "$seed" HEAD > "$seed.manifest.json"
    "$git_bin" -C "$seed" checkout -q -b factory-guardrail-approved
    cp "$seed.manifest.json" "$seed/guardrail-manifest.json"
    "$git_bin" -C "$seed" add guardrail-manifest.json
    "$git_bin" -C "$seed" commit -qm "approved guardrail manifest"
    "$git_bin" -C "$seed" push -q origin factory-guardrail-approved
    "$git_bin" -C "$seed" checkout -q main
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
event_has() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, sys
path, event, key, value = sys.argv[1:]
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if obj.get("event") == event and str(obj.get(key, "")) == value:
            raise SystemExit(0)
raise SystemExit(1)
PY
}
session_started() { grep -q " run " "$1"; }

# A: drift from approved manifest emits guardrail_drift, exits non-zero, no session.
setup_origin "$tmp/origin-drift.git" "$tmp/seed-drift" 1 1
run_tick "$tmp/origin-drift.git" "$tmp/wt-drift" "$tmp/events-drift.jsonl"
[[ "$RC" -ne 0 ]] && pass || fail "drift: expected non-zero exit, got $RC"
has_event "$tmp/events-drift.jsonl" guardrail_drift && pass || fail "drift: guardrail_drift event missing"
event_has "$tmp/events-drift.jsonl" guardrail_drift reason manifest_mismatch && pass || fail "drift: expected reason=manifest_mismatch"
if session_started "$opencode_log"; then fail "drift: a session was started"; else pass; fi
if has_event "$tmp/events-drift.jsonl" session_start; then fail "drift: session_start event present"; else pass; fi

# B: no drift must not trip the gate (tick completes its normal empty run).
setup_origin "$tmp/origin-ok.git" "$tmp/seed-ok" 1 0
run_tick "$tmp/origin-ok.git" "$tmp/wt-ok" "$tmp/events-ok.jsonl"
[[ "$RC" -eq 0 ]] && pass || fail "no-drift: expected zero exit, got $RC"
has_event "$tmp/events-ok.jsonl" guardrail_ok && pass || fail "no-drift: guardrail_ok event missing"
if has_event "$tmp/events-ok.jsonl" guardrail_drift; then fail "no-drift: false guardrail_drift"; else pass; fi

# C: missing approved ref fails closed with guardrail_drift and no session.
setup_origin "$tmp/origin-noref.git" "$tmp/seed-noref" 0 0
run_tick "$tmp/origin-noref.git" "$tmp/wt-noref" "$tmp/events-noref.jsonl"
[[ "$RC" -ne 0 ]] && pass || fail "no-ref: expected non-zero exit, got $RC"
has_event "$tmp/events-noref.jsonl" guardrail_drift && pass || fail "no-ref: guardrail_drift event missing"
event_has "$tmp/events-noref.jsonl" guardrail_drift reason approved_ref_fetch_failed && pass || fail "no-ref: expected reason=approved_ref_fetch_failed"
if session_started "$opencode_log"; then fail "no-ref: a session was started"; else pass; fi

# D: approved ref exists but manifest file is missing - fail closed.
setup_origin "$tmp/origin-nomanifest.git" "$tmp/seed-nomanifest" 0 0
"$git_bin" -C "$tmp/seed-nomanifest" checkout -q -b factory-guardrail-approved
printf 'not manifest\n' > "$tmp/seed-nomanifest/README.txt"
"$git_bin" -C "$tmp/seed-nomanifest" add README.txt
"$git_bin" -C "$tmp/seed-nomanifest" commit -qm "approved branch without manifest"
"$git_bin" -C "$tmp/seed-nomanifest" push -q origin factory-guardrail-approved
"$git_bin" -C "$tmp/seed-nomanifest" checkout -q main
run_tick "$tmp/origin-nomanifest.git" "$tmp/wt-nomanifest" "$tmp/events-nomanifest.jsonl"
[[ "$RC" -ne 0 ]] && pass || fail "no-manifest: expected non-zero exit, got $RC"
event_has "$tmp/events-nomanifest.jsonl" guardrail_drift reason manifest_missing && pass || fail "no-manifest: expected reason=manifest_missing"
if session_started "$opencode_log"; then fail "no-manifest: a session was started"; else pass; fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
