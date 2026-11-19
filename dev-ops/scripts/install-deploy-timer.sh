#!/usr/bin/env bash
#
# install-deploy-timer.sh — install or refresh the systemd user timer that
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
#   -h, --help          Show this help

set -euo pipefail

ENV_NAME="qa"
TIMEZONE="Europe/Stockholm"
HOURS="00,12"
DEPLOY_SCRIPT=""
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
DRY_RUN=0
ENABLE=1

log() { printf '[install-deploy-timer] %s\n' "$*"; }
die() { printf '[install-deploy-timer] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

[[ "$ENV_NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "invalid environment name: $ENV_NAME"
[[ -e "/usr/share/zoneinfo/$TIMEZONE" ]] || die "unknown IANA timezone: $TIMEZONE"

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

if [[ -z "$DEPLOY_SCRIPT" ]]; then
  DEPLOY_SCRIPT="/opt/booking-system-${ENV_NAME}/dev-ops/scripts/deploy-environment.sh"
fi
[[ -x "$DEPLOY_SCRIPT" ]] || die "deploy script is not executable: $DEPLOY_SCRIPT"
DEPLOY_SCRIPT_DIR="$(cd -- "$(dirname -- "$DEPLOY_SCRIPT")" && pwd)"
WORK_DIR="$(cd -- "$DEPLOY_SCRIPT_DIR/../.." && pwd)"

ON_CALENDAR="*-*-* ${normalized_hours}:00:00 ${TIMEZONE}"
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

write_unit() {
  local path="$1" content="$2"
  if [[ -f "$path" ]] && [[ "$(cat -- "$path")" == "$content" ]]; then
    log "unchanged: $path"
    return 0
  fi
  printf '%s\n' "$content" > "$path"
  log "wrote: $path"
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
    echo "loginctl enable-linger $(id -un)"
    echo "systemctl --user daemon-reload"
    echo "systemctl --user enable --now $TIMER_NAME"
    echo "systemctl --user list-timers $TIMER_NAME"
  else
    echo "# --no-enable: unit files only"
  fi
  exit 0
fi

mkdir -p "$UNIT_DIR"
write_unit "$SERVICE_PATH" "$(service_content)"
write_unit "$TIMER_PATH" "$(timer_content)"

if [[ "$ENABLE" -eq 1 ]]; then
  setup_user_bus
  user_name="$(id -un)"
  if [[ "$(loginctl show-user "$user_name" -p Linger --value 2>/dev/null || true)" != "yes" ]]; then
    if ! loginctl enable-linger "$user_name"; then
      log "WARNING: could not enable linger; the timer stops when the user logs out"
    fi
  fi
  systemctl --user daemon-reload
  systemctl --user enable --now "$TIMER_NAME"
  systemctl --user list-timers "$TIMER_NAME" --no-pager || true
else
  log "written; timer not enabled (--no-enable)"
fi
