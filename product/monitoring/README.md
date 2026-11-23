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

## Validation

From repo root:

```sh
product/monitoring/scripts/validate.sh
```

The script runs compose config, collector config validation, promtool checks,
ClickHouse init SQL smoke in a throwaway container, dashboard JSON/YAML parse,
and fails if Docker is unavailable (CI has Docker).

Instance smoke test (requires a running configured instance):

```sh
product/monitoring/scripts/smoke.sh projects/<name>/monitoring/.env
```

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
