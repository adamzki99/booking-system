# AGENTS.md (projects)

## Scope

This directory contains **deployment-specific documentation and configuration**. Each subdirectory under `projects/<name>/` represents one deployment that combines with the generic product in [`../product/`](../product/README.md). Projects must not contain generic product code.

Read the root [`../AGENTS.md`](../AGENTS.md) first for repository-wide rules (worktrees, PR workflow, no issue labels at creation, product vs sidecar boundaries, CQRS/event sourcing context, and the no-em-dash rule).

## Local verification and workflow commands

There are no repository-wide build/test/lint commands in this directory. Verification depends on the specific deployment and the components involved:

- Follow the deployment's own `README.md` and scripts under `projects/<name>/` (for example compose, setup, smoke-test, and sidecar commands).
- When a deployment change affects generic behavior, also run the relevant verification in [`../product/backend/`](../product/backend/AGENTS.md) and/or [`../product/frontend-solid/`](../product/frontend-solid/AGENTS.md).
- For operational/dev-ops tooling used by deployments, see [`../dev-ops/AGENTS.md`](../dev-ops/AGENTS.md).

If a deployment directory does not define a particular verification step (build, lint, smoke test, etc.), state that explicitly in the deployment docs or AGENTS file rather than assuming one exists.

## Conventions and invariants

- **Deployment-specific only:** keep project-specific rules, policies, branding, environment configuration, and documentation here. Do not move generic capabilities into `projects/` and do not put deployment-only logic into `product/`.
- **Product plus sidecar boundary:** deployment-specific runtime logic (for example sauna booking rules) belongs in that deployment's **stateless sidecar** and is called by the backend over REST. Sidecars must not keep persistent state.
- **Future deployment pattern:** when adding a new deployment, create `projects/<name>/` with clear documentation (README and, when helpful, AGENTS.md), deployment configuration, and a sidecar only if needed. Reuse the generic product; document how the deployment composes with it and what is deployment-specific.
- **Configuration and secrets:** keep deployment identifiers, tunnel tokens, hostnames, credentials, and other environment-specific values in deployment config or environment variables, not in `product/`. Do not commit secrets.
- **Consistency with product architecture:** deployment guidance must not contradict root/product rules about CQRS/event sourcing, append-only events, or stateless sidecars.

## Canonical references

- [`README.md`](README.md): overview of deployments and how they combine with `product/`.
- [`sauna/README.md`](sauna/README.md): first deployment example (roles, flows, sidecar, running/testing/ops notes).
- [`../product/AGENTS.md`](../product/AGENTS.md): generic product boundaries and cross-component expectations.
- [`../dev-ops/README.md`](../dev-ops/README.md): environments, deployment operations, and tooling.
