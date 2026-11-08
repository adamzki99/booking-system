#!/usr/bin/env bash
#
# run-playwright.sh — single entry point for agentic Playwright testing.
#
# Usage:
#   dev-ops/scripts/run-playwright.sh [--env ENV] [spec...]
#
# Requests + fetches a login code, then runs the Playwright suite inside a
# Docker container. Dev/QA only.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/dev-ops/environments.yaml"

ENV_NAME="qa"
LOCAL=0
SPECS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_NAME="$2"; shift 2 ;;
    --local) LOCAL=1; shift ;;
    *) SPECS+=("$1"); shift ;;
  esac
done

DEPLOY_DIR="${DEPLOY_DIR:-/opt/booking-system-${ENV_NAME}}"

read_port() {
  python3 - "$ENV_FILE" "$ENV_NAME" <<'PY'
import sys
path, env = sys.argv[1], sys.argv[2]
if env.lower() == "prod" or "prod" in env.lower():
    raise SystemExit("production environment not allowed")
port = None; found = False; in_env = False
with open(path) as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"): continue
        indent = len(line) - len(line.lstrip())
        key = line.strip().split(":", 1)[0].strip() if ":" in line.strip() else ""
        if indent == 2:
            in_env = (key == env)
            if in_env: found = True
            continue
        if in_env and indent >= 4 and ":" in line.strip():
            k, v = line.strip().split(":", 1)
            if k.strip() == "port":
                port = v.strip().strip('"').strip("'")
        if in_env and indent < 2 and line.strip():
            in_env = False
if not found: raise SystemExit(f"environment not found: {env}")
if not port: raise SystemExit(f"port missing for environment: {env}")
print(port)
PY
}

is_local() {
  if docker compose -p "booking-${ENV_NAME}" ps -q backend 2>/dev/null | grep -q .; then return 0; fi
  if [[ -d "$DEPLOY_DIR" ]]; then return 0; fi
  return 1
}

# Remote: re-exec on the dev server.
if [[ "$LOCAL" -ne 1 ]]; then
  if ! is_local; then
    SSH="${BOOKING_DEV_SSH:-}"
    [[ -n "$SSH" ]] || { echo "BOOKING_DEV_SSH is not set" >&2; exit 1; }
    exec ssh "$SSH" -- "$DEPLOY_DIR/dev-ops/scripts/run-playwright.sh" --env "$ENV_NAME" --local "${SPECS[@]}"
  fi
fi

PORT="$(read_port)" || exit 1
EMAIL="${TEST_USER_EMAIL:-}"
[[ -n "$EMAIL" ]] || { echo "TEST_USER_EMAIL is required" >&2; exit 1; }

CODE="$("$SCRIPT_DIR/get-login-code.sh" "$EMAIL" --env "$ENV_NAME" --request --local)"
[[ -n "$CODE" ]] || { echo "failed to obtain login code" >&2; exit 1; }

IMAGE="booking-playwright:local"
docker build -q -t "$IMAGE" "$REPO_ROOT/dev-ops/testing" >/dev/null

docker run --rm \
  --add-host=host.docker.internal:host-gateway \
  -v "$REPO_ROOT/dev-ops/testing:/tests" \
  -w /tests \
  -e BASE_URL="http://host.docker.internal:${PORT}" \
  -e TEST_USER_EMAIL="$EMAIL" \
  -e LOGIN_CODE="$CODE" \
  "$IMAGE" \
  npx playwright test "${SPECS[@]}"
