# Booking System

A reusable booking platform, first deployed as a **sauna booking system** for a
homeowner association.

## Repository organization

Each top-level directory is a "group" within the organization:

| Directory   | Contents |
|-------------|----------|
| `product/`  | The generic booking product — backend, frontend, and everything reusable across deployments. |
| `projects/` | One subdirectory per deployment (documentation and configuration). A `product/` folder plus one `projects/<name>/` folder makes a working application. |
| `dev-ops/`  | CI/CD, the software factory, environments, and code-quality tooling. |

## Stack

- **Backend:** Go
- **Frontend:** React
- **Database:** PostgreSQL
- **HTTP server:** Caddy
- **APM:** SigNoz
- **AuthN/AuthZ:** Authelia

## Architecture

- **CQRS + Event Sourcing** — the system only records events; state is produced
  by projections. Commands record events, queries read projections.
- **Product + sidecar** — deployment-specific (e.g. sauna) logic lives in a
  stateless sidecar container, called by the backend over REST.

See [`product/README.md`](product/README.md) and the deployment READMEs under
[`projects/`](projects/README.md) for details.
