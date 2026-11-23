# Product monitoring base

Generic, per-project monitoring stack for deployed booking products. Each
deployment under `projects/<name>/` runs its own instance with its own compose
project name, Docker network, volumes, ports, and `.env`.

This stack is for product observability (backend traces, metrics, logs, and
optional host/postgres/caddy metrics). It is separate from
[`dev-ops/factory/monitoring/`](../../dev-ops/factory/monitoring/README.md),
which monitors the software factory.

## Building blocks

| Component | Image | Version | Role |
|---|---|---:|---|
| OpenTelemetry Collector Contrib | `otel/opentelemetry-collector-contrib` | `0.165.0` | OTLP ingest, redaction, export to ClickHouse/Prometheus |
| ClickHouse | `clickhouse/clickhouse-server` | `26.9.36.3` | Traces and logs store (OTel schema) |
| Prometheus | `prom/prometheus` | `v3.16.0` | Metrics store, native OTLP receiver enabled |
| Grafana OSS | `grafana/grafana` | `13.3.1` | Dashboards/alerting, provisioned from files |
| Grafana ClickHouse plugin | `grafana-clickhouse-datasource` | `4.23.5` | Pinned via `GF_PLUGINS_PREINSTALL` |
| Node Exporter (profile `host`) | `prom/node-exporter` | `v1.13.1` | Optional host metrics |
| Postgres Exporter (profile `postgres`) | `quay.io/prometheuscommunity/postgres-exporter` | `v0.17.1` | Optional Postgres metrics |

Check versions on vendor release pages/registries before bumping. Dependabot is
configured for `/product/monitoring` and project monitoring directories.

## Architecture

```text
booking backend/sidecar
  -> OTLP/HTTP (4318) or OTLP/gRPC (4317)
  -> otel-collector
     -> memory_limiter, resourcedetection, transform/redact, filter/health, batch
     -> ClickHouse otel.otel_traces / otel.otel_logs
     -> Prometheus OTLP receiver (/api/v1/otlp)

Prometheus scrapes: prometheus, otel-collector, clickhouse, grafana,
  optional node-exporter, optional postgres-exporter, optional Caddy /metrics

Grafana provisions datasources, dashboards, alerting from git.
```

Metrics path choice: Prometheus 3 native OTLP ingestion with
`--web.enable-otlp-receiver` and `otlp.promote_resource_attributes` for
`service.instance.id`, `service.name`, `service.namespace`, `service.version`,
`deployment.environment`, and `project`. The collector exports metrics over
OTLP/HTTP to Prometheus. This keeps one OTLP pipeline and avoids maintaining a
second Prometheus scrape exporter for application metrics.

## Instantiate for a project

Create `projects/<name>/monitoring/` with:

1. `compose.yaml` that includes the base:

```yaml
name: ${MONITORING_PROJECT:?set MONITORING_PROJECT in .env}-monitoring

include:
  - path: ../../../product/monitoring/compose.yaml
```

2. `.env.example` copied from the base and filled with project values:

```sh
MONITORING_PROJECT=<name>
GRAFANA_PORT=3001      # pick unused 127.0.0.1 ports
OTLP_GRPC_PORT=4327
OTLP_HTTP_PORT=4328
```

3. Optional `dashboards/` directory for project-specific Grafana dashboards.
4. A booking-stack override `projects/<name>/docker-compose.monitoring.yml` that
   joins app services to the external `<name>-monitoring-net` and sets
   `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318`.

Start the instance:

```sh
cd projects/<name>/monitoring
cp .env.example .env
# fill required secrets
docker compose up -d
```

## Required env and secrets

All required secrets must be set in `.env`. Startup fails fast if empty.

| Variable | Required | Purpose |
|---|---:|---|
| `MONITORING_PROJECT` | yes | Project name; used for compose project, network, labels |
| `CLICKHOUSE_COLLECTOR_PASSWORD` | yes | ClickHouse write user password |
| `CLICKHOUSE_GRAFANA_PASSWORD` | yes | ClickHouse read-only user password |
| `GRAFANA_ADMIN_PASSWORD` | yes | Grafana admin password |
| `GRAFANA_PORT` | yes | Grafana UI on 127.0.0.1 |
| `OTLP_GRPC_PORT` | yes | OTLP gRPC on 127.0.0.1 |
| `OTLP_HTTP_PORT` | yes | OTLP HTTP on 127.0.0.1 |

See `.env.example` for retention and memory tuning knobs.

## Security defaults

- All UI/ingest ports bind to `127.0.0.1`.
- No default/hardcoded passwords; required secrets come from `.env`.
- Grafana anonymous access off, sign-up off, update checks off.
- ClickHouse has a write user (`collector`) and a read-only user (`grafana` with
  query limits).
- Collector redacts iCal token path segments in `url.path`, `url.full`,
  `http.target`, and `http.route`, drops `user.email`, and drops attributes
  matching token/password/secret/authorization/api key patterns.
- Collector drops health-check spans (`/healthz`, `/readyz`).

## Retention

- Traces TTL: `TRACES_TTL_DAYS` (default 7)
- Logs TTL: `LOGS_TTL_DAYS` (default 14)
- Prometheus retention: `PROMETHEUS_RETENTION` (15d) and
  `PROMETHEUS_RETENTION_SIZE` (2GB)

Retention is applied by ClickHouse table TTLs and Prometheus flags. Changing
TTL env vars requires re-applying init SQL (run `clickhouse-init` service again
or `docker compose run --rm clickhouse-init`).

## Optional profiles

- `host`: runs `node-exporter` for host CPU/memory/disk metrics.
- `postgres`: runs `postgres_exporter`. Create a read-only monitoring role
  manually; do not add it to product migrations. Example:

```sql
CREATE ROLE monitoring_readonly;
GRANT pg_monitor TO monitoring_readonly;
CREATE USER monitoring WITH PASSWORD '...';
GRANT monitoring_readonly TO monitoring;
```

Set `POSTGRES_EXPORTER_DSN`, `POSTGRES_EXPORTER_USER`, and
`POSTGRES_EXPORTER_PASSWORD` in `.env`.

- `caddy`: scrape Caddy's metrics endpoint by adding a Prometheus scrape job in
  a project-specific Prometheus config overlay. The Caddyfile change belongs to
  the project (`projects/<name>/`), not `product/`.

## Resource budget

Suggested starting limits for the base stack (small shared host, ~3.2 GB RAM):

| Service | Memory limit | Notes |
|---|---:|---|
| clickhouse | 768m | `max_server_memory_usage` also capped in config |
| prometheus | 256m | 15d / 2GB retention by default |
| grafana | 256m | provisioned plugins/dashboards |
| otel-collector | 192m | `memory_limiter` first in pipelines |
| clickhouse-init/check-env | one-shot/32m | negligible steady-state |
| node-exporter (`host`) | 64m | optional profile |
| postgres-exporter (`postgres`) | 64m | optional profile |

Always-on base total: ~1.47 GB. On a 3.2 GB dev host shared with booking and
factory monitoring, this exceeds the practical budget. Run at most one
monitoring stack at a time on that host, or move monitoring to a separate host.
Do not start product monitoring as a requirement for booking environments.

## Dashboards

Generic dashboards are provisioned into the Grafana `Product` folder. All
support variables `deployment_environment`, `service_name`, and `service_version`.

| UID | Title | What it answers |
|---|---|---|
| `product-overview` | Service overview | Request rate, 5xx error rate, p50/p95/p99 latency, top slow routes, top error routes, deploy/restart markers, telemetry freshness. |
| `product-traces` | Traces and logs | Recent traces, error traces, and log search with TraceId/SpanId correlation from ClickHouse OTel tables. |
| `product-event-sourcing` | Event sourcing and data | Events appended by type, projection checkpoint/lag/errors, command outcomes and duration, DB span latency, pgx pool stats, notification outbox health. |
| `product-usage` | Product usage | Bookings created/cancelled/rejected by reason, logins by result, codes issued, rate-limit rejections, sidecar requests/latency by result, email send results. |
| `product-runtime` | Runtime and dependencies | Go runtime memory/goroutines/GC, optional container memory, optional host/postgres/caddy profile panels with No data when profile is disabled. |

## Alerts

Grafana-managed alert rules are provisioned from
`grafana/provisioning/alerting/rules.yaml`. Defaults come from
`product/monitoring/.env.example` and are generated with
`scripts/generate_alert_rules.py`.

| Alert UID | Condition (default) | Runbook (first checks) |
|---|---|---|
| `product-backend-silent` | No backend telemetry for 10 min in an environment that reported in last 24h | Check backend logs/health, OTEL_EXPORTER_OTLP_ENDPOINT, collector health, and Prometheus recent samples. |
| `product-high-error-rate` | 5xx above 2% for 10 min with at least 20 requests | Inspect Traces and logs dashboard for error traces, backend logs by trace_id, deploy markers, projection.errors and DB health. |
| `product-high-latency` | p95 above 1s for 10 min | Inspect slow routes, DB span latency, pgx pool, sidecar duration, Go runtime/GC and host memory. |
| `product-projection-lag` | Projection lag above 100 events for 5 min, or any projection error increase | Inspect projection.lag/errors by projection, backend projection logs, event store head vs checkpoints; projections must remain rebuildable. |
| `product-notifications-failing` | notifications.failed increases, or pending above 50 for 30 min | Inspect notification metrics, backend SMTP/outbox logs, SMTP connectivity/credentials, outbox rows read-only. |
| `product-sidecar-failing` | Sidecar error rate above 5% for 10 min | Check sidecar health/logs, sidecar.requests/duration by endpoint/result, connectivity, recent deploys; sidecar fails open. |
| `product-telemetry-pipeline` | Collector refused/dropped/send_failed above 0 for 10 min | Check otel-collector logs/health, refused/dropped/send_failed metrics, ClickHouse and Prometheus health/disk. |
| `product-disk-retention` | Disk usage above 85% for 15 min where measurable | Check ClickHouse/Prometheus volume sizes, TTL/retention, node-exporter filesystem metrics; reduce retention or move host before outage. |

Notification policy groups by `alertname, project, deployment_environment`.

## Project overrides

- **Thresholds and contact point**: set `ALERT_*` variables in the project
  `.env`, run `python3 product/monitoring/scripts/generate_alert_rules.py` with
  those env vars, and commit the resulting alerting files in the project
  override (or regenerate base defaults in product when changing defaults).
  Projects can override alerting by mounting their own
  `projects/<name>/monitoring/grafana/provisioning/alerting/` over
  `/etc/grafana/provisioning/alerting:ro` in the project compose.
- **Dashboards**: place project-specific dashboard JSON files in
  `projects/<name>/monitoring/dashboards/`. The base provider provisions them
  into a Grafana folder named after `MONITORING_PROJECT`.
- **Contact points**: `ALERT_CONTACT_POINT_URL` controls the default webhook
  receiver. For non-webhook receivers, provide a project-specific
  `grafana/provisioning/alerting/contact-points.yaml` and mount it.
- **Prometheus scrape/jobs**: override `prometheus/prometheus.yml` in the
  project compose (for example to scrape a project Caddy endpoint).

## Validation

From repo root:

```sh
product/monitoring/scripts/validate.sh
```

The script runs compose config, collector config validation, promtool checks,
ClickHouse init SQL smoke in a throwaway container, dashboard JSON/YAML parse,
dashboard and alert generator up-to-date checks, and fails if Docker is
unavailable (CI has Docker). It also fails if deployment-specific names appear
in `product/monitoring`.

Instance smoke test (requires a running configured instance):

```sh
product/monitoring/scripts/smoke.sh projects/<name>/monitoring/.env
```

The smoke test sends synthetic OTLP traces/logs via a pinned `telemetrygen`
image, sends prompt 07 metric points via OTLP HTTP, waits for traces in
ClickHouse, checks Grafana health, and queries Prometheus for one key query per
dashboard.

## Operations

```sh
# from projects/<name>/monitoring
docker compose up -d
docker compose ps
docker compose logs -f --tail=200
docker compose down            # keeps volumes
docker compose down -v         # destructive: removes volumes
```

Or use `dev-ops/scripts/monitoring.sh <name> <up|down|status|logs|validate>`.
The helper never removes volumes unless `--volumes` is passed explicitly with a
confirmation prompt.
