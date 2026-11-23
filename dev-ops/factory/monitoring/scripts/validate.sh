#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
MON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$MON_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

fail=0
warn() { echo "[monitoring-validate] WARN: $*" >&2; }
run() {
  echo "+ $*"
  if ! "$@"; then
    echo "[monitoring-validate] FAILED: $*" >&2
    fail=1
  fi
}

have_docker() { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }

TMP_ENV=""
cleanup() {
  [[ -n "$TMP_ENV" && -f "$TMP_ENV" ]] && rm -f "$TMP_ENV"
}
trap cleanup EXIT

# Throwaway env file for compose config validation.
TMP_ENV="$(mktemp)"
cat > "$TMP_ENV" <<'ENV'
CLICKHOUSE_COLLECTOR_PASSWORD=test-collector
CLICKHOUSE_GRAFANA_PASSWORD=test-grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=test-admin
HOST_NAME=test-host
GRAFANA_PORT=3000
OTLP_GRPC_PORT=4317
OTLP_HTTP_PORT=4318
FACTORY_LOG_DIR=/tmp/factory-logs
FACTORY_METRICS_DIR=/tmp/factory-metrics
CLICKHOUSE_TTL_DAYS=400
PROMETHEUS_RETENTION_TIME=15d
PROMETHEUS_RETENTION_SIZE=2GB
ENV

if have_docker; then
  run docker compose -f dev-ops/factory/monitoring/docker-compose.yml --env-file "$TMP_ENV" config -q

  # Collector config validation. Provide env vars required by ${env:...}.
  run docker run --rm \
    -e FACTORY_LOG_DIR=/var/log/factory \
    -e HOST_NAME=test-host \
    -e CLICKHOUSE_ENDPOINT=tcp://clickhouse:9000 \
    -e CLICKHOUSE_COLLECTOR_PASSWORD=test \
    -v "$REPO_ROOT/dev-ops/factory/monitoring/otel-collector/config.yaml:/etc/otelcol/config.yaml:ro" \
    otel/opentelemetry-collector-contrib:0.165.0 \
    validate --config=/etc/otelcol/config.yaml

  # Prometheus config and rules.
  run docker run --rm \
    -v "$REPO_ROOT/dev-ops/factory/monitoring/prometheus:/etc/prometheus:ro" \
    --entrypoint promtool \
    prom/prometheus:v3.16.0 \
    check config /etc/prometheus/prometheus.yml

  run docker run --rm \
    -v "$REPO_ROOT/dev-ops/factory/monitoring/prometheus:/etc/prometheus:ro" \
    --entrypoint promtool \
    prom/prometheus:v3.16.0 \
    check rules /etc/prometheus/rules/factory-recording.yml

  # ClickHouse SQL syntax/init smoke: run init SQL against throwaway ClickHouse.
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
    -v "$REPO_ROOT/dev-ops/factory/monitoring/clickhouse/config.d:/etc/clickhouse-server/config.d:ro" \
    -v "$REPO_ROOT/dev-ops/factory/monitoring/clickhouse/users.d/users.xml:/etc/clickhouse-server/users.d/users.xml:ro" \
    clickhouse/clickhouse-server:26.9.36.3)"
  echo "[monitoring-validate] waiting for throwaway ClickHouse..."
  for _ in $(seq 1 60); do
    if docker exec "$CH_CID" clickhouse-client --query "SELECT 1" >/dev/null 2>&1; then break; fi
    sleep 1
  done
  docker exec "$CH_CID" clickhouse-client --query "SELECT 1" >/dev/null
  # Create users (passwords from env, same as clickhouse-init.sh).
  docker exec -i "$CH_CID" clickhouse-client --multiquery <<'SQL'
CREATE USER IF NOT EXISTS collector IDENTIFIED WITH plaintext_password BY 'test-collector';
CREATE USER IF NOT EXISTS grafana IDENTIFIED WITH plaintext_password BY 'test-grafana';
ALTER USER collector SETTINGS PROFILE 'collector_profile';
ALTER USER grafana SETTINGS PROFILE 'grafana_profile';
SQL
  # Create otel_logs minimal table so MV creation works.
  docker exec -i "$CH_CID" clickhouse-client --multiquery <<'SQL'
CREATE DATABASE IF NOT EXISTS otel;
CREATE TABLE IF NOT EXISTS otel.otel_logs (
  Timestamp DateTime64(9),
  TraceId String,
  SpanId String,
  TraceFlags UInt8,
  SeverityText LowCardinality(String),
  SeverityNumber UInt8,
  ServiceName LowCardinality(String),
  Body String,
  ResourceSchemaUrl LowCardinality(String),
  ResourceAttributes Map(LowCardinality(String), String),
  ScopeSchemaUrl LowCardinality(String),
  ScopeName String,
  ScopeVersion LowCardinality(String),
  ScopeAttributes Map(LowCardinality(String), String),
  LogAttributes Map(LowCardinality(String), String),
  EventName String
) ENGINE = MergeTree ORDER BY (Timestamp);
SQL
  for _ in $(seq 1 60); do
    if docker exec "$CH_CID" clickhouse-client --query "SELECT 1" >/dev/null 2>&1; then break; fi
    sleep 1
  done
  docker exec "$CH_CID" clickhouse-client --query "SELECT 1" >/dev/null
  for f in dev-ops/factory/monitoring/clickhouse/init/*.sql; do
    echo "+ clickhouse init $f"
    ok=0
    for attempt in 1 2 3; do
      if sed 's/__CLICKHOUSE_TTL_DAYS__/400/g' "$f" | docker exec -i "$CH_CID" clickhouse-client --multiquery; then
        ok=1
        break
      fi
      echo "[monitoring-validate] clickhouse init attempt $attempt failed for $f, retrying..." >&2
      docker logs --tail 40 "$CH_CID" >&2 || true
      for _ in $(seq 1 30); do
        if docker exec "$CH_CID" clickhouse-client --query "SELECT 1" >/dev/null 2>&1; then break; fi
        sleep 1
      done
      sleep 2
    done
    if [[ "$ok" -ne 1 ]]; then
      echo "[monitoring-validate] FAILED: clickhouse init $f" >&2
      docker logs --tail 80 "$CH_CID" >&2 || true
      fail=1
      break
    fi
  done
  docker exec -i "$CH_CID" clickhouse-client --multiquery <<'SQL'
GRANT INSERT ON otel.otel_logs TO collector;
GRANT INSERT ON otel.otel_traces TO collector;
GRANT INSERT ON factory.events TO collector;
GRANT SELECT ON otel.otel_logs TO collector;
GRANT SELECT ON factory.* TO grafana;
GRANT SELECT ON otel.otel_traces TO grafana;
GRANT SELECT ON otel.otel_logs TO grafana;
SQL
  docker exec "$CH_CID" clickhouse-client --query "EXISTS TABLE factory.events" | grep -q 1
  docker exec "$CH_CID" clickhouse-client --query "EXISTS TABLE factory.runs" | grep -q 1
  docker exec "$CH_CID" clickhouse-client --query "EXISTS TABLE factory.daily" | grep -q 1
  ch_cleanup
  CH_CID=""
  trap cleanup EXIT
else
  warn "docker not available; skipped compose/collector/promtool/clickhouse checks"
  fail=1
fi

# Dashboard JSON validation (no dashboards yet is ok if directory only has README).
shopt -s nullglob
dashboards=(dev-ops/factory/monitoring/grafana/dashboards/*.json)
if [ ${#dashboards[@]} -eq 0 ]; then
  echo "[monitoring-validate] no dashboard JSON files (placeholder ok)"
else
  for f in "${dashboards[@]}"; do
    run jq empty "$f"
  done
fi

# Basic YAML/JSON sanity for configs that should always be parseable.
run python3 -c "import json,sys,pathlib; [json.load(open(p)) for p in pathlib.Path('dev-ops/factory/monitoring').rglob('*.json')]"
run python3 -c "import yaml,sys,pathlib; [yaml.safe_load(open(p)) for p in pathlib.Path('dev-ops/factory/monitoring').rglob('*.yml')] + [yaml.safe_load(open(p)) for p in pathlib.Path('dev-ops/factory/monitoring').rglob('*.yaml')]"

if [[ $fail -ne 0 ]]; then
  echo "[monitoring-validate] FAIL" >&2
  exit 1
fi
echo "[monitoring-validate] OK"
