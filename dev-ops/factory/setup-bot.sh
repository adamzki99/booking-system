#!/usr/bin/env bash
#
# setup-bot.sh - guided setup for running the software factory as a GitHub App.
#
# The script creates a private environment file, installs a dedicated Python
# environment, configures bot attribution for gh and Git, and installs an
# idempotent cron entry. It never prints the App private key or access token.
#
# Usage:
#   dev-ops/factory/setup-bot.sh [options]
#
# Options:
#   --app-id ID              GitHub App id (required in non-interactive mode).
#   --private-key FILE       Downloaded App private key PEM. Defaults to the
#                            existing key in the config directory.
#   --repo OWNER/REPO        GitHub repository (default: origin remote).
#   --trusted-logins LIST    Comma/space separated human logins allowed to drive
#                            the factory (default: repository owner).
#   --schedule CRON          Five-field cron expression (default: 0 * * * *).
#   --config-dir DIR         Private config directory.
#   --worktree DIR           Isolated factory worktree.
#   --session-timeout SEC    Per-session timeout (default: 3000).
#   --container-mode 0|1     Enable the bwrap sandbox when available.
#   --on-usage-filled MODE   backup|skip|fail (default: backup).
#   --max-fix-sessions N     Maximum fix sessions per tick (default: 1).
#   --no-cron                Write config but do not install a cron entry.
#   --skip-dependencies      Use the current Python instead of creating a venv.
#   --skip-validation        Do not run tick.sh --dry-run before installing cron.
#   --non-interactive        Use supplied values and defaults without prompting.
#   --dry-run                Print the plan without writing or contacting GitHub.
#   -h, --help               Show this help.

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
TICK_SCRIPT="$SCRIPT_DIR/tick.sh"
MINT_SCRIPT="$SCRIPT_DIR/lib/mint_github_app_token.py"
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/booking-system-factory"
VENV_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/booking-system-factory/venv"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/factory"
KEY_FILE="$CONFIG_DIR/github-app.pem"
ENV_FILE="$CONFIG_DIR/factory.env"
WRAPPER_FILE="$CONFIG_DIR/run-tick.sh"
LOG_FILE="$STATE_DIR/tick.log"
WORKTREE="${REPO_ROOT}-factory-worktree"

APP_ID=""
KEY_SOURCE=""
REPO=""
TRUSTED_LOGINS=""
SCHEDULE="0 * * * *"
SESSION_TIMEOUT="3000"
CONTAINER_MODE="0"
ON_USAGE_FILLED="backup"
MAX_FIX_SESSIONS="1"
INSTALL_CRON=1
SKIP_DEPENDENCIES=0
SKIP_VALIDATION=0
NON_INTERACTIVE=0
DRY_RUN=0
PYTHON_BIN="${PYTHON_BIN:-python3}"
APP_TOKEN=""
KEY_TMP=""
CRON_TMP=""

CRON_BEGIN="# >>> booking-system-factory >>>"
CRON_END="# <<< booking-system-factory <<<"

cleanup() {
  unset APP_TOKEN
  [[ -z "$KEY_TMP" ]] || rm -f -- "$KEY_TMP"
  [[ -z "$CRON_TMP" ]] || rm -f -- "$CRON_TMP"
}
trap cleanup EXIT

log() { printf '[factory-setup] %s\n' "$*"; }
die() { printf '[factory-setup] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

need_value() {
  [[ $# -ge 2 ]] || die "$1 needs a value"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

prompt_value() {
  local label="$1" default="$2" value=""
  if [[ -t 0 ]]; then
    if [[ -n "$default" ]]; then
      read -r -p "$label [$default]: " value || die "could not read $label"
    else
      read -r -p "$label: " value || die "could not read $label"
    fi
    printf '%s' "${value:-$default}"
  else
    [[ -n "$default" ]] || die "$label is required in non-interactive mode"
    printf '%s' "$default"
  fi
}

prompt_yes_no() {
  local label="$1" default="$2" value=""
  if [[ -t 0 ]]; then
    read -r -p "$label [${default}]: " value || die "could not read $label"
    value="${value:-$default}"
  else
    value="$default"
  fi
  case "${value,,}" in
    y|yes) printf 'yes' ;;
    n|no) printf 'no' ;;
    *) die "answer yes or no" ;;
  esac
}

expand_path() {
  local path="$1"
  # The literal prefix is intentional; expansion is handled manually below.
  # shellcheck disable=SC2088
  if [[ "${path:0:2}" == "~/" ]]; then
    path="$HOME/${path:2}"
  elif [[ "$path" == "~" ]]; then
    path="$HOME"
  fi
  [[ "$path" == /* ]] || path="$PWD/$path"
  printf '%s' "$path"
}

canonical_path() {
  local path="$1"
  path="$(expand_path "$path")"
  realpath -m -- "$path"
}

detect_repo() {
  local remote owner_repo
  remote="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  if [[ "$remote" =~ github\.com[:/]([^/]+)/([^/]+) ]]; then
    owner_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    printf '%s' "${owner_repo%.git}"
  fi
}

normalize_logins() {
  local raw="$1" login normalized=""
  local -a logins=()
  raw="${raw//,/ }"
  read -r -a logins <<< "$raw"
  [[ ${#logins[@]} -gt 0 ]] || die "at least one trusted login is required"
  for login in "${logins[@]}"; do
    [[ "$login" =~ ^[A-Za-z0-9_-]+(\[bot\])?$ ]] \
      || die "invalid trusted GitHub login: $login"
    normalized+="${normalized:+,}$login"
  done
  printf '%s' "$normalized"
}

validate_schedule() {
  local value="$1" field
  local -a fields=()
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] \
    || die "cron schedule must be a single line"
  read -r -a fields <<< "$value"
  [[ ${#fields[@]} -eq 5 ]] || die "cron schedule must have exactly five fields"
  for field in "${fields[@]}"; do
    [[ "$field" =~ ^[A-Za-z0-9*/,-]+$ ]] \
      || die "invalid cron schedule field: $field"
  done
}

shell_assign() {
  printf 'export %s=%q\n' "$1" "$2"
}

cron_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

cron_escape_percent() {
  local value="$1"
  printf '%s' "${value//%/\\%}"
}

write_atomic() {
  local path="$1" mode="$2" content="$3" tmp
  tmp="$(mktemp "$(dirname -- "$path")/.$(basename -- "$path").XXXXXX")"
  printf '%s\n' "$content" > "$tmp"
  chmod "$mode" "$tmp"
  mv -f -- "$tmp" "$path"
}

print_plan() {
  log "Setup plan"
  printf '  Repository: %s\n' "$REPO"
  printf '  Config directory: %s\n' "$CONFIG_DIR"
  printf '  Private key: %s\n' "$KEY_FILE"
  printf '  Python environment: %s\n' "$VENV_DIR"
  printf '  Factory worktree: %s\n' "$WORKTREE"
  printf '  Trusted logins: %s\n' "$TRUSTED_LOGINS"
  printf '  Session timeout: %s seconds\n' "$SESSION_TIMEOUT"
  printf '  bwrap sandbox: %s\n' "$CONTAINER_MODE"
  if [[ "$INSTALL_CRON" == 1 ]]; then
    printf '  Cron schedule: %s (host local time)\n' "$SCHEDULE"
    printf '  Cron command: %s %s >> %s 2>&1\n' \
      "$SCHEDULE" "$(cron_quote "$WRAPPER_FILE")" "$(cron_quote "$LOG_FILE")"
  else
    printf '  Cron: not installed\n'
  fi
}

install_cron() {
  local existing new_content tmp err_file read_rc read_err=""
  err_file="$(mktemp)"
  set +e
  existing="$(LC_ALL=C crontab -l 2>"$err_file")"
  read_rc=$?
  set -e
  if [[ "$read_rc" -ne 0 ]]; then
    read_err="$(cat "$err_file" 2>/dev/null || true)"
    if [[ -n "$read_err" && "$read_err" != *"no crontab"* ]]; then
      rm -f -- "$err_file"
      die "could not read the current crontab: $read_err"
    fi
    existing=""
  fi
  rm -f -- "$err_file"

  new_content="$(printf '%s\n' "$existing" | awk -v begin="$CRON_BEGIN" -v end="$CRON_END" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ')"

  if [[ -n "$new_content" ]]; then
    new_content+=$'\n'
  fi
  new_content+="$CRON_BEGIN"$'\n'
  new_content+="$(cron_escape_percent "$SCHEDULE $(cron_quote "$WRAPPER_FILE") >> $(cron_quote "$LOG_FILE") 2>&1")"$'\n'
  new_content+="$CRON_END"

  if [[ "$existing" == "$new_content" ]]; then
    log "cron entry unchanged"
    return 0
  fi

  CRON_TMP="$(mktemp)"
  printf '%s\n' "$new_content" > "$CRON_TMP"
  if ! crontab - < "$CRON_TMP"; then
    die "could not install crontab; config files were left in place"
  fi
  rm -f -- "$CRON_TMP"
  CRON_TMP=""
  log "installed cron entry"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-id) need_value "$@"; APP_ID="$2"; shift 2 ;;
    --private-key) need_value "$@"; KEY_SOURCE="$2"; shift 2 ;;
    --repo) need_value "$@"; REPO="$2"; shift 2 ;;
    --trusted-logins) need_value "$@"; TRUSTED_LOGINS="$2"; shift 2 ;;
    --schedule) need_value "$@"; SCHEDULE="$2"; shift 2 ;;
    --config-dir) need_value "$@"; CONFIG_DIR="$2"; shift 2 ;;
    --worktree) need_value "$@"; WORKTREE="$2"; shift 2 ;;
    --session-timeout) need_value "$@"; SESSION_TIMEOUT="$2"; shift 2 ;;
    --container-mode) need_value "$@"; CONTAINER_MODE="$2"; shift 2 ;;
    --on-usage-filled) need_value "$@"; ON_USAGE_FILLED="$2"; shift 2 ;;
    --max-fix-sessions) need_value "$@"; MAX_FIX_SESSIONS="$2"; shift 2 ;;
    --no-cron) INSTALL_CRON=0; shift ;;
    --skip-dependencies) SKIP_DEPENDENCIES=1; shift ;;
    --skip-validation) SKIP_VALIDATION=1; shift ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

CONFIG_DIR="$(expand_path "$CONFIG_DIR")"
VENV_DIR="$(expand_path "$VENV_DIR")"
WORKTREE="$(expand_path "$WORKTREE")"
LOG_FILE="$(expand_path "$LOG_FILE")"
KEY_FILE="$CONFIG_DIR/github-app.pem"
ENV_FILE="$CONFIG_DIR/factory.env"
WRAPPER_FILE="$CONFIG_DIR/run-tick.sh"

[[ -n "$REPO" ]] || REPO="$(detect_repo)"
[[ -n "$TRUSTED_LOGINS" ]] || TRUSTED_LOGINS="${REPO%%/*}"
if [[ -z "$KEY_SOURCE" && -f "$KEY_FILE" ]]; then
  KEY_SOURCE="$KEY_FILE"
fi

if [[ "$NON_INTERACTIVE" == 0 ]]; then
  cat <<'INTRO'

This script configures the software factory to act as a GitHub App bot.

Before continuing:
1. Create a GitHub App at https://github.com/settings/apps.
2. Install it on this repository only.
3. Grant Contents, Issues, and Pull requests read/write, plus Actions,
   Checks, and Metadata read. Do not grant Workflows or Administration.
4. Download the App private key PEM.

INTRO
  APP_ID="$(prompt_value "GitHub App id" "$APP_ID")"
  KEY_SOURCE="$(prompt_value "Private key PEM path" "$KEY_SOURCE")"
  REPO="$(prompt_value "GitHub repository" "$REPO")"
  TRUSTED_LOGINS="$(prompt_value "Trusted human GitHub login(s)" "$TRUSTED_LOGINS")"
  SCHEDULE="$(prompt_value "Cron schedule" "$SCHEDULE")"
  CONFIG_DIR="$(prompt_value "Config directory" "$CONFIG_DIR")"
  WORKTREE="$(prompt_value "Factory worktree" "$WORKTREE")"
  SESSION_TIMEOUT="$(prompt_value "Session timeout seconds" "$SESSION_TIMEOUT")"
  if [[ "$(prompt_yes_no "Enable bwrap sandbox when available" "no")" == "yes" ]]; then
    CONTAINER_MODE=1
  fi
  if [[ "$(prompt_yes_no "Install the cron entry" "yes")" == "no" ]]; then
    INSTALL_CRON=0
  fi
fi

[[ "$APP_ID" =~ ^[0-9]+$ ]] || die "GitHub App id must be numeric"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "invalid repository: $REPO"
[[ "$SESSION_TIMEOUT" =~ ^[0-9]+$ ]] \
  || die "session timeout must be a non-negative integer"
[[ "$MAX_FIX_SESSIONS" =~ ^[0-9]+$ ]] || die "max fix sessions must be a non-negative integer"
SESSION_TIMEOUT=$((10#$SESSION_TIMEOUT))
MAX_FIX_SESSIONS=$((10#$MAX_FIX_SESSIONS))
[[ "$SESSION_TIMEOUT" -gt 0 && "$SESSION_TIMEOUT" -le 3300 ]] \
  || die "session timeout must be between 1 and 3300 seconds to leave margin before the App token expires"
case "$CONTAINER_MODE" in 0|1) ;; *) die "container mode must be 0 or 1" ;; esac
case "$ON_USAGE_FILLED" in backup|skip|fail) ;; *) die "invalid usage mode: $ON_USAGE_FILLED" ;; esac
validate_schedule "$SCHEDULE"
TRUSTED_LOGINS="$(normalize_logins "$TRUSTED_LOGINS")"
need_cmd realpath

CONFIG_DIR="$(canonical_path "$CONFIG_DIR")"
VENV_DIR="$(canonical_path "$VENV_DIR")"
WORKTREE="$(canonical_path "$WORKTREE")"
LOG_FILE="$(canonical_path "$LOG_FILE")"
KEY_FILE="$CONFIG_DIR/github-app.pem"
ENV_FILE="$CONFIG_DIR/factory.env"
WRAPPER_FILE="$CONFIG_DIR/run-tick.sh"
[[ -n "$KEY_SOURCE" ]] || die "private key path is required (use --private-key)"
KEY_SOURCE="$(canonical_path "$KEY_SOURCE")"

for path in "$CONFIG_DIR" "$VENV_DIR" "$WORKTREE" "$LOG_FILE"; do
  [[ "$path" != *$'\n'* ]] || die "runtime paths must not contain newlines"
  [[ "$path" != "$REPO_ROOT" && "$path" != "$REPO_ROOT/"* ]] \
    || die "runtime paths must be outside the repository checkout: $path"
done
[[ "$WORKTREE" != "$REPO_ROOT" ]] || die "factory worktree must differ from the primary checkout"
[[ -s "$KEY_SOURCE" ]] || die "private key not found or empty: $KEY_SOURCE"
[[ "$(head -n 1 -- "$KEY_SOURCE")" == *"PRIVATE KEY-----" ]] \
  || die "private key does not look like a PEM private key: $KEY_SOURCE"

print_plan
if [[ "$DRY_RUN" == 1 ]]; then
  log "dry run: no files written and no GitHub requests made"
  exit 0
fi

need_cmd git
need_cmd gh
need_cmd opencode
need_cmd flock
need_cmd timeout
if [[ "$INSTALL_CRON" == 1 ]]; then
  need_cmd crontab
fi
if [[ "$CONTAINER_MODE" == 1 ]] && ! command -v bwrap >/dev/null 2>&1; then
  log "warning: bwrap is unavailable; tick will fall back to host mode"
fi

install -d -m 700 "$CONFIG_DIR" "$(dirname -- "$LOG_FILE")"

if [[ "$KEY_SOURCE" != "$KEY_FILE" ]]; then
  KEY_TMP="$(mktemp "$CONFIG_DIR/.github-app.pem.XXXXXX")"
  cat -- "$KEY_SOURCE" > "$KEY_TMP"
  chmod 600 "$KEY_TMP"
  mv -f -- "$KEY_TMP" "$KEY_FILE"
  KEY_TMP=""
else
  chmod 600 "$KEY_FILE"
fi
log "stored private key with mode 0600"

if [[ "$SKIP_DEPENDENCIES" == 0 ]]; then
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    log "creating Python environment at $VENV_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR" \
      || die "could not create venv; install python3-venv and retry"
  fi
  PYTHON_BIN="$VENV_DIR/bin/python"
  "$PYTHON_BIN" -m pip install --disable-pip-version-check -r "$REQUIREMENTS_FILE"
else
  log "skipping Python environment creation"
fi
"$PYTHON_BIN" -c 'import jwt, yaml' \
  || die "PyJWT and PyYAML are required; rerun without --skip-dependencies"

if ! APP_TOKEN="$("$PYTHON_BIN" "$MINT_SCRIPT" \
  --app-id "$APP_ID" \
  --key-file "$KEY_FILE" \
  --repo "$REPO" \
  --repo-root "$REPO_ROOT")"; then
  die "could not mint a GitHub App installation token; check the App id, key, and repository installation"
fi
[[ -n "$APP_TOKEN" ]] || die "GitHub App returned an empty installation token"

if ! APP_SLUG="$("$PYTHON_BIN" "$MINT_SCRIPT" \
  --app-id "$APP_ID" \
  --key-file "$KEY_FILE" \
  --print-app-slug)"; then
  die "could not read the GitHub App slug"
fi
[[ "$APP_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "GitHub App returned an invalid slug"
BOT_LOGIN="${APP_SLUG}[bot]"
if ! BOT_ID="$(GH_TOKEN="$APP_TOKEN" gh api "users/$BOT_LOGIN" --jq '.id')"; then
  die "could not read the GitHub App bot user id"
fi
[[ "$BOT_ID" =~ ^[0-9]+$ ]] || die "GitHub App returned an invalid bot user id"
if ! GH_TOKEN="$APP_TOKEN" gh repo view "$REPO" --json nameWithOwner --jq '.nameWithOwner' >/dev/null; then
  die "the GitHub App cannot access $REPO; install it on this repository and retry"
fi
REPO_OWNER="${REPO%%/*}"
if ! REPO_OWNER_TYPE="$(GH_TOKEN="$APP_TOKEN" gh api "repos/$REPO" --jq '.owner.type')"; then
  die "could not determine the repository owner type"
fi
if [[ "$REPO_OWNER_TYPE" == "Organization" ]]; then
  [[ "$TRUSTED_LOGINS" != "$REPO_OWNER" ]] \
    || die "repository owner is an organization; set --trusted-logins to the human users allowed to drive the factory"
fi
unset APP_TOKEN
log "validated GitHub App identity: $BOT_LOGIN"

BOT_EMAIL="$BOT_ID+$BOT_LOGIN@users.noreply.github.com"

env_content="$(
  cat <<'ENV_HEADER'
# Generated by dev-ops/factory/setup-bot.sh. Do not commit this file.
ENV_HEADER
  shell_assign PATH "$VENV_DIR/bin:$HOME/.opencode/bin:$PATH"
  shell_assign FACTORY_GITHUB_APP_ID "$APP_ID"
  shell_assign FACTORY_GITHUB_APP_PRIVATE_KEY_FILE "$KEY_FILE"
  shell_assign FACTORY_LOGIN "$BOT_LOGIN"
  shell_assign FACTORY_TRUSTED_LOGINS "$TRUSTED_LOGINS"
  shell_assign FACTORY_ID "factory-1"
  shell_assign FACTORY_WORKTREE "$WORKTREE"
  shell_assign FACTORY_SESSION_TIMEOUT "$SESSION_TIMEOUT"
  shell_assign FACTORY_CONTAINER_MODE "$CONTAINER_MODE"
  shell_assign FACTORY_ON_USAGE_FILLED "$ON_USAGE_FILLED"
  shell_assign FACTORY_MAX_FIX_SESSIONS "$MAX_FIX_SESSIONS"
  shell_assign FACTORY_LOG_FILE "$STATE_DIR/tick.jsonl"
  shell_assign FACTORY_METRICS_DIR "$STATE_DIR/metrics"
  shell_assign FACTORY_SESSION_LOG_DIR "/tmp/opencode"
  shell_assign FACTORY_LOG_SESSION_OUTPUT "metadata"
  shell_assign FACTORY_PRESERVE_SESSION_LOGS "on-failure"
  shell_assign MODELS_CONFIG "$SCRIPT_DIR/models.yaml"
  shell_assign GIT_AUTHOR_NAME "$BOT_LOGIN"
  shell_assign GIT_AUTHOR_EMAIL "$BOT_EMAIL"
  shell_assign GIT_COMMITTER_NAME "$BOT_LOGIN"
  shell_assign GIT_COMMITTER_EMAIL "$BOT_EMAIL"
  shell_assign GIT_TERMINAL_PROMPT "0"
  shell_assign GIT_CONFIG_COUNT "3"
  shell_assign GIT_CONFIG_KEY_0 "credential.https://github.com.helper"
  shell_assign GIT_CONFIG_VALUE_0 '!gh auth git-credential'
  shell_assign GIT_CONFIG_KEY_1 "url.https://github.com/.insteadOf"
  shell_assign GIT_CONFIG_VALUE_1 "git@github.com:"
  shell_assign GIT_CONFIG_KEY_2 "url.https://github.com/.insteadOf"
  shell_assign GIT_CONFIG_VALUE_2 "ssh://git@github.com/"
)"

wrapper_content="$(
  cat <<'WRAPPER_HEADER'
#!/usr/bin/env bash
set -euo pipefail
WRAPPER_HEADER
  printf 'source %q\n' "$ENV_FILE"
  printf 'cd %q\n' "$REPO_ROOT"
  printf 'exec %q "$@"\n' "$TICK_SCRIPT"
)"

write_atomic "$ENV_FILE" 600 "$env_content"
write_atomic "$WRAPPER_FILE" 700 "$wrapper_content"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
log "wrote private factory environment and cron wrapper"

if [[ "$SKIP_VALIDATION" == 0 ]]; then
  log "validating configuration with tick.sh --dry-run"
  if ! (
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
    "$TICK_SCRIPT" --dry-run
  ); then
    die "factory dry run failed; cron was not installed; fix the reported problem and rerun setup"
  fi
fi

if [[ "$INSTALL_CRON" == 1 ]]; then
  install_cron
else
  if command -v crontab >/dev/null 2>&1 \
    && crontab -l 2>/dev/null | grep -Fqx "$CRON_BEGIN"; then
    log "warning: an existing factory cron block was left unchanged"
  else
    log "cron not installed"
  fi
  log "run this manually when ready:"
  printf '  %s %s >> %s 2>&1\n' \
    "$SCHEDULE" "$(cron_quote "$WRAPPER_FILE")" "$(cron_quote "$LOG_FILE")"
fi

log "setup complete"
printf '  Bot identity: %s\n' "$BOT_LOGIN"
printf '  Environment: %s\n' "$ENV_FILE"
printf '  Wrapper: %s\n' "$WRAPPER_FILE"
printf '  Log: %s\n' "$LOG_FILE"
cat <<'NEXT'

Next steps:
- Keep applying the owner approved label yourself. The bot must not self-approve.
- Prefer a dedicated Unix user without personal GitHub, SSH, Docker, or deploy credentials.
- Review the first bot-authored PR and confirm its author, comments, and commits.

NEXT
