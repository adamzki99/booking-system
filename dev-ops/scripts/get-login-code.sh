#!/usr/bin/env bash
#
# get-login-code.sh — retrieve the most recent 6-char login code for an email
# from a QA/dev environment's backend Compose logs.
#
# Usage:
#   dev-ops/scripts/get-login-code.sh <email> [--env ENV] [--request] [--local] [--from-file FILE]
#
# Only the code is printed to stdout; diagnostics go to stderr.
# Refuses production environments and unknown env names.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/dev-ops/environments.yaml"

ENV_NAME="qa"
REQUEST=0
LOCAL=0
FROM_FILE=""
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_NAME="$2"; shift 2 ;;
    --request) REQUEST=1; shift ;;
    --local) LOCAL=1; shift ;;
    --from-file) FROM_FILE="$2"; shift 2 ;;
    -*) echo "get-login-code: unknown flag: $1" >&2; exit 1 ;;
    *) positional+=("$1"); shift ;;
  esac
done
EMAIL="${positional[0]:-}"
[[ -n "$EMAIL" ]] || { echo "usage: get-login-code.sh <email> [--env ENV] [--request] [--local] [--from-file FILE]" >&2; exit 1; }

DEPLOY_DIR="${DEPLOY_DIR:-/opt/booking-system-${ENV_NAME}}"

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

PORT="$(read_port)" || exit 1

is_local() {
  if docker compose -p "booking-${ENV_NAME}" ps -q backend 2>/dev/null | grep -q .; then
    return 0
  fi
  if [[ -d "$DEPLOY_DIR" ]]; then
    return 0
  fi
  return 1
}

PY_SCRIPT='
import sys, json, re
email = sys.argv[1]
data = sys.stdin.read()
latest = None

def parse_text(line):
    msg = None; to = None; body = None
    m = re.search(r"\bmsg=\"([^\"]*)\"", line)
    if m: msg = m.group(1)
    else:
        m = re.search(r"\bmsg=(\S+)", line)
        if m: msg = m.group(1)
    m = re.search(r"\bto=\"([^\"]*)\"", line)
    if m: to = m.group(1)
    else:
        m = re.search(r"\bto=(\S+)", line)
        if m: to = m.group(1)
    m = re.search(r"\bbody=\"([^\"]*)\"", line)
    if m: body = m.group(1)
    else:
        m = re.search(r"\bbody=(\S+)", line)
        if m: body = m.group(1)
    return msg, to, body

for line in data.splitlines():
    line = line.strip()
    if not line:
        continue
    msg = to = body = None
    # try json (possibly embedded in a compose-prefixed line)
    start = line.find("{")
    end = line.rfind("}")
    if start != -1 and end != -1 and end > start:
        try:
            obj = json.loads(line[start:end+1])
            msg = obj.get("msg")
            to = obj.get("to")
            body = obj.get("body")
        except Exception:
            msg = to = body = None
    if msg is None:
        msg, to, body = parse_text(line)
    if msg == "email (log mode, not sent)" and to == email and body:
        if re.fullmatch(r"[A-Z0-9]{6}", body):
            latest = body

if latest is None:
    sys.stderr.write("no login code found for " + email + "\n")
    sys.exit(2)
print(latest)
'

extract_code() {
  python3 -c "$PY_SCRIPT" "$EMAIL"
}

# Remote execution: re-run on the dev server.
if [[ "$LOCAL" -ne 1 && -z "$FROM_FILE" ]]; then
  if ! is_local; then
    SSH="${BOOKING_DEV_SSH:-}"
    [[ -n "$SSH" ]] || { echo "BOOKING_DEV_SSH is not set" >&2; exit 1; }
    req_flag=""
    [[ "$REQUEST" -eq 1 ]] && req_flag="--request"
    exec ssh "$SSH" -- "$DEPLOY_DIR/dev-ops/scripts/get-login-code.sh" "$EMAIL" --env "$ENV_NAME" --local $req_flag
  fi
fi

fetch_logs() {
  if [[ -n "$FROM_FILE" ]]; then
    if [[ "$FROM_FILE" == "-" ]]; then
      cat
    else
      cat "$FROM_FILE"
    fi
  else
    local compose_file="$DEPLOY_DIR/projects/sauna/docker-compose.yml"
    docker compose -f "$compose_file" -p "booking-${ENV_NAME}" logs --no-color --no-log-prefix --since 15m --tail 5000 backend 2>/dev/null
  fi
}

if [[ "$REQUEST" -eq 1 ]]; then
  HOST="${BOOKING_DEV_HOST:-127.0.0.1}"
  curl -sS -X POST "http://${HOST}:${PORT}/api/auth/request-code" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${EMAIL}\"}" >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    code="$(fetch_logs | extract_code 2>/dev/null || true)"
    if [[ -n "$code" ]]; then
      printf '%s\n' "$code"
      exit 0
    fi
    sleep 0.5
  done
fi

fetch_logs | extract_code
