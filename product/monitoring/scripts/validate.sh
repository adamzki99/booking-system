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

CLICKHOUSE_IMAGE="$(python3 - <<'PY'
from pathlib import Path
import yaml
compose = yaml.safe_load(Path('product/monitoring/compose.yaml').read_text())
print(compose['services']['clickhouse']['image'])
PY
)"

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
  clickhouse_diagnostics() {
    echo "[product-monitoring-validate] ClickHouse container status:" >&2
    docker ps -a --filter "id=$CH_CID" --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}' >&2 || true
    docker inspect --format 'status={{.State.Status}} exit_code={{.State.ExitCode}} oom_killed={{.State.OOMKilled}} restarts={{.RestartCount}}' "$CH_CID" >&2 || true
    echo "[product-monitoring-validate] recent ClickHouse logs:" >&2
    docker logs --tail 100 "$CH_CID" >&2 || true
  }
  wait_for_clickhouse() {
    local attempt
    for attempt in $(seq 1 60); do
      if docker exec "$CH_CID" clickhouse-client --query "SELECT 1" >/dev/null 2>&1; then
        return 0
      fi
      [[ "$attempt" -eq 60 ]] || sleep 1
    done
    return 1
  }
  trap 'ch_cleanup; cleanup' EXIT
  CH_CID="$(docker run -d --rm \
    -e CLICKHOUSE_DB=otel \
    -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 \
    -e CLICKHOUSE_COLLECTOR_PASSWORD=test-collector \
    -e CLICKHOUSE_GRAFANA_PASSWORD=test-grafana \
    -v "$REPO_ROOT/product/monitoring/clickhouse/config.d:/etc/clickhouse-server/config.d:ro" \
    -v "$REPO_ROOT/product/monitoring/clickhouse/users.d/users.xml:/etc/clickhouse-server/users.d/users.xml:ro" \
    "$CLICKHOUSE_IMAGE")"
  echo "[product-monitoring-validate] waiting for throwaway ClickHouse ($CLICKHOUSE_IMAGE)..."
  if ! wait_for_clickhouse; then
    echo "[product-monitoring-validate] ClickHouse did not become ready after 60 attempts" >&2
    clickhouse_diagnostics
    fail=1
  else
    # The image entrypoint can briefly restart the server after first readiness.
    sleep 3
    if ! wait_for_clickhouse; then
      echo "[product-monitoring-validate] ClickHouse did not become stably ready" >&2
      clickhouse_diagnostics
      fail=1
    fi
  fi
  if [[ "$fail" -eq 0 ]]; then
    ch_sql_ok=0
    for attempt in 1 2 3; do
      if docker exec -i "$CH_CID" clickhouse-client --multiquery <<'SQL'
CREATE USER IF NOT EXISTS collector IDENTIFIED WITH plaintext_password BY 'test-collector';
CREATE USER IF NOT EXISTS grafana IDENTIFIED WITH plaintext_password BY 'test-grafana';
ALTER USER collector SETTINGS PROFILE 'collector_profile';
ALTER USER grafana SETTINGS PROFILE 'grafana_profile';
SQL
      then
        ch_sql_ok=1
        break
      fi
      echo "[product-monitoring-validate] clickhouse user setup attempt $attempt failed, retrying..." >&2
      clickhouse_diagnostics
      sleep 2
    done
    if [[ "$ch_sql_ok" -ne 1 ]]; then
      echo "[product-monitoring-validate] FAILED: ClickHouse user setup after retries" >&2
      clickhouse_diagnostics
      fail=1
    fi
  fi
  if [[ "$fail" -eq 0 ]]; then
    for f in product/monitoring/clickhouse/init/*.sql; do
      echo "+ clickhouse init $f"
      ok=0
      for attempt in 1 2 3; do
        if sed -e 's/__TRACES_TTL_DAYS__/7/g' -e 's/__LOGS_TTL_DAYS__/14/g' "$f" | docker exec -i "$CH_CID" clickhouse-client --multiquery; then
          ok=1
          break
        fi
        echo "[product-monitoring-validate] clickhouse init attempt $attempt failed for $f, retrying..." >&2
        clickhouse_diagnostics
        for _ in $(seq 1 30); do
          if docker exec "$CH_CID" clickhouse-client --query "SELECT 1" >/dev/null 2>&1; then break; fi
          sleep 1
        done
        sleep 2
      done
      if [[ "$ok" -ne 1 ]]; then
        echo "[product-monitoring-validate] FAILED: clickhouse init $f after retries" >&2
        clickhouse_diagnostics
        fail=1
        break
      fi
    done
  fi
  if [[ "$fail" -eq 0 ]]; then
    if ! docker exec -i "$CH_CID" clickhouse-client --multiquery <<'SQL'
GRANT INSERT ON otel.otel_logs TO collector;
GRANT INSERT ON otel.otel_traces TO collector;
GRANT SELECT ON otel.otel_logs TO grafana;
GRANT SELECT ON otel.otel_traces TO grafana;
SQL
    then
      echo "[product-monitoring-validate] FAILED: ClickHouse grants" >&2
      clickhouse_diagnostics
      fail=1
    fi
  fi
  if [[ "$fail" -eq 0 ]]; then
    for table in otel.otel_logs otel.otel_traces; do
      if ! docker exec "$CH_CID" clickhouse-client --query "EXISTS TABLE $table" | grep -q 1; then
        echo "[product-monitoring-validate] FAILED: missing table $table" >&2
        clickhouse_diagnostics
        fail=1
      fi
    done
  fi
  ch_cleanup
  CH_CID=""
  trap cleanup EXIT
else
  warn "docker not available; skipped compose/collector/promtool/clickhouse checks"
  fail=1
fi

shopt -s nullglob
dashboards=(product/monitoring/grafana/dashboards/*.json)
if [ ${#dashboards[@]} -eq 0 ]; then
  echo "[product-monitoring-validate] FAILED: no dashboard JSON files" >&2
  fail=1
else
  for f in "${dashboards[@]}"; do
    run jq empty "$f"
  done
fi

echo "+ check dashboard generator up to date"
tmpdash="$(mktemp -d)"
cp -r product/monitoring/grafana/dashboards "$tmpdash/dashboards.bak"
python3 product/monitoring/scripts/generate_dashboards.py >/dev/null
if ! diff -ru "$tmpdash/dashboards.bak" product/monitoring/grafana/dashboards >/dev/null; then
  echo "[product-monitoring-validate] FAILED: dashboard generator output is not up to date" >&2
  diff -ru "$tmpdash/dashboards.bak" product/monitoring/grafana/dashboards || true
  rm -rf product/monitoring/grafana/dashboards
  mv "$tmpdash/dashboards.bak" product/monitoring/grafana/dashboards
  fail=1
else
  rm -rf "$tmpdash"
fi

echo "+ check alert rules generator up to date"
tmpalert="$(mktemp -d)"
cp -r product/monitoring/grafana/provisioning/alerting "$tmpalert/alerting.bak"
python3 product/monitoring/scripts/generate_alert_rules.py >/dev/null
if ! diff -ru "$tmpalert/alerting.bak" product/monitoring/grafana/provisioning/alerting >/dev/null; then
  echo "[product-monitoring-validate] FAILED: alert rules generator output is not up to date" >&2
  diff -ru "$tmpalert/alerting.bak" product/monitoring/grafana/provisioning/alerting || true
  rm -rf product/monitoring/grafana/provisioning/alerting
  mv "$tmpalert/alerting.bak" product/monitoring/grafana/provisioning/alerting
  fail=1
else
  rm -rf "$tmpalert"
fi

project_name_check="$(printf '%s%s' 'sau' 'na')"
echo "+ check no ${project_name_check} references in product/monitoring"
if grep -rni "$project_name_check" product/monitoring >/dev/null; then
  echo "[product-monitoring-validate] FAILED: ${project_name_check} references found in product/monitoring" >&2
  grep -rni "$project_name_check" product/monitoring >&2 || true
  fail=1
fi

run python3 -c "import json,sys,pathlib; [json.load(open(p)) for p in pathlib.Path('product/monitoring').rglob('*.json')]"
run python3 -c "import yaml,pathlib; [yaml.safe_load(open(p)) for p in pathlib.Path('product/monitoring').rglob('*.yml')] + [yaml.safe_load(open(p)) for p in pathlib.Path('product/monitoring').rglob('*.yaml')]"

if [[ $fail -ne 0 ]]; then
  echo "[product-monitoring-validate] FAIL" >&2
  exit 1
fi
echo "[product-monitoring-validate] OK"
