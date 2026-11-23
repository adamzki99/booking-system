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

Dashboards and alert rules are added by prompt 04. Langfuse is added by prompt 05.
SigNoz removal is handled by prompt 09; this stack does not depend on SigNoz.

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

## Validation and smoke

```sh
# static validation (docker required for full checks)
dev-ops/factory/monitoring/scripts/validate.sh

# end-to-end smoke (docker required; creates and tears down its own temp project)
dev-ops/factory/monitoring/scripts/smoke.sh
```

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
