#!/usr/bin/env bash
#
# tick.sh — one tick of the software factory.
#
# Fetches open GitHub issues and starts at most two OpenCode sessions:
#
#   - one planning session, for the oldest issue with no labels (infant
#     state): the agent posts the implementation plan as a comment and
#     categorizes the issue with labels.
#   - one building session, for the oldest issue labeled "owner approved":
#     the agent implements the issue, creates a PR, and merges it.
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

# Print the number of the oldest open issue labeled "owner approved".
oldest_approved_issue() {
  gh issue list --state open --label "$APPROVED_LABEL" --limit 100 --json number,createdAt \
    --jq 'sort_by(.createdAt) | .[0].number // empty'
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

1. Read the issue and its plan: gh issue view $1 --comments
2. Create a branch named factory/issue-$1 and implement the issue. Follow
   AGENTS.md; add tests where the project has tests. Keep the change minimal.
3. Push the branch, open a pull request with "Closes #$1" in the body, merge
   it (squash), and delete the branch.
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

build_issue="$(oldest_approved_issue)"
if [[ -n "$build_issue" && "$(has_marker "$build_issue" "$BUILD_MARKER")" == "true" ]]; then
  log "issue #$build_issue already built (marker present); skipping"
  build_issue=""
fi

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
