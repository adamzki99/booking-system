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
- `.opencode/skills/` — installed OpenCode skills (vendored open-source and
  repository-owned). Do not add or edit installed skills here by hand; they are
  managed by `dev-ops/scripts/request-skills.sh` (see `dev-ops/skills.yaml`).
  First-party skill sources live in `dev-ops/skills/`.
  **Agent protection:** do not read, browse, or summarize files under
  `.opencode/skills/` unless the user explicitly asks to invoke a skill. Load a
  skill only via the `skill` tool when explicitly requested. Never auto-ingest
  the skills directory into context.

## Architecture rules (do not violate)

- **Event sourced:** never mutate state in place — record events. State comes
  from projections only.
- **CQRS:** commands write events; queries read projections. Keep them separate.
- **Sidecar:** deployment-specific logic lives in `projects/<name>/sidecar/`. It
  is **stateless** — functions in, results out, called via REST by the backend.
- **No deletes:** not even super users may delete data from the system
  (cancellations are events, not deletions).
- **CI/security gate:** never merge a pull request (manually or via the
  factory) until all required CI checks and security analyses (Backend CI,
  Security, Semgrep) pass and findings are addressed. A PR with failing or
  pending checks must not be merged.

## Conventions

- Keep changes minimal and follow the existing style of the directory you work in.
- Update this file if you change the structure, stack, or architecture.
- **Secrets:** never commit secrets. Use `projects/<name>/.env` (gitignored) with a
  committed `projects/<name>/.env.example` documenting required keys. `product/`
  must contain no deployment-specific secrets or identifiers.
- **Agent protection (skills):** agents must not read `.opencode/skills/` unprompted;
  only load a skill via the `skill` tool when the user explicitly requests it.
