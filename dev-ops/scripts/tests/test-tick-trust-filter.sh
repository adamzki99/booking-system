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
    issues = fixture.get("issues", [])
    pages = [issues[index:index + 100] for index in range(0, len(issues), 100)]
    print(json.dumps(pages))
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
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--file" ]]; then
    cp "$2" "$PROMPT_LOG"
    stat -c '%a' "$2" > "$PROMPT_MODE_LOG"
    break
  fi
  shift
done
exit 0
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
  "$git_bin" -C "$seed" tag factory-config
  "$git_bin" -C "$seed" push -q origin factory-config
  "$git_bin" clone -q "$origin" "$checkout"
}

run_tick() {
  local name="$1" fixture="$2"
  local checkout="$tmp/$name-checkout" events="$tmp/$name-events.jsonl" output="$tmp/$name-output.log"
  : > "$tmp/$name-gh.log"; : > "$tmp/$name-opencode.log"
  rm -f "$tmp/$name-prompt.txt" "$tmp/$name-prompt-mode.txt"
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
    OPENCODE_LOG="$tmp/$name-opencode.log" \
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

if grep -n -- "--comments" "$ROOT/dev-ops/factory/tick.sh" "$ROOT"/.opencode/agents/*.md; then
  fail "agent instructions still tell agents to fetch comments"
else
  pass
fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
