#!/bin/bash
set -euo pipefail

CH_HOST="${CH_HOST:-clickhouse}"
CH_PORT="${CH_PORT:-9000}"
CH_USER="${CH_USER:-default}"
CH_PASSWORD="${CH_PASSWORD:-}"
MAX_WAIT="${MAX_WAIT:-180}"

ch() {
  clickhouse-client --host "$CH_HOST" --port "$CH_PORT" --user "$CH_USER" \
    ${CH_PASSWORD:+--password "$CH_PASSWORD"} "$@"
}

sql_escape() {
  # Escape for ClickHouse SQL string literal: backslash and single quote.
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\'/\'\'}"
  printf '%s' "$s"
}

wait_ready() {
  for _ in $(seq 1 "$MAX_WAIT"); do
    if ch --query "SELECT 1" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "[clickhouse-init] clickhouse not ready" >&2
  return 1
}

echo "[clickhouse-init] waiting for clickhouse..."
wait_ready
# ClickHouse docker entrypoint may restart server after init; wait for stable readiness.
sleep 3
wait_ready

TTL_DAYS="${CLICKHOUSE_TTL_DAYS:-400}"
COLLECTOR_PW="$(sql_escape "${CLICKHOUSE_COLLECTOR_PASSWORD:-}")"
GRAFANA_PW="$(sql_escape "${CLICKHOUSE_GRAFANA_PASSWORD:-}")"
LANGFUSE_PW="$(sql_escape "${LANGFUSE_CLICKHOUSE_PASSWORD:-}")"

if [ -z "${CLICKHOUSE_COLLECTOR_PASSWORD:-}" ] || [ -z "${CLICKHOUSE_GRAFANA_PASSWORD:-}" ]; then
  echo "[clickhouse-init] missing CLICKHOUSE_COLLECTOR_PASSWORD or CLICKHOUSE_GRAFANA_PASSWORD" >&2
  exit 1
fi

echo "[clickhouse-init] creating users..."
users_ok=0
for _ in $(seq 1 30); do
  if ch --multiquery <<SQL
CREATE USER IF NOT EXISTS collector IDENTIFIED WITH plaintext_password BY '${COLLECTOR_PW}';
CREATE USER IF NOT EXISTS grafana IDENTIFIED WITH plaintext_password BY '${GRAFANA_PW}';
ALTER USER collector SETTINGS PROFILE 'collector_profile';
ALTER USER grafana SETTINGS PROFILE 'grafana_profile';
SQL
  then
    users_ok=1
    break
  fi
  sleep 2
done
if [ "$users_ok" -ne 1 ]; then
  echo "[clickhouse-init] failed to create users" >&2
  exit 1
fi

if [ -n "${LANGFUSE_CLICKHOUSE_PASSWORD:-}" ]; then
  echo "[clickhouse-init] creating langfuse database and user..."
  langfuse_ok=0
  for _ in $(seq 1 30); do
    if ch --multiquery <<SQL
CREATE DATABASE IF NOT EXISTS langfuse;
CREATE USER IF NOT EXISTS langfuse IDENTIFIED WITH plaintext_password BY '${LANGFUSE_PW}';
GRANT ALL ON langfuse.* TO langfuse;
GRANT SELECT(database, table, name, partition, partition_id, active, rows) ON system.parts TO langfuse;
GRANT SELECT(database, table, is_done) ON system.mutations TO langfuse;
GRANT SELECT(database, name, engine) ON system.tables TO langfuse;
GRANT SELECT ON system.processes TO langfuse;
GRANT SELECT ON system.query_log* TO langfuse;
GRANT SYSTEM SYNC REPLICA, SYSTEM MERGES, ALTER SETTINGS ON langfuse.observations_pid_tid_sorting TO langfuse;
SQL
    then
      langfuse_ok=1
      break
    fi
    sleep 2
  done
  if [ "$langfuse_ok" -ne 1 ]; then
    echo "[clickhouse-init] failed to create langfuse database/user" >&2
    exit 1
  fi
fi

echo "[clickhouse-init] applying init SQL (TTL_DAYS=$TTL_DAYS)..."
for f in /init/*.sql; do
  [ -f "$f" ] || continue
  echo "[clickhouse-init] applying $f"
  sed "s/__CLICKHOUSE_TTL_DAYS__/${TTL_DAYS}/g" "$f" | ch --multiquery
done

echo "[clickhouse-init] applying grants..."
ch --multiquery <<SQL
GRANT INSERT ON otel.otel_logs TO collector;
GRANT INSERT ON otel.otel_traces TO collector;
GRANT INSERT ON factory.events TO collector;
GRANT SELECT ON otel.otel_logs TO collector;
GRANT SELECT ON factory.* TO grafana;
GRANT SELECT ON otel.otel_traces TO grafana;
GRANT SELECT ON otel.otel_logs TO grafana;
GRANT SELECT ON system.parts TO grafana;
SQL

echo "[clickhouse-init] done"
