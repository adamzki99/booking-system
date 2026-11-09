#!/usr/bin/env bash
#
# dev-server-agent.sh — controlled, audited SSH access to the dev server.
#
# Usage:
#   dev-ops/scripts/dev-server-agent.sh --self-check
#   dev-ops/scripts/dev-server-agent.sh --command "uptime"
#   dev-ops/scripts/dev-server-agent.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

HOST="${DEV_SERVER_HOST:-}"
PORT="${DEV_SERVER_PORT:-22}"
USER_NAME="${DEV_SERVER_USER:-${USER:-$(id -un)}}"
KEY="${DEV_SERVER_KEY:-${DEV_SERVER_KEY_PATH:-}}"
KNOWN_HOSTS="${DEV_SERVER_KNOWN_HOSTS:-}"
PASSWORD="${DEV_SERVER_PASSWORD:-}"
LOG_FILE="${DEV_SERVER_LOG_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/booking-system/dev-server-agent.jsonl}"
MODE="agent"
COMMAND=""
IMPACT=""

log() { printf '[dev-server-agent] %s\n' "$*"; }
die() { printf '[dev-server-agent] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  dev-server-agent.sh [target options] --self-check
  dev-server-agent.sh [target options] --command COMMAND [--impact TEXT]
  dev-server-agent.sh [target options]

Target options override DEV_SERVER_* environment variables:
  --host HOST          SSH host (default: DEV_SERVER_HOST; required)
  --user USER          SSH user (default: DEV_SERVER_USER or current user)
  --port PORT          SSH port (default: DEV_SERVER_PORT or 22)
  --key PATH           Private key (default: DEV_SERVER_KEY/KEY_PATH, then
                       ~/.ssh/id_ed25519 or ~/.ssh/id_rsa)
  --known-hosts PATH   Known-hosts file (default: OpenSSH's standard files)

Modes:
  --self-check, --dry-run  Validate local prerequisites without connecting
  --command COMMAND        Run one remote command and exit
  --impact TEXT            Human-readable impact for an impactful command
  -h, --help               Show this help

Password authentication uses DEV_SERVER_PASSWORD only (never a command-line
argument), requires sshpass, and prompts for confirmation. All potentially
impactful commands require interactive confirmation and default to denial.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) [[ $# -ge 2 ]] || die "--host requires a value"; HOST="$2"; shift 2 ;;
    --user) [[ $# -ge 2 ]] || die "--user requires a value"; USER_NAME="$2"; shift 2 ;;
    --port) [[ $# -ge 2 ]] || die "--port requires a value"; PORT="$2"; shift 2 ;;
    --key) [[ $# -ge 2 ]] || die "--key requires a value"; KEY="$2"; shift 2 ;;
    --known-hosts) [[ $# -ge 2 ]] || die "--known-hosts requires a value"; KNOWN_HOSTS="$2"; shift 2 ;;
    --command) [[ $# -ge 2 ]] || die "--command requires a value"; MODE="command"; COMMAND="$2"; shift 2 ;;
    --impact) [[ $# -ge 2 ]] || die "--impact requires a value"; IMPACT="$2"; shift 2 ;;
    --self-check|--dry-run) MODE="self-check"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

command -v ssh >/dev/null 2>&1 || die "ssh is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required for structured logging"
[[ -n "$HOST" ]] || die "DEV_SERVER_HOST or --host is required"
[[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]] || die "SSH port must be between 1 and 65535"
[[ -n "$USER_NAME" && ! "$USER_NAME" =~ [[:space:]] && "$USER_NAME" != -* ]] || die "invalid SSH user"
[[ ! "$HOST" =~ [[:space:]] && "$HOST" != -* ]] || die "invalid SSH host"

if [[ -n "$KEY" && (! -f "$KEY" || ! -r "$KEY") ]]; then
  die "SSH key is missing or unreadable: $KEY"
fi
if [[ -z "$KEY" ]]; then
  for candidate in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa"; do
    if [[ -f "$candidate" && -r "$candidate" ]]; then
      KEY="$candidate"
      break
    fi
  done
fi
if [[ -z "$KEY" && -z "$PASSWORD" ]]; then
  die "provide a readable DEV_SERVER_KEY, a default SSH key, or DEV_SERVER_PASSWORD"
fi
if [[ -z "$KEY" && -n "$PASSWORD" ]]; then
  command -v sshpass >/dev/null 2>&1 || die "sshpass is required for password authentication"
fi
if [[ -n "$KNOWN_HOSTS" && (! -f "$KNOWN_HOSTS" || ! -r "$KNOWN_HOSTS") ]]; then
  die "known-hosts file is missing or unreadable: $KNOWN_HOSTS"
fi

if [[ "$MODE" == "self-check" ]]; then
  auth="password"
  [[ -n "$KEY" ]] && auth="key"
  log "OK (no connection attempted)"
  printf 'host=%s\nuser=%s\nport=%s\nauth=%s\n' "$HOST" "$USER_NAME" "$PORT" "$auth"
  printf 'key=%s\n' "${KEY:-none}"
  printf 'known_hosts=%s\n' "${KNOWN_HOSTS:-OpenSSH default}"
  exit 0
fi

TARGET="$USER_NAME@$HOST"
CONTROL_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/booking-system/dev-server-ssh"
CONTROL_PATH="$CONTROL_DIR/control-%C"
ACTOR="${DEV_SERVER_ACTOR:-${USER:-$(id -un)}}"

emit_log() { # event, outcome, exit code (optional)
  local event="$1" outcome="$2" exit_code="${3:-}"
  mkdir -p "$(dirname "$LOG_FILE")"
  ACTION_EVENT="$event" ACTION_OUTCOME="$outcome" ACTION_EXIT_CODE="$exit_code" \
    ACTION_COMMAND="$COMMAND" ACTION_IMPACT="$IMPACT" ACTION_MODE="$MODE" \
    ACTION_TARGET="$TARGET" ACTION_ACTOR="$ACTOR" ACTION_CLASS="${CLASSIFICATION:-none}" \
    ACTION_PASSWORD="$PASSWORD" ACTION_KEY="$KEY" \
    python3 - "$LOG_FILE" <<'PY'
import datetime
import json
import os
import re
import sys

path = sys.argv[1]
command = os.environ.get("ACTION_COMMAND", "")
impact = os.environ.get("ACTION_IMPACT", "")
for secret in (os.environ.get("ACTION_PASSWORD", ""), os.environ.get("ACTION_KEY", "")):
    if secret:
        command = command.replace(secret, "[REDACTED]")
        impact = impact.replace(secret, "[REDACTED]")
pattern = re.compile(
    r"(?i)([A-Z0-9_]*(?:PASSWORD|PASSWD|TOKEN|SECRET|PRIVATE_KEY)[A-Z0-9_]*\s*=\s*)(\"[^\"]*\"|'[^']*'|[^\s;]+)"
)
command = pattern.sub(r"\1[REDACTED]", command)
impact = pattern.sub(r"\1[REDACTED]", impact)
exit_code = os.environ.get("ACTION_EXIT_CODE", "")
record = {
    "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
    "actor": os.environ.get("ACTION_ACTOR", "unknown"),
    "event": os.environ.get("ACTION_EVENT", ""),
    "outcome": os.environ.get("ACTION_OUTCOME", ""),
    "mode": os.environ.get("ACTION_MODE", ""),
    "target": os.environ.get("ACTION_TARGET", ""),
    "classification": os.environ.get("ACTION_CLASS", "none"),
    "command": command,
    "impact": impact,
    "exit_code": int(exit_code) if exit_code else None,
}
fd = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
os.chmod(path, 0o600)
with os.fdopen(fd, "a", encoding="utf-8") as stream:
    stream.write(json.dumps(record, ensure_ascii=False) + "\n")
PY
}

SSH_BASE=(ssh -p "$PORT"
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=yes
  -o ControlMaster=auto
  -o ControlPersist=10m
  -o "ControlPath=$CONTROL_PATH")
if [[ -n "$KEY" ]]; then
  SSH_BASE+=(-i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes)
fi
if [[ -n "$KNOWN_HOSTS" ]]; then
  SSH_BASE+=(-o "UserKnownHostsFile=$KNOWN_HOSTS")
fi

run_ssh() {
  if [[ -n "$KEY" ]]; then
    "${SSH_BASE[@]}" "$@"
  else
    SSHPASS="$PASSWORD" sshpass -e "${SSH_BASE[@]}" "$@"
  fi
}

confirm_password_authentication() {
  local reply
  [[ -z "$KEY" && -n "$PASSWORD" ]] || return 0
  [[ -r /dev/tty && -w /dev/tty ]] || return 1
  printf 'No SSH key is configured. Use password authentication for %s? [y/N] ' "$TARGET" > /dev/tty
  IFS= read -r reply < /dev/tty || return 1
  [[ "$reply" == "y" || "$reply" == "Y" || "$reply" == "yes" ]]
}

open_connection() {
  mkdir -p "$CONTROL_DIR"
  chmod 700 "$CONTROL_DIR"
  if run_ssh -O check "$TARGET" >/dev/null 2>&1; then
    return 0
  fi
  run_ssh -MNf "$TARGET"
}

command_allowed() {
  local allowed
  [[ -n "${DEV_SERVER_ALLOWED_COMMANDS:-}" ]] || return 0
  while IFS= read -r allowed || [[ -n "$allowed" ]]; do
    [[ -z "$allowed" || "$COMMAND" != "$allowed" ]] || return 0
  done <<< "$DEV_SERVER_ALLOWED_COMMANDS"
  return 1
}

classify_command() {
  local command="$1" word subcommand
  local i
  local -a words
  CLASSIFICATION="impactful"
  if [[ -z "$command" || "$command" == *';'* || "$command" == *'&'* \
    || "$command" == *'|'* || "$command" == *'`'* || "$command" == *'$'* \
    || "$command" == *'<'* || "$command" == *'>'* || "$command" == *$'\n'* \
    || "$command" == *$'\r'* || "$command" == *"'"* || "$command" == *'"'* \
    || "$command" == *\\* ]]; then
    return
  fi
  read -r -a words <<< "$command"
  [[ ${#words[@]} -gt 0 ]] || return
  case "${words[0]}" in
    uptime|whoami|hostname|pwd|date|id)
      [[ ${#words[@]} -ne 1 ]] || CLASSIFICATION="read-only"
      ;;
    uname|df|free|ps|ls|cat|head|tail|grep)
      CLASSIFICATION="read-only"
      ;;
    find)
      CLASSIFICATION="read-only"
      for word in "${words[@]}"; do
        case "$word" in
          -delete|-exec|-execdir|-ok|-okdir|-fls|-fprint|-fprint0|-fprintf)
            CLASSIFICATION="impactful"
            return
            ;;
        esac
      done
      ;;
    journalctl)
      CLASSIFICATION="read-only"
      for word in "${words[@]}"; do
        case "$word" in
          --vacuum-*|--rotate|--flush|--relinquish-var|--sync)
            CLASSIFICATION="impactful"
            return
            ;;
        esac
      done
      ;;
    systemctl)
      [[ ${#words[@]} -ge 2 ]] || return
      case "${words[1]}" in
        status|show|is-active|is-enabled|list-units|list-unit-files)
          CLASSIFICATION="read-only"
          ;;
      esac
      ;;
    docker)
      [[ ${#words[@]} -ge 2 ]] || return
      case "${words[1]}" in
        ps|logs|inspect|images|info|version)
          CLASSIFICATION="read-only"
          ;;
        compose)
          i=2
          while [[ $i -lt ${#words[@]} ]]; do
            case "${words[i]}" in
              -f|--file|-p|--project-name|--profile|--env-file|--project-directory|--ansi|--parallel|--progress)
                i=$((i + 2))
                ;;
              --no-ansi|--compatibility|--dry-run)
                i=$((i + 1))
                ;;
              *) break ;;
            esac
          done
          subcommand="${words[i]:-}"
          [[ "$subcommand" != "ps" && "$subcommand" != "logs" ]] || CLASSIFICATION="read-only"
          ;;
      esac
      ;;
    git)
      [[ ${#words[@]} -ge 2 ]] || return
      case "${words[1]}" in
        status|diff|log|show|rev-parse) CLASSIFICATION="read-only" ;;
      esac
      ;;
  esac
}

approve_command() {
  local reply
  if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    return 1
  fi
  if [[ -z "$IMPACT" ]]; then
    printf 'Intended impact (required): ' > /dev/tty
    IFS= read -r IMPACT < /dev/tty || return 1
  fi
  [[ -n "$IMPACT" ]] || return 1
  printf '\nPotentially impactful remote command:\n  %s\nIntended impact: %s\n' \
    "$COMMAND" "$IMPACT" > /dev/tty
  printf 'Execute this command? [y/N] ' > /dev/tty
  IFS= read -r reply < /dev/tty || return 1
  [[ "$reply" == "y" || "$reply" == "Y" || "$reply" == "yes" ]]
}

run_agent() {
  local prompt status
  [[ -t 0 && -t 1 ]] || die "interactive agent mode requires a terminal; use --command for non-interactive inspection"
  command -v opencode >/dev/null 2>&1 || die "opencode is required for interactive agent mode"
  emit_log session requested || die "failed to write action log; agent not started"
  if ! confirm_password_authentication; then
    emit_log authentication denied || true
    die "agent not started: password authentication requires explicit interactive confirmation"
  fi
  if ! open_connection; then
    emit_log session failed 1 || true
    die "unable to establish an SSH connection; see the SSH error above"
  fi
  if [[ -z "${DEV_SERVER_ACTOR:-}" ]]; then
    export DEV_SERVER_ACTOR="$ACTOR/opencode"
  fi
  prompt="$(cat <<EOF
The operator has explicitly requested the dev-server-ssh skill. Load it with the skill tool and follow it exactly.

Use $REPO_ROOT/dev-ops/scripts/dev-server-agent.sh --command COMMAND for every remote operation. Never invoke ssh, scp, sftp, or a remote shell directly. For each command, first show the operator the exact command and intended impact. Read-only inspection may proceed through the wrapper; every mutating, destructive, ambiguous, or otherwise impactful command must use --impact and receives explicit y/N approval through the controlling terminal. If approval is unavailable or intent is ambiguous, do not act. Do not request or use OpenCode --auto approval. Keep changes minimal, never delete data or volumes, never edit secrets in place, and reconcile any server change back into this repository through a reviewed pull request.
EOF
)"
  cd "$REPO_ROOT"
  set +e
  opencode --prompt "$prompt"
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    emit_log session succeeded "$status" || true
  else
    emit_log session failed "$status" || true
  fi
  return "$status"
}

print_redacted_file() {
  REDACT_PASSWORD="$PASSWORD" REDACT_KEY="$KEY" python3 - "$1" <<'PY'
import os
import sys

with open(sys.argv[1], "rb") as stream:
    data = stream.read()
for value in (os.environ.get("REDACT_PASSWORD", ""), os.environ.get("REDACT_KEY", "")):
    if value:
        data = data.replace(value.encode(), b"[REDACTED]")
sys.stdout.buffer.write(data)
PY
}

run_remote_command() {
  local stdout_file stderr_file status
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"
  chmod 600 "$stdout_file" "$stderr_file"
  set +e
  run_ssh "$TARGET" "$COMMAND" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  print_redacted_file "$stdout_file"
  print_redacted_file "$stderr_file" >&2
  if [[ $status -eq 0 ]]; then
    emit_log command succeeded "$status" || die "failed to write action log"
  else
    emit_log command failed "$status" || die "failed to write action log"
  fi
  rm -f "$stdout_file" "$stderr_file" || true
  return "$status"
}

if [[ "$MODE" == "agent" ]]; then
  run_agent
  exit $?
fi

[[ -n "$COMMAND" ]] || die "--command must not be empty"
classify_command "$COMMAND"
emit_log command requested || die "failed to write action log; command not executed"
if [[ -n "$PASSWORD" && ( "$COMMAND" == *"$PASSWORD"* || "$IMPACT" == *"$PASSWORD"* ) ]]; then
  emit_log command denied || true
  die "command not executed: configured secrets must not appear in commands or impact text"
fi
if ! command_allowed; then
  emit_log command denied || true
  die "command not executed: not present in DEV_SERVER_ALLOWED_COMMANDS"
fi
if [[ "$CLASSIFICATION" != "read-only" ]]; then
  if ! approve_command; then
    emit_log command denied || true
    die "command not executed: explicit interactive approval is required"
  fi
  emit_log approval approved || die "failed to write action log; command not executed"
fi
if ! confirm_password_authentication; then
  emit_log authentication denied || true
  die "command not executed: password authentication requires explicit interactive confirmation"
fi
if ! open_connection; then
  emit_log command failed 1 || true
  die "unable to establish an SSH connection; see the SSH error above"
fi
run_remote_command
