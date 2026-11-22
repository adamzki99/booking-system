#!/usr/bin/env bash
#
# ci-canary.sh - prove that the CI gates still fail when they should.
#
# Usage:
#   dev-ops/scripts/ci-canary.sh gate <gate>
#   dev-ops/scripts/ci-canary.sh cleanup
#   dev-ops/scripts/ci-canary.sh report
#
# `gate` plants one deliberate defect on a throwaway canary/<gate>-<date>
# branch, opens a draft pull request and passes only when the PR's ci-gate
# check concludes failure. `cleanup` closes every open canary PR and deletes
# every canary/* branch. `report` files (or updates) the labelled bug issue
# when a canary run fails.
#
# Required environment:
#   GH_TOKEN or GITHUB_TOKEN   token with contents, pull-requests and issues write
#
# Optional environment:
#   CI_CANARY_REPO_ROOT        repository checkout (default: git toplevel)
#   CI_CANARY_REMOTE           git remote (default: origin)
#   CI_CANARY_BASE_BRANCH      base branch (default: main)
#   CI_CANARY_DATE             branch suffix (default: UTC YYYYMMDD)
#   CI_CANARY_TIMEOUT_SECONDS  wait for ci-gate (default: 1800)
#   CI_CANARY_POLL_SECONDS     poll interval (default: 30)
#   CI_CANARY_PUSH_URL         remote URL to use for pushes (default: leave as is)
#   CI_CANARY_RUN_URL          workflow run URL for the report body
#   GITHUB_STEP_SUMMARY        when set, append a gate result table

set -euo pipefail

REPO_ROOT="${CI_CANARY_REPO_ROOT:-}"
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel)"
fi
REMOTE="${CI_CANARY_REMOTE:-origin}"
BASE_BRANCH="${CI_CANARY_BASE_BRANCH:-main}"
CANARY_DATE="${CI_CANARY_DATE:-$(date -u +%Y%m%d)}"
TIMEOUT_SECONDS="${CI_CANARY_TIMEOUT_SECONDS:-1800}"
POLL_SECONDS="${CI_CANARY_POLL_SECONDS:-30}"

VALID_GATES=(gofmt gotest vitest semgrep dep-review gitleaks)

log() { printf '[ci-canary] %s\n' "$*"; }
die() { printf '[ci-canary] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
Usage: ci-canary.sh gate <gofmt|gotest|vitest|semgrep|dep-review|gitleaks>
       ci-canary.sh cleanup
       ci-canary.sh report
EOF
  exit 2
}

require_token() {
  if [[ -z "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]]; then
    die "GH_TOKEN or GITHUB_TOKEN is required"
  fi
  export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
}

require_repo() {
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || die "not a git repository: $REPO_ROOT"
  [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || die "CI_CANARY_TIMEOUT_SECONDS must be an integer"
  [[ "$POLL_SECONDS" =~ ^[0-9]+$ ]] || die "CI_CANARY_POLL_SECONDS must be an integer"
  command -v python3 >/dev/null 2>&1 || die "python3 is required"
}

use_push_url() {
  if [[ -n "${CI_CANARY_PUSH_URL:-}" ]]; then
    git -C "$REPO_ROOT" remote set-url "$REMOTE" "$CI_CANARY_PUSH_URL"
  fi
}

valid_gate() {
  local gate="$1" candidate
  for candidate in "${VALID_GATES[@]}"; do
    [[ "$candidate" == "$gate" ]] && return 0
  done
  return 1
}

branch_for() { printf 'canary/%s-%s' "$1" "$CANARY_DATE"; }

remote_branch_exists() {
  git -C "$REPO_ROOT" ls-remote --exit-code --heads "$REMOTE" "$1" >/dev/null 2>&1
}

write_summary() {
  local gate="$1" expected="$2" actual="$3" result="$4"
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] || return 0
  {
    printf '### CI canary: %s\n\n' "$gate"
    printf '| gate | expected | actual | result |\n'
    printf '| --- | --- | --- | --- |\n'
    printf '| %s | %s | %s | %s |\n\n' "$gate" "$expected" "$actual" "$result"
  } >>"$GITHUB_STEP_SUMMARY"
}

# write_defect plants the payload for one gate. Every payload is written on the
# throwaway canary branch only; nothing here exists on the base branch.
write_defect() {
  local gate="$1"
  local backend_dir="$REPO_ROOT/product/backend/internal/canary"
  local frontend_dir="$REPO_ROOT/product/frontend-solid"
  local frontend_test="$frontend_dir/src/ci-canary.test.ts"
  local semgrep_dir="$REPO_ROOT/dev-ops/canary"
  local secret_file="$semgrep_dir/ci_canary_secret.txt"

  case "$gate" in
    gofmt)
      mkdir -p "$backend_dir"
      cat >"$backend_dir/canary.go" <<'EOF'
package canary

var Answer=42
EOF
      git -C "$REPO_ROOT" add -- product/backend/internal/canary/canary.go
      ;;
    gotest)
      mkdir -p "$backend_dir"
      cat >"$backend_dir/canary_test.go" <<'EOF'
package canary

import "testing"

func TestCanaryFails(t *testing.T) {
	t.Fatal("ci-canary")
}
EOF
      git -C "$REPO_ROOT" add -- product/backend/internal/canary/canary_test.go
      ;;
    vitest)
      mkdir -p "$(dirname "$frontend_test")"
      cat >"$frontend_test" <<'EOF'
import { describe, expect, it } from "vitest";

describe("ci-canary", () => {
  it("fails on purpose", () => {
    expect(true).toBe(false);
  });
});
EOF
      git -C "$REPO_ROOT" add -- product/frontend-solid/src/ci-canary.test.ts
      ;;
    semgrep)
      mkdir -p "$semgrep_dir"
      cat >"$semgrep_dir/ci_canary_pattern.py" <<'EOF'
import subprocess


def run(command):
    return subprocess.call(command, shell=True)


def evaluate(expression):
    return eval(expression)


def query(cursor, name):
    return cursor.execute("SELECT * FROM users WHERE name = '%s'" % name)
EOF
      git -C "$REPO_ROOT" add -- dev-ops/canary/ci_canary_pattern.py
      ;;
    dep-review)
      command -v npm >/dev/null 2>&1 || die "npm is required for the dep-review canary"
      python3 - "$frontend_dir/package.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as handle:
    data = json.load(handle)
data.setdefault("dependencies", {})["lodash"] = "4.17.15"
with open(path, "w") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
      (
        cd "$frontend_dir"
        npm install --package-lock-only --ignore-scripts --no-audit --no-fund --loglevel=error
      )
      git -C "$REPO_ROOT" add -- product/frontend-solid/package.json product/frontend-solid/package-lock.json
      ;;
    gitleaks)
      mkdir -p "$semgrep_dir"
      local secret
      # Assemble the value at run time so no committed file on the base branch
      # matches a gitleaks rule.
      secret="$(head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-40)"
      [[ ${#secret} -eq 40 ]] || die "failed to generate canary secret"
      printf 'api_key = "%s"\n' "$secret" >"$secret_file"
      git -C "$REPO_ROOT" add -- dev-ops/canary/ci_canary_secret.txt
      ;;
    *)
      die "unknown gate: $gate"
      ;;
  esac
}

open_pr_for_branch() {
  local branch="$1" json number
  json="$(gh pr list --state open --head "$branch" --json number)" \
    || die "failed to list open pull requests for $branch"
  number="$(printf '%s' "$json" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
print(data[0]["number"] if data else "")
')"
  printf '%s' "$number"
}

create_draft_pr() {
  local gate="$1" branch="$2" url number
  url="$(gh pr create \
    --draft \
    --base "$BASE_BRANCH" \
    --head "$branch" \
    --title "[ci-canary] ${gate} gate must fail" \
    --body "Deliberate defect that proves the ${gate} CI gate fails when it should. This draft PR is created and removed by the monthly ci-canary workflow and must never be merged.")" \
    || die "failed to create canary pull request for $branch"
  number="${url##*/}"
  [[ "$number" =~ ^[0-9]+$ ]] || die "could not parse pull request number from: $url"
  printf '%s' "$number"
}

ci_gate_state() {
  local pr="$1" json
  json="$(gh pr view "$pr" --json statusCheckRollup)" \
    || return 1
  printf '%s' "$json" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
for item in data.get("statusCheckRollup") or []:
    name = item.get("name") or item.get("context") or ""
    if name != "ci-gate":
        continue
    status = (item.get("status") or "").upper()
    state = (item.get("conclusion") or item.get("state") or status or "").upper()
    if item.get("__typename") == "CheckRun" and status not in ("COMPLETED", ""):
        print("PENDING")
    else:
        print(state or "PENDING")
    raise SystemExit
print("MISSING")
'
}

# wait_for_ci_gate returns 0 only when ci-gate concluded failure. Every other
# outcome (success, skipped, cancelled, neutral, timeout) is a canary failure.
wait_for_ci_gate() {
  local pr="$1" deadline=$((SECONDS + TIMEOUT_SECONDS)) state errors=0
  CI_CANARY_LAST_STATE="PENDING"
  while :; do
    if state="$(ci_gate_state "$pr")"; then
      case "$state" in
        FAILURE | ERROR | TIMED_OUT | ACTION_REQUIRED | STARTUP_FAILURE)
          CI_CANARY_LAST_STATE="$state"
          return 0
          ;;
        SUCCESS | SKIPPED | NEUTRAL | CANCELLED | STALE)
          CI_CANARY_LAST_STATE="$state"
          return 1
          ;;
        PENDING | EXPECTED | MISSING | "")
          : # keep waiting
          ;;
        *)
          log "unknown ci-gate state '$state'; still waiting"
          ;;
      esac
      errors=0
    else
      errors=$((errors + 1))
      log "could not read ci-gate state (attempt $errors)"
      if ((errors >= 5)); then
        CI_CANARY_LAST_STATE="ERROR"
        return 1
      fi
    fi
    if ((SECONDS >= deadline)); then
      CI_CANARY_LAST_STATE="TIMEOUT"
      return 1
    fi
    sleep "$POLL_SECONDS"
  done
}

cmd_gate() {
  local gate="${1:-}"
  [[ -n "$gate" ]] || usage
  valid_gate "$gate" || die "unknown gate: $gate"
  require_token
  require_repo
  use_push_url

  local branch pr state
  branch="$(branch_for "$gate")"
  log "gate=$gate branch=$branch"

  git -C "$REPO_ROOT" fetch --quiet "$REMOTE" "$BASE_BRANCH"
  git -C "$REPO_ROOT" checkout --quiet -B "$branch" "$REMOTE/$BASE_BRANCH"

  write_defect "$gate"
  git -C "$REPO_ROOT" -c user.name="ci-canary" \
    -c user.email="ci-canary@users.noreply.github.com" \
    commit --quiet -m "test(ci-canary): plant ${gate} defect"

  if remote_branch_exists "$branch"; then
    log "removing stale remote branch $branch"
    git -C "$REPO_ROOT" push --quiet "$REMOTE" --delete "$branch"
  fi
  git -C "$REPO_ROOT" push --quiet --set-upstream "$REMOTE" "$branch"

  pr="$(open_pr_for_branch "$branch")"
  if [[ -z "$pr" ]]; then
    pr="$(create_draft_pr "$gate" "$branch")"
  else
    log "reusing open pull request #$pr"
  fi
  log "waiting for ci-gate on pull request #$pr"

  if wait_for_ci_gate "$pr"; then
    log "PASS: ci-gate concluded $CI_CANARY_LAST_STATE for $gate"
    write_summary "$gate" "failure" "$CI_CANARY_LAST_STATE" "pass"
    return 0
  fi

  state="$CI_CANARY_LAST_STATE"
  log "FAIL: ci-gate concluded $state for $gate (expected failure)"
  write_summary "$gate" "failure" "$state" "fail"
  return 1
}

list_open_canary_prs() {
  local json
  json="$(gh pr list --state open --limit 500 --json number,headRefName)" \
    || die "failed to list open pull requests"
  printf '%s' "$json" | python3 -c '
import json
import sys

for pr in json.load(sys.stdin):
    head = pr.get("headRefName") or ""
    if head.startswith("canary/"):
        print(str(pr["number"]) + "\t" + head)
'
}

cmd_cleanup() {
  require_token
  require_repo
  use_push_url

  local number head ref branch remaining open
  while IFS=$'\t' read -r number head; do
    [[ -n "$number" ]] || continue
    log "closing pull request #$number ($head)"
    if ! gh pr close "$number" --delete-branch; then
      log "could not delete the branch with the pull request; closing it alone"
      gh pr close "$number" || die "failed to close pull request #$number"
    fi
  done < <(list_open_canary_prs)

  while read -r ref; do
    [[ -n "$ref" ]] || continue
    branch="${ref#refs/heads/}"
    log "deleting remote branch $branch"
    git -C "$REPO_ROOT" push --quiet "$REMOTE" --delete "$branch" \
      || die "failed to delete remote branch $branch"
  done < <(git -C "$REPO_ROOT" ls-remote --heads "$REMOTE" 'canary/*' | awk '{print $2}')

  remaining="$(git -C "$REPO_ROOT" ls-remote --heads "$REMOTE" 'canary/*' || true)"
  [[ -z "$remaining" ]] || die "canary branches remain: $remaining"

  open="$(list_open_canary_prs)"
  [[ -z "$open" ]] || die "open canary pull requests remain: $open"

  log "cleanup complete"
}

cmd_report() {
  require_token
  local existing body run_url
  run_url="${CI_CANARY_RUN_URL:-}"
  body="The monthly CI canary failed: at least one gate did not fail when a deliberate defect was planted. Investigate the workflow run and the gate that unexpectedly passed."
  if [[ -n "$run_url" ]]; then
    body="${body}

Run: ${run_url}"
  fi

  existing="$(gh issue list --state open --limit 200 --json number,title \
    | python3 -c '
import json
import sys

for issue in json.load(sys.stdin):
    if (issue.get("title") or "").startswith("[ci-canary]"):
        print(issue["number"])
        break
')" || die "failed to list open issues"

  if [[ -n "$existing" ]]; then
    log "commenting on existing canary issue #$existing"
    gh issue comment "$existing" --body "$body" \
      || die "failed to comment on issue #$existing"
  else
    log "opening canary bug issue"
    gh issue create \
      --title "[ci-canary] CI gate canary failed" \
      --label bug \
      --label dev-ops \
      --body "$body" \
      || die "failed to open canary bug issue"
  fi
}

main() {
  local command="${1:-}"
  shift || true
  case "$command" in
    gate) cmd_gate "${1:-}" ;;
    cleanup) cmd_cleanup ;;
    report) cmd_report ;;
    *) usage ;;
  esac
}

main "$@"
