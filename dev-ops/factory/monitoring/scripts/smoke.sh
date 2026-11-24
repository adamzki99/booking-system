#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
MON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$MON_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

PROJECT="factory-monitoring-smoke-$$"
TMPDIR_SMOKE="$(mktemp -d)"
LOG_DIR="$TMPDIR_SMOKE/factory-logs"
METRICS_DIR="$TMPDIR_SMOKE/factory-metrics"
ENV_FILE="$TMPDIR_SMOKE/.env"
COMPOSE=(docker compose -f dev-ops/factory/monitoring/docker-compose.yml --env-file "$ENV_FILE" -p "$PROJECT")

cleanup() {
  echo "[smoke] cleaning up..."
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$TMPDIR_SMOKE"
}
trap cleanup EXIT

mkdir -p "$LOG_DIR" "$METRICS_DIR"

# Prometheus textfile metric for tick staleness check.
cat > "$METRICS_DIR/factory_tick.prom" <<PROM
factory_tick_last_run_timestamp_seconds $(date +%s)
factory_tick_last_success_timestamp_seconds $(date +%s)
factory_tick_last_exit_code 1
factory_telemetry_errors_last 0
PROM

cat > "$ENV_FILE" <<ENV
CLICKHOUSE_COLLECTOR_PASSWORD=smoke-collector-pass
CLICKHOUSE_GRAFANA_PASSWORD=smoke-grafana-pass
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=smoke-admin-pass
HOST_NAME=smoke-host
GRAFANA_PORT=13000
OTLP_GRPC_PORT=14317
OTLP_HTTP_PORT=14318
FACTORY_LOG_DIR=$LOG_DIR
FACTORY_METRICS_DIR=$METRICS_DIR
FACTORY_MONITORING_NETWORK=factory-monitoring-smoke-$$-net
CLICKHOUSE_TTL_DAYS=400
PROMETHEUS_RETENTION_TIME=1d
PROMETHEUS_RETENTION_SIZE=256MB
ENV

# Fixture v2 events. Includes duplicate event_id and covers dashboards/alerts.
# Use recent timestamps so time-windowed dashboard queries and alerts behave predictably.
NOW_EPOCH=$(date -u +%s)
ts_iso() { date -u -d "@$1" +"%Y-%m-%dT%H:%M:%S.000Z"; }
TS5="$(ts_iso $((NOW_EPOCH - 3600)))"
TS1="$(ts_iso $((NOW_EPOCH - 900)))"
TS2="$(ts_iso $((NOW_EPOCH - 600)))"
TS3="$(ts_iso $((NOW_EPOCH - 300)))"
TS4="$(ts_iso $((NOW_EPOCH - 120)))"
TS6="$(ts_iso $((NOW_EPOCH - 60)))"
TS7="$(ts_iso "$NOW_EPOCH")"
cat > "$LOG_DIR/tick.jsonl" <<JSONL
{"schema_version":2,"event_id":"11111111111111111111111111111111","event":"tick_start","ts":"$TS5","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system"}
{"schema_version":2,"event_id":"11111111111111111111111111111112","event":"issue.detected","ts":"$TS5","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","issue_id":42,"kind":"build"}
{"schema_version":2,"event_id":"11111111111111111111111111111113","event":"issue.assigned","ts":"$TS5","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","issue_id":42,"kind":"build","agent_id":"builder"}
{"schema_version":2,"event_id":"11111111111111111111111111111114","event":"agent.run.started","ts":"$TS1","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","run_id":"run-smoke-1","attempt":1,"fallback_level":"primary","kind":"build","agent_id":"builder","agent_version":"abc123def456","prompt_version":"prompt123456","model":"test/model","issue_id":42,"session_id":"ses_smoke","trace_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","tier_label":"standard"}
{"schema_version":2,"event_id":"11111111111111111111111111111115","event":"agent.tool.called","ts":"$TS1","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","run_id":"run-smoke-1","agent_id":"builder","model":"test/model","kind":"build","tool":"shell","status":"ok","duration_ms":100}
{"schema_version":2,"event_id":"22222222222222222222222222222222","event":"agent.run.completed","ts":"$TS2","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","run_id":"run-smoke-1","attempt":1,"fallback_level":"primary","kind":"build","agent_id":"builder","agent_version":"abc123def456","prompt_version":"prompt123456","model":"test/model","issue_id":42,"session_id":"ses_smoke","trace_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","duration_ms":5000,"input_tokens":100,"output_tokens":50,"reasoning_tokens":10,"cache_read_tokens":5,"cache_write_tokens":2,"cost_usd":0.01,"tool_calls":3,"tool_errors":0}
{"schema_version":2,"event_id":"22222222222222222222222222222222","event":"agent.run.completed","ts":"$TS2","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","run_id":"run-smoke-1","attempt":1,"fallback_level":"primary","kind":"build","agent_id":"builder","agent_version":"abc123def456","prompt_version":"prompt123456","model":"test/model","issue_id":42,"session_id":"ses_smoke","trace_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","duration_ms":5000,"input_tokens":100,"output_tokens":50,"reasoning_tokens":10,"cache_read_tokens":5,"cache_write_tokens":2,"cost_usd":0.01,"tool_calls":3,"tool_errors":0}
{"schema_version":2,"event_id":"33333333333333333333333333333333","event":"pr.created","ts":"$TS2","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"reconcile","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","pr_number":99,"issue_id":42,"created_at":"$TS2","head_branch":"factory/issue-42","draft":false}
{"schema_version":2,"event_id":"33333333333333333333333333333334","event":"pr.merged","ts":"$TS3","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"reconcile","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","pr_number":99,"issue_id":42,"merged_at":"$TS3","commits":2,"additions":10,"deletions":1,"changed_files":2,"review_comments":0,"human_commits":0}
{"schema_version":2,"event_id":"33333333333333333333333333333335","event":"issue.approved","ts":"$TS5","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"reconcile","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","issue_id":42,"approved_at":"$TS5"}
{"schema_version":2,"event_id":"33333333333333333333333333333336","event":"issue.closed","ts":"$TS4","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"reconcile","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","issue_id":42,"closed_at":"$TS4","state_reason":"completed"}
{"schema_version":2,"event_id":"44444444444444444444444444444441","event":"factory.queue","ts":"$TS6","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","infant":1,"planned":2,"approved_waiting":1,"in_pr":1,"blocked_pr":0}
{"schema_version":2,"event_id":"55555555555555555555555555555551","event":"agent.run.failed","ts":"$TS4","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","run_id":"run-quota","attempt":1,"fallback_level":"primary","kind":"build","agent_id":"builder","model":"test/model","issue_id":42,"failure_reason":"usage_filled","exit_code":1,"duration_ms":1000,"outcome":"failed"}
{"schema_version":2,"event_id":"55555555555555555555555555555552","event":"agent.run.started","ts":"$TS4","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","run_id":"run-free-1","attempt":2,"fallback_level":"free","kind":"build","agent_id":"builder","model":"test/free","issue_id":42}
{"schema_version":2,"event_id":"55555555555555555555555555555553","event":"agent.run.started","ts":"$TS4","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","run_id":"run-free-2","attempt":2,"fallback_level":"free","kind":"build","agent_id":"builder","model":"test/free","issue_id":42}
{"schema_version":2,"event_id":"55555555555555555555555555555554","event":"agent.run.started","ts":"$TS4","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","run_id":"run-free-3","attempt":2,"fallback_level":"free","kind":"build","agent_id":"builder","model":"test/free","issue_id":42}
{"schema_version":2,"event_id":"44444444444444444444444444444442","event":"tick_end","ts":"$TS6","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-1","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","exit_code":0,"duration_ms":120000,"telemetry_errors":0}
{"schema_version":2,"event_id":"44444444444444444444444444444443","event":"tick_end","ts":"$TS7","service.name":"factory-tick","factory_id":"factory-1","deployment.environment":"dev","host.name":"smoke-host","tick_id":"tick-smoke-2","dry_run":false,"on_usage_filled":"backup","repo":"adamzki99/booking-system","exit_code":1,"duration_ms":1000,"telemetry_errors":1}
JSONL

echo "[smoke] starting stack..."
"${COMPOSE[@]}" up -d

collector_cid=$("${COMPOSE[@]}" ps -q otel-collector)
collector_health=""
for _ in $(seq 1 30); do
  collector_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$collector_cid")"
  if [[ "$collector_health" == "healthy" || "$collector_health" == "none" ]]; then break; fi
  sleep 2
done
if [[ "$collector_health" != "healthy" && "$collector_health" != "none" ]]; then
  echo "[smoke] collector healthcheck failed: $collector_health" >&2
  "${COMPOSE[@]}" logs otel-collector >&2 || true
  exit 1
fi

echo "[smoke] waiting for clickhouse..."
for _ in $(seq 1 120); do
  if "${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT 1" >/dev/null 2>&1; then break; fi
  sleep 2
done
"${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT 1" >/dev/null

echo "[smoke] waiting for events in factory.events..."
for _ in $(seq 1 120); do
  count=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM factory.events FINAL" 2>/dev/null || echo 0)
  if [ "$count" -ge 10 ]; then break; fi
  sleep 2
done
count=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM factory.events FINAL")
echo "[smoke] factory.events FINAL count=$count"
[ "$count" -ge 10 ] || { echo "[smoke] expected >=10 events" >&2; exit 1; }

# Duplicate event_id should collapse: 4 lines inserted but 3 unique event_ids.
raw=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM factory.events")
echo "[smoke] factory.events raw count=$raw"

run_count=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM factory.runs")
echo "[smoke] factory.runs count=$run_count"
[ "$run_count" -eq 5 ] || { echo "[smoke] expected 5 runs" >&2; exit 1; }

# Timestamp equality check - ts stored should match fixture ts.
ts1=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT toString(ts) FROM factory.events FINAL WHERE event_id='11111111111111111111111111111111'")
expected_ts1=$(date -u -d "$TS5" +"%Y-%m-%d %H:%M:%S.000")
echo "[smoke] ts1=$ts1 expected=$expected_ts1"
echo "$ts1" | grep -q "$expected_ts1" || { echo "[smoke] timestamp mismatch" >&2; exit 1; }

# pr.merged landed
pr=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM factory.events FINAL WHERE event='pr.merged'")
echo "[smoke] pr.merged count=$pr"
[ "$pr" -eq 1 ] || { echo "[smoke] expected pr.merged" >&2; exit 1; }

quota=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT if(countIf(event='agent.run.failed' AND failure_reason IN ('usage_filled','usage_filled_skipped')) > 0 OR countIf(event='agent.run.started' AND fallback_level = 'free') > 2, 1, 0) AS value FROM factory.events FINAL WHERE ts >= now() - INTERVAL 24 HOUR AND event IN ('agent.run.failed','agent.run.started')")
[ "$quota" -eq 1 ] || { echo "[smoke] quota alert query did not match failure fixtures" >&2; exit 1; }

telemetry=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT if(argMaxIf(toInt64OrNull(attrs['telemetry_errors']), ts, event='tick_end') > 0, 1, 0) AS value FROM factory.events FINAL WHERE ts >= now() - INTERVAL 24 HOUR AND event='tick_end'")
[ "$telemetry" -eq 1 ] || { echo "[smoke] telemetry alert query did not match tick_end fixture" >&2; exit 1; }

ingestion=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT if(countIf(event='tick_end' AND ts >= now() - INTERVAL 2 HOUR) = 0, 1, 0) AS value FROM factory.events FINAL WHERE ts >= now() - INTERVAL 2 HOUR")
[ "$ingestion" -eq 0 ] || { echo "[smoke] recent tick_end incorrectly flagged ingestion as stale" >&2; exit 1; }

# Prometheus target and metric
echo "[smoke] waiting for prometheus..."
for _ in $(seq 1 90); do
  if "${COMPOSE[@]}" exec -T prometheus wget -qO- http://127.0.0.1:9090/-/healthy >/dev/null 2>&1; then break; fi
  sleep 2
done
"${COMPOSE[@]}" exec -T prometheus wget -qO- http://127.0.0.1:9090/-/healthy >/dev/null
targets=$("${COMPOSE[@]}" exec -T prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/targets' || true)
echo "$targets" | grep -q node-exporter || { echo "[smoke] node-exporter target missing" >&2; exit 1; }
echo "$targets" | python3 -c 'import sys,json; d=json.load(sys.stdin); active=d.get("data",{}).get("activeTargets",[]); ne=[t for t in active if t.get("labels",{}).get("job")=="node-exporter"]; print(ne[0]["health"] if ne else "missing")' | grep -q up || echo "[smoke] WARN: node-exporter target not up yet"
echo "$targets" | python3 -c 'import sys,json; d=json.load(sys.stdin); active=d.get("data",{}).get("activeTargets",[]); collector=[t for t in active if t.get("labels",{}).get("job")=="otel-collector"]; print(collector[0]["health"] if collector else "missing")' | grep -q up || { echo "[smoke] otel-collector target is not up" >&2; exit 1; }

# metric query
for _ in $(seq 1 60); do
  m=$("${COMPOSE[@]}" exec -T prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=factory_tick_last_run_timestamp_seconds' || true)
  echo "$m" | grep -q '"status":"success"' && echo "$m" | grep -q 'factory_tick_last_run_timestamp_seconds' && break
  sleep 2
done
m=$("${COMPOSE[@]}" exec -T prometheus wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=factory_tick_last_run_timestamp_seconds' || true)
echo "$m" | grep -q 'factory_tick_last_run_timestamp_seconds' || { echo "[smoke] metric missing" >&2; exit 1; }

assert_metric() {
  local metric="$1" expected="$2" response value
  response=$("${COMPOSE[@]}" exec -T prometheus wget -qO- "http://127.0.0.1:9090/api/v1/query?query=$metric" || true)
  value="$(printf '%s' "$response" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["data"]["result"][0]["value"][1])')"
  [ "$value" = "$expected" ] || { echo "[smoke] unexpected $metric value: $value" >&2; exit 1; }
}
assert_metric factory_tick_last_exit_code 1
# ClickHouse carries the telemetry error while the Prometheus counter is zero.
assert_metric factory_telemetry_errors_last 0

assert_prom_expr() {
  local expr="$1" expected="$2" encoded response value
  encoded="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$expr")"
  response=$("${COMPOSE[@]}" exec -T prometheus wget -qO- "http://127.0.0.1:9090/api/v1/query?query=$encoded" || true)
  value="$(printf '%s' "$response" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["data"]["result"][0]["value"][1])')"
  [ "$value" = "$expected" ] || { echo "[smoke] unexpected PromQL value for $expr: $value" >&2; exit 1; }
}
assert_prom_expr '(factory_tick_last_exit_code != bool 0) or vector(0)' 1
assert_prom_expr '(factory_telemetry_errors_last > bool 0) or vector(0)' 0
assert_prom_expr '((time() - factory_tick_last_run_timestamp_seconds) < bool 7200) or vector(0)' 1

# Grafana health and datasources
echo "[smoke] waiting for grafana..."
for _ in $(seq 1 120); do
  if curl -fsS http://127.0.0.1:13000/api/health >/dev/null 2>&1; then break; fi
  sleep 2
done
grafana_health="$(curl -fsS http://127.0.0.1:13000/api/health || true)"
if ! printf '%s' "$grafana_health" | grep -q ok; then
  echo "[smoke] grafana not healthy" >&2
  "${COMPOSE[@]}" logs --tail=200 grafana >&2 || true
  exit 1
fi

# datasource health (basic auth)
grafana_basic_auth="$(printf '%s' 'admin:smoke-admin-pass' | base64)"
for uid in clickhouse-factory prometheus-factory; do
  echo "[smoke] checking datasource $uid"
  ok=0
  for _ in $(seq 1 60); do
    resp=$(curl -fsS -H "Authorization: Basic $grafana_basic_auth" "http://127.0.0.1:13000/api/datasources/uid/$uid/health" || true)
    if echo "$resp" | grep -q '"status":"OK"\|"status":"ok"'; then ok=1; break; fi
    sleep 2
  done
  [ "$ok" -eq 1 ] || { echo "[smoke] datasource $uid unhealthy: $resp" >&2; exit 1; }
done

# Dashboards provisioned
echo "[smoke] checking dashboards..."
dash_resp=$(curl -fsS -H "Authorization: Basic $grafana_basic_auth" 'http://127.0.0.1:13000/api/search?type=dash-db&tag=factory')
echo "$dash_resp" | python3 -c 'import sys,json; d=json.load(sys.stdin); uids={x.get("uid") for x in d}; req={"factory-overview","factory-agents","factory-execution","factory-cost","factory-quality","factory-host"}; missing=req-uids; print("uids",sorted(uids)); sys.exit(1 if missing else 0)' || { echo "[smoke] missing dashboards: $dash_resp" >&2; exit 1; }

# Alert rules provisioned
echo "[smoke] checking alert rules..."
alert_resp=$(curl -fsS -H "Authorization: Basic $grafana_basic_auth" 'http://127.0.0.1:13000/api/v1/provisioning/alert-rules')
echo "$alert_resp" | python3 -c 'import sys,json; d=json.load(sys.stdin); titles={x.get("title") for x in d}; req={"Factory silent","Factory failing","Factory tick failed","Factory guardrail drift","Factory stuck run","Factory issue looping","Factory quota pressure","Factory deploy failed/stale","Factory telemetry broken","Factory event ingestion stale","Factory host memory high","Factory host disk high"}; missing=req-titles; print("alerts",len(titles)); sys.exit(1 if missing else 0)' || { echo "[smoke] missing alert rules: $alert_resp" >&2; exit 1; }

# Key ClickHouse query per dashboard (bounded) returns at least one row.
echo "[smoke] checking dashboard key queries..."
q_overview=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM factory.runs WHERE started_at >= now() - INTERVAL 1 DAY")
[ "$q_overview" -ge 1 ] || { echo "[smoke] overview query empty" >&2; exit 1; }
q_agents=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM factory.runs WHERE agent_id!='' AND started_at >= now() - INTERVAL 1 DAY")
[ "$q_agents" -ge 1 ] || { echo "[smoke] agents query empty" >&2; exit 1; }
q_exec=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM factory.tool_calls WHERE ts >= now() - INTERVAL 1 DAY")
[ "$q_exec" -ge 1 ] || { echo "[smoke] execution query empty" >&2; exit 1; }
q_cost=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM factory.runs WHERE cost_usd IS NOT NULL AND started_at >= now() - INTERVAL 1 DAY")
[ "$q_cost" -ge 1 ] || { echo "[smoke] cost query empty" >&2; exit 1; }
q_quality=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM factory.pr_outcomes WHERE merged_at IS NOT NULL")
[ "$q_quality" -ge 1 ] || { echo "[smoke] quality query empty" >&2; exit 1; }
q_host=$("${COMPOSE[@]}" exec -T clickhouse clickhouse-client --query "SELECT count() FROM factory.events FINAL WHERE ts >= now() - INTERVAL 1 DAY")
[ "$q_host" -ge 1 ] || { echo "[smoke] host/support query empty" >&2; exit 1; }

echo "[smoke] OK"
