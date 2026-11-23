# Factory monitoring stack

Persistent, reproducible Docker Compose stack for factory observability. It ingests
factory JSONL events and host metrics, stores factory events for analytics in
ClickHouse, and serves Grafana with provisioned datasources.

This stack monitors the AI software factory (ticks, agent runs, tokens/cost,
GitHub delivery outcomes, deploys, and factory host health). It is one instance per
factory host.

- Compose project: `factory-monitoring`
- Network: `factory-monitoring-net` (created by this stack, not external)
- Source of truth for issues/PRs: GitHub
- Factory event model: `dev-ops/factory/EVENTS.md` (independent of Langfuse)

## Architecture

```text
factory tick/deploy
  -> FACTORY_LOG_FILE (JSONL, append-only)
  -> otel-collector filelog receiver (file_storage offsets)
  -> ClickHouse otel.otel_logs
  -> materialized view factory.events_mv
  -> ClickHouse factory.events (ReplacingMergeTree, dedup by event_id)
  -> views: factory.runs, factory.issues, factory.daily, factory.stuck_runs
  -> Grafana (ClickHouse datasource, read-only user)

node-exporter + factory textfile metrics -> Prometheus -> Grafana
collector/clickhouse/grafana/prometheus self-metrics -> Prometheus
```

Grafana dashboards and alert rules are provisioned from git (prompt 04). Langfuse
is added by prompt 05. SigNoz removal is handled by prompt 09; this stack does not
depend on SigNoz.

## Pinned versions

| Component | Image | Version | Notes |
|---|---|---:|---|
| OpenTelemetry Collector Contrib | `otel/opentelemetry-collector-contrib` | `0.165.0` | filelog + clickhouse exporter + health_check |
| ClickHouse | `clickhouse/clickhouse-server` | `26.9.36.3` | single node, no ZooKeeper |
| Prometheus | `prom/prometheus` | `v3.16.0` | local TSDB |
| Node Exporter | `prom/node-exporter` | `v1.13.1` | host + textfile collector |
| Grafana OSS | `grafana/grafana` | `13.3.1` | provisioned datasources |
| Grafana ClickHouse plugin | `grafana-clickhouse-datasource` | `4.23.5` | pinned via `GF_PLUGINS_PREINSTALL` |

Check versions on vendor release pages/registries before bumping.

## Setup

1. Copy env file and fill required secrets:

```sh
cd dev-ops/factory/monitoring
cp .env.example .env
# edit .env: set CLICKHOUSE_COLLECTOR_PASSWORD, CLICKHOUSE_GRAFANA_PASSWORD,
# GRAFANA_ADMIN_PASSWORD, HOST_NAME, FACTORY_LOG_DIR, FACTORY_METRICS_DIR
```

2. Create host directories if needed:

```sh
mkdir -p "${FACTORY_LOG_DIR:-$HOME/.local/state/factory}"
mkdir -p "${FACTORY_METRICS_DIR:-$HOME/.local/state/factory/metrics}"
```

3. Start:

```sh
docker compose up -d
```

Startup fails fast if required secrets are empty (compose interpolation and check-env).

## Commands

```sh
# start
docker compose up -d

# status / logs
docker compose ps
docker compose logs -f --tail=200

# stop (keep volumes)
docker compose down

# stop and remove volumes (destructive)
docker compose down -v
```

Run commands from `dev-ops/factory/monitoring/`.

## Endpoints (127.0.0.1 only)

| Endpoint | Default | Notes |
|---|---|---|
| Grafana UI | `127.0.0.1:${GRAFANA_PORT:-3000}` | admin password from `.env`, anonymous off |
| OTLP gRPC | `127.0.0.1:${OTLP_GRPC_PORT:-4317}` | for local/remote OTLP senders |
| OTLP HTTP | `127.0.0.1:${OTLP_HTTP_PORT:-4318}` | for local/remote OTLP senders |

Prometheus and ClickHouse are not published by default. Reach them via:

```sh
docker compose exec prometheus wget -qO- http://127.0.0.1:9090/-/healthy
docker compose exec clickhouse clickhouse-client --query "SELECT 1"
```

Or use an SSH tunnel when needed.

## Event ingestion

### Same host (default)

`tick.sh` and `deploy-environment.sh` append v2 JSONL events to
`FACTORY_LOG_FILE` (default `${XDG_STATE_HOME:-~/.local/state}/factory/tick.jsonl`).
Mount that directory read-only into the collector with `FACTORY_LOG_DIR`.

The collector uses `filelog` with `file_storage` offsets so restarts do not lose
or duplicate data, and `start_at: beginning` for first-run backfill.

### Remote shipper (optional)

If `tick.sh` runs on another machine, use `dev-ops/factory/otel-collector.yaml`
as a remote shipper. It tails the same JSONL with `file_storage`, applies the same
parsing/redaction, and exports OTLP/HTTP to `FACTORY_OTLP_ENDPOINT`. It does not
send a SigNoz ingestion key.

### Rotation/copytruncate

`factory-tick.logrotate` uses `copytruncate`. The collector filelog receiver tracks
files by fingerprint; with `start_at: beginning` and file_storage offsets, normal
append is stable. A copytruncate event can be sensitive to fingerprint changes;
verify with `scripts/smoke.sh` and monitor duplicate counts in ClickHouse
(`ReplacingMergeTree` dedups by `event_id`, and dashboard queries should use FINAL
or argMax). Document any observed duplication in the PR/incident notes.

## Schema and idempotency

ClickHouse init SQL is in `clickhouse/init/` and applied idempotently by
`clickhouse-init`.

We own the otel log/trace table DDL (`create_schema: false` in collector exporter)
so materialized view creation is deterministic. The init service creates `otel`
and `factory` databases, otel tables, `factory.events`, `factory.events_mv`, and
views. The exporter uses `IF NOT EXISTS` behavior and inserts into existing tables.

`factory.events` is `ReplacingMergeTree(ts)` ordered by `event_id`, partitioned by
month, with TTL from `CLICKHOUSE_TTL_DAYS` (default 400). Views use `FINAL`/`argMax`
to avoid duplicate double-counting.

Users:
- `collector`: INSERT on `otel.otel_logs`, `otel.otel_traces`, `factory.events`; SELECT on `otel.otel_logs` for MV internals.
- `grafana`: SELECT on `factory.*`, `otel.otel_traces`, `otel.otel_logs`; `readonly=2` profile with query limits.

Passwords come from env; compose fails fast when required secrets are empty.

## Retention and backups

- ClickHouse event TTL: `CLICKHOUSE_TTL_DAYS` (default 400 days).
- ClickHouse system log tables have short TTLs configured in `config.d/low-memory.xml`.
- Prometheus retention: `PROMETHEUS_RETENTION_TIME` (15d) and `PROMETHEUS_RETENTION_SIZE` (2GB).

Backups (manual, documented; not automated here):

```sh
# simple local backup of factory tables
docker compose exec clickhouse clickhouse-client --query \
  "BACKUP DATABASE factory TO Disk('backups', 'factory-backup-{timestamp}')"
```

Configure a ClickHouse backup disk before using `BACKUP TO Disk(...)`, or use
`clickhouse-backup` for object storage workflows. Verify restore in a throwaway
container before relying on backups.

## Security defaults

- All published ports bind to `127.0.0.1`.
- No default passwords; required secrets come from `.env` and startup fails if empty.
- Grafana anonymous access off, sign-up off, update checks off.
- ClickHouse users are least-privilege (`collector` insert, `grafana` read-only).
- Collector redacts common sensitive keys (`output_tail`, token/password/secret/authorization/api key patterns) as defence in depth.

## Resource budget

Suggested starting limits (small shared host, ~3.2 GB RAM total):

| Service | Memory limit |
|---|---:|
| clickhouse | 768m |
| grafana | 256m |
| prometheus | 256m |
| otel-collector | 192m |
| node-exporter | 64m |
| clickhouse-init/check-env | one-shot, negligible |

Total always-on monitoring budget: ~1.54 GB. Update `dev-ops/README.md` with real
numbers after observing load. If totals exceed host budget, state it honestly and
reduce retention/scrape frequency before adding services.

## Dashboards

Provisioned from `grafana/dashboards/*.json` (generated from
`scripts/generate_dashboards.py`). All dashboards are in Grafana folder `Factory`,
have stable UIDs, include template variables `factory_id`, `agent_id`, `model`,
`kind`, and a time range, and use bounded ClickHouse queries with `$__timeFilter(...)`.

| UID | Dashboard | Answers |
|---|---|---|
| `factory-overview` | Factory overview | Issues processed/completed, run success rate, active agents, avg pickup-to-merge, tokens/cost, throughput over time, last tick age, current queue snapshot, recent merged PRs. |
| `factory-agents` | Agent performance | Per agent/version/model: runs, success rate, duration, cost/successful issue, fallback share, PR touch count; prompt version breakdown; leaderboard by merged PRs per run hour (EVENTS.md agent efficiency). |
| `factory-execution` | Execution analytics | Runs/hour, duration p50/p90, top tools, skill loads, failures by reason/fingerprint, issues with most runs, retries/fallbacks/operational events, stuck runs. |
| `factory-cost` | Cost and efficiency | Reported cost and tokens by time/model/agent/kind; cost per merged PR and tokens per merged PR (approx); usage-filled/backup/free share. Cost is as reported by OpenCode and may be 0 for subscription models. |
| `factory-quality` | Quality and outcomes | PR acceptance rate, human intervention proxy, lead time p50/p90, first-pass success, rework/abandonment, CI/check outcomes, review comments. |
| `factory-host` | Factory host | Host CPU/memory/disk/load, collector records, per-container memory (if cAdvisor metrics present), ClickHouse disk by table (best effort), Prometheus TSDB size. |

Regenerate dashboards:

```sh
python3 dev-ops/factory/monitoring/scripts/generate_dashboards.py
```

## Alerts

Grafana-managed alerts are provisioned from `grafana/provisioning/alerting/`.
Contact point: `factory-default` (webhook + email receivers), configured via env.
If no real contact is configured, alerts still evaluate and appear in Grafana;
delivery may fail to the default no-op endpoints. Notification policy groups by
`alertname` and repeats at most every 4 hours.

| Alert | Condition (default) | Severity | Runbook |
|---|---|---|---|
| Factory silent | No successful tick for 2h (`time() - factory_tick_last_success_timestamp_seconds > 7200`) | critical | Check factory timer/service, tick logs, and textfile metric freshness in `FACTORY_METRICS_DIR`. Confirm deploy/tick jobs are running. |
| Factory failing | Run failure rate > 50% over 6h with >=3 runs, or any `discovery_failed` | critical | Inspect Execution Analytics, failed runs, `discovery_failed`, `gh_op_failed`, auth/quota/rate-limit errors. Do not weaken gates. |
| Factory guardrail drift | Any `guardrail_drift` in last 2h | critical | Stop and inspect guardrail drift event. Diff `AGENTS.md`, `opencode.jsonc`, `.opencode/agents/` against `factory-config` tag before any merge. |
| Factory stuck run | Any row in `factory.stuck_runs` (>3900s started, no end) | warning | Inspect stuck run details, session logs, OpenCode process, host load. Diagnose before killing processes; preserve logs. |
| Factory issue looping | Same issue has >3 runs in 24h | warning | Inspect issue runs/failures/PR feedback. May need human clarification, issue split, or factory fix; do not blindly retry. |
| Factory quota pressure | Any `usage_filled`, or more than 2 `free_retry` in 24h | warning | Check Cost & Efficiency and Execution dashboards. Confirm OpenCode quota, fallback behavior, and whether backup/free models are acceptable. |
| Factory deploy failed/stale | Any `deploy.failed` in 26h, or QA deploy started but no `deploy.completed` in 26h | critical | Check deploy logs, QA timer, `deploy-environment.sh` output, and QA deployment GitHub issue. Fix cause before rerun. |
| Factory telemetry broken | `telemetry_errors > 0` on latest tick_end in 24h, or no factory events ingested for 2h while ticks run | warning | Check collector logs, ClickHouse ingestion, filelog offsets, `FACTORY_LOG_DIR` mount, and tick_end telemetry_errors. |
| Factory host memory high | Host memory > 90% for 10m | warning | Check host dashboard and container memory. Reduce retention/scrape or stop nonessential services; do not start optional monitoring on an exhausted host. |
| Factory host disk high | Any filesystem > 85% for 10m | warning | Check disk dashboard, ClickHouse/Prometheus volumes, Docker logs/artifacts. Clean safely; preserve evidence. |

## Alert contact env vars

Set in `.env` (optional):

- `ALERT_EMAIL_TO`: e-mail recipient(s), comma-separated. Requires `GF_SMTP_*`.
- `ALERT_WEBHOOK_URL`: webhook endpoint (ntfy/Slack/Discord/custom).
- `GF_SMTP_ENABLED`, `GF_SMTP_HOST`, `GF_SMTP_USER`, `GF_SMTP_PASSWORD`,
  `GF_SMTP_FROM_ADDRESS`, `GF_SMTP_FROM_NAME`.

## Validation and smoke

```sh
# static validation (docker required for full checks)
dev-ops/factory/monitoring/scripts/validate.sh

# end-to-end smoke (docker required; creates and tears down its own temp project)
dev-ops/factory/monitoring/scripts/smoke.sh
```

`validate.sh` also checks that generated dashboard JSON is up to date and that
alert provisioning contains the required rule titles. `smoke.sh` boots a
temporary stack, ingests fixture events, checks datasources, verifies
provisioned dashboards and alert rules, and asserts one key ClickHouse query per
dashboard returns rows.

## Troubleshooting

- **Collector not ingesting**: check `docker compose logs otel-collector`; confirm
  `FACTORY_LOG_DIR` is mounted and contains `.jsonl` files; inspect file_storage volume.
- **ClickHouse MV missing data**: ensure `otel.otel_logs` has rows and `factory.events_mv`
  exists; check collector exporter errors.
- **Grafana datasource unhealthy**: verify ClickHouse password in `.env` and that
  plugin `grafana-clickhouse-datasource@4.23.5` is installed.
- **High memory**: lower ClickHouse caches/max_server_memory_usage, reduce Prometheus
  retention, and keep only required scrape targets.

## Upgrade procedure

1. Bump image tags in `docker-compose.yml` and this README table.
2. Run `scripts/validate.sh`.
3. Run `scripts/smoke.sh` on a docker host.
4. `docker compose pull && docker compose up -d`.
5. Verify Grafana health, datasource health, and ClickHouse row counts.
