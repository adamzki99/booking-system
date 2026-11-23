#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
MON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$MON_DIR/../.." && pwd)"
cd "$REPO_ROOT"

fail=0
warn() { echo "[product-monitoring-validate] WARN: $*" >&2; }
run() {
  echo "+ $*"
  if ! "$@"; then
    echo "[product-monitoring-validate] FAILED: $*" >&2
    fail=1
  fi
}

have_docker() { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }

TMP_ENV=""
cleanup() {
  [[ -n "$TMP_ENV" && -f "$TMP_ENV" ]] && rm -f "$TMP_ENV"
}
trap cleanup EXIT

TMP_ENV="$(mktemp)"
cat > "$TMP_ENV" <<'ENV'
MONITORING_PROJECT=example
CLICKHOUSE_COLLECTOR_PASSWORD=test-collector
CLICKHOUSE_GRAFANA_PASSWORD=test-grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=test-admin
HOST_NAME=test-host
GRAFANA_PORT=13001
OTLP_GRPC_PORT=14317
OTLP_HTTP_PORT=14318
TRACES_TTL_DAYS=7
LOGS_TTL_DAYS=14
PROMETHEUS_RETENTION=15d
PROMETHEUS_RETENTION_SIZE=2GB
ENV

if have_docker; then
  run docker compose -f product/monitoring/compose.yaml --env-file "$TMP_ENV" config -q

  run docker run --rm \
    -e HOST_NAME=test-host \
    -e MONITORING_PROJECT=example \
    -e CLICKHOUSE_ENDPOINT=tcp://clickhouse:9000 \
    -e CLICKHOUSE_COLLECTOR_PASSWORD=test \
    -e PROMETHEUS_OTLP_ENDPOINT=http://prometheus:9090/api/v1/otlp \
    -v "$REPO_ROOT/product/monitoring/otel-collector/config.yaml:/etc/otelcol/config.yaml:ro" \
    otel/opentelemetry-collector-contrib:0.165.0 \
    validate --config=/etc/otelcol/config.yaml

  run docker run --rm \
    -v "$REPO_ROOT/product/monitoring/prometheus:/etc/prometheus:ro" \
    --entrypoint promtool \
    prom/prometheus:v3.16.0 \
    check config /etc/prometheus/prometheus.yml

  run docker run --rm \
    -v "$REPO_ROOT/product/monitoring/prometheus:/etc/prometheus:ro" \
    --entrypoint promtool \
    prom/prometheus:v3.16.0 \
    check rules /etc/prometheus/rules/product-recording.yml

  CH_CID=""
  ch_cleanup() {
    if [[ -n "$CH_CID" ]]; then
      docker rm -f "$CH_CID" >/dev/null 2>&1 || true
    fi
  }
  trap 'ch_cleanup; cleanup' EXIT
  CH_CID="$(docker run -d --rm \
    -e CLICKHOUSE_DB=otel \
    -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 \
    -e CLICKHOUSE_COLLECTOR_PASSWORD=test-collector \
    -e CLICKHOUSE_GRAFANA_PASSWORD=test-grafana \
    -v "$REPO_ROOT/product/monitoring/clickhouse/config.d:/etc/clickhouse-server/config.d:ro" \
    -v "$REPO_ROOT/product/monitoring/clickhouse/users.d/users.xml:/etc/clickhouse-server/users.d/users.xml:ro" \
    clickhouse/clickhouse-server:26.9.36.3)"
  echo "[product-monitoring-validate] waiting for throwaway ClickHouse..."
  for _ in $(seq 1 60); do
    if docker exec "$CH_CID" clickhouse-client --query "SELECT 1" >/dev/null 2>&1; then break; fi
    sleep 1
  done
  docker exec "$CH_CID" clickhouse-client --query "SELECT 1" >/dev/null
  docker exec -i "$CH_CID" clickhouse-client --multiquery <<'SQL'
CREATE USER IF NOT EXISTS collector IDENTIFIED WITH plaintext_password BY 'test-collector';
CREATE USER IF NOT EXISTS grafana IDENTIFIED WITH plaintext_password BY 'test-grafana';
ALTER USER collector SETTINGS PROFILE 'collector_profile';
ALTER USER grafana SETTINGS PROFILE 'grafana_profile';
SQL
  for f in product/monitoring/clickhouse/init/*.sql; do
    echo "+ clickhouse init $f"
    ok=0
    for attempt in 1 2 3; do
      if sed -e 's/__TRACES_TTL_DAYS__/7/g' -e 's/__LOGS_TTL_DAYS__/14/g' "$f" | docker exec -i "$CH_CID" clickhouse-client --multiquery; then
        ok=1
        break
      fi
      echo "[product-monitoring-validate] clickhouse init attempt $attempt failed for $f, retrying..." >&2
      docker logs --tail 40 "$CH_CID" >&2 || true
      for _ in $(seq 1 30); do
        if docker exec "$CH_CID" clickhouse-client --query "SELECT 1" >/dev/null 2>&1; then break; fi
        sleep 1
      done
      sleep 2
    done
    if [[ "$ok" -ne 1 ]]; then
      echo "[product-monitoring-validate] FAILED: clickhouse init $f" >&2
      docker logs --tail 80 "$CH_CID" >&2 || true
      fail=1
      break
    fi
  done
  docker exec -i "$CH_CID" clickhouse-client --multiquery <<'SQL'
GRANT INSERT ON otel.otel_logs TO collector;
GRANT INSERT ON otel.otel_traces TO collector;
GRANT SELECT ON otel.otel_logs TO grafana;
GRANT SELECT ON otel.otel_traces TO grafana;
SQL
  docker exec "$CH_CID" clickhouse-client --query "EXISTS TABLE otel.otel_logs" | grep -q 1
  docker exec "$CH_CID" clickhouse-client --query "EXISTS TABLE otel.otel_traces" | grep -q 1
  ch_cleanup
  CH_CID=""
  trap cleanup EXIT
else
  warn "docker not available; skipped compose/collector/promtool/clickhouse checks"
fi

shopt -s nullglob
dashboards=(product/monitoring/grafana/dashboards/*.json)
if [ ${#dashboards[@]} -eq 0 ]; then
  echo "[product-monitoring-validate] no dashboard JSON files (prompt 08 placeholder ok)"
else
  for f in "${dashboards[@]}"; do
    run jq empty "$f"
  done
fi

run python3 -c "import json,sys,pathlib; [json.load(open(p)) for p in pathlib.Path('product/monitoring').rglob('*.json')]"
run python3 -c "import yaml,pathlib; [yaml.safe_load(open(p)) for p in pathlib.Path('product/monitoring').rglob('*.yml')] + [yaml.safe_load(open(p)) for p in pathlib.Path('product/monitoring').rglob('*.yaml')]"

if [[ $fail -ne 0 ]]; then
  echo "[product-monitoring-validate] FAIL" >&2
  exit 1
fi
echo "[product-monitoring-validate] OK"
