#!/usr/bin/env bash
# Provision a fresh Linux host and start the sauna booking stack.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

REPO_URL="${REPO_URL:-https://github.com/adamzki99/booking-system.git}"
INSTALL_DIR="${DEPLOY_DIR:-${INSTALL_DIR:-/opt/booking-system}}"

# Install git if missing.
if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y git
  elif command -v yum >/dev/null 2>&1; then
    yum install -y git
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y git
  else
    echo "git is required but no supported package manager found." >&2
    exit 1
  fi
fi

# Install Docker Engine + Compose plugin if missing.
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found; installing Docker Engine + Compose plugin..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi

# Fetch or update the repository.
if [ ! -d "$INSTALL_DIR/.git" ]; then
  git clone "$REPO_URL" "$INSTALL_DIR"
else
  git -C "$INSTALL_DIR" pull --ff-only
fi

cd "$INSTALL_DIR/projects/sauna"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "WARNING: .env created from .env.example. Edit secrets (POSTGRES_PASSWORD, etc.) before exposing publicly." >&2
fi

# Load env for port reporting.
set -a
# shellcheck disable=SC1091
. ./.env
set +a

docker compose up -d --build

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo "Stack started. Caddy URL: http://${HOST_IP:-localhost}:${PORT:-8080}"
docker compose ps
