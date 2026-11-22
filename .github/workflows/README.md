# GitHub Actions workflows

`ci.yml` is the single entry point for pull requests and pushes to `main`. It runs a `changes` job (pinned `dorny/paths-filter`) and calls the reusable suite workflows, gating backend, frontend and sidecar on the filter outputs. `ci-gate` is the only required check: it always runs and fails only when a needed job failed or was cancelled; skipped suites pass. New suites must be added to `ci-gate`'s `needs:` list.

Path-filtered workflows for this monorepo-style layout. Keep workflows minimal and avoid coupling product CI to deployment-specific sidecar behavior except where explicitly testing a deployment package.

## `ci.yml`

**Triggers:** every `pull_request`, push to `main`, and `workflow_dispatch`.

**Jobs:**
- **Detect changed paths** (`changes`): uses `dorny/paths-filter` to decide which of backend, frontend and sidecar run.
- **Backend CI**, **Frontend CI**, **Sidecar CI**: reusable workflow calls, gated on the filter outputs.
- **Security**, **Semgrep**: reusable workflow calls that always run.
- **ci-gate**: always runs; fails if any needed job failed or was cancelled. This is the only required check.

## `backend-ci.yml`

**Triggers:** `pull_request` and `push` when `product/backend/**` or the workflow file changes; `workflow_dispatch`.

**Jobs:**
- **Format, vet, test, build** (`product/backend`): checks `gofmt`, runs `go vet ./...`, runs `go test -race -shuffle=on -timeout 20m -json ./...` into `$RUNNER_TEMP/go-test.json`, and builds `./cmd/server`. The following "Test report" step always runs `dev-ops/scripts/go-test-report.sh`, which fails on any test-level `skip`, requires a non-zero pass count for the seven Postgres integration packages (`auth`, `booking`, `eventstore`, `notification`, `projection`, `registry`, `user`), and writes per-package counts to the job summary. Go version comes from `product/backend/go.mod`.
- **Docker build smoke test**: builds `product/backend/Dockerfile` from the repo root to catch Dockerfile regressions.

**Notes:** `go test -json ./...` includes integration tests (e.g. `*_integration_test.go`). Those tests use [testcontainers-go](https://golang.testcontainers.org/) and require a working Docker daemon; GitHub-hosted Ubuntu runners provide Docker. There is no separate `services: postgres` job because the backend's integration tests manage their own PostgreSQL containers. The test command uses a file redirect rather than a pipe so the exit status of `go test` still fails the step. `-race` surfaces concurrency defects and `-shuffle=on` surfaces order-dependent tests; neither flag may be relaxed to hide a failure. Do not call `t.Skip` in backend tests: the report step fails the job on any test-level skip. A package-level skip (a package with no test files) is allowed.

## `frontend-ci.yml`

**Triggers:** `pull_request` and `push` to `main` when `product/frontend-solid/**` or the workflow file changes; `workflow_dispatch`.

**Jobs:**
- **Install, typecheck, test, build** (`product/frontend-solid`): installs dependencies with `npm ci` (deterministic, from `package-lock.json`), runs typecheck (`npm run typecheck`), runs the Vitest suite (`npm test`), and runs the production build (`npm run build`, which runs `tsc --noEmit` then `vite build`). Node 22 is used, matching `product/frontend-solid/Dockerfile`. Dependencies are cached via `actions/setup-node`. Actions are pinned to full commit SHAs (`actions/checkout` and `actions/setup-node` v4.4.0) so a repointed tag cannot inject code into the job.

**Notes:** Any failing typecheck, test, or build error fails the check. No secrets are required.

## `sidecar-ci.yml`

**Triggers:** `pull_request` and `push` to `main` when `projects/sauna/sidecar/**` or the workflow file changes; `workflow_dispatch`.

**Jobs:**
- **Sidecar tests** (`projects/sauna/sidecar`): runs `go test -race -shuffle=on -json ./...` into `$RUNNER_TEMP/go-test.json`, then the "Test report" step runs `dev-ops/scripts/go-test-report.sh` (no required-package flags, since the sidecar is a single stdlib-only package). Go version comes from `projects/sauna/sidecar/go.mod`. The sidecar has no `go.sum`, so Go module caching is disabled (`cache: false`).

**Notes:** Any failing sidecar test fails the check. Sidecar logic stays deployment-specific and is intentionally not coupled to `backend-ci.yml`.

## `security.yml`

**Triggers:** `pull_request`, `push` to `main`, weekly schedule (Monday 06:17 UTC), `workflow_dispatch`.

**Jobs:**
- **Dependency review** (PRs only): uses `actions/dependency-review-action`. Requires GitHub Dependency Graph to be enabled for the repository.
- **Go vulnerability scan**: runs `govulncheck ./...` in `product/backend`.

**Triage owner:** repository maintainers / dev-ops. Configure `CODEOWNERS`, security contacts, or a `SECURITY.md` as the team grows so vulnerability findings have a clear owner.

**Code scanning:** Semgrep OSS rules run in the `semgrep.yml` workflow on every PR and push; findings in changed files fail `ci-gate`. See `dev-ops/README.md` for details.

## `semgrep.yml`

**Triggers:** `pull_request` to `main`/`master`/`release/**`, `push` to `main`/`master`/`release/**` (workflow file only), `workflow_dispatch`, and a daily `schedule` (randomized time).

**Jobs:**
- **Semgrep** (`semgrep/ci`): runs a tokenless OSS Semgrep scan in the `semgrep/semgrep` container, as defined in [`semgrep.yml`](semgrep.yml). No repository secret is required. Skips `dependabot[bot]`.

**Notes:** Uses tokenless OSS rules. On PRs and pushes, `SEMGREP_BASELINE_COMMIT` limits findings to those introduced by the change; the daily run scans the full tree. Excludes live in `.semgrepignore`. Findings fail the job and therefore `ci-gate`, the only required status check for `main`.

## Required secrets

No repository secrets are required for the current CI, security, or Semgrep checks. Future deployment or image-publish workflows will need secrets (registry credentials, SSH/runner access, database/application configuration) - document them here when added.

### Secret handling policy

- Never commit secrets. Runtime values live in `projects/<name>/.env` (gitignored) or in
  GitHub Environment/Repository secrets; document required keys in `projects/<name>/.env.example`.
- The `secret-scan` job runs gitleaks on every PR/push to catch accidental commits.
- If a secret is ever committed, rotate it - deleting the file is not enough.

## Running checks locally

From the repository root:

```sh
# Backend checks (mirrors backend-ci)
cd product/backend
gofmt -l .                    # should print nothing
go vet ./...
go test -race -shuffle=on -timeout 20m -json ./... > /tmp/go-test.json  # integration tests need Docker/testcontainers
../../dev-ops/scripts/go-test-report.sh /tmp/go-test.json \
  --require-package auth --require-package booking --require-package eventstore \
  --require-package notification --require-package projection --require-package registry \
  --require-package user
go build ./cmd/server

# Docker smoke build
docker build -f product/backend/Dockerfile product/backend

# Vulnerability scan
cd product/backend
go install golang.org/x/vuln/cmd/govulncheck@latest
govulncheck ./...
```
