#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." >/dev/null && pwd)"
BASE_COMPOSE="$REPO_ROOT/projects/sauna/docker-compose.yml"
MONITORING_COMPOSE="$REPO_ROOT/projects/sauna/docker-compose.monitoring.yml"
ENV_FILE="$REPO_ROOT/projects/sauna/.env.example"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/projects/sauna"
  cp "$BASE_COMPOSE" "$MONITORING_COMPOSE" "$tmp/projects/sauna/"
  cp "$ENV_FILE" "$tmp/projects/sauna/.env"
  base_services="$(cd "$tmp/projects/sauna" && docker compose -f docker-compose.yml config --services)"
  monitoring_services="$(cd "$tmp/projects/sauna" && docker compose \
    -f docker-compose.yml -f docker-compose.monitoring.yml config --services)"
  (cd "$tmp/projects/sauna" && docker compose \
    -f docker-compose.yml -f docker-compose.monitoring.yml config -q)
else
  base_services="$(python3 - "$BASE_COMPOSE" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as stream:
    compose = yaml.safe_load(stream)
for name in compose["services"]:
    print(name)
PY
)"
  monitoring_services="$(python3 - "$BASE_COMPOSE" "$MONITORING_COMPOSE" <<'PY'
import sys
import yaml

services = {}
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as stream:
        compose = yaml.safe_load(stream)
    for name, config in (compose.get("services") or {}).items():
        services.setdefault(name, {}).update(config or {})
for name, config in services.items():
    if not config.get("profiles"):
        print(name)
PY
)"
  pass "Docker unavailable; checked Compose service profile merge with PyYAML"
fi

printf '%s\n' "$base_services" | grep -qx caddy \
  || fail "base deployment must enable caddy"
printf '%s\n' "$monitoring_services" | grep -qx caddy \
  || fail "monitoring override must not put caddy behind an opt-in profile"
[[ "$(printf '%s\n' "$base_services" | sort)" == "$(printf '%s\n' "$monitoring_services" | sort)" ]] \
  || fail "monitoring override must preserve the active deployment service set"
pass "monitoring override preserves caddy and the health-checked HTTP listener"
