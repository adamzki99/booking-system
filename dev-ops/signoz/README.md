# SigNoz (APM) — persistent dev-ops service

SigNoz collects traces and metrics exported by booking backends (OpenTelemetry
OTLP/HTTP). It runs as a **separate, persistent** Docker Compose project
(`name: signoz`) so restarting or redeploying any `booking-*` environment does
**not** take SigNoz down.

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

Booking environments run in their own compose projects (`COMPOSE_PROJECT_NAME=booking-*`).
The SigNoz collector publishes ports `4317`/`4318` on the host. Backends running
in Docker on the same host reach it via `host.docker.internal` (the sauna compose
adds `extra_hosts: host.docker.internal:host-gateway`), so the default endpoint is:

```env
OTEL_EXPORTER_OTLP_ENDPOINT=http://host.docker.internal:4318
OTEL_SERVICE_NAME=booking-backend
```

If the collector runs on another machine, set `OTEL_EXPORTER_OTLP_ENDPOINT=http://<signoz-host>:4318`.
Leave `OTEL_EXPORTER_OTLP_ENDPOINT` empty to disable export.

## Persistence

Named volumes keep data across container restarts, stack restarts, and host
reboots:

- `signoz-clickhouse-data` — telemetry store
- `signoz-sqlite` — SigNoz metadata (users, dashboards, alerts)
- `signoz-zookeeper-data` — ClickHouse coordination
- `signoz-user-scripts` — ClickHouse UDF binaries (e.g. `histogramQuantile`)

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
