#!/usr/bin/env bash
#
# run-ui-audit.sh - run a scheduled, agent-driven Playwright UI/UX audit.
#
# Usage:
#   dev-ops/scripts/run-ui-audit.sh [options]
#
# Spawns an agent-driven dynamic Playwright audit against a non-production
# environment (QA/dev). The agent explores the application as basic, super,
# and admin users, evaluates Nielsen's 10 usability heuristics, and records
# findings and evidence as artifacts.
#
# Options:
#   --env ENV                 Environment name from dev-ops/environments.yaml (default: qa)
#   --local                   Run locally (do not re-exec over SSH)
#   --dry-run                 Prepare run artifacts/prompt and print plan without starting agent
#   --issue-filing            Allow the agent to file GitHub issues (default: disabled)
#   --no-issue-filing         Disable GitHub issue filing (default)
#   --artifact-dir DIR        Base artifact directory for this run (default: state dir)
#   --run-id ID               Run identifier (default: UTC timestamp)
#   --basic-email EMAIL       Basic user account email (default: user1@test.local)
#   --super-email EMAIL       Super user account email (default: superuser@test.local)
#   --admin-email EMAIL       Admin user account email (default: admin@test.local)
#   --title-prefix TEXT       Finding issue title prefix (default: [agent-playwright-audit])
#   --parent-title-prefix TEXT
#                             Parent run issue title prefix (default: [agent-playwright-audit][run])
#   --repo OWNER/REPO         GitHub repository for issue operations (default: detected via gh)
#   --timeout-minutes N       Agent session timeout in minutes (default: 60, 0 disables)
#   -h, --help                Show help
#
# Environment:
#   BOOKING_DEV_SSH           SSH target for remote execution (dev/QA host)
#   DEPLOY_DIR                Deploy checkout path override (default: /opt/booking-system-<env>)
#   UI_AUDIT_ARTIFACT_ROOT    Artifact root override
#   UI_AUDIT_AGENT_CMD        Agent command override (default: opencode)
#
# Dev/QA only. Production environment names are rejected.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/dev-ops/environments.yaml"
PROMPT_TEMPLATE="$REPO_ROOT/dev-ops/ui-audit/AUDIT_PROMPT.md"

ENV_NAME="qa"
LOCAL=0
DRY_RUN=0
ISSUE_FILING=0
ARTIFACT_DIR=""
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
BASIC_EMAIL="${UI_AUDIT_BASIC_EMAIL:-user1@test.local}"
SUPER_EMAIL="${UI_AUDIT_SUPER_EMAIL:-superuser@test.local}"
ADMIN_EMAIL="${UI_AUDIT_ADMIN_EMAIL:-admin@test.local}"
TITLE_PREFIX="[agent-playwright-audit]"
PARENT_TITLE_PREFIX="[agent-playwright-audit][run]"
REPO="${UI_AUDIT_REPO:-}"
TIMEOUT_MINUTES="${UI_AUDIT_TIMEOUT_MINUTES:-60}"
AGENT_CMD="${UI_AUDIT_AGENT_CMD:-opencode}"

log() { printf '[ui-audit] %s\n' "$*"; }
die() { printf '[ui-audit] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,48p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) [[ $# -ge 2 ]] || die "--env requires a value"; ENV_NAME="$2"; shift 2 ;;
    --local) LOCAL=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --issue-filing) ISSUE_FILING=1; shift ;;
    --no-issue-filing) ISSUE_FILING=0; shift ;;
    --artifact-dir) [[ $# -ge 2 ]] || die "--artifact-dir requires a value"; ARTIFACT_DIR="$2"; shift 2 ;;
    --run-id) [[ $# -ge 2 ]] || die "--run-id requires a value"; RUN_ID="$2"; shift 2 ;;
    --basic-email) [[ $# -ge 2 ]] || die "--basic-email requires a value"; BASIC_EMAIL="$2"; shift 2 ;;
    --super-email) [[ $# -ge 2 ]] || die "--super-email requires a value"; SUPER_EMAIL="$2"; shift 2 ;;
    --admin-email) [[ $# -ge 2 ]] || die "--admin-email requires a value"; ADMIN_EMAIL="$2"; shift 2 ;;
    --title-prefix) [[ $# -ge 2 ]] || die "--title-prefix requires a value"; TITLE_PREFIX="$2"; shift 2 ;;
    --parent-title-prefix) [[ $# -ge 2 ]] || die "--parent-title-prefix requires a value"; PARENT_TITLE_PREFIX="$2"; shift 2 ;;
    --repo) [[ $# -ge 2 ]] || die "--repo requires a value"; REPO="$2"; shift 2 ;;
    --timeout-minutes) [[ $# -ge 2 ]] || die "--timeout-minutes requires a value"; TIMEOUT_MINUTES="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

[[ "$ENV_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || die "invalid environment name: $ENV_NAME"
[[ "${ENV_NAME,,}" != *prod* ]] || die "production environments are not allowed"
[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid run id: $RUN_ID"
[[ "$TIMEOUT_MINUTES" =~ ^[0-9]+$ ]] || die "invalid --timeout-minutes value: $TIMEOUT_MINUTES"

DEPLOY_DIR="${DEPLOY_DIR:-/opt/booking-system-${ENV_NAME}}"
ARTIFACT_ROOT="${UI_AUDIT_ARTIFACT_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/booking-ui-audit}"
if [[ -z "$ARTIFACT_DIR" ]]; then
  ARTIFACT_DIR="$ARTIFACT_ROOT/$ENV_NAME/$RUN_ID"
fi

[[ -f "$ENV_FILE" ]] || die "environment file not found: $ENV_FILE"
[[ -f "$PROMPT_TEMPLATE" ]] || die "prompt template not found: $PROMPT_TEMPLATE"

read_port() {
  python3 - "$ENV_FILE" "$ENV_NAME" <<'PY'
import sys
path, env = sys.argv[1], sys.argv[2]
if env.lower() == "prod" or "prod" in env.lower():
    raise SystemExit("production environment not allowed")
port = None
found = False
in_env = False
with open(path) as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        key = line.strip().split(":", 1)[0].strip() if ":" in line.strip() else ""
        if indent == 2:
            in_env = (key == env)
            if in_env:
                found = True
            continue
        if in_env and indent >= 4 and ":" in line.strip():
            k, v = line.strip().split(":", 1)
            if k.strip() == "port":
                port = v.strip().strip('"').strip("'")
        if in_env and indent < 2 and line.strip():
            in_env = False
if not found:
    raise SystemExit(f"environment not found: {env}")
if not port:
    raise SystemExit(f"port missing for environment: {env}")
print(port)
PY
}

is_local() {
  if command -v docker >/dev/null 2>&1; then
    if docker compose -p "booking-${ENV_NAME}" ps -q backend 2>/dev/null | grep -q .; then
      return 0
    fi
  fi
  [[ -d "$DEPLOY_DIR" ]]
}

if [[ "$LOCAL" -ne 1 ]] && ! is_local; then
  SSH="${BOOKING_DEV_SSH:-}"
  [[ -n "$SSH" ]] || die "BOOKING_DEV_SSH is not set (required for remote dev/QA execution)"
  remote_args=(--env "$ENV_NAME" --local --run-id "$RUN_ID")
  [[ "$DRY_RUN" -eq 1 ]] && remote_args+=(--dry-run)
  [[ "$ISSUE_FILING" -eq 1 ]] && remote_args+=(--issue-filing) || remote_args+=(--no-issue-filing)
  [[ -n "$ARTIFACT_DIR" ]] && remote_args+=(--artifact-dir "$ARTIFACT_DIR")
  remote_args+=(--basic-email "$BASIC_EMAIL" --super-email "$SUPER_EMAIL" --admin-email "$ADMIN_EMAIL")
  remote_args+=(--title-prefix "$TITLE_PREFIX" --parent-title-prefix "$PARENT_TITLE_PREFIX")
  [[ -n "$REPO" ]] && remote_args+=(--repo "$REPO")
  remote_args+=(--timeout-minutes "$TIMEOUT_MINUTES")
  exec ssh "$SSH" -- "$DEPLOY_DIR/dev-ops/scripts/run-ui-audit.sh" "${remote_args[@]}"
fi

PORT="$(read_port)" || exit 1
BASE_URL="${UI_AUDIT_BASE_URL:-http://127.0.0.1:${PORT}}"

if [[ -z "$REPO" ]] && command -v gh >/dev/null 2>&1; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
REPO="${REPO:-adamzki99/booking-system}"

umask 077
mkdir -p "$ARTIFACT_DIR/evidence"
chmod 700 "$ARTIFACT_DIR" "$ARTIFACT_DIR/evidence" 2>/dev/null || true

ISSUE_FILING_MODE="disabled"
[[ "$ISSUE_FILING" -eq 1 ]] && ISSUE_FILING_MODE="enabled"

PROMPT_FILE="$ARTIFACT_DIR/audit-prompt.md"
RUN_META_FILE="$ARTIFACT_DIR/run.json"
REPORT_FILE="$ARTIFACT_DIR/report.md"
FINDINGS_FILE="$ARTIFACT_DIR/findings.json"

python3 - "$PROMPT_TEMPLATE" "$PROMPT_FILE" \
  "$RUN_ID" "$ENV_NAME" "$BASE_URL" "$ARTIFACT_DIR" "$REPO" "$ISSUE_FILING_MODE" \
  "$BASIC_EMAIL" "$SUPER_EMAIL" "$ADMIN_EMAIL" "$TITLE_PREFIX" "$PARENT_TITLE_PREFIX" <<'PY'
import pathlib
import sys

template_path, out_path = sys.argv[1], sys.argv[2]
values = {
    "RUN_ID": sys.argv[3],
    "ENV_NAME": sys.argv[4],
    "BASE_URL": sys.argv[5],
    "ARTIFACT_DIR": sys.argv[6],
    "REPO": sys.argv[7],
    "ISSUE_FILING": sys.argv[8],
    "BASIC_EMAIL": sys.argv[9],
    "SUPER_EMAIL": sys.argv[10],
    "ADMIN_EMAIL": sys.argv[11],
    "TITLE_PREFIX": sys.argv[12],
    "PARENT_TITLE_PREFIX": sys.argv[13],
}
text = pathlib.Path(template_path).read_text(encoding="utf-8")
for key, value in values.items():
    text = text.replace("{{" + key + "}}", value)
pathlib.Path(out_path).write_text(text, encoding="utf-8")
PY
chmod 600 "$PROMPT_FILE" 2>/dev/null || true

if [[ ! -f "$FINDINGS_FILE" ]]; then
  printf '[]\n' > "$FINDINGS_FILE"
fi
if [[ ! -f "$REPORT_FILE" ]]; then
  cat > "$REPORT_FILE" <<EOF
# UI/UX audit report

- Run ID: $RUN_ID
- Environment: $ENV_NAME
- Base URL: $BASE_URL
- Issue filing: $ISSUE_FILING_MODE
- Status: pending
EOF
fi

python3 - "$RUN_META_FILE" "$RUN_ID" "$ENV_NAME" "$BASE_URL" "$ARTIFACT_DIR" "$ISSUE_FILING_MODE" "$BASIC_EMAIL" "$SUPER_EMAIL" "$ADMIN_EMAIL" "$REPO" <<'PY'
import json
import sys
from datetime import datetime, timezone

path = sys.argv[1]
obj = {
    "run_id": sys.argv[2],
    "environment": sys.argv[3],
    "base_url": sys.argv[4],
    "artifact_dir": sys.argv[5],
    "issue_filing_mode": sys.argv[6],
    "roles": {
        "basic": {"email": sys.argv[7], "status": "pending"},
        "super": {"email": sys.argv[8], "status": "pending"},
        "admin": {"email": sys.argv[9], "status": "pending"},
    },
    "repo": sys.argv[10],
    "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "status": "prepared",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2)
    f.write("\n")
PY
chmod 600 "$RUN_META_FILE" "$REPORT_FILE" "$FINDINGS_FILE" 2>/dev/null || true

log "run_id=$RUN_ID"
log "environment=$ENV_NAME"
log "base_url=$BASE_URL"
log "artifact_dir=$ARTIFACT_DIR"
log "issue_filing=$ISSUE_FILING_MODE"
log "prompt=$PROMPT_FILE"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry run: prepared prompt and artifact skeleton; agent not started"
  exit 0
fi

# Best-effort: ensure Playwright docker image and local deps are available for the agent.
if command -v docker >/dev/null 2>&1; then
  docker build -q -t booking-playwright:local "$REPO_ROOT/dev-ops/testing" >/dev/null 2>&1 || true
fi
if command -v npm >/dev/null 2>&1 && [[ ! -d "$REPO_ROOT/dev-ops/testing/node_modules" ]]; then
  (cd "$REPO_ROOT/dev-ops/testing" && npm ci --silent >/dev/null 2>&1) || true
fi

command -v "$AGENT_CMD" >/dev/null 2>&1 || die "$AGENT_CMD is required for agent-driven audit (use --dry-run to prepare artifacts only)"

SESSION_LOG="$ARTIFACT_DIR/session.log"
: > "$SESSION_LOG"
chmod 600 "$SESSION_LOG" 2>/dev/null || true

python3 - "$RUN_META_FILE" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    obj = json.load(f)
obj["status"] = "running"
with open(path, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2)
    f.write("\n")
PY

set +e
if [[ "$TIMEOUT_MINUTES" -gt 0 ]] && command -v timeout >/dev/null 2>&1; then
  (cd "$REPO_ROOT" && timeout --signal=TERM --kill-after=30 "$((TIMEOUT_MINUTES * 60))" "$AGENT_CMD" run --auto --title "UI/UX audit ${ENV_NAME} ${RUN_ID}" --format json --file "$PROMPT_FILE" "Follow the attached audit prompt.") 2>&1 | tee "$SESSION_LOG"
  rc=${PIPESTATUS[0]}
else
  (cd "$REPO_ROOT" && "$AGENT_CMD" run --auto --title "UI/UX audit ${ENV_NAME} ${RUN_ID}" --format json --file "$PROMPT_FILE" "Follow the attached audit prompt.") 2>&1 | tee "$SESSION_LOG"
  rc=${PIPESTATUS[0]}
fi
set -e

python3 - "$RUN_META_FILE" "$rc" <<'PY'
import json
import sys
from datetime import datetime, timezone

path, rc = sys.argv[1], int(sys.argv[2])
with open(path, "r", encoding="utf-8") as f:
    obj = json.load(f)
obj["finished_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
obj["agent_exit_code"] = rc
if rc == 0:
    obj["status"] = "completed"
elif rc == 124:
    obj["status"] = "timed_out"
else:
    obj["status"] = "failed"
with open(path, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2)
    f.write("\n")
PY

if [[ $rc -ne 0 ]]; then
  log "agent session exited with code $rc (artifacts: $ARTIFACT_DIR)"
  exit "$rc"
fi

log "audit complete (artifacts: $ARTIFACT_DIR)"
exit 0
