# AGENTS.md

Guidance for coding agents working in this repository.

## What this is

A reusable booking platform, deployed (first) as a sauna booking system for a
homeowner association. See `README.md` for the stack and
`projects/sauna/README.md` for the domain requirements (user roles, test flows).

## Repository layout

- `product/` — generic, reusable booking product. Nothing deployment-specific here.
  - `product/backend/` — Go service (CQRS + event sourcing).
  - `product/frontend/` — React SPA.
- `projects/<name>/` — one folder per deployment: documentation, configuration,
  and that deployment's sidecar. `product/` + one `projects/<name>/` = a working app.
- `dev-ops/` — software factory, environments, code quality.

## Architecture rules (do not violate)

- **Event sourced:** never mutate state in place — record events. State comes
  from projections only.
- **CQRS:** commands write events; queries read projections. Keep them separate.
- **Sidecar:** deployment-specific logic lives in `projects/<name>/sidecar/`. It
  is **stateless** — functions in, results out, called via REST by the backend.
- **No deletes:** not even super users may delete data from the system
  (cancellations are events, not deletions).

## Conventions

- Keep changes minimal and follow the existing style of the directory you work in.
- Update this file if you change the structure, stack, or architecture.
