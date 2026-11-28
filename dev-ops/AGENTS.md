# AGENTS.md (dev-ops)

## Scope

This directory contains **CI/CD, the software factory, environments, deployment/operational tooling, and code-quality configuration** for the repository. It includes factory automation (`factory/`), scripts (`scripts/`), environment definitions, monitoring stack assets, and operational documentation.

Read the root [`../AGENTS.md`](../AGENTS.md) first for repository-wide rules (worktrees, PR workflow, no issue labels at creation, and the no-em-dash rule).

## Local verification and workflow commands

Run commands from the repository root unless noted.

- Validate issue body against the agentic template: `dev-ops/scripts/validate-issue-body.sh /path/to/issue-body.md`
- Check acceptance-criteria readiness: `dev-ops/scripts/check-acceptance-criteria.sh --issue <number>` or `--body-file <path>`
- Factory validation (syntax/lint where available, model validation, schema smoke checks, and factory unit tests): `dev-ops/factory/validate.sh`
- Factory tick help/dry run: `dev-ops/factory/tick.sh --help` and `dev-ops/factory/tick.sh --dry-run` (see [`factory/AGENTS.md`](factory/AGENTS.md) and [`factory/README.md`](factory/README.md) for behavior and prerequisites)
- Dev-ops script tests (bash): `bash dev-ops/scripts/tests/test-deploy-environment.sh`, `bash dev-ops/scripts/tests/test-dev-server-agent.sh`, `bash dev-ops/scripts/tests/test-install-deploy-timer.sh`, `bash dev-ops/scripts/tests/test-check-acceptance-criteria.sh`, `bash dev-ops/scripts/tests/test-get-login-code.sh`, `bash dev-ops/scripts/tests/test-run-ui-audit.sh`, `bash dev-ops/scripts/tests/test-install-ui-audit-timer.sh`, `bash dev-ops/scripts/tests/test-dependabot-sweep.sh` (run the specific suite relevant to your change)
- Lint and typecheck the Playwright package: `npm --prefix dev-ops/testing run lint`, `npm --prefix dev-ops/testing run typecheck` (oxlint with type-aware rules; see [`code-quality/oxc.md`](code-quality/oxc.md))
- Install/request OpenCode skills: `dev-ops/scripts/request-skills.sh --local` or `dev-ops/scripts/request-skills.sh` (see script behavior before opening PRs)

No single lint/format command covers all dev-ops assets. `dev-ops/testing` is
covered by oxlint; for everything else use the relevant validator or test
script for the area you modify. JS/JSON/YAML/Markdown here are formatted by
`npm run fmt` at the repository root, with the exclusions in `.oxfmtrc.jsonc`
still applying (Grafana dashboards and provisioning files, historical repo
reports).

## Conventions and invariants

- **Scripts are written in bash:** scripts in this directory must be bash (`.sh`, `#!/usr/bin/env bash`, `set -euo pipefail`); do not add Node ESM (`.mjs`), CommonJS (`.cjs`), or other-language scripts. A bash script may invoke installed tools such as `jq`, `node`, `npx`, `gh`, `docker`, or `python3`, but the script itself is bash. Pre-existing Python helpers under `factory/` and `scripts/` are grandfathered; do not add new non-bash scripts.
- **Factory and issue workflow:** issues should follow the agentic template and pass validation when created via the repository flow. Do **not** add labels when creating issues; labels are applied automatically by `factory/tick.sh` after issue creation. Preserve factory invariants (isolated worktree usage, idempotent ticks, owner-approved gate, no bypassing checks/protections) as documented in [`factory/README.md`](factory/README.md).
- **PR-only changes:** deliver dev-ops changes through pull requests; do not push directly to `main`.
- **Operational safety:** scripts and docs in this area can affect deployments, automation, and credentials. Do not hardcode secrets, do not weaken safety checks, and keep environment-specific values in deployment configuration/environment variables (for example under `projects/<name>/` or local `.env` files that are not committed).
- **Deployment boundaries:** dev-ops provides shared tooling and environment orchestration; deployment-specific application behavior and sidecar logic remain in `projects/<name>/` and the generic product remains in `product/`.
- **Canonical sources over duplication:** when updating guidance, prefer linking to existing scripts, READMEs, and config files rather than copying procedures that may drift.

## Canonical references

- [`README.md`](README.md): dev-ops overview, factory summary, scheduled QA deploys, agent SSH access, factory and product monitoring, issue creation flow, code quality, skills, and Playwright testing notes.
- [`factory/README.md`](factory/README.md): factory behavior, invariants, CLI/env, claims/timeouts, observability, security expectations.
- [`factory/tick.sh`](factory/tick.sh), [`factory/models.yaml`](factory/models.yaml), [`factory/validate.sh`](factory/validate.sh): factory implementation and validation entry points.
- [`issue-templates/agentic.md`](issue-templates/agentic.md): required structure for agent-ready issues.
- [`scripts/validate-issue-body.sh`](scripts/validate-issue-body.sh), [`scripts/check-acceptance-criteria.sh`](scripts/check-acceptance-criteria.sh): issue quality validators.
- [`environments.yaml`](environments.yaml): environment/port registry.
- [`../.opencode/commands/create-github-issue.md`](../.opencode/commands/create-github-issue.md): OpenCode command for creating validated issues.
- [`../.github/workflows/`](../.github/workflows/): CI workflows (including Semgrep).
