#!/usr/bin/env bash
#
# install-deploy-timer.sh - install or refresh the systemd user timer that
# deploys one environment twice daily.
#
# The dev host runs UTC and Debian cron does not implement CRON_TZ, so a plain
# crontab cannot express "00:00 and 12:00 Europe/Stockholm" across DST changes.
# systemd's OnCalendar accepts an IANA timezone, so the schedule stays at the
# owner's local time all year.
#
# Usage:
#   dev-ops/scripts/install-deploy-timer.sh [options]
#
# Options:
#   --env NAME          Environment from environments.yaml (default: qa)
#   --timezone TZ       IANA timezone for the schedule (default: Europe/Stockholm)
#   --times HH,HH       Local hours to deploy (default: 00,12)
#   --script PATH       Deploy script to run
#                       (default: /opt/booking-system-<env>/dev-ops/scripts/deploy-environment.sh)
#   --unit-dir DIR      Where to write the unit files
#                       (default: ${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user)
#   --dry-run           Print the units and commands without changing anything
#   --no-enable         Write the unit files but do not enable/start the timer
#   --no-linger         Do not require user lingering (timer stops at logout)
#   -h, --help          Show this help

set -euo pipefail

ENV_NAME="qa"
TIMEZONE="Europe/Stockholm"
HOURS="00,12"
DEPLOY_SCRIPT=""
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
DRY_RUN=0
ENABLE=1
LINGER=1

log() { printf '[install-deploy-timer] %s\n' "$*"; }
die() { printf '[install-deploy-timer] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) [[ $# -ge 2 ]] || die "--env needs a value"; ENV_NAME="$2"; shift 2 ;;
    --timezone) [[ $# -ge 2 ]] || die "--timezone needs a value"; TIMEZONE="$2"; shift 2 ;;
    --times) [[ $# -ge 2 ]] || die "--times needs a value"; HOURS="$2"; shift 2 ;;
    --script) [[ $# -ge 2 ]] || die "--script needs a value"; DEPLOY_SCRIPT="$2"; shift 2 ;;
    --unit-dir) [[ $# -ge 2 ]] || die "--unit-dir needs a value"; UNIT_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-enable) ENABLE=0; shift ;;
    --no-linger) LINGER=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

[[ "$ENV_NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "invalid environment name: $ENV_NAME"
[[ "$TIMEZONE" =~ ^[A-Za-z0-9_+.-]+(/[A-Za-z0-9_+.-]+)*$ ]] || die "invalid IANA timezone: $TIMEZONE"
[[ "$TIMEZONE" != *..* ]] || die "invalid IANA timezone: $TIMEZONE"
[[ -f "/usr/share/zoneinfo/$TIMEZONE" ]] || die "unknown IANA timezone: $TIMEZONE"

# Normalize "0,12" / "00,12" to systemd's two-digit hour form.
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

if [[ -z "$DEPLOY_SCRIPT" ]]; then
  DEPLOY_SCRIPT="/opt/booking-system-${ENV_NAME}/dev-ops/scripts/deploy-environment.sh"
  [[ -x "$DEPLOY_SCRIPT" ]] || die "deploy script not found: $DEPLOY_SCRIPT; run 'dev-ops/scripts/deploy-environment.sh ${ENV_NAME}' once to provision the checkout, or pass --script"
fi
[[ "$DEPLOY_SCRIPT" != *[[:space:]]* ]] || die "deploy script path must not contain whitespace: $DEPLOY_SCRIPT"
if [[ "$DEPLOY_SCRIPT" != /* ]]; then
  DEPLOY_SCRIPT="$PWD/$DEPLOY_SCRIPT"
fi
DEPLOY_SCRIPT_DIR="$(cd -- "$(dirname -- "$DEPLOY_SCRIPT")" 2>/dev/null && pwd)" \
  || die "deploy script directory not found: $DEPLOY_SCRIPT"
DEPLOY_SCRIPT="$DEPLOY_SCRIPT_DIR/$(basename -- "$DEPLOY_SCRIPT")"
[[ -x "$DEPLOY_SCRIPT" ]] || die "deploy script is not executable: $DEPLOY_SCRIPT"
WORK_DIR="$(cd -- "$DEPLOY_SCRIPT_DIR/../.." && pwd)" \
  || die "cannot resolve repository root from deploy script: $DEPLOY_SCRIPT"

SERVICE_NAME="booking-${ENV_NAME}-deploy.service"
TIMER_NAME="booking-${ENV_NAME}-deploy.timer"
SERVICE_PATH="$UNIT_DIR/$SERVICE_NAME"
TIMER_PATH="$UNIT_DIR/$TIMER_NAME"

service_content() {
  cat <<EOF
[Unit]
Description=Deploy the ${ENV_NAME} environment from its branch
Documentation=file://${DEPLOY_SCRIPT}
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=${WORK_DIR}
# A lingering user timer can start before the Docker daemon is ready.
ExecStartPre=/bin/bash -c 'for i in {1..120}; do docker info >/dev/null 2>&1 && exit 0; sleep 5; done; exit 1'
ExecStart=${DEPLOY_SCRIPT} ${ENV_NAME}
# Docker build plus the two-minute health check need more than the default.
TimeoutStartSec=45min
Nice=10
EOF
}

timer_content() {
  cat <<EOF
[Unit]
Description=Twice-daily ${ENV_NAME} deployment (${TIMEZONE})

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
