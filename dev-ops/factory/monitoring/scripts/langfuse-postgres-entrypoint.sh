#!/usr/bin/env bash
set -euo pipefail

pgdata="${PGDATA:-/var/lib/postgresql/data}"

if [[ -f "$pgdata/PG_VERSION" ]]; then
  data_major="$(tr -d '[:space:]' < "$pgdata/PG_VERSION")"
  image_major="${PG_MAJOR:-}"

  if [[ -z "$image_major" ]]; then
    echo "[langfuse-postgres] PG_MAJOR is unset; refusing to open an existing data directory." >&2
    exit 1
  fi

  if [[ "$data_major" != "$image_major" ]]; then
    echo "[langfuse-postgres] Refusing to open PostgreSQL $data_major data with PostgreSQL $image_major binaries." >&2
    echo "[langfuse-postgres] A major upgrade requires a verified dump/restore or pg_upgrade." >&2
    echo "[langfuse-postgres] Follow the Langfuse v4 and PostgreSQL 18 upgrade procedure in dev-ops/factory/monitoring/README.md." >&2
    exit 1
  fi
fi

exec docker-entrypoint.sh "$@"
