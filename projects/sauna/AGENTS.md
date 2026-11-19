# AGENTS.md (projects/sauna)

## Scope

This directory contains the **sauna deployment**: deployment-specific documentation, Docker Compose/configuration, setup and smoke-test scripts, and the sauna **stateless sidecar**. It combines with the generic product in [`../../product/`](../../product/README.md). Sauna-specific rules and deployment details must stay here (or in deployment config/env), not in `product/`.

Read the root [`../../AGENTS.md`](../../AGENTS.md) and [`../AGENTS.md`](../AGENTS.md) first for repository-wide and deployment-boundary rules.

## Local verification and workflow commands

Run commands from `projects/sauna/` unless noted. Available commands depend on local prerequisites (Docker, a running stack, network access, etc.).

- Start/update local stack: `cp .env.example .env` (edit values) then `docker compose up -d --build` (see [`README.md`](README.md) for prerequisites and variants such as Authelia profile and Cloudflare tunnel compose file).
- Logs / stop: `docker compose logs -f` and `docker compose down`
- Backend E2E tests relevant to sauna flows (from repo): `cd ../../product/backend && go test ./internal/e2e/...` (requires Docker for testcontainers unless `DATABASE_URL` is set; see [`README.md`](README.md))
- Public iCal feed smoke check (deployed stack): `CALENDAR_URL='https://<site>/calendar/<token>.ics' scripts/smoke-calendar-feed.sh` after obtaining a token via the API; validate Caddy config when applicable as documented in [`README.md`](README.md)
- Sidecar (Go) local checks from `sidecar/`: `go fmt ./...`, `go vet ./...`, `go build ./...`, `go test ./...` (use the commands relevant to your change; sidecar behavior is stateless and configured via environment variables)

No dedicated frontend lint/format script is defined for this deployment directory. If a specific verification step is not applicable or not set up in your environment, do not invent results; state what was and was not run.

## Conventions and invariants

- **Stateless sidecar:** sauna-specific runtime logic lives in `sidecar/` and is exposed over REST for the backend to call. The sidecar must remain stateless (no persistent storage or hidden durable state). Keep deployment-specific booking/policy logic here rather than in `../../product/`.
- **Deployment-specific configuration:** hostnames, tunnel tokens, secrets, ACME/public base URLs, and other environment values belong in `.env`/deployment config (not committed secrets) and deployment docs. Do not move deployment identifiers into generic product code.
- **Product boundary:** reuse generic product capabilities from `../../product/backend/` and `../../product/frontend/`. Only extend the generic product when a capability is useful to every deployment.
- **Operational context:** this deployment is commonly used with dev/QA tooling described in [`../../dev-ops/README.md`](../../dev-ops/README.md). QA-mode/testing-agent behavior is dev/QA only; do not enable or assume it for production environments.
- **Architecture alignment:** follow root/product rules (CQRS/event sourcing, append-only events, PR-based workflow, no issue labels at creation, no em-dashes).

## Canonical references

- [`README.md`](README.md): roles, flows, E2E/smoke guidance, SigNoz/telemetry, sidecar overview, running/provisioning, Cloudflare tunnel and TLS notes.
- [`sidecar/README.md`](sidecar/README.md): sidecar endpoints and configuration.
- [`docker-compose.yml`](docker-compose.yml), [`docker-compose.cloudflare-tunnel.yml`](docker-compose.cloudflare-tunnel.yml), [`.env.example`](.env.example), [`config/`](config/): deployment runtime configuration.
- [`scripts/smoke-calendar-feed.sh`](scripts/smoke-calendar-feed.sh), [`setup.sh`](setup.sh): deployment helper scripts.
- [`../README.md`](../README.md): deployment pattern and project index.
- [`../../dev-ops/README.md`](../../dev-ops/README.md): deployment/QA operations, agent access, and testing tooling.
