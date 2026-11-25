#!/usr/bin/env bash
#
# install-ui-audit-timer.sh - install or refresh the systemd user timer that
# runs the agent-driven Playwright UI/UX audit on a recurring schedule.
#
# Usage:
#   dev-ops/scripts/install-ui-audit-timer.sh [options]
#
# Options:
#   --env NAME          Target environment from environments.yaml (default: qa)
#   --timezone TZ       IANA timezone for the schedule (default: Europe/Stockholm)
#   --times HH[,HH...]  Local hours to run the audit (default: 02)
#   --script PATH       Audit script to run
#                       (default: /opt/booking-system-<env>/dev-ops/scripts/run-ui-audit.sh)
#   --unit-dir DIR      Where to write the unit files
#                       (default: ${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user)
#   --artifact-root DIR Artifact root passed to the audit script (optional)
#   --issue-filing      Enable GitHub issue filing for scheduled runs (default: disabled)
#   --no-issue-filing   Disable GitHub issue filing for scheduled runs (default)
#   --dry-run           Print the units and commands without changing anything
#   --no-enable         Write the unit files but do not enable/start the timer
#   --no-linger         Do not require user lingering (timer stops at logout)
#   -h, --help          Show this help
#
# Dev/QA only. Production environment names are rejected.

set -euo pipefail

ENV_NAME="qa"
TIMEZONE="Europe/Stockholm"
HOURS="02"
AUDIT_SCRIPT=""
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
ARTIFACT_ROOT=""
ISSUE_FILING=0
DRY_RUN=0
ENABLE=1
LINGER=1

log() { printf '[install-ui-audit-timer] %s\n' "$*"; }
die() { printf '[install-ui-audit-timer] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) [[ $# -ge 2 ]] || die "--env needs a value"; ENV_NAME="$2"; shift 2 ;;
    --timezone) [[ $# -ge 2 ]] || die "--timezone needs a value"; TIMEZONE="$2"; shift 2 ;;
    --times) [[ $# -ge 2 ]] || die "--times needs a value"; HOURS="$2"; shift 2 ;;
    --script) [[ $# -ge 2 ]] || die "--script needs a value"; AUDIT_SCRIPT="$2"; shift 2 ;;
    --unit-dir) [[ $# -ge 2 ]] || die "--unit-dir needs a value"; UNIT_DIR="$2"; shift 2 ;;
    --artifact-root) [[ $# -ge 2 ]] || die "--artifact-root needs a value"; ARTIFACT_ROOT="$2"; shift 2 ;;
    --issue-filing) ISSUE_FILING=1; shift ;;
    --no-issue-filing) ISSUE_FILING=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-enable) ENABLE=0; shift ;;
    --no-linger) LINGER=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

[[ "$ENV_NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "invalid environment name: $ENV_NAME"
[[ "${ENV_NAME,,}" != *prod* ]] || die "production environments are not allowed"
[[ "$TIMEZONE" =~ ^[A-Za-z0-9_+.-]+(/[A-Za-z0-9_+.-]+)*$ ]] || die "invalid IANA timezone: $TIMEZONE"
[[ "$TIMEZONE" != *..* ]] || die "invalid IANA timezone: $TIMEZONE"
[[ -f "/usr/share/zoneinfo/$TIMEZONE" ]] || die "unknown IANA timezone: $TIMEZONE"

normalized_hours=""
IFS=',' read -r -a hour_values <<< "$HOURS"
for hour in "${hour_values[@]}"; do
  [[ "$hour" =~ ^[0-9]{1,2}$ ]] || die "invalid hour in --times: $hour"
  (( 10#$hour <= 23 )) || die "hour out of range in --times: $hour"
  printf -v formatted '%02d' "$((10#$hour))"
  normalized_hours+="${normalized_hours:+,}${formatted}"
done
[[ -n "$normalized_hours" ]] || die "--times must contain at least one hour"

ON_CALENDAR="*-*-* ${normalized_hours}:00:00 ${TIMEZONE}"
if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze calendar "$ON_CALENDAR" >/dev/null 2>&1 \
    || die "systemd rejected OnCalendar expression: $ON_CALENDAR"
fi

if [[ -z "$AUDIT_SCRIPT" ]]; then
  AUDIT_SCRIPT="/opt/booking-system-${ENV_NAME}/dev-ops/scripts/run-ui-audit.sh"
  [[ -x "$AUDIT_SCRIPT" || -f "$AUDIT_SCRIPT" ]] || die "audit script not found: $AUDIT_SCRIPT; run from a provisioned checkout or pass --script"
fi
[[ "$AUDIT_SCRIPT" != *[[:space:]]* ]] || die "audit script path must not contain whitespace: $AUDIT_SCRIPT"
if [[ "$AUDIT_SCRIPT" != /* ]]; then
  AUDIT_SCRIPT="$PWD/$AUDIT_SCRIPT"
fi
AUDIT_SCRIPT_DIR="$(cd -- "$(dirname -- "$AUDIT_SCRIPT")" 2>/dev/null && pwd)" \
  || die "audit script directory not found: $AUDIT_SCRIPT"
AUDIT_SCRIPT="$AUDIT_SCRIPT_DIR/$(basename -- "$AUDIT_SCRIPT")"
[[ -f "$AUDIT_SCRIPT" ]] || die "audit script is not readable: $AUDIT_SCRIPT"
WORK_DIR="$(cd -- "$AUDIT_SCRIPT_DIR/../.." && pwd)" \
  || die "cannot resolve repository root from audit script: $AUDIT_SCRIPT"

SERVICE_NAME="booking-${ENV_NAME}-ui-audit.service"
TIMER_NAME="booking-${ENV_NAME}-ui-audit.timer"
SERVICE_PATH="$UNIT_DIR/$SERVICE_NAME"
TIMER_PATH="$UNIT_DIR/$TIMER_NAME"

issue_flag="--no-issue-filing"
[[ "$ISSUE_FILING" -eq 1 ]] && issue_flag="--issue-filing"

service_content() {
  local env_line=""
  if [[ -n "$ARTIFACT_ROOT" ]]; then
    [[ "$ARTIFACT_ROOT" != *[[:space:]]* ]] || die "artifact root path must not contain whitespace: $ARTIFACT_ROOT"
    env_line="Environment=UI_AUDIT_ARTIFACT_ROOT=${ARTIFACT_ROOT}"
  fi
  cat <<EOF
[Unit]
Description=Run agent-driven Playwright UI/UX audit (${ENV_NAME})
Documentation=file://${AUDIT_SCRIPT}
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=${WORK_DIR}
# The audit may need Docker and a running QA environment.
ExecStartPre=/bin/bash -c 'for i in {1..60}; do docker info >/dev/null 2>&1 && exit 0; sleep 5; done; exit 1'
${env_line}
ExecStart=${AUDIT_SCRIPT} --env ${ENV_NAME} --local ${issue_flag}
# Agent-driven exploration can take significant time.
TimeoutStartSec=120min
Nice=10
EOF
}

timer_content() {
  cat <<EOF
[Unit]
Description=Scheduled agent-driven UI/UX audit (${ENV_NAME}, ${TIMEZONE})

[Timer]
OnCalendar=${ON_CALENDAR}
Persistent=true
AccuracySec=1min
Unit=${SERVICE_NAME}

[Install]
WantedBy=timers.target
EOF
}

changed=0
write_unit() {
  local path="$1" content="$2"
  if [[ -f "$path" ]] && [[ "$(cat -- "$path")" == "$content" ]]; then
    log "unchanged: $path"
    changed=0
    return 0
  fi
  printf '%s\n' "$content" > "$path"
  log "wrote: $path"
  changed=1
}

setup_user_bus() {
  local uid
  uid="$(id -u)"
  if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$uid" ]]; then
    export XDG_RUNTIME_DIR="/run/user/$uid"
  fi
  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -n "${XDG_RUNTIME_DIR:-}" && -S "$XDG_RUNTIME_DIR/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
  fi
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "# $SERVICE_PATH"
  service_content
  echo
  echo "# $TIMER_PATH"
  timer_content
  echo
  echo "# commands"
  if [[ "$ENABLE" -eq 1 ]]; then
    if [[ "$LINGER" -eq 1 ]]; then
      echo "loginctl enable-linger $(id -un)"
    fi
    echo "systemctl --user daemon-reload"
    echo "systemctl --user enable $TIMER_NAME"
    echo "systemctl --user restart $TIMER_NAME   # start, or re-arm after a unit change"
    echo "systemctl --user list-timers $TIMER_NAME"
  else
    echo "# --no-enable: unit files only"
  fi
  exit 0
fi

mkdir -p "$UNIT_DIR"
write_unit "$SERVICE_PATH" "$(service_content)"
service_changed=$changed
write_unit "$TIMER_PATH" "$(timer_content)"
timer_changed=$changed

if [[ "$ENABLE" -eq 1 ]]; then
  setup_user_bus
  user_name="$(id -un)"
  if [[ "$LINGER" -eq 1 ]]; then
    if [[ "$(loginctl show-user "$user_name" -p Linger --value 2>/dev/null || true)" != "yes" ]]; then
      loginctl enable-linger "$user_name" \
        || die "could not enable user lingering; run 'sudo loginctl enable-linger $user_name' or rerun with --no-linger"
    fi
  else
    log "skipping linger; the timer stops when the user logs out"
  fi
  systemctl --user daemon-reload
  systemctl --user enable "$TIMER_NAME"
  if [[ "$service_changed" -eq 1 || "$timer_changed" -eq 1 ]]; then
    systemctl --user restart "$TIMER_NAME"
  else
    systemctl --user start "$TIMER_NAME"
  fi
  systemctl --user list-timers "$TIMER_NAME" --no-pager || true
else
  log "written; timer not enabled (--no-enable)"
fi
