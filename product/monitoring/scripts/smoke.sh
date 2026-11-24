#!/usr/bin/env bash
set -euo pipefail

# Smoke test for a product monitoring instance.
# Usage: ./scripts/smoke.sh [path/to/.env]
# Requires docker, curl. Uses telemetrygen image (pinned) and curl OTLP.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
MON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${1:-$MON_DIR/.env}"
TELEMETRYGEN_IMAGE="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.165.0"

if [ ! -f "$ENV_FILE" ]; then
  echo "missing env file: $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
: "${MONITORING_PROJECT:?MONITORING_PROJECT required}"
: "${OTLP_HTTP_PORT:?OTLP_HTTP_PORT required}"
: "${GRAFANA_PORT:?GRAFANA_PORT required}"
: "${GRAFANA_METRICS_PASSWORD:?GRAFANA_METRICS_PASSWORD required}"

ENV_DIR="$(cd -- "$(dirname -- "$ENV_FILE")" >/dev/null && pwd)"
if [ -f "$ENV_DIR/compose.yaml" ]; then
  COMPOSE_FILE="$ENV_DIR/compose.yaml"
elif [ -f "$ENV_DIR/docker-compose.yml" ]; then
  COMPOSE_FILE="$ENV_DIR/docker-compose.yml"
else
  COMPOSE_FILE="$MON_DIR/compose.yaml"
fi
COMPOSE=(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE")

echo "[smoke] checking services..."
"${COMPOSE[@]}" ps

echo "[smoke] sending synthetic OTLP data via telemetrygen (${TELEMETRYGEN_IMAGE})..."
docker run --rm --network host "${TELEMETRYGEN_IMAGE}" traces \
  --otlp-endpoint 127.0.0.1:${OTLP_HTTP_PORT} \
  --otlp-http \
  --otlp-insecure \
  --traces 5 \
  --service smoke-test \
  --telemetry-attributes project=\"${MONITORING_PROJECT}\" \
  --telemetry-attributes deployment.environment=\"smoke\" \
  --telemetry-attributes service.version=\"smoke\" >/dev/null

docker run --rm --network host "${TELEMETRYGEN_IMAGE}" logs \
  --otlp-endpoint 127.0.0.1:${OTLP_HTTP_PORT} \
  --otlp-http \
  --otlp-insecure \
  --logs 5 \
  --service smoke-test \
  --telemetry-attributes project=\"${MONITORING_PROJECT}\" \
  --telemetry-attributes deployment.environment=\"smoke\" \
  --telemetry-attributes service.version=\"smoke\" >/dev/null

echo "[smoke] sending prompt 07 metric points via OTLP HTTP..."
now_ns="$(date +%s)000000000"
metric_payload=$(cat <<JSON
{"resourceMetrics":[{"resource":{"attributes":[
  {"key":"service.name","value":{"stringValue":"booking-backend"}},
  {"key":"service.version","value":{"stringValue":"smoke"}},
  {"key":"deployment.environment","value":{"stringValue":"smoke"}},
  {"key":"project","value":{"stringValue":"${MONITORING_PROJECT}"}}
]},"scopeMetrics":[{"scope":{"name":"smoke"},"metrics":[
  {"name":"events.appended","sum":{"aggregationTemporality":2,"isMonotonic":true,"dataPoints":[{"asInt":"3","timeUnixNano":"${now_ns}","attributes":[{"key":"type","value":{"stringValue":"booking.created"}}]}]}},
  {"name":"commands.handled","sum":{"aggregationTemporality":2,"isMonotonic":true,"dataPoints":[{"asInt":"2","timeUnixNano":"${now_ns}","attributes":[{"key":"command","value":{"stringValue":"CreateBooking"}},{"key":"outcome","value":{"stringValue":"ok"}}]}]}},
  {"name":"projection.lag","gauge":{"dataPoints":[{"asInt":"0","timeUnixNano":"${now_ns}","attributes":[{"key":"projection","value":{"stringValue":"bookings"}}]}]}},
  {"name":"projection.errors","sum":{"aggregationTemporality":2,"isMonotonic":true,"dataPoints":[{"asInt":"0","timeUnixNano":"${now_ns}","attributes":[{"key":"projection","value":{"stringValue":"bookings"}}]}]}},
  {"name":"bookings.created","sum":{"aggregationTemporality":2,"isMonotonic":true,"dataPoints":[{"asInt":"1","timeUnixNano":"${now_ns}"}]}},
  {"name":"bookings.cancelled","sum":{"aggregationTemporality":2,"isMonotonic":true,"dataPoints":[{"asInt":"0","timeUnixNano":"${now_ns}"}]}},
  {"name":"bookings.rejected","sum":{"aggregationTemporality":2,"isMonotonic":true,"dataPoints":[{"asInt":"0","timeUnixNano":"${now_ns}","attributes":[{"key":"reason","value":{"stringValue":"double_booking"}}]}]}},
  {"name":"auth.logins","sum":{"aggregationTemporality":2,"isMonotonic":true,"dataPoints":[{"asInt":"1","timeUnixNano":"${now_ns}","attributes":[{"key":"result","value":{"stringValue":"success"}}]}]}},
  {"name":"sidecar.requests","sum":{"aggregationTemporality":2,"isMonotonic":true,"dataPoints":[{"asInt":"1","timeUnixNano":"${now_ns}","attributes":[{"key":"endpoint","value":{"stringValue":"validate"}},{"key":"result","value":{"stringValue":"ok"}}]}]}},
  {"name":"notifications.pending","gauge":{"dataPoints":[{"asInt":"0","timeUnixNano":"${now_ns}"}]}}
]}]}]}
JSON
)
curl -fsS -X POST "http://127.0.0.1:${OTLP_HTTP_PORT}/v1/metrics" \
  -H 'Content-Type: application/json' \
  -d "$metric_payload" >/dev/null

echo "[smoke] waiting for trace in ClickHouse..."
trace_ok=0
for _ in $(seq 1 60); do
  c=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM otel.otel_traces WHERE ServiceName='smoke-test'" 2>/dev/null || echo 0)
  c="$(echo "$c" | tr -d '[:space:]')"
  if [ "${c:-0}" -ge 1 ]; then trace_ok=1; break; fi
  sleep 2
done
[ "$trace_ok" -eq 1 ] || { echo "[smoke] trace not found in ClickHouse" >&2; exit 1; }

echo "[smoke] checking Grafana health..."
curl -fsS "http://127.0.0.1:${GRAFANA_PORT}/api/health" | grep -q ok

metrics_status=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${GRAFANA_PORT}/metrics")
[ "$metrics_status" = "401" ] || { echo "[smoke] /metrics without auth returned $metrics_status, expected 401" >&2; exit 1; }
metrics_basic_auth="$(printf 'prometheus:%s' "$GRAFANA_METRICS_PASSWORD" | base64)"
metrics_auth_status=$(curl -sS -o /dev/null -w '%{http_code}' \
  -H "Authorization: Basic $metrics_basic_auth" "http://127.0.0.1:${GRAFANA_PORT}/metrics")
[ "$metrics_auth_status" = "200" ] || { echo "[smoke] /metrics with auth returned $metrics_auth_status, expected 200" >&2; exit 1; }
echo "[smoke] Grafana /metrics requires basic auth"

prom_query() {
  local q="$1"
  "${COMPOSE[@]}" exec -T prometheus wget -qO- --post-data="query=${q}" http://127.0.0.1:9090/api/v1/query 2>/dev/null
}

has_result() {
  python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("status")=="success" and len(d.get("data",{}).get("result",[]))>0 else 1)'
}

grafana_up=0
for _ in $(seq 1 60); do
  if prom_query 'up{job="grafana"}' | python3 -c 'import json,sys; d=json.load(sys.stdin); r=d.get("data",{}).get("result",[]); sys.exit(0 if r and r[0].get("value",[None,"0"])[1]=="1" else 1)'; then
    grafana_up=1
    break
  fi
  sleep 2
done
[ "$grafana_up" -eq 1 ] || { echo "[smoke] grafana target is not up" >&2; exit 1; }

echo "[smoke] waiting for metrics in Prometheus and asserting key dashboard queries..."
# Query Prometheus to discover actual translated metric names, then check one key query per dashboard.
queries=(
  'sum(rate({__name__=~"http_server_request_duration_seconds_count|http_server_duration_milliseconds_count|events_appended_total|commands_handled_total"}[15m]))'
  'sum({__name__=~"events_appended_total|commands_handled_total|bookings_created_total|projection_lag|notifications_pending"})'
  'sum({__name__=~"bookings_created_total|bookings_cancelled_total|bookings_rejected_total|auth_logins_total|sidecar_requests_total|email_sent_total|ratelimit_rejected_total"})'
  'sum({__name__=~"projection_lag|projection_errors_total|notifications_pending|notifications_enqueued_total"})'
  'sum({__name__=~"go_goroutine_count|process_runtime_go_mem_heap_alloc_bytes|go_memory_used_bytes|up"} )'
)
labels=("product-overview" "product-traces/logs-metric-presence" "product-usage" "product-event-sourcing" "product-runtime")

ok_all=1
for i in "${!queries[@]}"; do
  q="${queries[$i]}"
  label="${labels[$i]}"
  found=0
  for _ in $(seq 1 60); do
    if prom_query "$q" | has_result; then
      echo "[smoke] OK dashboard query: ${label}"
      found=1
      break
    fi
    sleep 2
  done
  if [ "$found" -ne 1 ]; then
    echo "[smoke] FAILED dashboard query: ${label}" >&2
    echo "[smoke] query: $q" >&2
    prom_query "$q" >&2 || true
    ok_all=0
  fi
done

[ "$ok_all" -eq 1 ] || exit 1
echo "[smoke] OK"
