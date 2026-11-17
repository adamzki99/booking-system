#!/usr/bin/env bash
#
# nightly-cleanup.sh — remove factory git worktrees and factory logs.
#
# Intended for a nightly cron job (and safe to run manually). It:
#   - removes registered git worktrees created for factory work that are clean
#     (no uncommitted/untracked changes), then prunes stale worktree metadata;
#   - removes factory session logs (factory-*.log) from the log directory.
#
# The primary checkout and any dirty/in-progress worktree are left untouched.
#
# Portable by design: derives paths from this script's location and environment,
# does not assume machine- or user-specific paths, and validates prerequisites.
#
# Usage:
#   ./nightly-cleanup.sh [--dry-run] [--logs-days N]
#
# Options:
#   --dry-run      print actions without changing anything
#   --logs-days=N  remove factory-*.log files older than N days (default: 1)
#
# Environment:
#   FACTORY_WORKTREE  path to the factory's sibling worktree (default: derived
#                     from the repository root as ../<repo>-factory-worktree)
#   FACTORY_LOG_DIR   directory containing factory-*.log files (default: /tmp/opencode)
#
set -euo pipefail

log()  { printf '[factory-cleanup] %s\n' "$*"; }
warn() { printf '[factory-cleanup] warning: %s\n' "$*" >&2; }
die()  { printf '[factory-cleanup] ERROR: %s\n' "$*" >&2; exit 1; }

DRY_RUN=0
LOGS_DAYS=1

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --logs-days=*) LOGS_DAYS="${arg#*=}" ;;
    -h|--help)
      sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "unknown argument: $arg" ;;
  esac
done

[[ "$LOGS_DAYS" =~ ^[0-9]+$ ]] || die "--logs-days must be a non-negative integer (got: $LOGS_DAYS)"

# --- validation -------------------------------------------------------------
for cmd in git find; do
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
done

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" >/dev/null 2>&1 && pwd)" \
  || die "cannot determine script directory"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." >/dev/null 2>&1 && pwd)" \
  || die "cannot determine repository root from script location: $SCRIPT_DIR"
git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || die "not a git repository: $REPO_ROOT"

LOG_DIR="${FACTORY_LOG_DIR:-/tmp/opencode}"
REPO_BASENAME="$(basename "$REPO_ROOT")"
FACTORY_WORKTREE="${FACTORY_WORKTREE:-$(dirname "$REPO_ROOT")/${REPO_BASENAME}-factory-worktree}"

run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '[factory-cleanup] dry-run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

is_clean_worktree() {
  local wt="$1"
  [[ -d "$wt" ]] || return 1
  # Treat unreadable/unexpected status as dirty to avoid destructive cleanup.
  local st
  st="$(git -C "$wt" status --porcelain 2>/dev/null)" || return 1
  [[ -z "$st" ]]
}

# --- git worktrees ----------------------------------------------------------
# Remove factory-managed linked worktrees that are clean. Never touch the main
# worktree or any worktree with local changes.
main_wt="$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null || true)"

current=""
while IFS= read -r line; do
  if [[ "$line" == worktree\ * ]]; then
    current="${line#worktree }"
    continue
  fi
  # blank line terminates a porcelain record
  if [[ -z "$line" ]]; then
    if [[ -n "$current" ]]; then
      wt="$current"
      current=""

      # skip main checkout
      if [[ -n "$main_wt" && "$wt" == "$main_wt" ]]; then
        continue
      fi

      # only factory-managed locations (path-derived, no user/machine names)
      managed=0
      case "$wt" in
        "$FACTORY_WORKTREE"|"$LOG_DIR"/factory-*|"$LOG_DIR"/issue-*-worktree|"$LOG_DIR"/worktrees/*)
          managed=1 ;;
      esac
      [[ "$managed" -eq 1 ]] || continue

      if [[ ! -e "$wt" ]]; then
        log "stale worktree entry (missing path): $wt"
        continue
      fi

      if ! is_clean_worktree "$wt"; then
        log "skip dirty/in-progress worktree: $wt"
        continue
      fi

      log "removing worktree: $wt"
      run git -C "$REPO_ROOT" worktree remove --force "$wt" || warn "failed to remove $wt"
    fi
    continue
  fi
done < <(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null; echo)

log "pruning stale worktree metadata"
run git -C "$REPO_ROOT" worktree prune --expire now || warn "git worktree prune failed"

# --- logs -------------------------------------------------------------------
if [[ -d "$LOG_DIR" ]]; then
  log "removing factory logs in $LOG_DIR older than $LOGS_DAYS day(s)"
  # factory session logs only; leave unrelated files untouched
  if [[ "$DRY_RUN" == 1 ]]; then
    find "$LOG_DIR" -maxdepth 1 -type f -name 'factory-*.log' -mtime "+$((LOGS_DAYS - 1))" -print 2>/dev/null \
      | while IFS= read -r f; do [[ -n "$f" ]] && log "dry-run: would remove $f"; done || true
  else
    find "$LOG_DIR" -maxdepth 1 -type f -name 'factory-*.log' -mtime "+$((LOGS_DAYS - 1))" -delete 2>/dev/null || true
  fi
else
  log "log dir not found: $LOG_DIR (skipping log cleanup)"
fi

log "done"
