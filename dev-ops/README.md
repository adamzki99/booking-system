# Dev-ops

CI/CD, the software factory, and code quality for the booking system.

## Software factory

See [`factory/`](factory/README.md). [`factory/tick.sh`](factory/tick.sh) runs
on a 1-hour interval and picks up GitHub issues and pull requests:

- **No labels** → the issue is in its infant state → a planning agent posts an
  implementation plan as a comment and categorizes the issue with labels.
- **Open factory PR blocked from merge** → a fix agent resolves failing checks,
  requested changes, or merge conflicts and merges when possible (capped per
  tick; idempotent per PR head SHA + blocking reasons).
- **`owner approved` label** (no open factory PR) → a builder agent implements
  the issue, creates a PR, and merges it.
- Labels select which model a session uses (`factory/models.yaml`).
- Each hourly tick may create **one planning** session plus build-path sessions
  (fixes and/or a new build), with configurable caps to spread token usage.

The system owner steers the project purely by interacting with GitHub issues.

Deployment of `main` to the **QA environment** happens at **12 am and 12 pm**
daily (host local time), leaving ~12 h for Playwright testing on QA.

## Scheduled deployment (QA)

The dev machine runs a cron entry that deploys `main` to QA twice daily:

```cron
0 0,12 * * * /path/to/repo/dev-ops/scripts/deploy-environment.sh qa >> /var/log/booking-qa-deploy.log 2>&1
```

- Cron uses the host's local time; 12 am / 12 pm are local time. If the host is
  UTC, set `CRON_TZ=<owner timezone>` (e.g. `Europe/Stockholm`) in the crontab.
- The `flock` in the script makes manual re-runs safe.
- Logs: `/var/log/booking-qa-deploy.log`.
- Manual deploy: `dev-ops/scripts/deploy-environment.sh qa`
- Dry run: `dev-ops/scripts/deploy-environment.sh qa --dry-run`
- A failed deployment keeps/creates a GitHub issue titled `QA deployment
  failed` (labels `bug`, `dev-ops`) with the failing log tail; the next
  successful deploy comments `Recovered in <sha>` and closes it.

## Branches and environments

- There is always a **QA environment** built from the base branch.
- Every **release branch** gets one **candidate environment**.
- Everything runs via Docker Desktop; each environment is reachable on a
  distinct port on the dev machine. Ports are recorded in
  [`environments.yaml`](environments.yaml).

## SigNoz (APM)

[SigNoz](signoz/) runs as a **persistent** dev-ops service (separate compose
project, `name: signoz`) so environment deploys/restarts do not affect it. Bring
it up once on the dev machine:

```sh
docker compose -f dev-ops/signoz/docker-compose.yml up -d
```

The OTLP/HTTP collector is published on host port `4318`. Booking backends
default to `OTEL_EXPORTER_OTLP_ENDPOINT=http://host.docker.internal:4318` (see
`projects/sauna/.env.example` and [signoz/README.md](signoz/README.md)). Data
persists in named volumes across restarts and host reboots.

## Code quality

### Semgrep AppSec Platform (Option 1)

Semgrep posts inline PR comments automatically, filtered by **remediation
policies** (e.g. only high severity/confidence rules) to control noise. Combined
with the repo's *require conversation resolution* branch protection, unresolved
findings block merging.

- Workflow: `.github/workflows/semgrep.yml` — job name/context `semgrep/ci`,
  runs `semgrep ci` in the `semgrep/semgrep` container on PRs to `main`,
  `master`, and `release/**` (diff-aware), plus push-to-main baseline scans,
  `workflow_dispatch`, and a daily full scan.
- Ruleset config: `.semgrep.yml` (repo-specific overrides only) and
  `.semgrepignore` (excludes build artifacts, vendored/generated code).
- Rule selection, severity gating (Block / Comment / Monitor), and remediation
  policies are managed in the Semgrep AppSec Platform for this repository.
- Findings fail the check (and thus block merge via branch protection once
  `semgrep/ci` is a required status check on `main`).

**Manual steps (owner):**
- [x] Create a Semgrep AppSec Platform account + organization (free tier: ≤10 contributors)
- [x] Install the `semgrep-app` GitHub App on this repo with read/write access to actions, pull requests, secrets, security events, and workflows
- [ ] Add `SEMGREP_APP_TOKEN` as a repository secret
- [ ] Configure remediation policies in the platform to control which rules leave PR comments
- [ ] (Optional) Configure a custom PR/MR comment footer in **Settings > General > Global > Custom PR/MR comments footers** (max 400 characters; plaintext and markdown links supported) to point to internal docs or your team's channel. Example: "Questions about this issue? Check [our documentation](https://notion.so/appsecdocs) on fixing security issues here or post in #appsec on Slack."
- [ ] Wire `semgrep/ci` as a required status check on `main` branch protection (preserve existing required PR reviews, linear history, and conversation resolution).

A Semgrep instance also runs on the development server, connected to this repo,
performing checks on merges into `main` and release branches.

## Open-source skills

[`scripts/request-skills.sh`](scripts/request-skills.sh) calls for the addition
of open-source [OpenCode skills](https://opencode.ai/v2/docs/skills/) to this
repository. It vendors each skill listed in [`skills.yaml`](skills.yaml) into
`.opencode/skills/` and opens a pull request proposing the addition:

```sh
dev-ops/scripts/request-skills.sh          # vendor + open a PR
dev-ops/scripts/request-skills.sh --local  # vendor only, no PR
```

Skills already present are skipped. Each vendored skill carries a `.source`
file recording its origin (repo, path, ref). Review licenses and content before
merging — skills are instructions loaded by the factory agents.

## Agentic Playwright testing (dev/QA only)

A testing agent can drive the UI against the QA/dev environment using Playwright
running inside a Docker container. Because login is passwordless (email code),
the agent fetches the current 6-character code from the backend's Compose logs.

### Environment variables

- `BOOKING_DEV_SSH` — SSH target for the dev server (e.g. `user@host`), used
  when the script is not running on the dev server itself. Never committed.
- `TEST_USER_EMAIL` — email of an existing QA user account used for tests.
- `DEPLOY_DIR` (optional) — override the deploy checkout path
  (default `/opt/booking-system-<env>`).

### Retrieve a login code

```sh
dev-ops/scripts/get-login-code.sh <email> [--env qa] [--request] [--local] [--from-file FILE]
```

- Resolves env → port from `environments.yaml`; compose project `booking-<env>`.
- Detects whether it runs on the dev server (Docker compose backend present or
  `DEPLOY_DIR` exists); otherwise connects over SSH using `BOOKING_DEV_SSH`.
- `--request` first POSTs to `/api/auth/request-code`, then polls logs ~15 s.
- Only the code is printed to stdout; diagnostics go to stderr.
- Refuses unknown env names and any env matching `prod`.

### Run Playwright tests

```sh
dev-ops/scripts/run-playwright.sh [--env qa] [spec...]
```

Single entry point: requests + fetches the code, builds the Playwright image,
then runs the suite in a container with `BASE_URL`, `TEST_USER_EMAIL` and
`LOGIN_CODE` passed as env vars (code never written to a file). HTML/JUnit
reporters are disabled so codes do not leak into artifacts.

### Security

- Dev/QA only. Never enable in production; `prod` env names are rejected.
- Codes are passed as environment variables only and are not persisted to files
  or CI artifacts.

## Self-hosting

- [Self-hosting with Cloudflare Tunnels (HTTPS-compliant)](self-hosting-cloudflare-tunnel.md)
  — repo preparation, deployment config surface, `cloudflared`/Caddy/Authelia
  guidance, and a validation checklist. Keep tunnel tokens, hostnames, and other
  deployment-specific identifiers in `projects/<name>/` config or environment
  variables, not in `product/`.
