#!/usr/bin/env bash
#
# tick.sh — one tick of the software factory.
#
# Fetches open GitHub issues/PRs and starts OpenCode sessions:
#
#   - one planning session, for the oldest issue with no labels (infant
#     state): the agent posts the implementation plan as a comment and
#     categorizes the issue with labels.
#   - build-path sessions (fixes, then optionally a new build):
#       - fix sessions for open factory PRs (head "factory/issue-*") that need
#         fixes before merge: failing/status checks, changes requested, or merge
#         conflicts/non-mergeable. Up to FACTORY_MAX_FIX_SESSIONS per tick
#         (default: 1). Fix attempts are idempotent per PR head SHA + blocking
#         reasons via <!-- factory:fix-pr:... --> PR comments.
#       - one building session, for the highest-priority issue labeled
#         "owner approved" with no build marker and no open factory PR: priority
#         is determined by GitHub Projects (v2) membership — issues in the oldest
#         project (by createdAt) come first, then by the project's numeric "Build
#         order" field (ascending, from 1); issues not in any project are ranked
#         after project issues. The agent implements the issue, creates a PR, and
#         merges it.
#
# Labels select the session model per models.yaml. Finished work is marked
# with <!-- factory:plan --> / <!-- factory:build --> comments, so ticks are
# idempotent and never re-plan or re-build the same issue. Ticks do not
# overlap: a tick that finds a previous one still running exits immediately.
#
# If a session fails because usage/quota is filled, --on-usage-filled controls
# the behavior (default: backup = retry once with the configured backup model).
#
# Schedule hourly, e.g.:  0 * * * * /path/to/repo/dev-ops/factory/tick.sh
#
# Usage:
#   dev-ops/factory/tick.sh [--dry-run] [--on-usage-filled=backup|skip|fail]
#                           [--max-fix-sessions=N]
#
# Dependencies: gh (authenticated), opencode, python3 + PyYAML, flock.
#
set -euo pipefail

# cron (and other minimal environments) may not include ~/.opencode/bin on PATH
export PATH="${HOME}/.opencode/bin:${PATH}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

MODELS_CONFIG="${MODELS_CONFIG:-$SCRIPT_DIR/models.yaml}"
APPROVED_LABEL="owner approved"
PLAN_MARKER='<!-- factory:plan -->'
BUILD_MARKER='<!-- factory:build -->'
FIX_MARKER_PREFIX='<!-- factory:fix-pr:'
DRY_RUN=0
ON_USAGE_FILLED="${FACTORY_ON_USAGE_FILLED:-backup}"
MAX_FIX_SESSIONS="${FACTORY_MAX_FIX_SESSIONS:-1}"
FREE_MODEL="${FACTORY_FREE_MODEL:-opencode-go/beam-free}"

log() { printf '[factory-tick] %s\n' "$*"; }
die() { printf '[factory-tick] ERROR: %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --on-usage-filled=*) ON_USAGE_FILLED="${arg#*=}" ;;
    --max-fix-sessions=*) MAX_FIX_SESSIONS="${arg#*=}" ;;
    *) die "unknown argument: $arg" ;;
  esac
done

case "$ON_USAGE_FILLED" in
  backup|skip|fail) ;;
  *) die "invalid --on-usage-filled value: $ON_USAGE_FILLED (use backup, skip, or fail)" ;;
esac

[[ "$MAX_FIX_SESSIONS" =~ ^[0-9]+$ ]] || die "invalid --max-fix-sessions value: $MAX_FIX_SESSIONS (use a non-negative integer)"

[[ -f "$MODELS_CONFIG" ]] || die "config not found: $MODELS_CONFIG"
command -v gh >/dev/null || die "gh is required"
command -v opencode >/dev/null || die "opencode is required"
command -v python3 >/dev/null || die "python3 is required"
python3 -c 'import yaml' 2>/dev/null || die "PyYAML is required (pip install pyyaml)"

# Do not overlap ticks: a slow session must not pile up followers.
exec 9>"$(git rev-parse --git-dir)/factory-tick.lock"
flock -n 9 || { log "previous tick still running; exiting"; exit 0; }

# Print the number of the oldest open issue with no labels, or nothing.
oldest_unlabeled_issue() {
  gh issue list --state open --limit 200 --json number,labels,createdAt \
    --jq '[.[] | select((.labels | length) == 0)] | sort_by(.createdAt) | .[0].number // empty'
}

# Print candidate open "owner approved" issue numbers, best build candidate
# first. Priority: issues in a GitHub Project (v2) come before others; among
# project issues, the older project (by createdAt) wins, then the numeric
# "Build order" project field ascending (ties broken by issue age). Issues not
# in any project are ranked after project issues, oldest first. One number per
# line; the caller skips issues whose build marker is already present.
approved_build_candidates() {
  python3 - "$APPROVED_LABEL" << 'PYEOF'
import json, math, subprocess, sys

label = sys.argv[1]


def gh_json(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "").strip())
    return json.loads(r.stdout or "null")


def by_created(it):
    n = it["number"]
    created = it.get("createdAt") or "9999"
    return (created, n)


def emit(items, prio):
    def key(it):
        n = it["number"]
        created = it.get("createdAt") or "9999"
        if n in prio:
            pc, pn, bo = prio[n]
            return (0, pc, pn, bo, created, n)
        return (1, "9999", math.inf, math.inf, created, n)

    for it in sorted(items, key=key):
        print(it["number"])


try:
    issues = gh_json(
        "issue",
        "list",
        "--state",
        "open",
        "--label",
        label,
        "--limit",
        "200",
        "--json",
        "number,createdAt",
    )
except Exception:
    issues = []
if not issues:
    raise SystemExit

# Build project priority map. On any failure, fall back to issue age so a
# project-metadata/auth issue never suppresses building.
try:
    repo = gh_json("repo", "view", "--json", "owner,nameWithOwner")
    owner = repo["owner"]["login"]
    full = repo["nameWithOwner"]

    projects = []
    for q in (
        "query($login:String!){ user(login:$login){ projectsV2(first:50){ nodes{ number id createdAt closed } } } }",
        "query($login:String!){ organization(login:$login){ projectsV2(first:50){ nodes{ number id createdAt closed } } } }",
    ):
        try:
            pdata = gh_json("api", "graphql", "-f", f"query={q}", "-F", f"login={owner}")["data"]
            for key in ("user", "organization"):
                nodes = ((pdata.get(key) or {}).get("projectsV2") or {}).get("nodes") or []
                projects.extend([n for n in nodes if n])
        except Exception:
            pass
    seen_p = set()
    uniq_projects = []
    for p in projects:
        n = p.get("number")
        if n not in seen_p:
            seen_p.add(n)
            uniq_projects.append(p)

    items_q = (
        "query($id:ID!, $after:String){ node(id:$id){ ... on ProjectV2{"
        " items(first:100, after:$after){ nodes{ content{ __typename"
        " ... on Issue{ number repository{ nameWithOwner } }"
        " ... on PullRequest{ number repository{ nameWithOwner } } }"
        " fieldValueByName(name:\"Build order\"){ __typename"
        " ... on ProjectV2ItemFieldNumberValue{ number }"
        " ... on ProjectV2ItemFieldTextValue{ text } } }"
        " pageInfo{ hasNextPage endCursor } } } } }"
    )

    # issue number -> best (project_createdAt, project_number, build_order)
    prio = {}
    for p in uniq_projects:
        if p.get("closed") or not p.get("id"):
            continue
        pnum = p.get("number")
        pcreated = p.get("createdAt") or "9999"
        after = None
        while True:
            try:
                args = ["api", "graphql", "-f", f"query={items_q}", "-f", f"id={p['id']}"]
                if after:
                    args += ["-f", f"after={after}"]
                conn = ((gh_json(*args).get("data") or {}).get("node") or {}).get("items") or {}
            except Exception:
                break
            for it in conn.get("nodes") or []:
                content = it.get("content") or {}
                if (content.get("__typename") or "").lower() != "issue":
                    continue
                repo_name = ((content.get("repository") or {}).get("nameWithOwner") or "").strip()
                if repo_name != full:
                    continue
                num = content.get("number")
                if not isinstance(num, int):
                    continue
                fv = it.get("fieldValueByName") or {}
                bo = fv.get("number")
                if bo is None:
                    bo = fv.get("text")
                try:
                    bof = float(bo)
                except Exception:
                    bof = math.inf
                cand = (pcreated, pnum or math.inf, bof)
                if num not in prio or cand < prio[num]:
                    prio[num] = cand
            page = conn.get("pageInfo") or {}
            if not page.get("hasNextPage"):
                break
            after = page.get("endCursor")
            if not after:
                break

    emit(issues, prio)
except Exception as e:
    sys.stderr.write(f"[factory-tick] project priority unavailable, using issue age: {e}\n")
    for it in sorted(issues, key=by_created):
        print(it["number"])
PYEOF
}

# Print fix candidates for open factory PRs (head factory/issue-*): one line per
# candidate as: pr_number<TAB>issue_number<TAB>head_sha<TAB>reasons<TAB>marker
# "reasons" is a comma-separated list (failing-checks,changes-requested,conflicts).
# "marker" is the idempotency marker for this PR head+reasons. Candidates with no
# blocking reasons are omitted. On API errors, prints nothing (never blocks ticks).
fix_pr_candidates() {
  python3 - << 'PYEOF'
import json, re, subprocess, sys

FAIL = {"FAILURE", "FAILED", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"}


def gh_json(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "").strip())
    return json.loads(r.stdout or "null")


def check_state(item):
    # statusCheckRollup items: CheckRun has status/conclusion; StatusContext has state.
    if not isinstance(item, dict):
        return ""
    st = (item.get("state") or item.get("conclusion") or item.get("status") or "").upper()
    if item.get("__typename") == "CheckRun" and (item.get("status") or "").upper() not in ("COMPLETED", ""):
        # in progress / queued - not an actionable failure
        return "PENDING"
    return st


try:
    prs = gh_json(
        "pr", "list", "--state", "open", "--limit", "100",
        "--json", "number,headRefName,headRefOid,mergeable,reviewDecision,statusCheckRollup,isDraft,createdAt",
    )
except Exception as e:
    sys.stderr.write(f"[factory-tick] fix-pr discovery unavailable: {e}\n")
    raise SystemExit

rows = []
for pr in prs or []:
    if pr.get("isDraft"):
        continue
    head = pr.get("headRefName") or ""
    m = re.match(r"^factory/issue-(\d+)$", head)
    if not m:
        continue
    issue = int(m.group(1))
    sha = (pr.get("headRefOid") or "").strip()
    if not sha:
        continue
    reasons = []
    rollup = pr.get("statusCheckRollup") or []
    if isinstance(rollup, list):
        for item in rollup:
            st = check_state(item)
            if st in FAIL:
                reasons.append("failing-checks")
                break
    rd = (pr.get("reviewDecision") or "").upper()
    if rd == "CHANGES_REQUESTED":
        reasons.append("changes-requested")
    mergeable = (pr.get("mergeable") or "").upper()
    if mergeable == "CONFLICTING":
        reasons.append("conflicts")
    if not reasons:
        continue
    reasons = sorted(set(reasons))
    rkey = ",".join(reasons)
    marker = f"<!-- factory:fix-pr:{sha}:{rkey} -->"
    rows.append((pr.get("createdAt") or "9999", pr.get("number"), issue, sha, rkey, marker))

for _created, prnum, issue, sha, rkey, marker in sorted(rows):
    print(f"{prnum}\t{issue}\t{sha}\t{rkey}\t{marker}")
PYEOF
}

has_marker() { # $1 issue number, $2 marker string; prints true/false
  local marker_json
  marker_json="$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$2")"
  gh issue view "$1" --json comments \
    --jq "[.comments[].body | contains($marker_json)] | any"
}

has_pr_marker() { # $1 PR number, $2 marker string; prints true/false
  local marker_json
  marker_json="$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$2")"
  gh pr view "$1" --json comments \
    --jq "[.comments[].body | contains($marker_json)] | any" 2>/dev/null || echo "false"
}

issue_labels() { # $1 issue number; prints one label name per line
  gh issue view "$1" --json labels --jq '.labels[].name'
}

open_factory_pr_for_issue() { # $1 issue number; prints PR number or nothing
  gh pr list --state open --head "factory/issue-$1" --json number --jq '.[0].number // empty' 2>/dev/null || true
}

# Print "<model>\t<backup_model>" for the given label names per models.yaml:
# the first label (in models.yaml order) with an entry, else default.
# backup_model falls back to the default entry's backup_model when unset.
model_for_labels() { # $@ label names
  python3 - "$MODELS_CONFIG" "$@" << 'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    entries = (yaml.safe_load(f) or {}).get("labels") or {}
have = set(sys.argv[2:])
model = backup = ""
for name, cfg in entries.items():
    if name != "default" and name in have and isinstance(cfg, dict):
        model = cfg.get("model") or ""
        backup = cfg.get("backup_model") or cfg.get("backup") or ""
        if model:
            break
if not model:
    model = (entries.get("default") or {}).get("model") or ""
    backup = backup or (entries.get("default") or {}).get("backup_model") or (entries.get("default") or {}).get("backup") or ""
if not backup:
    backup = (entries.get("default") or {}).get("backup_model") or (entries.get("default") or {}).get("backup") or ""
print(model + "\t" + backup)
PYEOF
}

is_usage_filled() { # $1 output text (case-insensitive patterns)
  local out="${1,,}"
  [[ "$out" == *"usage limit"* ]] && return 0
  [[ "$out" == *"limit exceeded"* ]] && return 0
  [[ "$out" == *"rate limit"* ]] && return 0
  [[ "$out" == *"quota"* && "$out" == *"exceed"* ]] && return 0
  [[ "$out" == *"usage"* && "$out" == *"exceed"* ]] && return 0
  return 1
}

plan_prompt() { # $1 issue number
  cat << EOF
You are the planning agent of this software factory. Turn GitHub issue #$1
into a planned, categorized issue.

1. Read it: gh issue view $1 --comments
2. Post one comment with a concrete, minimal implementation plan. The comment
   body must start with this exact marker line:

$PLAN_MARKER

3. Categorize the issue with labels (see gh label list). If the task is
   large, also add the heavy-build-task label. Never add the
   "$APPROVED_LABEL" label — only the repository owner applies it.

Do not modify any code or files.
EOF
}

build_prompt() { # $1 issue number
  cat << EOF
You are the builder agent of this software factory. Implement GitHub issue
#$1 and land it on the base branch.

Load and follow these OpenCode skills (use the skill tool) as they apply:
- \`implement\` — build the issue from its spec/plan (state the issue title
  after fetching it; use TDD at pre-agreed seams when practical; run
  typechecking and targeted tests regularly; run the full test suite once at
  the end; run a code review before landing).
- \`tdd\` — drive red-green-refactor for features/fixes when the project has
  tests (as \`implement\` directs).
- \`code-review\` — review changes before landing when available.
- \`diagnosing-bugs\` — use for hard bugs or performance regressions.
- \`domain-modeling\` — use when changing domain terminology, CQRS/event-sourced
  models, or project glossary/ADR-worthy decisions.
- \`frontend-design\` / \`webapp-testing\` — use for \`product/frontend/\` UI
  work and Playwright/browser verification when relevant.
- \`pr\` — when opening the pull request, write the PR body in that format
  (Summary, Evidence, Merge Danger). Include \`Closes #$1\` in the body.

Factory delivery rules (these override generic skill defaults where they
conflict):
1. Read the issue and its plan: gh issue view $1 --comments
2. Create a branch named factory/issue-$1 and implement the issue. Follow
   AGENTS.md; add tests where the project has tests. Keep the change minimal.
3. Push the branch, open a pull request whose body follows the \`pr\` skill and
   includes \`Closes #$1\`. Capture the PR number.
3a. Put yourself in an agent loop that watches the PR with a bash command
   until the actions and security scan results have come in. Example:

   PR=<number>
   gh pr checks "$PR" --watch

   Only after this command exits (all checks finished) evaluate the results.
3b. Wait for ALL required checks and security analyses to complete and pass
   (Backend CI: format/vet/test/build, Docker build; Security: govulncheck,
   secret scan; Semgrep). Run the relevant local checks yourself first
   (\`gofmt -l .\`, \`go vet ./...\`, \`go test ./...\`, \`go build ./cmd/server\`
   for backend). Do NOT merge until every check is green and no security
   finding is outstanding; if any fail, fix them and re-push.
3b. Only once checks/security are green and the PR is mergeable with no
   requested changes, merge it (squash) and delete the branch.
4. Post one comment on the issue summarizing what was merged. The comment
   body must start with this exact marker line:

$BUILD_MARKER
EOF
}

fix_prompt() { # $1 PR number, $2 issue number, $3 reasons, $4 marker
  cat << EOF
You are the fix agent of this software factory. Pull request #$1 (for issue
#$2, branch factory/issue-$2) is open but blocked from merge. Make it
mergeable.

Blocking reasons reported by GitHub: $3
(failing-checks = status/CI failures; changes-requested = review requested
changes; conflicts = merge conflicts / not mergeable.)

1. Read context: gh pr view $1 --comments; gh pr checks $1 || true; gh issue view $2 --comments
2. Check out the PR branch (gh pr checkout $1). Fix the blocking issues with
   minimal, focused changes. Follow AGENTS.md and the issue plan.
3. If checks failed, reproduce/fix the failures and ensure relevant tests and
   checks pass. If changes were requested, address the review comments. If
   there are merge conflicts, resolve them against the base branch.
4. Push fixes to the PR branch. Re-run/verify the failing checks locally.
   Put yourself in an agent loop that watches PR #$1 with a bash command
   until the actions and security scan results have come in:

   PR=$1
   gh pr checks "$PR" --watch

   Only after this command exits evaluate the results, and wait for ALL required
   checks and security analyses to complete and pass
   (Backend CI, Security, Semgrep). Do NOT merge until every check is green,
   security analysis is clean, the PR is mergeable, and there are no requested
   changes. Only then merge it (squash) and delete the branch.
5. Post one comment on PR #$1 summarizing what you fixed and the merge/result
   status. The comment body must start with this exact marker line (required
   for factory idempotency):

$4

If the PR was merged, also ensure issue #$2 has a comment starting with:

$BUILD_MARKER

summarizing what was merged (add it if missing).
EOF
}

# Normalize a model id: free models (beam-free) always run with "high" effort.
normalize_model() { # $1 model id (may be empty)
  local m="$1"
  [[ -z "$m" ]] && { printf '%s' "$m"; return; }
  case "${m%%#*}" in
    opencode-go/beam-free)
      m="opencode-go/beam-free#high"
      ;;
  esac
  printf '%s' "$m"
}

run_opencode() { # $1 title, $2 model (empty = opencode default), $3 agent (empty = default), $4 prompt
  local model
  model="$(normalize_model "$2")"
  local args=(run --auto --title "$1")
  [[ -n "$model" ]] && args+=(--model "$model")
  [[ -n "$3" ]] && args+=(--agent "$3")
  args+=("$4")
  opencode "${args[@]}"
}

start_session() { # $1 kind (plan/build/fix), $2 ref (issue or PR), $3 title, $4 model, $5 backup_model, $6 prompt
  local kind="$1" ref="$2" title="$3" model="$4" backup="$5" prompt="$6"
  local agent=""
  case "$kind" in
    plan) agent="planner" ;;
    build) agent="builder" ;;
    fix) agent="fixer" ;;
  esac
  local out status=0

  local logfile="/tmp/opencode/factory-${kind}-${ref}.log"
  mkdir -p /tmp/opencode
  : > "$logfile"
  log "starting $kind session for #$ref (model: ${model:-opencode default}, agent: ${agent:-default})"
  set +e
  out="$(run_opencode "$title" "$model" "$agent" "$prompt" 2>&1 | tee "$logfile")"
  status=${PIPESTATUS[0]}
  set -e
  if [[ $status -eq 0 ]]; then
    printf '%s\n' "$out"
    return 0
  fi

  printf '%s\n' "$out" >&2
  if is_usage_filled "$out"; then
    log "session for #$ref failed: usage/quota appears filled (on-usage-filled=$ON_USAGE_FILLED)"
    case "$ON_USAGE_FILLED" in
      backup)
        # Try the configured backup model first.
        if [[ -n "$backup" && "$backup" != "$model" ]]; then
          local bout bstatus=0
          log "retrying #$ref with backup model: $backup"
          set +e
          bout="$(run_opencode "$title (backup)" "$backup" "$agent" "$prompt" 2>&1 | tee -a "$logfile")"
          bstatus=${PIPESTATUS[0]}
          set -e
          printf '%s\n' "$bout" >&2
          if [[ $bstatus -eq 0 ]]; then
            return 0
          fi
          if ! is_usage_filled "$bout"; then
            return "$bstatus"
          fi
          log "backup model for #$ref also hit usage/quota limit"
        fi
        # Final fallback: a free model is not subject to the Go weekly
        # usage limit, so it is the only model guaranteed to still work
        # when paid models are exhausted. Try it if it is not already the
        # model/backup we just attempted.
        if [[ "$model" != "$FREE_MODEL" && "$backup" != "$FREE_MODEL" ]]; then
          log "retrying #$ref with free model: $FREE_MODEL"
          run_opencode "$title (free)" "$FREE_MODEL" "$agent" "$prompt" 2>&1 | tee -a "$logfile" || return $?
          return 0
        fi
        log "no distinct free model configured for #$ref; failing"
        return "$status"
        ;;
      skip)
        log "skipping #$ref due to filled usage"
        return 0
        ;;
      fail)
        return "$status"
        ;;
    esac
  fi

  log "$kind session for #$ref failed (exit $status)"
  return "$status"
}

plan_issue="$(oldest_unlabeled_issue)"
if [[ -n "$plan_issue" && "$(has_marker "$plan_issue" "$PLAN_MARKER")" == "true" ]]; then
  log "issue #$plan_issue already planned (marker present); skipping"
  plan_issue=""
fi

# Build path, sub-path 1: fix open factory PRs blocked from merge.
fix_count=0
fix_pids=()
if [[ "$MAX_FIX_SESSIONS" -gt 0 ]]; then
  while IFS=$'\t' read -r pr_number issue_number head_sha reasons marker; do
    [[ -z "$pr_number" ]] && continue
    [[ "$fix_count" -ge "$MAX_FIX_SESSIONS" ]] && break
    if [[ "$(has_pr_marker "$pr_number" "$marker")" == "true" ]]; then
      log "PR #$pr_number already attempted for head $head_sha ($reasons); skipping"
      continue
    fi
    if [[ "$(has_marker "$issue_number" "$BUILD_MARKER")" == "true" ]]; then
      log "issue #$issue_number already built; skipping fix for PR #$pr_number"
      continue
    fi
    mapfile -t labels < <(issue_labels "$issue_number")
    IFS=$'\t' read -r model backup_model < <(model_for_labels "${labels[@]}")
    if [[ "$DRY_RUN" == 1 ]]; then
      log "dry-run: would fix PR #$pr_number (issue #$issue_number, reasons: $reasons, model: ${model:-opencode default}, backup: ${backup_model:-none}, on-usage-filled: $ON_USAGE_FILLED)"
      fix_count=$((fix_count + 1))
    else
      start_session "fix" "$pr_number" "factory: fix PR #$pr_number (issue #$issue_number)" "$model" "$backup_model" "$(fix_prompt "$pr_number" "$issue_number" "$reasons" "$marker")" &
      fix_pids+=($!)
      fix_count=$((fix_count + 1))
    fi
  done < <(fix_pr_candidates)
  if [[ ${#fix_pids[@]} -gt 0 ]]; then
    for pid in "${fix_pids[@]}"; do
      wait "$pid" || true
    done
  fi
fi

# Build path, sub-path 2: build a new approved issue (no open factory PR).
build_issue=""
while IFS= read -r candidate; do
  [[ -z "$candidate" ]] && continue
  if [[ "$(has_marker "$candidate" "$BUILD_MARKER")" == "true" ]]; then
    log "issue #$candidate already built (marker present); skipping"
    continue
  fi
  if [[ -n "$(open_factory_pr_for_issue "$candidate")" ]]; then
    log "issue #$candidate has an open factory PR; skipping new build"
    continue
  fi
  build_issue="$candidate"
  break
done < <(approved_build_candidates)

if [[ -z "$plan_issue" && "$fix_count" -eq 0 && -z "$build_issue" ]]; then
  log "nothing to do"
  exit 0
fi

if [[ -n "$plan_issue" ]]; then
  IFS=$'\t' read -r model backup_model < <(model_for_labels)
  if [[ "$DRY_RUN" == 1 ]]; then
    log "dry-run: would plan issue #$plan_issue (model: ${model:-opencode default}, backup: ${backup_model:-none}, on-usage-filled: $ON_USAGE_FILLED)"
  else
    start_session "plan" "$plan_issue" "factory: plan issue #$plan_issue" "$model" "$backup_model" "$(plan_prompt "$plan_issue")"
  fi
fi

if [[ -n "$build_issue" ]]; then
  mapfile -t labels < <(issue_labels "$build_issue")
  IFS=$'\t' read -r model backup_model < <(model_for_labels "${labels[@]}")
  if [[ "$DRY_RUN" == 1 ]]; then
    log "dry-run: would build issue #$build_issue (model: ${model:-opencode default}, backup: ${backup_model:-none}, on-usage-filled: $ON_USAGE_FILLED)"
  else
    start_session "build" "$build_issue" "factory: build issue #$build_issue" "$model" "$backup_model" "$(build_prompt "$build_issue")"
  fi
fi
