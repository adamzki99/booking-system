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

The collector image is distroless and has no `/bin/sh` or `wget`, so the stack
does not define an invalid Docker healthcheck. Collector availability is checked
through its Prometheus target and through factory event ingestion.

Grafana dashboards and alert rules are provisioned from git. Langfuse is available
as an optional profile. This stack is independent of any external APM vendor.

## Pinned versions

| Component                       | Image                                  |       Version | Notes                                        |
| ------------------------------- | -------------------------------------- | ------------: | -------------------------------------------- |
| OpenTelemetry Collector Contrib | `otel/opentelemetry-collector-contrib` |     `0.165.0` | filelog + clickhouse exporter + health_check |
| ClickHouse                      | `clickhouse/clickhouse-server`         | `26.10.4.207` | single node, no ZooKeeper                    |
| Prometheus                      | `prom/prometheus`                      |     `v3.16.0` | local TSDB                                   |
| Node Exporter                   | `prom/node-exporter`                   |     `v1.13.1` | host + textfile collector                    |
| Grafana OSS                     | `grafana/grafana`                      |      `13.3.1` | provisioned datasources                      |
| Grafana ClickHouse plugin       | `grafana-clickhouse-datasource`        |      `4.23.5` | pinned via `GF_PLUGINS_PREINSTALL`           |

Check versions on vendor release pages/registries before bumping.

## Setup

1. Copy env file and fill required secrets:

```sh
cd dev-ops/factory/monitoring
cp .env.example .env
# edit .env: set CLICKHOUSE_COLLECTOR_PASSWORD, CLICKHOUSE_GRAFANA_PASSWORD,
# GRAFANA_ADMIN_PASSWORD, GRAFANA_METRICS_PASSWORD, HOST_NAME, FACTORY_LOG_DIR,
# FACTORY_METRICS_DIR, and the browser-reachable GRAFANA_ROOT_URL
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

### Operator action before redeploy

- Set the new required `GRAFANA_METRICS_PASSWORD` in `.env`. The one-shot
  `check-env` service writes it to a private file in the `grafana-metrics-auth`
  volume for Prometheus. Grafana uses the fixed username `prometheus`; the
  password is not committed or placed directly in `prometheus.yml`.
- Keep `GRAFANA_BIND_ADDR=127.0.0.1` and `OTLP_BIND_ADDR=127.0.0.1` for local-only
  access. To keep reaching Grafana or OTLP on the LAN, explicitly set the
  relevant bind address to `0.0.0.0` and restrict access with a firewall. These
  services use plain HTTP unless fronted by TLS (Caddy, Tailscale Serve, or an
  SSH tunnel).
- Set `GRAFANA_ROOT_URL` to the full browser-reachable Grafana URL, including the
  trailing slash and any reverse-proxy sub-path. For direct LAN access this is
  typically `http://<host>:3000/`; for a TLS proxy use its HTTPS URL.
- If the Langfuse profile is exposed, set `LANGFUSE_BIND_ADDR` deliberately and
  set `LANGFUSE_PUBLIC_URL` to the browser-reachable base URL. The one-shot
  `check-env` service renders that value into the provisioned Run Detail
  dashboard before Grafana starts.

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

## Endpoints (loopback by default)

| Endpoint                         | Default                                                   | Notes                                     |
| -------------------------------- | --------------------------------------------------------- | ----------------------------------------- |
| Grafana UI                       | `${GRAFANA_BIND_ADDR:-127.0.0.1}:${GRAFANA_PORT:-3000}`   | admin password from `.env`, anonymous off |
| OTLP gRPC                        | `${OTLP_BIND_ADDR:-127.0.0.1}:${OTLP_GRPC_PORT:-4317}`    | for local/remote OTLP senders             |
| OTLP HTTP                        | `${OTLP_BIND_ADDR:-127.0.0.1}:${OTLP_HTTP_PORT:-4318}`    | for local/remote OTLP senders             |
| Langfuse UI (`langfuse` profile) | `${LANGFUSE_BIND_ADDR:-127.0.0.1}:${LANGFUSE_PORT:-3001}` | optional profile                          |

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
parsing/redaction, and exports OTLP/HTTP to `FACTORY_OTLP_ENDPOINT`.

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
- The ClickHouse background pool has 16 slots so Langfuse v4 projected MergeTree migrations satisfy ClickHouse's default mutation thresholds.
- Prometheus retention: `PROMETHEUS_RETENTION_TIME` (15d) and `PROMETHEUS_RETENTION_SIZE` (2GB).

Backups are manual and are not automated by this stack. Configure and
restore-test a ClickHouse backup disk before relying on `BACKUP TO Disk(...)`,
or use `clickhouse-backup` for object storage workflows. For a pre-upgrade backup,
stop writers and take synchronous backups of every database in use:

```sh
# from dev-ops/factory/monitoring
docker compose stop otel-collector
# When the langfuse profile is enabled, also stop langfuse-worker and langfuse-web.
stamp=$(date -u +%Y%m%dT%H%M%SZ)
docker compose exec -T clickhouse clickhouse-client --query \
  "BACKUP DATABASE otel TO Disk('backups', 'otel-before-${stamp}')"
docker compose exec -T clickhouse clickhouse-client --query \
  "BACKUP DATABASE factory TO Disk('backups', 'factory-before-${stamp}')"
# When enabled:
docker compose exec -T clickhouse clickhouse-client --query \
  "BACKUP DATABASE langfuse TO Disk('backups', 'langfuse-before-${stamp}')"
docker compose exec -T clickhouse clickhouse-client --query \
  "SELECT name, status, error FROM system.backups ORDER BY start_time DESC LIMIT 10"
```

Proceed only when every required backup reports `BACKUP_CREATED` with no error.
Users and profiles come from `users.d/users.xml` and `clickhouse-init.sh`; if
SQL-managed access entities are added later, include them in the backup plan.

## Security defaults

- Published ports bind to `127.0.0.1` by default. Override the relevant bind
  address only when needed; direct LAN access is plain HTTP unless fronted by TLS.
- No default passwords; required secrets come from `.env` and startup fails if empty.
- Grafana anonymous access off, sign-up off, update checks off, external snapshots
  off, externally shared dashboards off, and UI plugin administration off.
- Grafana `/metrics` requires basic auth. Prometheus reads the password from a
  startup-generated file with owner-only permissions.
- ClickHouse users are least-privilege (`collector` insert, `grafana` read-only).
- Collector redacts common sensitive keys (`output_tail`, token/password/secret/authorization/api key patterns) as defence in depth.

### Grafana accounts and password rotation

`GRAFANA_ADMIN_PASSWORD` is applied only when Grafana first creates its SQLite
database in the `grafana-data` volume. Changing it later in `.env` does not
change an existing admin password. Rotate it inside the running container:

```sh
docker compose exec grafana grafana cli admin reset-admin-password '<new password>'
```

Use the shared admin account only for administration. For day-to-day dashboard
use, sign in as admin, open **Administration > Users and access > Users**, invite
or create a user, and assign the **Viewer** role. Do not provision personal
credentials in git.

## Resource budget

Suggested starting limits (small shared host, ~3.2 GB RAM total):

| Service                   |         Memory limit |
| ------------------------- | -------------------: |
| clickhouse                |                 768m |
| grafana                   |                 256m |
| prometheus                |                 256m |
| otel-collector            |                 192m |
| node-exporter             |                  64m |
| clickhouse-init/check-env | one-shot, negligible |

Total always-on monitoring budget: ~1.54 GB. Update `dev-ops/README.md` with real
numbers after observing load. If totals exceed host budget, state it honestly and
reduce retention/scrape frequency before adding services.

## Dashboards

Provisioned from `grafana/dashboards/*.json` (generated from
`scripts/generate_dashboards.py`). All dashboards are in Grafana folder `Factory`,
have stable UIDs, include template variables `factory_id`, `agent_id`, `model`,
`kind`, and a time range, and use bounded ClickHouse queries with `$__timeFilter(...)`.

| UID                  | Dashboard            | Answers                                                                                                                                                                                                                               |
| -------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `factory-overview`   | Factory overview     | Issues processed/completed, run success rate, active agents, avg pickup-to-merge, tokens/cost, throughput over time, last tick age, current queue snapshot, recent merged PRs.                                                        |
| `factory-agents`     | Agent performance    | Per agent/version/model: runs, success rate, duration, cost/successful issue, fallback share, PR touch count; prompt version breakdown; leaderboard by merged PRs per run hour (EVENTS.md agent efficiency).                          |
| `factory-execution`  | Execution analytics  | Runs/hour, duration p50/p90, top tools, skill loads, failures by reason/fingerprint, issues with most runs, retries/fallbacks/operational events, stuck runs.                                                                         |
| `factory-cost`       | Cost and efficiency  | Reported cost and tokens by time/model/agent/kind; cost per merged PR and tokens per merged PR (approx); usage-filled/backup/free share. Cost is as reported by OpenCode and may be 0 for subscription models.                        |
| `factory-quality`    | Quality and outcomes | PR acceptance rate, human intervention proxy, lead time p50/p90, first-pass success, rework/abandonment, CI/check outcomes, review comments.                                                                                          |
| `factory-host`       | Factory host         | Host CPU/memory/disk/load, collector records, per-container memory (if cAdvisor metrics present), ClickHouse disk by table (best effort), Prometheus TSDB size.                                                                       |
| `factory-run-detail` | Factory run detail   | Deep dive for one run: run summary, factory events, trace waterfall (otel_traces), tool calls, tokens/cost per step, and Langfuse trace link when Langfuse profile is enabled. Defaults to the newest run in the selected time range. |

Regenerate dashboards:

```sh
python3 dev-ops/factory/monitoring/scripts/generate_dashboards.py
```

The Run Detail `run_id` query is ordered newest first and has no saved empty
selection, so Grafana preselects the newest run. An explicitly empty `run_id` or
`trace_id` still produces valid SQL and no rows.

Grafana 13.3 file provisioning supports environment variables in provisioning
configuration, but not in dashboard JSON definition files. The committed Run
Detail dashboard therefore contains a `__LANGFUSE_PUBLIC_URL__` placeholder. At
stack startup, the one-shot `check-env` service renders the source dashboards
into the derived `grafana-dashboards` volume, substituting `LANGFUSE_PUBLIC_URL`
with a fallback of `http://127.0.0.1:3001`. Grafana mounts that rendered volume
read-only and keeps `allowUiUpdates: false`, so the repository remains the source
of truth and no manual textbox edit is required. After changing
`LANGFUSE_PUBLIC_URL`, run `docker compose up -d check-env grafana` to re-render
the dashboard volume before reloading Grafana.

## Langfuse (optional profile, prompt 05)

Langfuse is available as an optional Docker Compose profile for deep agent
trace diagnosis. It is off by default and does not start with the default profile.

```sh
# configure .env with LANGFUSE_* secrets, then
docker compose --profile langfuse up -d
```

All service images are pinned in `docker-compose.yml`. The Langfuse web and worker
images must always use the same version. Langfuse reuses the factory stack
ClickHouse server with a separate `langfuse` database and `langfuse` user (created
by `clickhouse-init` when `LANGFUSE_CLICKHOUSE_PASSWORD` is set). This keeps one
ClickHouse process. The pinned ClickHouse version meets the Langfuse v4 minimum;
`clickhouse-init` also applies the system-table and merge-control grants that v4
requires.

### Langfuse v4 migration safety

For upgrades from v3, Compose defaults to `legacy` write mode with dual-write
native OTel behavior, the v4 read paths disabled, and historic backfill disabled.
This retains the v3 ingestion and read behavior while v4 schema migrations run.
Override these only as part of the staged migration described in the
[upgrade procedure](#langfuse-v4-and-postgres-18-upgrade):

- `LANGFUSE_MIGRATION_V4_WRITE_MODE=legacy`
- `LANGFUSE_MIGRATION_V4_NATIVE_OTEL_BEHAVIOUR=dual_write`
- `LANGFUSE_MIGRATION_V4_ALLOW_PREVIEW_OPT_IN=false`
- `LANGFUSE_BACKGROUND_MIGRATION_V4_ENABLE_HISTORIC_BACKFILL=false`

Do not switch directly to `events_only` unless every producer and API consumer is
compatible and historic data is already covered. The worker healthcheck includes
`failIfEventPropagationStuck=true`, and the web healthcheck fails when PostgreSQL
is unavailable. Worker startup waits for a healthy web service so schema
migrations finish before background migrations begin.

Security/privacy defaults:

- UI published on `${LANGFUSE_BIND_ADDR:-127.0.0.1}:${LANGFUSE_PORT:-3001}` by default.
- All secrets from `.env`; no defaults. `langfuse-check-env` fails startup if required secrets are empty.
- Langfuse telemetry/phone-home disabled (`TELEMETRY_ENABLED=false`).
- Factory OTLP trace export sends no prompt/completion/tool content by default. Set `FACTORY_TRACE_CONTENT=1` only for trusted, self-hosted diagnosis. Collector redaction is a second defence.
- Do not point Langfuse OTLP at Langfuse Cloud by default. If you do, understand that trace metadata and any opted-in content leave the host.

OTLP fan-out: the collector always includes a `otlphttp/langfuse` exporter in the traces pipeline. When the Langfuse profile is not running, exports to that endpoint fail and are dropped after bounded retry; ClickHouse trace export continues. Set `LANGFUSE_OTLP_ENDPOINT` and `LANGFUSE_OTLP_AUTH_HEADER` (Basic base64 of `public_key:secret_key`) in `.env` when enabling Langfuse.

Resource impact (Langfuse profile): postgres 256m, redis 96m, minio 256m, langfuse-worker 512m, langfuse-web 512m, minio-init/check-env one-shot. Total ~1.63 GB. Combined with the base monitoring stack (~1.54 GB), this exceeds the ~3.2 GB dev host budget. Do not run Langfuse alongside all factory/QA workloads on that host unless memory is increased; start it only for targeted diagnosis.

## Alerts

Grafana-managed alerts are provisioned from `grafana/provisioning/alerting/`.
Contact point: `factory-default` (webhook + email receivers), configured via env.
If no real contact is configured, alerts still evaluate and appear in Grafana;
delivery may fail to the default no-op endpoints. Notification policy groups by
`alertname` and repeats at most every 4 hours.

| Alert                         | Condition (default)                                                                                                                                              | Severity | Runbook                                                                                                                                                  |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Factory silent                | No successful tick for 2h (`time() - factory_tick_last_success_timestamp_seconds > 7200`)                                                                        | critical | Check factory timer/service, tick logs, and textfile metric freshness in `FACTORY_METRICS_DIR`. Confirm deploy/tick jobs are running.                    |
| Factory failing               | Run failure rate > 50% over 6h with >=3 runs, or any `discovery_failed`                                                                                          | critical | Inspect Execution Analytics, failed runs, `discovery_failed`, `gh_op_failed`, auth/quota/rate-limit errors. Do not weaken gates.                         |
| Factory tick failed           | `factory_tick_last_exit_code != 0`                                                                                                                               | critical | Inspect the latest `tick_end` and failure events in the factory log.                                                                                     |
| Factory guardrail drift       | Any `guardrail_drift` in last 2h                                                                                                                                 | critical | Stop and inspect guardrail drift event. Diff `AGENTS.md`, `opencode.jsonc`, `.opencode/agents/` against `factory-config` tag before any merge.           |
| Factory stuck run             | Any row in `factory.stuck_runs` (>3900s started, no end)                                                                                                         | warning  | Inspect stuck run details, session logs, OpenCode process, host load. Diagnose before killing processes; preserve logs.                                  |
| Factory issue looping         | Same issue has >3 runs in 24h                                                                                                                                    | warning  | Inspect issue runs/failures/PR feedback. May need human clarification, issue split, or factory fix; do not blindly retry.                                |
| Factory quota pressure        | Any `agent.run.failed` with `failure_reason` `usage_filled` or `usage_filled_skipped`, or more than 2 `agent.run.started` runs with `fallback_level=free` in 24h | warning  | Check Cost & Efficiency and Execution dashboards. Confirm OpenCode quota, fallback behavior, and whether backup/free models are acceptable.              |
| Factory deploy failed/stale   | Any `deploy.failed` in 26h, or QA deploy started but no `deploy.completed` in 26h                                                                                | critical | Check deploy logs, QA timer, `deploy-environment.sh` output, and QA deployment GitHub issue. Fix cause before rerun.                                     |
| Factory telemetry broken      | `factory_telemetry_errors_last > 0`, or `telemetry_errors > 0` on latest tick_end in 24h                                                                         | warning  | Check collector logs, ClickHouse ingestion, filelog offsets, `FACTORY_LOG_DIR` mount, and telemetry error metrics.                                       |
| Factory event ingestion stale | A tick ran in the last 2h, but no `tick_end` reached ClickHouse in that window                                                                                   | warning  | Check the local JSONL file, collector offsets, exporter errors, and ClickHouse health.                                                                   |
| Factory host memory high      | Host memory > 90% for 10m                                                                                                                                        | warning  | Check host dashboard and container memory. Reduce retention/scrape or stop nonessential services; do not start optional monitoring on an exhausted host. |
| Factory host disk high        | Any filesystem > 85% for 10m                                                                                                                                     | warning  | Check disk dashboard, ClickHouse/Prometheus volumes, Docker logs/artifacts. Clean safely; preserve evidence.                                             |

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

`validate.sh` also checks that generated dashboard JSON is up to date, renders
default and multi-value dashboard SQL (including empty Run Detail selections),
checks Grafana/Prometheus hardening, and verifies alert provisioning contains the
required rule titles. Its throwaway ClickHouse container uses the image read from
`docker-compose.yml`. Startup is retried for 60 attempts; a readiness failure
prints container status and recent logs before validation exits. `smoke.sh` boots
a temporary stack, ingests fixture events, parses and executes every rendered
dashboard query with ClickHouse, verifies the newest-run default, checks
datasources, dashboards and alert rules, asserts Grafana `/metrics` returns 401
without credentials and 200 with them, confirms the Prometheus `grafana` target
is up, and asserts one key ClickHouse query per dashboard returns rows.

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

ClickHouse data is persistent. Use the
[product monitoring backup and canary runbook](../../product/monitoring/README.md#backups-and-persistent-clickhouse-upgrades)
for the same safety rules, with these factory-specific steps:

1. Bump image tags in `docker-compose.yml` and this README table. Run
   `scripts/validate.sh` and `scripts/smoke.sh` against the candidate tree in a
   disposable project. Do not attach the production `clickhouse-data` volume.
2. Record current row counts, partition bounds, image tag, datasource health,
   dashboard state, and alert provisioning. Stop the collector and any enabled
   Langfuse writers, then create the verified backups described in
   [Retention and backups](#retention-and-backups).
3. Restore each required backup into an empty canary running the candidate image.
   Drop only the canary's empty auto-created databases before a database-level
   restore. Rerun `clickhouse-init`, the factory smoke test, and all dashboard
   key queries. If Langfuse is enabled, run its migrations and health checks in
   the canary without using production credentials or data. Compare restored
   counts and partitions with the recorded values, then tear down the canary.
4. Only after the canary passes, recreate ClickHouse without immediately
   restarting writers:

   ```sh
   # from dev-ops/factory/monitoring
   docker compose pull clickhouse
   docker compose up -d clickhouse
   docker compose run --rm clickhouse-init
   docker compose up -d
   ```

5. Verify `SELECT version()`, table/view counts, fresh event ingestion,
   ClickHouse and Prometheus datasource health, provisioned dashboards, and all
   alert rules. When Langfuse is enabled, verify its migrations and health too.
6. On failure, stop writers and retain the failed volume and backup. Do not
   assume an in-place ClickHouse downgrade is supported. Restore the verified
   backup into a previous-version disposable server and switch only after that
   restore passes, or fix forward on the target. Keep old volumes and backups
   through the rollback window.

### Langfuse v4 and PostgreSQL 18 upgrade

Treat this as a staged data migration, not an image-only update. Rehearse it in a
disposable project with restored production-like data first. Keep the same
`LANGFUSE_SALT`, `LANGFUSE_ENCRYPTION_KEY`, and `LANGFUSE_NEXTAUTH_SECRET` across
the upgrade and rollback window.

1. Stay on the latest v3 Langfuse release until ClickHouse is at least 25.12 and
   every v3 background migration has finished. Run `clickhouse-init` again so the
   v4 ClickHouse grants are present, then verify this query returns zero rows:

   ```sh
   docker compose exec -T langfuse-postgres psql -U langfuse -d langfuse -v ON_ERROR_STOP=1 \
     -c "SELECT name, failed_at, failed_reason FROM background_migrations WHERE finished_at IS NULL AND name NOT LIKE '20260701_v4_%';"
   ```

   Recent v3 releases pre-create the `20260701_v4_*` historic-backfill rows. Those
   rows are expected to remain unfinished while
   `LANGFUSE_BACKGROUND_MIGRATION_V4_ENABLE_HISTORIC_BACKFILL=false`; do not
   enable that backfill before dual write is active.

2. Record PostgreSQL table and key row counts, ClickHouse counts and partitions,
   Redis queue depth, image versions, and health status. Stop the collector,
   Langfuse web, and Langfuse worker. Create and verify the ClickHouse backups
   described above. Also back up the MinIO `langfuse` bucket, run Redis `SAVE`
   with the password from `.env`, and take a consistent PostgreSQL dump. Keep the
   encryption secrets with the backup.

3. Upgrade PostgreSQL with a logical dump/restore. The guard in the PostgreSQL
   entrypoint deliberately refuses to open a PostgreSQL 17 directory with
   PostgreSQL 18 binaries. `PGDATA` remains `/var/lib/postgresql/data`, so an
   existing volume cannot be mistaken for a fresh database. From
   `dev-ops/factory/monitoring`, after `docker compose down`:

   ```sh
   set -euo pipefail
   umask 077
   stamp=$(date -u +%Y%m%dT%H%M%SZ)
   backup_dir="${HOME}/.local/state/factory-monitoring/backups/langfuse-${stamp}"
   install -d -m 700 "$backup_dir"
   volume="$(docker compose config --format json | jq -er '.volumes["langfuse-postgres-data"].name | select(type == "string" and length > 0)')"
   target_volume="${volume}-18-${stamp}"
   dump_container="factory-monitoring-postgres-dump-${stamp}"
   upgrade_container="factory-monitoring-postgres-upgrade-${stamp}"
   cleanup() {
     docker rm -f "$dump_container" "$upgrade_container" >/dev/null 2>&1 || true
   }
   trap cleanup EXIT

   docker volume inspect "$volume"
   docker volume create "$target_volume"
   docker run -d --name "$dump_container" \
     -e PGDATA=/var/lib/postgresql/data \
     -v "$volume:/var/lib/postgresql/data" \
     postgres:17.9
   for _ in $(seq 1 60); do
     docker exec "$dump_container" pg_isready -U langfuse -d langfuse && break
     sleep 2
   done
   docker exec "$dump_container" pg_isready -U langfuse -d langfuse
   docker exec "$dump_container" psql -U langfuse -d langfuse -Atc 'SELECT 1'
   docker exec "$dump_container" pg_dumpall -U langfuse --no-password > "$backup_dir/langfuse.sql"
   docker stop "$dump_container"
   docker rm "$dump_container"
   test -s "$backup_dir/langfuse.sql"

   # Restore into a new volume. The original cluster remains untouched.
   docker run -d --name "$upgrade_container" --network none \
     -e POSTGRES_USER=upgrade \
     -e POSTGRES_PASSWORD="$(openssl rand -hex 24)" \
     -e POSTGRES_DB=upgrade \
     -e PGDATA=/var/lib/postgresql/data \
     -v "$target_volume:/var/lib/postgresql/data" \
     postgres:18.6
   for _ in $(seq 1 60); do
     docker exec "$upgrade_container" pg_isready -U upgrade -d upgrade && break
     sleep 2
   done
   docker exec "$upgrade_container" pg_isready -U upgrade -d upgrade
   docker exec "$upgrade_container" psql -U upgrade -d upgrade -Atc 'SELECT 1'
   docker exec -i "$upgrade_container" \
     psql -U upgrade -d upgrade -v ON_ERROR_STOP=1 < "$backup_dir/langfuse.sql"

   docker exec "$upgrade_container" psql -U upgrade -d postgres -Atc 'SHOW server_version'
   docker exec "$upgrade_container" psql -U upgrade -d langfuse -Atc \
     "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"
   docker stop "$upgrade_container"
   docker rm "$upgrade_container"
   ```

   Confirm the server version is 18.x and compare schema and key row counts with
   the recorded values before starting Langfuse. Then set
   `LANGFUSE_POSTGRES_VOLUME=$target_volume` in `.env`. If restore fails, remove
   only the new container and `$target_volume`; the original `$volume` remains
   unchanged. Do not run `docker compose down -v` while either volume is needed
   for rollback.

4. Keep the Redis `/data` volume, start PostgreSQL 18, and verify the guard passes.
   Upgrade Redis to 8 while preserving that volume, then start both Langfuse v4
   images together. Keep the `legacy` migration defaults until ingestion, reads,
   background migrations, and rollback have been verified:

   ```sh
   docker compose --profile langfuse up -d langfuse-postgres langfuse-redis
   docker compose --profile langfuse up -d
   curl -fsS 'http://127.0.0.1:3001/api/public/health?failIfDatabaseUnavailable=true'
   docker compose --profile langfuse exec -T langfuse-worker \
     wget -qO- 'http://127.0.0.1:3030/api/health?failIfEventPropagationStuck=true'
   docker compose --profile langfuse exec -T langfuse-postgres \
     psql -U langfuse -d langfuse -c \
     "SELECT name, failed_at, failed_reason FROM background_migrations WHERE finished_at IS NULL;"
   ```

   Adjust the health URL if `LANGFUSE_PORT` changed. Send a test OTLP trace and
   confirm it is queryable before enabling the v4 read paths.

5. Prefer fixing forward in v4 `legacy` mode. A plain v3 image rollback after v4
   schema migrations is not supported. Before cutover, either restore both
   verified pre-upgrade database backups or use the same v4 image to rewind the
   ClickHouse schema to version 37 as described in the
   [Langfuse rollback guide](https://langfuse.com/self-hosting/upgrade/upgrade-guides/upgrade-v3-to-v4#rollback-without-restore).
   For a PostgreSQL volume rollback, stop the stack, set
   `LANGFUSE_POSTGRES_VOLUME=$volume` in `.env` to select the untouched v3 volume,
   and deploy the previous v3 Compose revision with the original secrets. Keep
   the failed 18 volume until the rollback window closes.

6. Only after all producers, API consumers, evaluators, and exports are compatible,
   move from `legacy` to `dual`, verify new writes, then choose historic backfill
   with roughly 3x ClickHouse disk headroom or wait for a full retention window.
   Cut over to `events_only` only after historic data is covered. That cutover is
   the point of commitment and is not part of this dependency update.
