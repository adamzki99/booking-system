# GitHub Actions workflows

Path-filtered workflows for this monorepo-style layout. Keep workflows minimal and avoid coupling product CI to deployment-specific sidecar behavior except where explicitly testing a deployment package.

## `backend-ci.yml`

**Triggers:** `pull_request` and `push` when `product/backend/**` or the workflow file changes; `workflow_dispatch`.

**Jobs:**
- **Format, vet, test, build** (`product/backend`): checks `gofmt`, runs `go vet ./...`, runs `go test ./...`, and builds `./cmd/server`. Go version comes from `product/backend/go.mod`.
- **Docker build smoke test**: builds `product/backend/Dockerfile` from the repo root to catch Dockerfile regressions.

**Notes:** `go test ./...` includes integration tests (e.g. `*_integration_test.go`). Those tests use [testcontainers-go](https://golang.testcontainers.org/) and require a working Docker daemon; GitHub-hosted Ubuntu runners provide Docker. There is no separate `services: postgres` job because the backend's integration tests manage their own PostgreSQL containers.

## `frontend-ci.yml`

**Triggers:** `pull_request` and `push` to `main` when `product/frontend/**` or the workflow file changes; `workflow_dispatch`.

**Jobs:**
- **Install, test, build** (`product/frontend`): installs dependencies with `npm ci` (deterministic, from `package-lock.json`), runs the Vitest suite (`npm test`), and runs the production build (`npm run build`, which runs `tsc --noEmit` then `vite build`). Node 22 is used, matching `product/frontend/Dockerfile`. Dependencies are cached via `actions/setup-node`. Actions are pinned to full commit SHAs (`actions/checkout` and `actions/setup-node` v4.4.0) so a repointed tag cannot inject code into the job.

**Notes:** Any failing test or type/build error fails the check. No secrets are required.

## `security.yml`

**Triggers:** `pull_request`, `push` to `main`, weekly schedule (Monday 06:17 UTC), `workflow_dispatch`.

**Jobs:**
- **Dependency review** (PRs only): uses `actions/dependency-review-action`. Requires GitHub Dependency Graph to be enabled for the repository.
- **Go vulnerability scan**: runs `govulncheck ./...` in `product/backend`.

**Triage owner:** repository maintainers / dev-ops. Configure `CODEOWNERS`, security contacts, or a `SECURITY.md` as the team grows so vulnerability findings have a clear owner.

**Code scanning:** Semgrep checks already run on the development server for merges into `main`/release branches (see `dev-ops/README.md`). GitHub CodeQL or a Semgrep GitHub Action can be added later if you want results directly in PR checks; keep the chosen approach documented here.

## `semgrep.yml`

**Triggers:** `pull_request` to `main`/`master`/`release/**`, `push` to `main`/`master`/`release/**` (workflow file only), `workflow_dispatch`, and a daily `schedule` (randomized time).

**Jobs:**
- **Semgrep** (`semgrep/ci`): runs `semgrep ci` in the `semgrep/semgrep` container; diff-aware on PRs. Requires the `SEMGREP_APP_TOKEN` repository secret. Skips `dependabot[bot]`.

**Notes:** Rule selection and remediation policies (Block / Comment / Monitor) are managed in the Semgrep AppSec Platform; `.semgrep.yml` holds repo-specific overrides only. Once a successful run exists, wire `semgrep/ci` as a required status check on `main` branch protection.

## Required secrets

`SEMGREP_APP_TOKEN` (repository secret) is required by `.github/workflows/semgrep.yml` for `semgrep ci` to report to the Semgrep AppSec Platform. No other workflow-specific repository secrets are required for the current CI/security checks. Future deployment or image-publish workflows will need secrets (registry credentials, SSH/runner access, database/application configuration) — document them here when added.

### Secret handling policy

- Never commit secrets. Runtime values live in `projects/<name>/.env` (gitignored) or in
  GitHub Environment/Repository secrets; document required keys in `projects/<name>/.env.example`.
- The `secret-scan` job runs gitleaks on every PR/push to catch accidental commits.
- If a secret is ever committed, rotate it — deleting the file is not enough.

## Running checks locally

From the repository root:

```sh
# Backend checks (mirrors backend-ci)
cd product/backend
gofmt -l .                    # should print nothing
go vet ./...
go test ./...                 # integration tests need Docker/testcontainers
go build ./cmd/server

# Docker smoke build
docker build -f product/backend/Dockerfile product/backend

# Vulnerability scan
cd product/backend
go install golang.org/x/vuln/cmd/govulncheck@latest
govulncheck ./...
```
