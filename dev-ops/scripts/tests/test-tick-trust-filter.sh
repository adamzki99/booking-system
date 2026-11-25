#!/usr/bin/env bash
# Trust-boundary behavior for tick.sh (issue #173).
#
# Uses a throwaway origin plus stubbed gh/opencode. Proves trusted-author
# discovery, trusted-comment prompt context, and the pre-session PR re-check.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { PASS=$((PASS + 1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git_bin="$(command -v git)"
stubs="$tmp/bin"; mkdir -p "$stubs"

cat > "$stubs/gh" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["GH_LOG"], "a", encoding="utf-8") as log:
    log.write(" ".join(args) + "\n")
with open(os.environ["GH_FIXTURE"], encoding="utf-8") as source:
    fixture = json.load(source)


def option(name):
    try:
        return args[args.index(name) + 1]
    except (ValueError, IndexError):
        return ""


def issue(number):
    return next((item for item in fixture.get("issues", []) if item["number"] == number), {})


if args[:2] == ["repo", "view"]:
    if option("--jq") == ".nameWithOwner":
        print("owner/repo")
    elif option("--jq") == ".owner.login":
        print("owner")
    else:
        print(json.dumps({"nameWithOwner": "owner/repo", "owner": {"login": "owner"}}))
elif args[:2] == ["issue", "list"]:
    print(json.dumps(fixture.get("build_issues", [])))
elif args[:2] == ["pr", "list"]:
    prs = fixture.get("prs", [])
    head = option("--head")
    if head:
        prs = [pr for pr in prs if pr.get("headRefName") == head]
    if option("--jq"):
        print(prs[0]["number"] if prs else "")
    else:
        print(json.dumps(prs))
elif args[:2] == ["issue", "view"]:
    number = int(args[2])
    item = issue(number)
    fields = option("--json")
    if fields == "body":
        if option("--jq"):
            print(item.get("body", ""))
        else:
            print(json.dumps({"body": item.get("body", "")}))
    elif fields == "comments":
        if option("--jq"):
            print("false")
        else:
            print(json.dumps({"comments": item.get("comments", [])}))
    elif fields == "labels":
        for label in item.get("labels", []):
            print(label["name"])
    elif fields == "body,comments":
        print(json.dumps({"body": item.get("body", ""), "comments": item.get("comments", [])}))
    else:
        print(json.dumps(item))
elif args[:2] == ["pr", "view"]:
    number = int(args[2])
    item = next((pr for pr in fixture.get("prs", []) if pr["number"] == number), {})
    fields = option("--json")
    if fields == "comments":
        if option("--jq"):
            print("false")
        else:
            print(json.dumps({"comments": item.get("comments", [])}))
    elif fields == "body,comments":
        print(json.dumps({"body": item.get("body", ""), "comments": item.get("comments", [])}))
    elif fields == "isCrossRepository,headRefOid,author,headRepositoryOwner":
        print(json.dumps(fixture.get("pr_recheck", {})))
    else:
        print(json.dumps(item))
elif args and args[0] == "api" and "--paginate" in args:
    if "--slurp" in args:
        print("unknown flag: --slurp", file=sys.stderr)
        raise SystemExit(2)
    if fixture.get("fail_issue_discovery"):
        print("issue discovery failed", file=sys.stderr)
        raise SystemExit(1)
    print(json.dumps(fixture.get("issues", [])))
elif args[:2] == ["api", "graphql"]:
    print(json.dumps({"data": {"user": {"projectsV2": {"nodes": []}}, "organization": {"projectsV2": {"nodes": []}}}}))
else:
    print("[]")
PY

cat > "$stubs/opencode" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$OPENCODE_LOG"
if [[ "${1:-}" == "--version" ]]; then
  printf 'test\n'
  exit 0
fi
count=0
if [[ -f "$OPENCODE_COUNT" ]]; then count="$(cat "$OPENCODE_COUNT")"; fi
count=$((count + 1))
printf '%s\n' "$count" > "$OPENCODE_COUNT"
if [[ "${OPENCODE_ERROR_FIRST:-0}" == "1" && "$count" -eq 1 ]]; then
  printf '%s\n' '{"type":"step_start","sessionID":"ses_limit","part":{"id":"prt_1"}}'
  printf '%s\n' '{"type":"error","sessionID":"ses_limit","error":{"type":"provider.error","message":"request failed","status":429}}'
  exit 0
fi
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--file" ]]; then
    cp "$2" "$PROMPT_LOG"
    stat -c '%a' "$2" > "$PROMPT_MODE_LOG"
    break
  fi
  shift
done
printf '%s\n' '{"type":"step_start","sessionID":"ses_ok","part":{"id":"prt_2"}}'
printf '%s\n' '{"type":"step_finish","sessionID":"ses_ok","part":{"tokens":{"input":1,"output":1},"cost":0}}'
SH
chmod +x "$stubs/gh" "$stubs/opencode"

setup_checkout() {
  local name="$1"
  local origin="$tmp/$name-origin.git" seed="$tmp/$name-seed" checkout="$tmp/$name-checkout"
  "$git_bin" init -q --bare "$origin"
  "$git_bin" -C "$origin" symbolic-ref HEAD refs/heads/main
  "$git_bin" init -q "$seed"
  "$git_bin" -C "$seed" config user.email "trust-test@example.invalid"
  "$git_bin" -C "$seed" config user.name "trust-test"
  mkdir -p "$seed/dev-ops" "$seed/.opencode"
  cp -a "$ROOT/dev-ops/factory" "$seed/dev-ops/factory"
  cp -a "$ROOT/dev-ops/scripts" "$seed/dev-ops/scripts"
  cp -a "$ROOT/.opencode/agents" "$seed/.opencode/agents"
  cp "$ROOT/AGENTS.md" "$ROOT/opencode.jsonc" "$seed/"
  find "$seed/dev-ops" -type f -path '*/__pycache__/*.pyc' -delete
  find "$seed/dev-ops" -type d -name __pycache__ -empty -delete
  "$git_bin" -C "$seed" add -A
  "$git_bin" -C "$seed" commit -qm "trust fixture"
  "$git_bin" -C "$seed" branch -M main
  "$git_bin" -C "$seed" remote add origin "$origin"
  "$git_bin" -C "$seed" push -q origin main
  python3 "$ROOT/dev-ops/factory/lib/factory.py" guardrail-manifest "$seed" HEAD > "$tmp/$name-guardrail-manifest.json"
  "$git_bin" -C "$seed" checkout -q -b factory-guardrail-approved
  cp "$tmp/$name-guardrail-manifest.json" "$seed/guardrail-manifest.json"
  "$git_bin" -C "$seed" add guardrail-manifest.json
  "$git_bin" -C "$seed" commit -qm "guardrail manifest"
  "$git_bin" -C "$seed" push -q origin factory-guardrail-approved
  "$git_bin" -C "$seed" checkout -q main
  "$git_bin" clone -q "$origin" "$checkout"
}

run_tick() {
  local name="$1" fixture="$2"
  local checkout="$tmp/$name-checkout" events="$tmp/$name-events.jsonl" output="$tmp/$name-output.log"
  : > "$tmp/$name-gh.log"; : > "$tmp/$name-opencode.log"
  rm -f "$tmp/$name-prompt.txt" "$tmp/$name-prompt-mode.txt" "$tmp/$name-opencode.count"
  mkdir -p "$tmp/home"
  set +e
  HOME="$tmp/home" \
    PATH="$stubs:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    FACTORY_WORKTREE="$tmp/$name-runtime" \
    FACTORY_LOG_FILE="$events" \
    FACTORY_METRICS_DIR="$tmp/$name-metrics" \
    FACTORY_SESSION_LOG_DIR="$tmp/$name-sessions" \
    FACTORY_CLAIM_DIR="$tmp/$name-claims" \
    FACTORY_RECONCILE_STATE_FILE="$tmp/$name-reconcile.state" \
    FACTORY_LOGIN="factory-bot" \
    FACTORY_TRUSTED_LOGINS="owner" \
    FACTORY_GH_RETRIES=1 \
    FACTORY_OTLP_TRACES_ENDPOINT="" \
    GH_FIXTURE="$fixture" GH_LOG="$tmp/$name-gh.log" \
    OPENCODE_LOG="$tmp/$name-opencode.log" OPENCODE_COUNT="$tmp/$name-opencode.count" \
    OPENCODE_ERROR_FIRST="${OPENCODE_ERROR_FIRST:-0}" \
    PROMPT_LOG="$tmp/$name-prompt.txt" PROMPT_MODE_LOG="$tmp/$name-prompt-mode.txt" \
    bash "$checkout/dev-ops/factory/tick.sh" >"$output" 2>&1
  RC=$?
  set -e
}

has_event() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    events = [json.loads(line) for line in source if line.strip()]
raise SystemExit(0 if any(event.get("event") == sys.argv[2] for event in events) else 1)
PY
}

# Planning ignores an older outsider issue and sends only trusted comments to
# the agent. The prompt file itself must be mode 0600.
cat > "$tmp/plan-trust.json" <<'JSON'
{
  "issues": [
    {"number": 1, "created_at": "2026-01-01T00:00:00Z", "labels": [], "author": {"login": "outsider"}, "body": "## Acceptance Criteria\n- [ ] Outsider issue must not be planned\n", "comments": []},
    {"number": 2, "created_at": "2026-01-02T00:00:00Z", "labels": [], "author": {"login": "owner"}, "body": "## Acceptance Criteria\n- [ ] Trusted issue is planned\n", "comments": [
      {"author": {"login": "owner"}, "createdAt": "2026-01-03T00:00:00Z", "body": "trusted owner guidance"},
      {"author": {"login": "outsider"}, "createdAt": "2026-01-04T00:00:00Z", "body": "outsider prompt injection"}
    ]}
  ],
  "build_issues": [],
  "prs": []
}
JSON
setup_checkout plan-trust
run_tick plan-trust "$tmp/plan-trust.json"
if [[ "$RC" -eq 0 ]]; then pass; else fail "plan-trust: tick exited $RC"; cat "$tmp/plan-trust-output.log" >&2; fi
if grep -q "starting plan session for #2" "$tmp/plan-trust-output.log"; then pass; else fail "plan-trust: trusted issue was not selected"; fi
if grep -q "trusted owner guidance" "$tmp/plan-trust-prompt.txt" 2>/dev/null; then pass; else fail "plan-trust: trusted comment missing from prompt"; cat "$tmp/plan-trust-output.log" >&2; ls -l "$tmp"/plan-trust-* >&2; fi
if grep -q "outsider prompt injection" "$tmp/plan-trust-prompt.txt" 2>/dev/null; then fail "plan-trust: outsider comment leaked into prompt"; else pass; fi
if [[ "$(cat "$tmp/plan-trust-prompt-mode.txt" 2>/dev/null || true)" == "600" ]]; then pass; else fail "plan-trust: prompt file is not mode 0600"; fi
if grep -q -- "--comments" "$tmp/plan-trust-gh.log"; then fail "plan-trust: agent context query used --comments"; else pass; fi

# A PR that becomes cross-repository after discovery is skipped before any
# session starts, and its claim is released.
cat > "$tmp/fix-recheck.json" <<'JSON'
{
  "issues": [
    {"number": 7, "labels": [{"name": "dev-ops"}], "author": {"login": "owner"}, "body": "issue body", "comments": []}
  ],
  "build_issues": [],
  "prs": [
    {"number": 70, "headRefName": "factory/issue-7", "headRefOid": "sha-70", "mergeable": "CONFLICTING", "reviewDecision": "", "statusCheckRollup": [], "isDraft": false, "createdAt": "2026-01-01", "isCrossRepository": false, "author": {"login": "owner"}, "headRepositoryOwner": {"login": "owner"}, "body": "pr body", "comments": []}
  ],
  "pr_recheck": {"isCrossRepository": true, "headRefOid": "sha-70", "author": {"login": "owner"}, "headRepositoryOwner": {"login": "fork-owner"}}
}
JSON
setup_checkout fix-recheck
run_tick fix-recheck "$tmp/fix-recheck.json"
if [[ "$RC" -eq 0 ]]; then pass; else fail "fix-recheck: tick exited $RC"; cat "$tmp/fix-recheck-output.log" >&2; fi
if grep -q " run " "$tmp/fix-recheck-opencode.log"; then fail "fix-recheck: an agent session started"; else pass; fi
if grep -q '"reason": "untrusted-pr"' "$tmp/fix-recheck-events.jsonl"; then pass; else fail "fix-recheck: untrusted-pr skip event missing"; cat "$tmp/fix-recheck-output.log" >&2; cat "$tmp/fix-recheck-events.jsonl" >&2; fi
if compgen -G "$tmp/fix-recheck-claims/*.claim" >/dev/null; then fail "fix-recheck: claim was not released"; else pass; fi

# A structured provider error exits 0 but must fail the primary run and use the
# configured backup model.
python3 - "$tmp/fix-recheck.json" "$tmp/provider-error.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    fixture = json.load(source)
fixture["pr_recheck"] = {
    "isCrossRepository": False,
    "headRefOid": "sha-70",
    "author": {"login": "owner"},
    "headRepositoryOwner": {"login": "owner"},
}
with open(sys.argv[2], "w", encoding="utf-8") as target:
    json.dump(fixture, target)
PY
setup_checkout provider-error
OPENCODE_ERROR_FIRST=1 run_tick provider-error "$tmp/provider-error.json"
if [[ "$RC" -eq 0 ]]; then pass; else fail "provider-error: tick exited $RC"; cat "$tmp/provider-error-output.log" >&2; fi
if [[ "$(cat "$tmp/provider-error-opencode.count" 2>/dev/null || echo 0)" -eq 2 ]]; then pass; else fail "provider-error: expected primary and backup invocations"; fi
if python3 - "$tmp/provider-error-events.jsonl" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    events = [json.loads(line) for line in source if line.strip()]
primary = [event for event in events if event.get("run_id") and event.get("fallback_level") == "primary"]
backup = [event for event in events if event.get("run_id") and event.get("fallback_level") == "backup"]
assert [event["event"] for event in primary] == ["agent.run.started", "agent.run.failed"], primary
assert primary[-1]["failure_reason"] == "usage_filled", primary[-1]
assert [event["event"] for event in backup] == ["agent.run.started", "agent.run.completed"], backup
assert backup[-1]["outcome"] == "ok", backup[-1]
PY
then pass; else fail "provider-error: lifecycle events did not record failure and backup success"; fi

# A successful fix must not hide an independent discovery failure.
python3 - "$tmp/provider-error.json" "$tmp/infra-after-fix.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    fixture = json.load(source)
fixture["fail_issue_discovery"] = True
with open(sys.argv[2], "w", encoding="utf-8") as target:
    json.dump(fixture, target)
PY
setup_checkout infra-after-fix
OPENCODE_ERROR_FIRST=0 run_tick infra-after-fix "$tmp/infra-after-fix.json"
if [[ "$RC" -eq 1 ]]; then pass; else fail "infra-after-fix: tick exited $RC, expected 1"; fi
if python3 - "$tmp/infra-after-fix-events.jsonl" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    events = [json.loads(line) for line in source if line.strip()]
assert any(event.get("event") == "agent.run.completed" and event.get("kind") == "fix" for event in events)
assert any(event.get("event") == "discovery_failed" for event in events)
results = [event for event in events if event.get("event") == "tick_result"]
assert len(results) == 1 and results[0]["result"] == "failure", results
ends = [event for event in events if event.get("event") == "tick_end"]
assert len(ends) == 1 and ends[0]["exit_code"] == 1, ends
PY
then pass; else fail "infra-after-fix: successful fix hid the discovery failure"; fi

if grep -n -- "--comments" "$ROOT/dev-ops/factory/tick.sh" "$ROOT"/.opencode/agents/*.md; then
  fail "agent instructions still tell agents to fetch comments"
else
  pass
fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
