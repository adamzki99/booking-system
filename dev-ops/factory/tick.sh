#!/usr/bin/env bash
#
# tick.sh — one tick of the software factory.
#
# Fetches open GitHub issues and starts at most two OpenCode sessions:
#
#   - one planning session, for the oldest issue with no labels (infant
#     state): the agent posts the implementation plan as a comment and
#     categorizes the issue with labels.
#   - one building session, for the highest-priority issue labeled
#     "owner approved": priority is determined by GitHub Projects (v2)
#     membership — issues in the oldest project (by createdAt) come first,
#     then by the project's numeric "Build order" field (ascending, from 1);
#     issues not in any project are ranked after project issues. The agent
#     implements the issue, creates a PR, and merges it.
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
#
# Dependencies: gh (authenticated), opencode, python3 + PyYAML, flock.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

MODELS_CONFIG="${MODELS_CONFIG:-$SCRIPT_DIR/models.yaml}"
APPROVED_LABEL="owner approved"
PLAN_MARKER='<!-- factory:plan -->'
BUILD_MARKER='<!-- factory:build -->'
DRY_RUN=0
ON_USAGE_FILLED="${FACTORY_ON_USAGE_FILLED:-backup}"

log() { printf '[factory-tick] %s\n' "$*"; }
die() { printf '[factory-tick] ERROR: %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --on-usage-filled=*) ON_USAGE_FILLED="${arg#*=}" ;;
    *) die "unknown argument: $arg" ;;
  esac
done

case "$ON_USAGE_FILLED" in
  backup|skip|fail) ;;
  *) die "invalid --on-usage-filled value: $ON_USAGE_FILLED (use backup, skip, or fail)" ;;
esac

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

has_marker() { # $1 issue number, $2 marker string; prints true/false
  local marker_json
  marker_json="$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$2")"
  gh issue view "$1" --json comments \
    --jq "[.comments[].body | contains($marker_json)] | any"
}

issue_labels() { # $1 issue number; prints one label name per line
  gh issue view "$1" --json labels --jq '.labels[].name'
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
   includes \`Closes #$1\`, merge it (squash), and delete the branch.
4. Post one comment on the issue summarizing what was merged. The comment
   body must start with this exact marker line:

$BUILD_MARKER
EOF
}

run_opencode() { # $1 title, $2 model (empty = opencode default), $3 prompt
  local args=(run --auto --title "$1")
  [[ -n "$2" ]] && args+=(--model "$2")
  args+=("$3")
  opencode "${args[@]}"
}

start_session() { # $1 kind (plan/build), $2 issue, $3 title, $4 model, $5 backup_model, $6 prompt
  local kind="$1" issue="$2" title="$3" model="$4" backup="$5" prompt="$6"
  local out status=0

  log "starting $kind session for issue #$issue (model: ${model:-opencode default})"
  set +e
  out="$(run_opencode "$title" "$model" "$prompt" 2>&1)"
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    printf '%s\n' "$out"
    return 0
  fi

  printf '%s\n' "$out" >&2
  if is_usage_filled "$out"; then
    log "session for issue #$issue failed: usage/quota appears filled (on-usage-filled=$ON_USAGE_FILLED)"
    case "$ON_USAGE_FILLED" in
      backup)
        if [[ -n "$backup" && "$backup" != "$model" ]]; then
          log "retrying issue #$issue with backup model: $backup"
          run_opencode "$title (backup)" "$backup" "$prompt" || return $?
          return 0
        fi
        log "no distinct backup model configured for issue #$issue; failing"
        return "$status"
        ;;
      skip)
        log "skipping issue #$issue due to filled usage"
        return 0
        ;;
      fail)
        return "$status"
        ;;
    esac
  fi

  log "$kind session for issue #$issue failed (exit $status)"
  return "$status"
}

plan_issue="$(oldest_unlabeled_issue)"
if [[ -n "$plan_issue" && "$(has_marker "$plan_issue" "$PLAN_MARKER")" == "true" ]]; then
  log "issue #$plan_issue already planned (marker present); skipping"
  plan_issue=""
fi

build_issue=""
while IFS= read -r candidate; do
  [[ -z "$candidate" ]] && continue
  if [[ "$(has_marker "$candidate" "$BUILD_MARKER")" == "true" ]]; then
    log "issue #$candidate already built (marker present); skipping"
    continue
  fi
  build_issue="$candidate"
  break
done < <(approved_build_candidates)

if [[ -z "$plan_issue" && -z "$build_issue" ]]; then
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
