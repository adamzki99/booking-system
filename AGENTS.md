# AGENTS.md

Guidance for AI agents (and humans) working in this repository. Read this file before making changes.

## Product

This repository builds a **reusable booking platform**. It was first deployed as a **sauna booking system** for a homeowner association, but the product itself is generic: anything specific to one deployment must stay out of the generic product code.

A working application is made by combining the generic `product/` with one deployment folder under `projects/<name>/`.

## Repository layout

Each top-level directory is a "group" within the organization:

| Path        | Contents                                                                                                   |
| ----------- | ---------------------------------------------------------------------------------------------------------- |
| `product/`  | The generic booking product: backend, frontend, and everything reusable across deployments.                |
| `projects/` | One subdirectory per deployment (documentation and configuration).                                        |
| `dev-ops/`  | CI/CD, the software factory, environments, and code-quality tooling.                                       |

Other notable files and directories:

- `.github/workflows/` holds the GitHub Actions workflows.
- `.semgrep.yml` and `.semgrepignore` configure Semgrep. Keep changes passing these checks.
- `.opencode/` and `opencode.jsonc` hold agent tooling configuration.

For details, read `product/README.md` and the deployment READMEs under `projects/` (start with `projects/README.md`).

## Stack

- **Backend:** Go
- **Frontend:** React
- **Database:** PostgreSQL
- **HTTP server:** Caddy
- **APM:** SigNoz
- **AuthN/AuthZ:** Authelia

## Architecture

### CQRS and Event Sourcing

The system only records events. State is produced by projections.

- **Commands** record events. They do not write state directly.
- **Queries** read projections. They do not mutate anything.
- Events are the source of truth. Treat recorded events as immutable, and change behavior by adding new event types or versions rather than rewriting history.
- Projections are derived data and should be rebuildable from the event stream.

### Product plus sidecar

Deployment-specific logic (for example, sauna rules) lives in a **stateless sidecar container**. The backend calls the sidecar over REST.

- Do not put deployment-specific rules into the generic product.
- Do not give the sidecar its own persistent state.
- If a deployment needs new behavior, first ask whether it belongs in the sidecar. Only extend the product when the capability is useful to every deployment.

## Workflow

### Changes are made through pull requests

All changes are implemented through **pull requests**. Do not push directly to `main`.

An issue is **not always required**. It is fine to open a PR without a matching issue (small fixes, refactors, docs, and tooling changes are common examples). If a related issue does exist, reference it in the PR description.

Keep PRs focused: one logical change per PR, with a clear title and description.

### Issues and labels

**Do not add labels when creating an issue.** Labels are applied automatically by the factory program `factory/tick.sh` after the issue exists. Do not set labels through the UI, the `gh` CLI (`--label`), the API, or any script at creation time, and do not work around `tick.sh` by labeling manually.

## Writing rules

### No em-dashes, anywhere

**Em-dashes (the long dash character, Unicode U+2014) must not appear anywhere in this repository.** This applies to everything:

- source code, comments, and string literals
- documentation and Markdown files
- configuration and generated files
- commit messages, PR titles and descriptions, and issue text

Use a hyphen, comma, colon, semicolon, or parentheses instead, or split the sentence in two. If you come across an existing em-dash while editing a file, replace it.

To check your changes before committing:

```sh
git grep -n -F "$(printf '\342\200\224')"
```

The command prints nothing when the repository is clean.
