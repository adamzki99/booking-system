#!/usr/bin/env bash
#
# dependabot-sweep.sh
#
# Unattended Dependabot PR triage for this repository, driven by an OpenCode
# session. Designed to run from cron or a systemd timer.
#
# What it does:
#   1. Takes a lock so overlapping runs cannot happen.
#   2. Refreshes a dedicated clone of the repo (never your working checkout).
#   3. Asks GitHub whether any Dependabot PRs are open. If none, it exits
#      without calling the model, so empty runs cost nothing.
#   4. Runs `opencode run` with dependabot-sweep-prompt.md plus a run-config
#      header.
#   5. Logs everything and prunes old logs.
#
# Requirements: bash, git, gh, opencode, flock, timeout, plus whatever
# toolchain the repo needs for its tests (Go, Node, ...).
#
# Configuration: environment variables, or put them in
# ~/.config/dependabot-sweep/env (chmod 600). Typical contents:
#   GH_TOKEN=github_pat_xxx
#   MODEL=opencode-go/kimi-k2.5
#   DRY_RUN=1
#
# Optional environment variables:
#   REPO_SLUG        owner/repo (default: detected from origin, fallback booking-system)
#   WORK_DIR         state/log/clone root (default: $XDG_STATE_HOME/dependabot-sweep)
#   REPO_DIR         dedicated clone path (default: $WORK_DIR/repo)
#   LOG_DIR          log directory (default: $WORK_DIR/logs)
#   PROMPT_FILE      prompt path (default: script dir/dependabot-sweep-prompt.md)
#   MODEL            opencode model ID (default: opencode-go/kimi-k2.5)
#   AGENT            opencode agent name (default: empty, uses opencode default)
#   MAX_PRS          max PRs per run (default: 10)
#   AUTO_MERGE       1 merge verified PRs, 0 verify/comment only (default: 1)
#   DRY_RUN          1 no pushes/merges/comments/labels (default: 0)
#   AUTO_APPROVE     1 pass --auto to opencode run (default: 1)
#   RUN_TIMEOUT      opencode timeout (default: 90m)
#   LOG_RETENTION_DAYS old log retention (default: 30)
#   GIT_USER_NAME    git identity for fix commits
#   GIT_USER_EMAIL   git identity for fix commits

set -Eeuo pipefail

ENV_FILE="${ENV_FILE:-$HOME/.config/dependabot-sweep/env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

# Cron starts with a minimal PATH. Add common install locations without
# overriding binaries already present in the caller's PATH.
export PATH="$PATH:$HOME/.opencode/bin:$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_SLUG="adamzki99/booking-system"
if git -C "$SCRIPT_DIR" remote get-url origin >/dev/null 2>&1; then
  origin_url="$(git -C "$SCRIPT_DIR" remote get-url origin)"
  if [[ "$origin_url" =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
    DEFAULT_REPO_SLUG="${BASH_REMATCH[1]}"
  fi
fi

REPO_SLUG="${REPO_SLUG:-$DEFAULT_REPO_SLUG}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
WORK_DIR="${WORK_DIR:-$STATE_HOME/dependabot-sweep}"
REPO_DIR="${REPO_DIR:-$WORK_DIR/repo}"
LOG_DIR="${LOG_DIR:-$WORK_DIR/logs}"
PROMPT_FILE="${PROMPT_FILE:-$SCRIPT_DIR/dependabot-sweep-prompt.md}"

MODEL="${MODEL:-opencode-go/kimi-k3}"
AGENT="${AGENT:-}"

MAX_PRS="${MAX_PRS:-10}"
AUTO_MERGE="${AUTO_MERGE:-1}"
DRY_RUN="${DRY_RUN:-0}"
AUTO_APPROVE="${AUTO_APPROVE:-1}"
RUN_TIMEOUT="${RUN_TIMEOUT:-90m}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"

GIT_USER_NAME="${GIT_USER_NAME:-dependabot-sweep}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-dependabot-sweep@users.noreply.github.com}"

mkdir -p "$WORK_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/sweep-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { log "ERROR: $*"; exit 1; }

trap 'log "ERROR: command failed on line $LINENO (exit $?)"' ERR

exec 9>"$WORK_DIR/sweep.lock"
if ! flock -n 9; then
  log "Another sweep is still running. Exiting."
  exit 0
fi

for bin in git gh opencode flock timeout; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' not found in PATH ($PATH)"
done
[[ -f "$PROMPT_FILE" ]] || die "Prompt file not found: $PROMPT_FILE"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Set GH_TOKEN in $ENV_FILE or run 'gh auth login'."

models_out="$(opencode models 2>/dev/null || true)"
if [[ -n "$models_out" ]] && ! grep -qxF "$MODEL" <<<"$models_out"; then
  log "WARNING: '$MODEL' not found in 'opencode models'. Is the configured provider connected for this user?"
fi

PR_NUMBERS="$(gh pr list -R "$REPO_SLUG" --state open --author 'app/dependabot' --limit 100 \
  --json number --jq '[.[].number] | sort | map("#" + tostring) | join(", ")')"

if [[ -z "$PR_NUMBERS" ]]; then
  log "No open Dependabot PRs in $REPO_SLUG. Nothing to do."
  exit 0
fi
log "Open Dependabot PRs: $PR_NUMBERS"

if [[ ! -d "$REPO_DIR/.git" ]]; then
  log "Cloning $REPO_SLUG into $REPO_DIR"
  gh repo clone "$REPO_SLUG" "$REPO_DIR"
fi

cd "$REPO_DIR"
git remote get-url origin | grep -qi "$REPO_SLUG" \
  || die "$REPO_DIR does not look like a clone of $REPO_SLUG. Refusing to continue."

gh auth setup-git
git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

DEFAULT_BRANCH="$(gh repo view "$REPO_SLUG" --json defaultBranchRef --jq '.defaultBranchRef.name')"
reset_clone() {
  git fetch --prune origin
  git checkout -f "$DEFAULT_BRANCH"
  git checkout -B "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH"
  git clean -fd
}
reset_clone

PROMPT="$(cat <<EOF
You are running unattended from a scheduled job. Follow the instructions below.

RUN CONFIG
- Repository: $REPO_SLUG
- Default branch: $DEFAULT_BRANCH
- Working directory (already cloned, clean, on the default branch): $REPO_DIR
- Open Dependabot PRs at start: $PR_NUMBERS
- MAX_PRS: $MAX_PRS
- AUTO_MERGE: $AUTO_MERGE
- DRY_RUN: $DRY_RUN
- Started: $(date -Is)

EOF
)"
PROMPT+=$'\n'"$(cat "$PROMPT_FILE")"

args=(run --model "$MODEL")
[[ "$AUTO_APPROVE" == "1" ]] && args+=(--auto)
[[ -n "$AGENT" ]] && args+=(--agent "$AGENT")

log "Starting OpenCode (model=$MODEL agent=${AGENT:-default} dry_run=$DRY_RUN auto_merge=$AUTO_MERGE timeout=$RUN_TIMEOUT)"

set +e
timeout --kill-after=60s "$RUN_TIMEOUT" opencode "${args[@]}" "$PROMPT"
rc=$?
set -e

if [[ $rc -eq 124 ]]; then
  log "OpenCode hit the $RUN_TIMEOUT timeout and was stopped."
elif [[ $rc -ne 0 ]]; then
  log "OpenCode exited with status $rc."
else
  log "OpenCode finished."
fi

result_line="$(grep -E '^SWEEP_RESULT:' "$LOG_FILE" | tail -n 1 || true)"
log "${result_line:-No SWEEP_RESULT line found in output.}"

reset_clone || log "WARNING: could not reset clone after run."
find "$LOG_DIR" -name 'sweep-*.log' -mtime "+$LOG_RETENTION_DAYS" -delete 2>/dev/null || true

log "Log: $LOG_FILE"
exit "$rc"
