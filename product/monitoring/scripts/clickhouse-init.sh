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
sleep 3
wait_ready

TRACES_TTL_DAYS="${TRACES_TTL_DAYS:-7}"
LOGS_TTL_DAYS="${LOGS_TTL_DAYS:-14}"
COLLECTOR_PW="$(sql_escape "${CLICKHOUSE_COLLECTOR_PASSWORD:-}")"
GRAFANA_PW="$(sql_escape "${CLICKHOUSE_GRAFANA_PASSWORD:-}")"

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

echo "[clickhouse-init] applying init SQL (TRACES_TTL_DAYS=$TRACES_TTL_DAYS LOGS_TTL_DAYS=$LOGS_TTL_DAYS)..."
for f in /init/*.sql; do
  [ -f "$f" ] || continue
  echo "[clickhouse-init] applying $f"
  sed -e "s/__TRACES_TTL_DAYS__/${TRACES_TTL_DAYS}/g" \
      -e "s/__LOGS_TTL_DAYS__/${LOGS_TTL_DAYS}/g" "$f" | ch --multiquery
done

echo "[clickhouse-init] applying grants..."
ch --multiquery <<SQL
GRANT INSERT ON otel.otel_logs TO collector;
GRANT INSERT ON otel.otel_traces TO collector;
GRANT SELECT ON otel.otel_logs TO collector;
GRANT SELECT ON otel.otel_traces TO collector;
GRANT SELECT ON otel.otel_logs TO grafana;
GRANT SELECT ON otel.otel_traces TO grafana;
GRANT SELECT ON system.parts TO grafana;
SQL

echo "[clickhouse-init] done"
