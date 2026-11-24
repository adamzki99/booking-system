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

run bash dev-ops/scripts/tests/test-langfuse-postgres-entrypoint.sh

TMP_ENV=""
TMP_DASH=""
cleanup() {
  if [[ -n "$TMP_ENV" && -f "$TMP_ENV" ]]; then rm -f "$TMP_ENV"; fi
  if [[ -n "$TMP_DASH" && -d "$TMP_DASH" ]]; then rm -rf "$TMP_DASH"; fi
  return 0
}
trap cleanup EXIT

# Throwaway env file for compose config validation.
TMP_ENV="$(mktemp)"
cat > "$TMP_ENV" <<'ENV'
CLICKHOUSE_COLLECTOR_PASSWORD=test-collector
CLICKHOUSE_GRAFANA_PASSWORD=test-grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=test-admin
GRAFANA_METRICS_PASSWORD=test-metrics
GRAFANA_BIND_ADDR=127.0.0.1
OTLP_BIND_ADDR=127.0.0.1
GRAFANA_ROOT_URL=http://127.0.0.1:13000/
HOST_NAME=test-host
GRAFANA_PORT=3000
OTLP_GRPC_PORT=4317
OTLP_HTTP_PORT=4318
FACTORY_LOG_DIR=/tmp/factory-logs
FACTORY_METRICS_DIR=/tmp/factory-metrics
CLICKHOUSE_TTL_DAYS=400
PROMETHEUS_RETENTION_TIME=15d
PROMETHEUS_RETENTION_SIZE=2GB
LANGFUSE_OTLP_ENDPOINT=http://127.0.0.1:1
LANGFUSE_OTLP_AUTH_HEADER=Basic ZGlzYWJsZWQ6ZGlzYWJsZWQ=
LANGFUSE_NEXTAUTH_SECRET=test-nextauth
LANGFUSE_SALT=test-salt
LANGFUSE_ENCRYPTION_KEY=00000000000000000000000000000000
LANGFUSE_POSTGRES_PASSWORD=test-postgres
LANGFUSE_REDIS_AUTH=test-redis
LANGFUSE_MINIO_ROOT_USER=langfuse
LANGFUSE_MINIO_ROOT_PASSWORD=test-minio
LANGFUSE_CLICKHOUSE_PASSWORD=test-langfuse-clickhouse
LANGFUSE_INIT_PROJECT_PUBLIC_KEY=pk-lf-test
LANGFUSE_INIT_PROJECT_SECRET_KEY=sk-lf-test
ENV

CLICKHOUSE_IMAGE="$(python3 - <<'PY'
from pathlib import Path
import yaml
compose = yaml.safe_load(Path('dev-ops/factory/monitoring/docker-compose.yml').read_text())
print(compose['services']['clickhouse']['image'])
PY
)"

if have_docker; then
  run docker compose -f dev-ops/factory/monitoring/docker-compose.yml --env-file "$TMP_ENV" config -q
  run docker compose -f dev-ops/factory/monitoring/docker-compose.yml --env-file "$TMP_ENV" --profile langfuse config -q

  # Collector config validation. Provide env vars required by ${env:...}.
  run docker run --rm \
    -e FACTORY_LOG_DIR=/var/log/factory \
    -e HOST_NAME=test-host \
    -e CLICKHOUSE_ENDPOINT=tcp://clickhouse:9000 \
    -e CLICKHOUSE_COLLECTOR_PASSWORD=test \
    -e LANGFUSE_OTLP_ENDPOINT=http://127.0.0.1:1 \
    -e LANGFUSE_OTLP_AUTH_HEADER='Basic ZGlzYWJsZWQ6ZGlzYWJsZWQ=' \
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
  clickhouse_diagnostics() {
    echo "[monitoring-validate] ClickHouse container status:" >&2
    docker ps -a --filter "id=$CH_CID" --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}' >&2 || true
    docker inspect --format 'status={{.State.Status}} exit_code={{.State.ExitCode}} oom_killed={{.State.OOMKilled}} restarts={{.RestartCount}}' "$CH_CID" >&2 || true
    echo "[monitoring-validate] recent ClickHouse logs:" >&2
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
    -v "$REPO_ROOT/dev-ops/factory/monitoring/clickhouse/config.d:/etc/clickhouse-server/config.d:ro" \
    -v "$REPO_ROOT/dev-ops/factory/monitoring/clickhouse/users.d/users.xml:/etc/clickhouse-server/users.d/users.xml:ro" \
    -v "$REPO_ROOT/dev-ops/factory/monitoring/clickhouse/init:/init:ro" \
    -v "$REPO_ROOT/dev-ops/factory/monitoring/scripts/clickhouse-init.sh:/clickhouse-init.sh:ro" \
    "$CLICKHOUSE_IMAGE")"
  echo "[monitoring-validate] waiting for throwaway ClickHouse ($CLICKHOUSE_IMAGE)..."
  if ! wait_for_clickhouse; then
    echo "[monitoring-validate] ClickHouse did not become ready after 60 attempts" >&2
    clickhouse_diagnostics
    exit 1
  fi
  # The image entrypoint can briefly restart the server after first readiness.
  sleep 3
  if ! wait_for_clickhouse; then
    echo "[monitoring-validate] ClickHouse did not become stably ready" >&2
    clickhouse_diagnostics
    exit 1
  fi
  # Create users (passwords from env, same as clickhouse-init.sh).
  users_ok=0
  for attempt in 1 2 3; do
    if docker exec -i "$CH_CID" clickhouse-client --multiquery <<'SQL'
CREATE USER IF NOT EXISTS collector IDENTIFIED WITH plaintext_password BY 'test-collector';
CREATE USER IF NOT EXISTS grafana IDENTIFIED WITH plaintext_password BY 'test-grafana';
ALTER USER collector SETTINGS PROFILE 'collector_profile';
ALTER USER grafana SETTINGS PROFILE 'grafana_profile';
SQL
    then
      users_ok=1
      break
    fi
    echo "[monitoring-validate] clickhouse user setup attempt $attempt failed, retrying..." >&2
    clickhouse_diagnostics
    if ! wait_for_clickhouse; then
      clickhouse_diagnostics
      exit 1
    fi
    sleep 2
  done
  if [[ "$users_ok" -ne 1 ]]; then
    echo "[monitoring-validate] FAILED: ClickHouse user setup after retries" >&2
    clickhouse_diagnostics
    exit 1
  fi
  # Create otel_logs minimal table so MV creation works.
  logs_table_ok=0
  for attempt in 1 2 3; do
    if docker exec -i "$CH_CID" clickhouse-client --multiquery <<'SQL'
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
    then
      logs_table_ok=1
      break
    fi
    echo "[monitoring-validate] clickhouse logs table setup attempt $attempt failed, retrying..." >&2
    clickhouse_diagnostics
    if ! wait_for_clickhouse; then
      clickhouse_diagnostics
      exit 1
    fi
    sleep 2
  done
  if [[ "$logs_table_ok" -ne 1 ]]; then
    echo "[monitoring-validate] FAILED: ClickHouse logs table setup after retries" >&2
    clickhouse_diagnostics
    exit 1
  fi
  if ! wait_for_clickhouse; then
    echo "[monitoring-validate] ClickHouse became unavailable after user setup" >&2
    clickhouse_diagnostics
    exit 1
  fi
  for f in dev-ops/factory/monitoring/clickhouse/init/*.sql; do
    echo "+ clickhouse init $f"
    ok=0
    for attempt in 1 2 3; do
      if sed 's/__CLICKHOUSE_TTL_DAYS__/400/g' "$f" | docker exec -i "$CH_CID" clickhouse-client --multiquery; then
        ok=1
        break
      fi
      echo "[monitoring-validate] clickhouse init attempt $attempt failed for $f, retrying..." >&2
      clickhouse_diagnostics
      for _ in $(seq 1 30); do
        if docker exec "$CH_CID" clickhouse-client --query "SELECT 1" >/dev/null 2>&1; then break; fi
        sleep 1
      done
      sleep 2
    done
    if [[ "$ok" -ne 1 ]]; then
      echo "[monitoring-validate] FAILED: clickhouse init $f" >&2
      clickhouse_diagnostics
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
GRANT SELECT ON system.parts TO grafana;
SQL

  # Exercise the real init script, including the additional ClickHouse grants
  # required before Langfuse v4 starts.
  if ! docker exec \
    -e CH_HOST=127.0.0.1 \
    -e CLICKHOUSE_COLLECTOR_PASSWORD=test-collector \
    -e CLICKHOUSE_GRAFANA_PASSWORD=test-grafana \
    -e CLICKHOUSE_TTL_DAYS=400 \
    -e LANGFUSE_CLICKHOUSE_PASSWORD=test-langfuse-clickhouse \
    "$CH_CID" /bin/bash /clickhouse-init.sh; then
    echo "[monitoring-validate] FAILED: clickhouse-init.sh" >&2
    clickhouse_diagnostics
    exit 1
  fi
  langfuse_grants="$(docker exec "$CH_CID" clickhouse-client --query "SHOW GRANTS FOR langfuse")"
  for required_grant in system.parts system.mutations system.tables system.processes system.query_log 'SYSTEM MERGES'; do
    if ! grep -qF "$required_grant" <<<"$langfuse_grants"; then
      echo "[monitoring-validate] FAILED: missing Langfuse ClickHouse grant: $required_grant" >&2
      printf '%s\n' "$langfuse_grants" >&2
      exit 1
    fi
  done
  # ClickHouse accepts ALTER SETTINGS before the backfill table exists but does
  # not list it separately in SHOW GRANTS. Verify the effective permission.
  docker exec "$CH_CID" clickhouse-client --user langfuse \
    --password test-langfuse-clickhouse --query \
    "CREATE TABLE IF NOT EXISTS langfuse.observations_pid_tid_sorting (id UInt64, PROJECTION latest_source_versions (SELECT id ORDER BY id)) ENGINE = ReplacingMergeTree ORDER BY id SETTINGS deduplicate_merge_projection_mode = 'rebuild', lightweight_mutation_projection_mode = 'rebuild'"
  if ! docker exec "$CH_CID" clickhouse-client --user langfuse \
    --password test-langfuse-clickhouse --query \
    "ALTER TABLE langfuse.observations_pid_tid_sorting MODIFY SETTING index_granularity = 8192"; then
    echo "[monitoring-validate] FAILED: Langfuse cannot alter backfill table settings" >&2
    clickhouse_diagnostics
    exit 1
  fi
  docker exec "$CH_CID" clickhouse-client --query "DROP TABLE langfuse.observations_pid_tid_sorting"

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

# Dashboard JSON validation and generator freshness.
shopt -s nullglob
dashboards=(dev-ops/factory/monitoring/grafana/dashboards/*.json)
if [ ${#dashboards[@]} -eq 0 ]; then
  echo "[monitoring-validate] no dashboard JSON files (placeholder ok)"
else
  for f in "${dashboards[@]}"; do
    run jq empty "$f"
  done
fi
if [ -f dev-ops/factory/monitoring/scripts/generate_dashboards.py ]; then
  TMP_DASH="$(mktemp -d)"
  cp -r dev-ops/factory/monitoring/grafana/dashboards "$TMP_DASH/dashboards.bak"
  run python3 dev-ops/factory/monitoring/scripts/generate_dashboards.py
  if ! diff -ru "$TMP_DASH/dashboards.bak" dev-ops/factory/monitoring/grafana/dashboards; then
    echo "[monitoring-validate] FAILED: dashboard JSON not up to date with generator" >&2
    rm -rf dev-ops/factory/monitoring/grafana/dashboards
    mv "$TMP_DASH/dashboards.bak" dev-ops/factory/monitoring/grafana/dashboards
    TMP_DASH=""
    fail=1
  else
    rm -rf "$TMP_DASH"
    TMP_DASH=""
  fi
  run python3 dev-ops/factory/monitoring/scripts/check_dashboards.py
fi

# Grafana alerting provisioning sanity.
run python3 - <<'PYALERT'
import yaml, pathlib, sys
base = pathlib.Path('dev-ops/factory/monitoring/grafana/provisioning/alerting')
files = list(base.glob('*.yaml')) + list(base.glob('*.yml'))
if not files:
    print('no alerting provisioning files', file=sys.stderr); sys.exit(1)
uids=set(); titles=set()
for f in files:
    doc=yaml.safe_load(f.read_text())
    for g in doc.get('groups',[]) or []:
        for r in g.get('rules',[]) or []:
            u=r.get('uid'); t=r.get('title')
            if not u or not t: print(f'missing uid/title in {f}', file=sys.stderr); sys.exit(1)
            if u in uids: print(f'duplicate uid {u}', file=sys.stderr); sys.exit(1)
            uids.add(u); titles.add(t)
required={'Factory silent','Factory failing','Factory tick failed','Factory guardrail drift','Factory stuck run','Factory issue looping','Factory quota pressure','Factory deploy failed/stale','Factory telemetry broken','Factory event ingestion stale','Factory host memory high','Factory host disk high'}
missing=required-titles
if missing:
    print('missing alert titles: '+', '.join(sorted(missing)), file=sys.stderr); sys.exit(1)
print(f'alerting ok: {len(uids)} rules')
PYALERT

# The pinned collector image is distroless. A CMD-SHELL healthcheck cannot run
# because /bin/sh is absent, even though the collector itself is healthy.
run python3 - <<'PY'
import pathlib
import sys
import yaml
compose = yaml.safe_load(pathlib.Path('dev-ops/factory/monitoring/docker-compose.yml').read_text())
healthcheck = compose['services']['otel-collector'].get('healthcheck') or {}
test = healthcheck.get('test') or []
if test and test[0] == 'CMD-SHELL':
    print('otel-collector healthcheck requires /bin/sh, which is absent from the distroless image', file=sys.stderr)
    sys.exit(1)
PY

# Langfuse v4 projected-table DDL is validated against ClickHouse's default
# free-entry thresholds even when low-memory.xml overrides them. Also honor any
# larger thresholds configured locally.
run python3 - <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse('dev-ops/factory/monitoring/clickhouse/config.d/low-memory.xml').getroot()
pool = int(root.findtext('background_pool_size'))
ratio = int(root.findtext('background_merges_mutations_concurrency_ratio'))
merge_tree = root.find('merge_tree')
thresholds = [
    int(merge_tree.findtext(name, default='0'))
    for name in (
        'number_of_free_entries_in_pool_to_execute_mutation',
        'number_of_free_entries_in_pool_to_lower_max_size_of_merge',
        'number_of_free_entries_in_pool_to_execute_optimize_entire_partition',
    )
]
required = max(25, *thresholds)
if pool * ratio < required:
    print(f'ClickHouse background mutation capacity {pool * ratio} is below {required}', file=sys.stderr)
    sys.exit(1)
print(f'ClickHouse background mutation capacity={pool * ratio}')
PY

# Basic YAML/JSON sanity for configs that should always be parseable.
run python3 -c "import json,sys,pathlib; [json.load(open(p)) for p in pathlib.Path('dev-ops/factory/monitoring').rglob('*.json')]"
run python3 -c "import yaml,sys,pathlib; [yaml.safe_load(open(p)) for p in pathlib.Path('dev-ops/factory/monitoring').rglob('*.yml')] + [yaml.safe_load(open(p)) for p in pathlib.Path('dev-ops/factory/monitoring').rglob('*.yaml')]"
run python3 dev-ops/scripts/check-monitoring-hardening.py \
  --compose dev-ops/factory/monitoring/docker-compose.yml \
  --prometheus dev-ops/factory/monitoring/prometheus/prometheus.yml \
  --env-example dev-ops/factory/monitoring/.env.example

if [[ $fail -ne 0 ]]; then
  echo "[monitoring-validate] FAIL" >&2
  exit 1
fi
echo "[monitoring-validate] OK"
