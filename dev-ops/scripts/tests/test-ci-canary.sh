#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
SCRIPT="$SCRIPT_DIR/../ci-canary.sh"

PASS=0
FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { PASS=$((PASS + 1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

stubs="$tmp/bin"
mkdir -p "$stubs"
GH_LOG="$tmp/gh.log"
GH_STATE="$tmp/gh-state.json"
export GH_LOG GH_STATE
: >"$GH_LOG"

cat >"$stubs/gh" <<'EOF'
#!/usr/bin/env python3
import json
import os
import sys

log_path = os.environ["GH_LOG"]
state_path = os.environ["GH_STATE"]

with open(log_path, "a") as handle:
    handle.write(" ".join(sys.argv[1:]) + "\n")

try:
    with open(state_path) as handle:
        state = json.load(handle)
except FileNotFoundError:
    state = {"next_pr": 1, "next_issue": 1, "prs": {}, "issues": {}}


def save():
    with open(state_path, "w") as handle:
        json.dump(state, handle)


def option(name):
    args = sys.argv[1:]
    if name in args:
        index = args.index(name)
        if index + 1 < len(args):
            return args[index + 1]
    return ""


args = sys.argv[1:]

if args[:2] == ["pr", "list"]:
    head = option("--head")
    rows = []
    for number, pr in state["prs"].items():
        if not pr.get("open", True):
            continue
        if head and pr.get("head") != head:
            continue
        rows.append({"number": int(number), "headRefName": pr.get("head", "")})
    print(json.dumps(rows))
elif args[:2] == ["pr", "create"]:
    head = option("--head")
    number = state["next_pr"]
    state["next_pr"] = number + 1
    state["prs"][str(number)] = {"head": head, "open": True}
    save()
    print("https://github.com/example/repo/pull/%d" % number)
elif args[:2] == ["pr", "view"]:
    number = args[2]
    pr = state["prs"].get(number)
    if pr is None:
        sys.stderr.write("unknown pull request %s\n" % number)
        raise SystemExit(1)
    head = pr.get("head", "")
    gate = head.split("/", 1)[1].rsplit("-", 1)[0] if "/" in head else ""
    key = "GH_CHECK_STATE_" + gate.upper().replace("-", "_")
    check = os.environ.get(key, os.environ.get("GH_CHECK_STATE", "FAILURE")).upper()
    if check in ("PENDING", "MISSING"):
        rollup = []
    else:
        rollup = [
            {
                "__typename": "CheckRun",
                "name": "ci-gate",
                "status": "COMPLETED",
                "conclusion": check,
            }
        ]
    print(json.dumps({"statusCheckRollup": rollup}))
elif args[:2] == ["pr", "close"]:
    number = args[2]
    if number in state["prs"]:
        state["prs"][number]["open"] = False
    save()
elif args[:2] == ["issue", "list"]:
    rows = [
        {"number": int(number), "title": issue.get("title", "")}
        for number, issue in state["issues"].items()
        if issue.get("open", True)
    ]
    print(json.dumps(rows))
elif args[:2] == ["issue", "create"]:
    number = state["next_issue"]
    state["next_issue"] = number + 1
    state["issues"][str(number)] = {
        "open": True,
        "title": option("--title"),
        "labels": [value for index, value in enumerate(args) if index > 0 and args[index - 1] == "--label"],
    }
    save()
    print("https://github.com/example/repo/issues/%d" % number)
elif args[:2] == ["issue", "comment"]:
    number = args[2]
    if number in state["issues"]:
        state["issues"][number]["commented"] = True
    save()
else:
    sys.stderr.write("unexpected gh command: %s\n" % " ".join(args))
    raise SystemExit(1)
EOF
chmod +x "$stubs/gh"

cat >"$stubs/npm" <<'EOF'
#!/usr/bin/env bash
printf '{"lockfileVersion":3,"packages":{"node_modules/lodash":{"version":"4.17.15"}}}\n' >package-lock.json
EOF
chmod +x "$stubs/npm"

make_fixture() {
  local name="$1"
  origin="$tmp/$name-origin.git"
  work="$tmp/$name-work"
  git init -q --bare "$origin"
  git init -q "$work"
  git -C "$work" config user.email "canary-test@example.invalid"
  git -C "$work" config user.name "canary-test"
  mkdir -p "$work/product/backend" "$work/product/frontend-solid/src" "$work/dev-ops/canary"
  echo "# fixture" >"$work/README.md"
  printf '{"name":"fixture","dependencies":{}}\n' >"$work/product/frontend-solid/package.json"
  printf '{"lockfileVersion":3,"packages":{}}\n' >"$work/product/frontend-solid/package-lock.json"
  git -C "$work" add -A
  git -C "$work" commit -qm "test: fixture"
  git -C "$work" branch -M main
  git -C "$work" remote add origin "$origin"
  git -C "$work" push -q origin main
  git -C "$origin" symbolic-ref HEAD refs/heads/main
  printf '{"next_pr":1,"next_issue":1,"prs":{},"issues":{}}' >"$GH_STATE"
  : >"$GH_LOG"
}

canary_refs() {
  git -C "$origin" for-each-ref --format='%(refname:short)' refs/heads/canary/
}

pr_create_count() {
  grep -c '^pr create' "$GH_LOG" 2>/dev/null || true
}

issue_create_count() {
  grep -c '^issue create' "$GH_LOG" 2>/dev/null || true
}

open_pr_count() {
  python3 - "$GH_STATE" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    state = json.load(handle)
print(sum(1 for pr in state["prs"].values() if pr.get("open", True)))
PY
}

run_gate() {
  local gate="$1"
  shift
  env PATH="$stubs:$PATH" \
    GH_LOG="$GH_LOG" GH_STATE="$GH_STATE" \
    CI_CANARY_REPO_ROOT="$work" \
    CI_CANARY_REMOTE=origin \
    CI_CANARY_BASE_BRANCH=main \
    CI_CANARY_DATE=20260101 \
    CI_CANARY_TIMEOUT_SECONDS="${CI_CANARY_TIMEOUT_SECONDS:-5}" \
    CI_CANARY_POLL_SECONDS=0 \
    GH_TOKEN=test-token \
    "$@" \
    "$SCRIPT" gate "$gate"
}

run_cleanup() {
  env PATH="$stubs:$PATH" \
    GH_LOG="$GH_LOG" GH_STATE="$GH_STATE" \
    CI_CANARY_REPO_ROOT="$work" \
    CI_CANARY_REMOTE=origin \
    CI_CANARY_BASE_BRANCH=main \
    CI_CANARY_DATE=20260101 \
    GH_TOKEN=test-token \
    "$SCRIPT" cleanup
}

run_report() {
  env PATH="$stubs:$PATH" \
    GH_LOG="$GH_LOG" GH_STATE="$GH_STATE" \
    CI_CANARY_RUN_URL="https://github.com/example/repo/actions/runs/1" \
    GH_TOKEN=test-token \
    "$SCRIPT" report
}

# All six gates must fail ci-gate; cleanup removes every PR and branch.
make_fixture all-fail
for gate in gofmt gotest vitest semgrep dep-review gitleaks; do
  if run_gate "$gate" >"$tmp/all-fail-$gate.log" 2>&1; then
    pass
  else
    fail "gate $gate should pass when ci-gate fails"
  fi
done
[[ "$(pr_create_count)" -eq 6 ]] && pass || fail "expected 6 draft PRs, got $(pr_create_count)"
[[ "$(open_pr_count)" -eq 6 ]] && pass || fail "expected 6 open PRs before cleanup"
if run_cleanup >"$tmp/all-fail-cleanup.log" 2>&1; then
  pass
else
  fail "cleanup should succeed"
fi
[[ -z "$(canary_refs)" ]] && pass || fail "canary branches remain after cleanup"
[[ "$(open_pr_count)" -eq 0 ]] && pass || fail "canary PRs remain open after cleanup"

# One gate that unexpectedly passes fails the run and files exactly one bug issue.
make_fixture one-success
GH_CHECK_STATE_GOFMT=SUCCESS
export GH_CHECK_STATE_GOFMT
if run_gate gofmt >"$tmp/one-success-gofmt.log" 2>&1; then
  fail "gofmt gate should fail the canary when ci-gate succeeds"
else
  pass
fi
for gate in gotest vitest semgrep dep-review gitleaks; do
  if run_gate "$gate" >"$tmp/one-success-$gate.log" 2>&1; then
    pass
  else
    fail "gate $gate should still pass"
  fi
done
unset GH_CHECK_STATE_GOFMT
if run_report >"$tmp/one-success-report.log" 2>&1; then
  pass
else
  fail "report should succeed"
fi
[[ "$(issue_create_count)" -eq 1 ]] && pass || fail "expected exactly one bug issue"
python3 - "$GH_STATE" <<'PY' && pass || fail "bug issue must carry bug and dev-ops labels"
import json
import sys

with open(sys.argv[1]) as handle:
    state = json.load(handle)
issues = list(state["issues"].values())
if len(issues) != 1:
    raise SystemExit(1)
labels = set(issues[0].get("labels") or [])
if not {"bug", "dev-ops"}.issubset(labels):
    raise SystemExit(1)
PY
if run_report >"$tmp/one-success-report-again.log" 2>&1; then
  pass
else
  fail "second report should succeed"
fi
[[ "$(issue_create_count)" -eq 1 ]] && pass || fail "second report must not create another issue"
python3 - "$GH_STATE" <<'PY' && pass || fail "second report must comment on the existing issue"
import json
import sys

with open(sys.argv[1]) as handle:
    state = json.load(handle)
issues = list(state["issues"].values())
if len(issues) != 1 or not issues[0].get("commented"):
    raise SystemExit(1)
PY
if run_cleanup >"$tmp/one-success-cleanup.log" 2>&1; then
  pass
else
  fail "cleanup after one-success run should succeed"
fi
[[ -z "$(canary_refs)" ]] && pass || fail "canary branches remain after one-success cleanup"

# A pending ci-gate times out, and cleanup still removes the branch and PR.
make_fixture timeout
GH_CHECK_STATE_GOTEST=PENDING
export GH_CHECK_STATE_GOTEST
CI_CANARY_TIMEOUT_SECONDS=0
export CI_CANARY_TIMEOUT_SECONDS
if run_gate gotest >"$tmp/timeout.log" 2>&1; then
  fail "timeout gate should fail the canary"
else
  pass
fi
grep -q "TIMEOUT" "$tmp/timeout.log" && pass || fail "timeout should be reported"
[[ "$(open_pr_count)" -eq 1 ]] && pass || fail "timeout should leave a PR for cleanup"
if run_cleanup >"$tmp/timeout-cleanup.log" 2>&1; then
  pass
else
  fail "cleanup after timeout should succeed"
fi
[[ -z "$(canary_refs)" ]] && pass || fail "canary branches remain after timeout cleanup"
[[ "$(open_pr_count)" -eq 0 ]] && pass || fail "canary PR remains open after timeout cleanup"
unset GH_CHECK_STATE_GOTEST CI_CANARY_TIMEOUT_SECONDS

# No token means a clear error and no branch at all.
make_fixture no-token
set +e
env -u GH_TOKEN -u GITHUB_TOKEN PATH="$stubs:$PATH" \
  GH_LOG="$GH_LOG" GH_STATE="$GH_STATE" \
  CI_CANARY_REPO_ROOT="$work" \
  CI_CANARY_REMOTE=origin \
  CI_CANARY_BASE_BRANCH=main \
  CI_CANARY_DATE=20260101 \
  "$SCRIPT" gate gofmt >"$tmp/no-token.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass || fail "missing token should exit non-zero"
grep -q "GH_TOKEN or GITHUB_TOKEN" "$tmp/no-token.log" && pass || fail "missing token should explain the requirement"
[[ -z "$(canary_refs)" ]] && pass || fail "missing token must not create a branch"

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
