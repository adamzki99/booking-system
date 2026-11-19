# AGENTS.md (product)

## Scope

This directory contains the **generic booking product**: reusable backend and frontend code shared by every deployment. It does **not** contain deployment-specific rules, branding, infrastructure configuration, or sidecar implementations; those belong under `projects/<name>/`.

Read the root [`../AGENTS.md`](../AGENTS.md) first for repository-wide rules (worktrees, PR workflow, no issue labels at creation, CQRS/event sourcing, product vs sidecar boundaries, and the no-em-dash rule).

## Local verification and workflow commands

There is no single build, test, or lint command for `product/` as a whole. Run verification in the component you change:

- Backend (Go): see [`backend/AGENTS.md`](backend/AGENTS.md) and [`backend/README.md`](backend/README.md).
- Frontend (React): see [`frontend/AGENTS.md`](frontend/AGENTS.md) and [`frontend/README.md`](frontend/README.md).

For full-stack or deployment-level checks, use the relevant deployment docs under [`../projects/`](../projects/README.md) (for example [`../projects/sauna/README.md`](../projects/sauna/README.md)).

## Conventions and invariants

- **Generic only:** keep deployment-specific behavior, policies, and configuration out of `product/`. If a change is only needed for one deployment, implement it in that deployment's sidecar or configuration under `projects/<name>/`.
- **CQRS and event sourcing:** commands record events; queries read projections. Events are append-only and are the source of truth. Do not mutate recorded events or write state directly from commands. Projections must remain rebuildable from the event stream.
- **Product plus stateless sidecar:** deployment-specific logic is provided by a stateless sidecar called by the backend over REST. Do not give the sidecar persistent state and do not bake deployment rules into generic product code.
- **Frontend UI and mockups:** when supplied mockups or design references exist, frontend UI must follow them for layout, styling, coloring, spacing, typography, and component states. Keep the fixed frontend stack (**React 18, TypeScript, Vite, React Router, Chakra UI v2**) and implement mockup intent with Chakra primitives, theme tokens, and component recipes/variants (see [`frontend/AGENTS.md`](frontend/AGENTS.md) and [`frontend/README.md`](frontend/README.md)). Keep deployment-specific branding/copy/assets in `projects/<name>/`.
- **Cross-component consistency:** when changing API contracts, event shapes, auth/session behavior, or UI flows, update backend, frontend, and affected deployment docs/config together as needed.
- **Reuse and scope:** prefer extending existing product capabilities in ways that are useful to every deployment; avoid one-off branches for a single project.

## Canonical references

- [`README.md`](README.md): product overview and component responsibilities.
- [`backend/README.md`](backend/README.md): backend responsibilities, event store notes, and open decisions.
- [`frontend/README.md`](frontend/README.md): frontend stack, Chakra UI usage, testing helper, and theming guidance.
- [`../projects/README.md`](../projects/README.md): how deployments combine with the product.
