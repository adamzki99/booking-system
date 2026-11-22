# SigNoz (APM) - persistent dev-ops service

SigNoz collects traces, metrics, and logs exported by booking backends and
factory ticks (OpenTelemetry OTLP/HTTP and filelog). It runs as a **separate,
persistent** Docker Compose project (`name: signoz`) so restarting or
redeploying any `booking-*` environment does **not** take SigNoz down.

## Bring up

From the repo root (or anywhere, with `-f` pointing at this file):

```sh
docker compose -f dev-ops/signoz/docker-compose.yml up -d
```

Logs:

```sh
docker compose -f dev-ops/signoz/docker-compose.yml logs -f
```

Stop (keeps data volumes):

```sh
docker compose -f dev-ops/signoz/docker-compose.yml down
```

## Endpoints

- **SigNoz UI:** `http://<host>:3301` (override host port with `SIGNOZ_UI_PORT`)
- **OTLP/HTTP collector:** `http://<host>:4318` (used by booking backends)
- **OTLP/gRPC collector:** `http://<host>:4317`

## How environments discover the collector

Booking environments run in their own compose projects (`COMPOSE_PROJECT_NAME=booking-*`)
and attach the backend to the shared external `signoz-net` Docker network. Backends
reach the collector by container DNS name, so the default endpoint is:

```env
OTEL_EXPORTER_OTLP_ENDPOINT=http://signoz-otel-collector:4318
OTEL_SERVICE_NAME=booking-backend
```

Ports `4317`/`4318` are published on loopback only. Use an SSH tunnel or Tailscale
to reach them from another machine.

If the collector runs on another machine, set `OTEL_EXPORTER_OTLP_ENDPOINT=http://<signoz-host>:4318`.
Leave `OTEL_EXPORTER_OTLP_ENDPOINT` empty to disable export.

## Log collection

The SigNoz collector also ships logs to ClickHouse/SigNoz Logs:

- **Factory tick events:** `filelog/factory` tails `/var/log/factory/tick.jsonl`
  inside the collector and exports records with `service.name=factory-tick`. Mount
  the host directory containing `tick.jsonl` with `FACTORY_LOG_DIR` (defaults to
  `${XDG_STATE_HOME:-$HOME/.local/state}/factory`):

  ```sh
  FACTORY_LOG_DIR=/path/to/factory/state docker compose -f dev-ops/signoz/docker-compose.yml up -d
  ```

  The directory must match `FACTORY_LOG_FILE` used by `dev-ops/factory/tick.sh`.

- **Docker container stdout/stderr:** `filelog/docker` tails
  `/var/lib/docker/containers/*/*-json.log` (mounted read-only from the host).
  This captures application logs from booking services and other containers on the
  same Docker host.

## Persistence

Named volumes keep data across container restarts, stack restarts, and host
reboots:

- `signoz-clickhouse-data` - telemetry store
- `signoz-sqlite` - SigNoz metadata (users, dashboards, alerts)
- `signoz-zookeeper-data` - ClickHouse coordination
- `signoz-user-scripts` - ClickHouse UDF binaries (e.g. `histogramQuantile`)

## Independence from booking environments

This stack uses compose project name `signoz` (not `booking-*`) and its own
volumes/network. `dev-ops/scripts/deploy-environment.sh` sets
`COMPOSE_PROJECT_NAME=booking-${ENV_NAME}` for environment deploys and never
touches this project.

## Notes

- Config and image versions are derived from SigNoz deploy patterns (MIT). When
  upgrading, update image tags and `otel-collector-config.yaml` together.
- On first start, `signoz-init-clickhouse` downloads the `histogramQuantile` UDF
  binary (requires outbound network) and schema migrators initialize ClickHouse.
- Telemetry export from booking backends is best-effort/non-fatal if SigNoz is
  down, but the backend will retry/log per its OTEL SDK behavior.

## Host health (hostmetrics)

The collector now scrapes host-level metrics for the machine it runs on via the
`hostmetrics` receiver (CPU, memory, disk, filesystem, load, network, processes).
These are exported to SigNoz ClickHouse and appear under **Hosts / Infrastructure**
in the SigNoz UI, keyed by the host name resolved by the `resourcedetection`
processor (`host.name`).

### Required container mounts and environment variables

The collector container must see the host filesystem. The compose file mounts:

- `/proc` → `/hostfs/proc` (read-only)
- `/sys` → `/hostfs/sys` (read-only)

and sets:

- `HOST_PROC=/hostfs/proc`
- `HOST_SYS=/hostfs/sys`

The `hostmetrics` receiver uses `root_path: /hostfs`. Do not remove these mounts
or the env vars; hostmetrics will silently report container (not host) values.

### Resource limits and health checks

The dev machine has only ~3.2 GB RAM. Limits are set to keep the collector from
worsening OOM pressure:

- Collector: `mem_limit` 512 MB, `cpus` 0.5, `memory_limiter` processor at
  384 MiB (spike 64 MiB).
- ClickHouse: 1536 MB, Zookeeper: 512 MB, server: 512 MB, migrators/init: 256 MB.
- Collector exposes a health check on `http://localhost:13133/`.

The `memory_limiter` processor is placed first in every pipeline so an overload
sheds load before batching/export.

### Startup and health checks (reproducible)

```sh
# From the repo root:
docker compose -f dev-ops/signoz/docker-compose.yml up -d

# Wait for health:
docker compose -f dev-ops/signoz/docker-compose.yml ps

# Collector health:
curl -fsS http://localhost:13133/ && echo OK

# SigNoz UI:
#   http://<host>:3301
```

Expected startup order (handled by compose `depends_on` conditions):

1. `signoz-init-clickhouse` (one-shot) populates the ClickHouse user scripts.
2. `signoz-zookeeper` becomes healthy.
3. `signoz-clickhouse` becomes healthy.
4. `signoz-schema-migrator-sync` completes.
5. `signoz-server` becomes healthy.
6. `signoz-otel-collector` starts (depends on server healthy) plus async migrator.

If `signoz-server` or `signoz-otel-collector` remain in `Created` state, inspect
the schema migrator logs:

```sh
docker compose -f dev-ops/signoz/docker-compose.yml logs signoz-schema-migrator-sync
```

### Low-memory / collector-only mode

On hosts with < 4 GB RAM, run only the collector against a remote SigNoz
instance instead of the full stack:

```sh
# Point the collector at a remote SigNoz ClickHouse/OTLP endpoint by editing
# dev-ops/signoz/otel-collector-config.yaml exporters, or run the collector
# image alone with the same config and mounts. Keep the hostmetrics mounts/env.
```

All collected host data is operational telemetry; it contains no secrets or
untrusted content.
