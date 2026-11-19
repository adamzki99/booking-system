# AGENTS.md (product/backend)

## Scope

This directory contains the **generic Go backend** for the booking platform: REST API, command handling, event store integration, projections, queries, auth flows, email/notification support, iCal, telemetry, and sidecar client integration. Deployment-specific booking rules and configuration belong in deployment sidecars and `projects/<name>/`, not here.

Read the root [`../../AGENTS.md`](../../AGENTS.md) and [`../AGENTS.md`](../AGENTS.md) first for repository-wide and product-level rules.

## Local verification and workflow commands

Run commands from `product/backend/` unless noted.

- Format: `go fmt ./...`
- Vet: `go vet ./...`
- Build: `go build ./...`
- Test (all packages): `go test ./...`
  - Some tests, including `./internal/e2e/...`, require Docker for testcontainers. If a PostgreSQL instance is already available, you can run e2e tests with `DATABASE_URL="postgres://user:pass@host:5432/db?sslmode=disable" go test ./internal/e2e/...` to skip testcontainers.
- Targeted e2e tests: `go test ./internal/e2e/...`

No dedicated lint or code-generation command is defined in this directory beyond standard Go tooling. Database migrations live in `migrations/` and are applied by the application/migration code paths; do not invent manual migration steps without checking existing behavior.

## Conventions and invariants

- **CQRS and event sourcing:** commands validate intent and append events; they must not write read-model state directly. Queries read projections/read models only. State is derived from events.
- **Events are immutable:** never rewrite or delete recorded events. Change behavior by introducing new event types or versions and by evolving projections/handlers accordingly.
- **Projections are rebuildable:** treat projection data as derived. Keep projection updates consistent with event handling and avoid hidden sources of truth.
- **Append-only event store:** PostgreSQL-backed event storage is append-only. Preserve existing serialization and correctness guarantees (for example, booking conflict handling described in [`README.md`](README.md)) when modifying command flows.
- **Generic product boundary:** keep sauna- or deployment-specific policy in the sidecar (`projects/<name>/sidecar/`) and call it over REST. The backend may integrate with sidecars, but must not absorb deployment-only rules.
- **Package organization:** code is organized under `cmd/` and `internal/` by domain/responsibility (auth, booking, eventstore, projection, server, sidecar, e2e, etc.). Follow existing patterns and naming in nearby packages before introducing new structure.

## Canonical references

- [`README.md`](README.md): backend responsibilities, event store and locking notes, open decisions.
- [`../README.md`](../README.md): generic product scope and architecture.
- [`../../AGENTS.md`](../../AGENTS.md): repository-wide workflow and architecture rules.
- [`migrations/`](migrations/): SQL migrations and migration wiring.
