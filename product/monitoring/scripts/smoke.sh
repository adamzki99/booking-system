#!/usr/bin/env bash
set -euo pipefail

# Smoke test for a product monitoring instance.
# Usage: ./scripts/smoke.sh [path/to/.env]
# Requires docker compose, curl, and a configured .env.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
MON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${1:-$MON_DIR/.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "missing env file: $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
: "${MONITORING_PROJECT:?MONITORING_PROJECT required}"
: "${OTLP_HTTP_PORT:?OTLP_HTTP_PORT required}"
: "${GRAFANA_PORT:?GRAFANA_PORT required}"

COMPOSE=(docker compose -f "$MON_DIR/compose.yaml" --env-file "$ENV_FILE")

echo "[smoke] checking services..."
"${COMPOSE[@]}" ps

echo "[smoke] sending test trace/log/metric via OTLP HTTP..."
now_ns="$(date +%s)000000000"
trace_id="$(openssl rand -hex 16)"
span_id="$(openssl rand -hex 8)"
curl -fsS -X POST "http://127.0.0.1:${OTLP_HTTP_PORT}/v1/traces" \
  -H 'Content-Type: application/json' \
  -d "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"smoke-test\"}},{\"key\":\"service.version\",\"value\":{\"stringValue\":\"smoke\"}},{\"key\":\"deployment.environment\",\"value\":{\"stringValue\":\"smoke\"}},{\"key\":\"project\",\"value\":{\"stringValue\":\"${MONITORING_PROJECT}\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"${trace_id}\",\"spanId\":\"${span_id}\",\"name\":\"smoke-span\",\"kind\":1,\"startTimeUnixNano\":\"${now_ns}\",\"endTimeUnixNano\":\"${now_ns}\",\"attributes\":[{\"key\":\"http.route\",\"value\":{\"stringValue\":\"/smoke\"}}]}]}]}]}" >/dev/null

curl -fsS -X POST "http://127.0.0.1:${OTLP_HTTP_PORT}/v1/logs" \
  -H 'Content-Type: application/json' \
  -d "{\"resourceLogs\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"smoke-test\"}},{\"key\":\"project\",\"value\":{\"stringValue\":\"${MONITORING_PROJECT}\"}}]},\"scopeLogs\":[{\"logRecords\":[{\"timeUnixNano\":\"${now_ns}\",\"severityText\":\"INFO\",\"body\":{\"stringValue\":\"smoke log\"}}]}]}]}" >/dev/null

echo "[smoke] waiting for trace in ClickHouse..."
for _ in $(seq 1 60); do
  c=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM otel.otel_traces WHERE TraceId='${trace_id}'" 2>/dev/null || echo 0)
  if [ "$c" -ge 1 ]; then break; fi
  sleep 2
done
c=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM otel.otel_traces WHERE TraceId='${trace_id}'")
[ "$c" -ge 1 ] || { echo "[smoke] trace not found in ClickHouse" >&2; exit 1; }

echo "[smoke] checking Grafana health..."
curl -fsS "http://127.0.0.1:${GRAFANA_PORT}/api/health" | grep -q ok

echo "[smoke] OK"
