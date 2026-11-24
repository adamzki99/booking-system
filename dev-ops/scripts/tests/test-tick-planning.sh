#!/usr/bin/env bash
# Planning queue behavior for tick.sh.
#
# Uses a throwaway origin plus stubbed gh so candidate selection can be tested
# through the public --dry-run interface without network access or live issues.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
TICK="$SCRIPT_DIR/../../factory/tick.sh"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { PASS=$((PASS + 1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git_bin="$(command -v git)"
stubs="$tmp/bin"; mkdir -p "$stubs"
gh_log="$tmp/gh.log"; opencode_log="$tmp/opencode.log"
: > "$gh_log"; : > "$opencode_log"

cat > "$stubs/gh" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["GH_LOG"], "a", encoding="utf-8") as log:
    log.write(" ".join(args) + "\n")
with open(os.environ["GH_FIXTURE"], encoding="utf-8") as fixture_file:
    fixture = json.load(fixture_file)


def option(name):
    try:
        return args[args.index(name) + 1]
    except (ValueError, IndexError):
        return ""


def issue(number):
    return next((item for item in fixture.get("issues", []) if item["number"] == number), {})


def trusted_fixture_items(items):
    for item in items:
        if isinstance(item, dict):
            item.setdefault("author", {"login": "owner"})
    return items


if args[:2] == ["repo", "view"]:
    if option("--jq") == ".nameWithOwner":
        print("owner/repo")
    else:
        print(json.dumps({"nameWithOwner": "owner/repo", "owner": {"login": "owner"}}))
elif args[:2] == ["issue", "list"]:
    if not option("--label") and fixture.get("fail_issue_discovery"):
        print("issue discovery failed", file=sys.stderr)
        raise SystemExit(1)
    items = fixture.get("build_issues", []) if option("--label") else fixture.get("issues", [])
    items = trusted_fixture_items(items)
    limit = int(option("--limit") or 0)
    print(json.dumps(items[:limit] if limit else items))
elif args[:2] == ["issue", "view"]:
    number = int(args[2])
    item = issue(number)
    fields = option("--json")
    jq = option("--jq")
    if fields == "comments":
        if not jq and number in fixture.get("fail_comment_issues", []):
            print("comment query failed", file=sys.stderr)
            raise SystemExit(1)
        if jq:
            marker = "<!-- factory:plan -->" if "factory:plan" in jq else "<!-- factory:build -->"
            print("true" if any(marker in (comment.get("body") or "") for comment in item.get("comments", [])) else "false")
        else:
            print(json.dumps({"comments": item.get("comments", [])}))
    elif fields == "labels":
        for label in item.get("labels", []):
            print(label["name"])
    elif fields == "body":
        if number in fixture.get("fail_body_issues", []):
            print("body query failed", file=sys.stderr)
            raise SystemExit(1)
        print(item.get("body", ""))
    else:
        print(json.dumps(item))
elif args[:2] == ["pr", "list"]:
    head = option("--head")
    prs = fixture.get("prs", [])
    if head:
        prs = [pr for pr in prs if pr.get("headRefName") == head]
        if option("--jq"):
            print(prs[0]["number"] if prs else "")
        else:
            print(json.dumps(prs))
    else:
        print(json.dumps(prs))
elif args[:2] == ["pr", "view"]:
    print(json.dumps({"comments": []}))
elif args[:2] == ["label", "list"]:
    print(json.dumps([{"name": "owner approved"}, {"name": "plan-task"}]))
elif args[:2] == ["api", "graphql"]:
    print(json.dumps({"data": {"user": {"projectsV2": {"nodes": []}}, "organization": {"projectsV2": {"nodes": []}}}}))
elif args and args[0] == "api" and any("issues?" in arg for arg in args):
    if "--slurp" in args:
        print("unknown flag: --slurp", file=sys.stderr)
        raise SystemExit(2)
    if fixture.get("fail_issue_discovery"):
        print("issue discovery failed", file=sys.stderr)
        raise SystemExit(1)
    issues = trusted_fixture_items(fixture.get("issues", []))
    if fixture.get("concatenated_issue_pages"):
        pages = [issues[index:index + 100] for index in range(0, len(issues), 100)]
        sys.stdout.write("".join(json.dumps(page) for page in pages))
    else:
        print(json.dumps(issues))
else:
    print("[]")
PY

cat > "$stubs/opencode" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$OPENCODE_LOG"
if [[ "${1:-}" == "--version" ]]; then printf 'test\n'; fi
exit 0
SH
chmod +x "$stubs/gh" "$stubs/opencode"

setup_origin() {
  local origin="$1" seed="$2"
  "$git_bin" init -q --bare "$origin"
  "$git_bin" -C "$origin" symbolic-ref HEAD refs/heads/main
  "$git_bin" init -q "$seed"
  "$git_bin" -C "$seed" config user.email "planning-test@example.invalid"
  "$git_bin" -C "$seed" config user.name "planning-test"
  mkdir -p "$seed/.opencode/agents" "$seed/dev-ops/scripts"
  printf '# builder\n' > "$seed/.opencode/agents/builder.md"
  printf '{"approved": true}\n' > "$seed/opencode.jsonc"
  printf '# repo rules\n' > "$seed/AGENTS.md"
  cp "$SCRIPT_DIR/../check-acceptance-criteria.sh" "$seed/dev-ops/scripts/check-acceptance-criteria.sh"
  "$git_bin" -C "$seed" add -A
  "$git_bin" -C "$seed" commit -qm "planning fixture"
  "$git_bin" -C "$seed" branch -M main
  "$git_bin" -C "$seed" remote add origin "$origin"
  "$git_bin" -C "$seed" push -q origin main
  python3 "$SCRIPT_DIR/../../factory/lib/factory.py" guardrail-manifest "$seed" HEAD > "$seed.guardrail-manifest.json"
  "$git_bin" -C "$seed" checkout -q -b factory-guardrail-approved
  cp "$seed.guardrail-manifest.json" "$seed/guardrail-manifest.json"
  "$git_bin" -C "$seed" add guardrail-manifest.json
  "$git_bin" -C "$seed" commit -qm "guardrail manifest"
  "$git_bin" -C "$seed" push -q origin factory-guardrail-approved
  "$git_bin" -C "$seed" checkout -q main
}

run_tick() {
  local name="$1" fixture="$2" expected_rc="${3:-0}"
  local origin="$tmp/$name-origin.git" seed="$tmp/$name-seed" worktree="$tmp/$name-worktree"
  local events="$tmp/$name-events.jsonl" output="$tmp/$name-output.log"
  setup_origin "$origin" "$seed"
  "$git_bin" clone -q "$origin" "$worktree"
  : > "$gh_log"; : > "$opencode_log"
  set +e
  PATH="$stubs:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    FACTORY_WORKTREE="$worktree" \
    FACTORY_LOG_FILE="$events" \
    FACTORY_METRICS_DIR="$tmp/$name-metrics" \
    FACTORY_SESSION_LOG_DIR="$tmp/$name-sessions" \
    FACTORY_CLAIM_DIR="$tmp/$name-claims" \
    FACTORY_LOGIN="factory-bot" \
    FACTORY_TRUSTED_LOGINS="owner" \
    FACTORY_GH_RETRIES=1 \
    FACTORY_OTLP_TRACES_ENDPOINT="" \
    GH_FIXTURE="$fixture" GH_LOG="$gh_log" OPENCODE_LOG="$opencode_log" \
    bash "$TICK" --dry-run >"$output" 2>&1
  RC=$?
  set -e
  if [[ "$RC" -ne "$expected_rc" ]]; then
    fail "$name: tick exited $RC, expected $expected_rc"
    cat "$output" >&2
    return 1
  fi
  return 0
}

assert_actions() {
  local name="$1" events="$2" expected_plans="$3" expected_builds="$4"
  if python3 - "$events" "$expected_plans" "$expected_builds" <<'PY'
import json
import sys

events_path, expected_plans, expected_builds = sys.argv[1:]
with open(events_path, encoding="utf-8") as events_file:
    events = [json.loads(line) for line in events_file if line.strip()]
plans = [int(event["issue"]) for event in events if event.get("event") == "dry_run" and event.get("kind") == "plan"]
builds = [int(event["issue"]) for event in events if event.get("event") == "dry_run" and event.get("kind") == "build"]
expected_plans = [int(value) for value in expected_plans.split(",") if value]
expected_builds = [int(value) for value in expected_builds.split(",") if value]
assert plans == expected_plans, f"plans={plans}, expected={expected_plans}"
assert builds == expected_builds, f"builds={builds}, expected={expected_builds}"
PY
  then
    pass
  else
    fail "$name: wrong dry-run actions"
  fi
}

assert_event() {
  local name="$1" events="$2" event="$3"
  if grep -q "\"event\": \"$event\"" "$events"; then
    pass
  else
    fail "$name: missing $event event"
  fi
}

assert_no_event() {
  local name="$1" events="$2" event="$3"
  if grep -q "\"event\": \"$event\"" "$events"; then
    fail "$name: unexpected $event event"
  else
    pass
  fi
}

assert_metrics_modes() {
  local name="$1" dir="$2"
  if [[ "$(stat -c '%a' "$dir" 2>/dev/null || true)" == "755" ]]; then
    pass
  else
    fail "$name: metrics directory is not mode 755"
  fi
  if [[ "$(stat -c '%a' "$dir/factory_tick.prom" 2>/dev/null || true)" == "644" ]]; then
    pass
  else
    fail "$name: metrics file is not mode 644"
  fi
}

cat > "$tmp/non-bot-marker.json" <<'JSON'
{
  "issues": [
    {"number": 2, "created_at": "2026-01-01T00:00:00Z", "labels": [], "body": "## Acceptance Criteria\n- [ ] Second issue\n", "comments": []},
    {"number": 1, "created_at": "2026-01-02T00:00:00Z", "labels": [], "body": "## Acceptance Criteria\n- [ ] First issue\n", "comments": [{"author": {"login": "owner"}, "body": "<!-- factory:plan -->"}]}
  ],
  "build_issues": [],
  "prs": []
}
JSON
if run_tick non-bot-marker "$tmp/non-bot-marker.json"; then
  assert_actions non-bot-marker "$tmp/non-bot-marker-events.jsonl" "2,1" ""
fi

cat > "$tmp/head-of-line.json" <<'JSON'
{
  "issues": [
    {"number": 1, "createdAt": "2026-01-01", "labels": [], "body": "## Acceptance Criteria\n- [ ] Already planned\n", "comments": [{"author": {"login": "factory-bot"}, "body": "<!-- factory:plan -->"}]},
    {"number": 2, "createdAt": "2026-01-02", "labels": [], "body": "No acceptance criteria yet", "comments": []},
    {"number": 3, "createdAt": "2026-01-03", "labels": [], "body": "## Acceptance Criteria\n- [ ] Third issue\n", "comments": []},
    {"number": 4, "createdAt": "2026-01-04", "labels": [], "body": "## Acceptance Criteria\n- [ ] Fourth issue\n", "comments": []},
    {"number": 5, "createdAt": "2026-01-05", "labels": [], "body": "## Acceptance Criteria\n- [ ] Fifth issue\n", "comments": []}
  ],
  "build_issues": [],
  "prs": []
}
JSON
if run_tick head-of-line "$tmp/head-of-line.json"; then
  assert_actions head-of-line "$tmp/head-of-line-events.jsonl" "3,4" ""
fi

cat > "$tmp/build-slot.json" <<'JSON'
{
  "issues": [
    {"number": 1, "createdAt": "2026-01-01", "labels": [], "body": "## Acceptance Criteria\n- [ ] First issue\n", "comments": []},
    {"number": 2, "createdAt": "2026-01-02", "labels": [], "body": "## Acceptance Criteria\n- [ ] Second issue\n", "comments": []},
    {"number": 3, "createdAt": "2026-01-03", "labels": [], "body": "## Acceptance Criteria\n- [ ] Third issue\n", "comments": []},
    {"number": 10, "createdAt": "2026-01-04", "labels": [{"name": "owner approved"}], "body": "## Acceptance Criteria\n- [ ] Build issue\n", "comments": []}
  ],
  "build_issues": [
    {"number": 10, "createdAt": "2026-01-04"}
  ],
  "prs": []
}
JSON
if run_tick build-slot "$tmp/build-slot.json"; then
  assert_actions build-slot "$tmp/build-slot-events.jsonl" "1" "10"
fi

cat > "$tmp/open-pr-build-slot.json" <<'JSON'
{
  "issues": [
    {"number": 1, "createdAt": "2026-01-01", "labels": [], "body": "## Acceptance Criteria\n- [ ] First issue\n", "comments": []},
    {"number": 2, "createdAt": "2026-01-02", "labels": [], "body": "## Acceptance Criteria\n- [ ] Second issue\n", "comments": []},
    {"number": 3, "createdAt": "2026-01-03", "labels": [], "body": "## Acceptance Criteria\n- [ ] Third issue\n", "comments": []},
    {"number": 10, "createdAt": "2026-01-04", "labels": [{"name": "owner approved"}], "body": "## Acceptance Criteria\n- [ ] Build issue\n", "comments": []}
  ],
  "build_issues": [
    {"number": 10, "createdAt": "2026-01-04"}
  ],
  "prs": [
    {"number": 100, "headRefName": "factory/issue-10", "headRefOid": "abc", "isDraft": true, "reviewDecision": "", "mergeable": "MERGEABLE", "statusCheckRollup": [], "createdAt": "2026-01-05"}
  ]
}
JSON
if run_tick open-pr-build-slot "$tmp/open-pr-build-slot.json"; then
  assert_actions open-pr-build-slot "$tmp/open-pr-build-slot-events.jsonl" "1,2" ""
fi

cat > "$tmp/failed-candidates.json" <<'JSON'
{
  "issues": [
    {"number": 1, "createdAt": "2026-01-01", "labels": [], "body": "## Acceptance Criteria\n- [ ] Comment query fails\n", "comments": []},
    {"number": 2, "createdAt": "2026-01-02", "labels": [], "body": "## Acceptance Criteria\n- [ ] Body query fails\n", "comments": []},
    {"number": 3, "createdAt": "2026-01-03", "labels": [], "body": "## Acceptance Criteria\n- [ ] Third issue\n", "comments": []},
    {"number": 4, "createdAt": "2026-01-04", "labels": [], "body": "## Acceptance Criteria\n- [ ] Fourth issue\n", "comments": []},
    {"number": 5, "createdAt": "2026-01-05", "labels": [], "body": "## Acceptance Criteria\n- [ ] Fifth issue\n", "comments": []}
  ],
  "fail_comment_issues": [1],
  "fail_body_issues": [2],
  "build_issues": [],
  "prs": []
}
JSON
if run_tick failed-candidates "$tmp/failed-candidates.json" 1; then
  assert_actions failed-candidates "$tmp/failed-candidates-events.jsonl" "3,4" ""
  assert_event failed-candidates "$tmp/failed-candidates-events.jsonl" marker_skip
  assert_event failed-candidates "$tmp/failed-candidates-events.jsonl" plan_skipped
  assert_event failed-candidates "$tmp/failed-candidates-events.jsonl" discovery_failed
fi

cat > "$tmp/discovery-failure.json" <<'JSON'
{
  "issues": [],
  "fail_issue_discovery": true,
  "build_issues": [],
  "prs": []
}
JSON
if run_tick discovery-failure "$tmp/discovery-failure.json" 1; then
  assert_event discovery-failure "$tmp/discovery-failure-events.jsonl" discovery_failed
  assert_no_event discovery-failure "$tmp/discovery-failure-events.jsonl" nothing_to_do
fi

python3 - "$tmp/pagination.json" <<'PY'
import datetime
import json
import sys

start = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
issues = []
for number in range(1, 206):
    created = start + datetime.timedelta(minutes=206 - number)
    issues.append({
        "number": number,
        "created_at": created.isoformat().replace("+00:00", "Z"),
        "labels": [],
        "body": "## Acceptance Criteria\n- [ ] Behavior works\n",
        "comments": [],
    })
with open(sys.argv[1], "w", encoding="utf-8") as fixture_file:
    json.dump({"issues": issues, "build_issues": [], "prs": [], "concatenated_issue_pages": True}, fixture_file)
PY
if run_tick pagination "$tmp/pagination.json"; then
  assert_actions pagination "$tmp/pagination-events.jsonl" "205,204" ""
  if grep -q -- '--slurp' "$gh_log"; then
    fail "pagination: tick used unsupported --slurp"
  else
    pass
  fi
  assert_metrics_modes pagination "$tmp/pagination-metrics"
fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
