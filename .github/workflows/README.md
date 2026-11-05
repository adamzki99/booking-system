# GitHub Actions workflows

Path-filtered workflows for this monorepo-style layout. Keep workflows minimal and avoid coupling product CI to deployment-specific sidecar behavior except where explicitly testing a deployment package.

## `backend-ci.yml`

**Triggers:** `pull_request` and `push` when `product/backend/**` or the workflow file changes; `workflow_dispatch`.

**Jobs:**
- **Format, vet, test, build** (`product/backend`): checks `gofmt`, runs `go vet ./...`, runs `go test ./...`, and builds `./cmd/server`. Go version comes from `product/backend/go.mod`.
- **Docker build smoke test**: builds `product/backend/Dockerfile` from the repo root to catch Dockerfile regressions.

**Notes:** `go test ./...` includes integration tests (e.g. `*_integration_test.go`). Those tests use [testcontainers-go](https://golang.testcontainers.org/) and require a working Docker daemon; GitHub-hosted Ubuntu runners provide Docker. There is no separate `services: postgres` job because the backend's integration tests manage their own PostgreSQL containers.

## `security.yml`

**Triggers:** `pull_request`, `push` to `main`, weekly schedule (Monday 06:17 UTC), `workflow_dispatch`.

**Jobs:**
- **Dependency review** (PRs only): uses `actions/dependency-review-action`. Requires GitHub Dependency Graph to be enabled for the repository.
- **Go vulnerability scan**: runs `govulncheck ./...` in `product/backend`.

**Triage owner:** repository maintainers / dev-ops. Configure `CODEOWNERS`, security contacts, or a `SECURITY.md` as the team grows so vulnerability findings have a clear owner.

**Code scanning:** Semgrep checks already run on the development server for merges into `main`/release branches (see `dev-ops/README.md`). GitHub CodeQL or a Semgrep GitHub Action can be added later if you want results directly in PR checks; keep the chosen approach documented here.

## Required secrets

No workflow-specific repository secrets are required for the current CI/security checks. Future deployment or image-publish workflows will need secrets (registry credentials, SSH/runner access, database/application configuration) — document them here when added.

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
