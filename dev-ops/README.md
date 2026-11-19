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

Deployment of `main` to the **QA environment** happens at **00:00 and 12:00
Europe/Stockholm** daily, leaving ~12 h for Playwright testing on QA.

## Scheduled deployment (QA)

The dev machine runs a systemd **user timer** that deploys `main` to QA twice
daily. The host clock is UTC and Debian cron ignores `CRON_TZ`, so a plain
crontab cannot keep a local-time schedule across DST changes; `OnCalendar`
accepts an IANA timezone.

Provision the QA checkout once if it does not exist yet:

```sh
dev-ops/scripts/deploy-environment.sh qa
```

Then install or refresh the timer:

```sh
dev-ops/scripts/install-deploy-timer.sh
```

The installer writes `booking-qa-deploy.service` and `booking-qa-deploy.timer`
to `~/.config/systemd/user/`, enables user lingering so the timer survives
logout, then enables and starts the timer. It points at
`/opt/booking-system-qa/dev-ops/scripts/deploy-environment.sh`, so each run
uses the script from the deployed checkout, which the deploy fast-forwards to
`origin/main`. Override the location, timezone, or hours with `--script`,
`--timezone`, and `--times`; use `--dry-run` to inspect the generated units.
If the host rejects self-lingering, `--no-linger` allows installation but the
timer only runs while the user has a session; `sudo loginctl enable-linger
<user>` is preferable.

The service waits up to ten minutes for Docker before deploying. If a cron
entry from an earlier setup is still present, remove it before enabling the
timer so QA does not deploy twice per slot.

Run the installer test suite with:

```sh
bash dev-ops/scripts/tests/test-install-deploy-timer.sh
```

Run the deploy script test suite (lock handling and a stubbed end-to-end
deploy) with:

```sh
bash dev-ops/scripts/tests/test-deploy-environment.sh
```

Check the schedule and recent runs:

```sh
systemctl --user list-timers booking-qa-deploy.timer
systemctl --user status booking-qa-deploy.timer
journalctl --user -u booking-qa-deploy.service
```

Run the same job immediately with `systemctl --user start
booking-qa-deploy.service`.

### Deploy lock ownership

Only one deploy per environment runs at a time: the script holds an exclusive
`flock` for its whole run. The lock file must be creatable and writable by the
user that runs the deploy (the systemd user timer, cron, or an interactive
shell), so the script uses the first usable path from:

1. `$DEPLOY_LOCK_FILE` - explicit override, used alone with no fallbacks.
2. `$XDG_STATE_HOME/booking-deploy-<env>.lock`, or
   `~/.local/state/booking-deploy-<env>.lock` when `XDG_STATE_HOME` is unset  - 
   the default, deterministic for a given user so a timer run and a cron run
   take the same lock.
3. `${TMPDIR:-/tmp}/booking-deploy-<env>-<uid>.lock` - per-user fallback.
4. `/var/lock/booking-deploy-<env>.lock` - shared lock, only if writable.

If none can be opened, the deploy stops before any other work, prints every
attempted path, and reports a `QA deployment failed` issue through the same
mechanism as other failures. `deploy-environment.sh <env> --dry-run` prints the
first lock path it would try.

The per-user name in step 3 is deliberate: a lock file left in `/tmp` or in the
sticky `/var/lock` by an earlier `sudo` run is owned by `root`, so the deploy
user can neither open it nor replace it. To keep using the shared
`/var/lock/booking-deploy-qa.lock`, fix its ownership once instead of relying on
the fallback:

```sh
sudo touch /var/lock/booking-deploy-qa.lock
sudo chown lasrvr:lasrvr /var/lock/booking-deploy-qa.lock
sudo chmod 0644 /var/lock/booking-deploy-qa.lock
```

### Cron alternative

On a host whose cron supports `CRON_TZ` (cronie, for example), the equivalent
crontab entry is:

```cron
CRON_TZ=Europe/Stockholm
0 0,12 * * * /opt/booking-system-qa/dev-ops/scripts/deploy-environment.sh qa >> /home/lasrvr/booking-qa-deploy.log 2>&1
```

- The `flock` in the deploy script makes manual re-runs safe.
- The cron redirection opens the log file *before* the script starts, so the
  deploy user must be able to append to it. Redirect to a user-owned path (as
  above) or provision `/var/log/booking-qa-deploy.log`:
  ```sh
  sudo touch /var/log/booking-qa-deploy.log
  sudo chown lasrvr:lasrvr /var/log/booking-qa-deploy.log
  sudo chmod 0644 /var/log/booking-qa-deploy.log
  ```
  Verify with `sudo -u lasrvr test -w /var/log/booking-qa-deploy.log && echo writable`.

### Manual deploy and failures

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

## Agent SSH access to the dev server

[`scripts/dev-server-agent.sh`](scripts/dev-server-agent.sh) provides controlled,
audited SSH access for a human-supervised OpenCode agent. The accompanying
`dev-server-ssh` skill contains the operating protocol. This is for **dev/QA
only**, not production.

Copy [`dev-ops/.env.example`](.env.example) to the gitignored `dev-ops/.env`,
fill it in locally, and export it without printing it:

```sh
set -a
. dev-ops/.env
set +a
```

`DEV_SERVER_HOST` is required. The port defaults to `22`, the user defaults to
the current local user, and `DEV_SERVER_KEY`/`DEV_SERVER_KEY_PATH` falls back to
`~/.ssh/id_ed25519` then `~/.ssh/id_rsa`. OpenSSH's standard known-hosts files
are used unless `DEV_SERVER_KNOWN_HOSTS` is set; strict host-key checking is
always on. `--host`, `--user`, `--port`, `--key`, and `--known-hosts` override
the environment. Password auth requires `DEV_SERVER_PASSWORD`, `sshpass`, and a
separate interactive confirmation; never pass a password as an argument.

Validate the local configuration without connecting, run one inspection command,
or start the interactive agent:

```sh
dev-ops/scripts/dev-server-agent.sh --self-check
dev-ops/scripts/dev-server-agent.sh --command 'uptime'
dev-ops/scripts/dev-server-agent.sh
```

Command mode captures remote stdout/stderr and preserves the exit status. It
uses a reusable SSH control connection and checks reachability before running.
Clearly read-only commands (status, logs, `docker compose ps`, etc.) may run
without a prompt. Unknown/complex shell and every mutating or potentially
impactful command require an impact description and explicit controlling-TTY
`y/N` approval:

```sh
dev-ops/scripts/dev-server-agent.sh \
  --command '<approved command>' \
  --impact '<specific intended impact>'
```

The default is denial; non-interactive sessions cannot approve mutations. Agent
mode starts OpenCode **without** `--auto` and instructs it to load the
`dev-server-ssh` skill and use only this wrapper. The agent must show each exact
command and impact, ask whenever anything is ambiguous, and never answer its own
approval prompt or use direct `ssh`/`scp`/`sftp`. The wrapper is an approval and
audit boundary, not a sandbox.

`DEV_SERVER_ALLOWED_COMMANDS` optionally restricts execution to newline-separated
exact commands; it never pre-approves a mutation. Actions are appended as JSONL
to `${XDG_STATE_HOME:-~/.local/state}/booking-system/dev-server-agent.jsonl` (or
`DEV_SERVER_LOG_FILE`) with actor, target, redacted command, impact, and outcome.
Do not commit logs or put secrets in commands. Configured secrets are redacted
from logs and captured output.

Run the wrapper's test suite (uses local fakes, never connects):

```sh
bash dev-ops/scripts/tests/test-dev-server-agent.sh
```

Read logs/status, restart dev/QA services, and apply small approved config fixes
as needed. Never delete data or volumes, edit secrets in place, disable checks,
or bypass review. Reconcile every persistent server change through a reviewed
PR. Use [`environments.yaml`](environments.yaml) for ports/services and
`projects/<name>/` for deployment config; the sauna env example also contains
empty operator-only `DEV_SERVER_*` entries.

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

## Agentic issue creation

Use the OpenCode command `/create-github-issue`
(`.opencode/commands/create-github-issue.md`) to create GitHub issues that
autonomous agents can implement without clarification. It is based on
`dev-ops/issue-templates/agentic.md` and validated by
`dev-ops/scripts/validate-issue-body.sh` before `gh issue create` runs.

Required sections: Problem Statement, Motivation, Relevant Repository Context,
Functional Requirements, Acceptance Criteria (with measurable checkboxes),
Implementation Tasks, Testing and Validation, and Constraints and
Considerations. The validator exits non-zero if any required section is missing
or empty, or if no acceptance-criteria checkbox is present.

Created issues are left uncategorized (no labels); the factory's planning agent
posts the implementation plan and applies labels afterward. This preserves
compatibility with the factory's planning and labeling workflow.

Dry-run validation of a body file:

```sh
dev-ops/scripts/validate-issue-body.sh /path/to/issue-body.md
```

## Code quality

### Semgrep AppSec Platform (Option 1)

Semgrep posts inline PR comments automatically, filtered by **remediation
policies** (e.g. only high severity/confidence rules) to control noise.
Findings are reported on the pull request; merging is gated by the `main`
ruleset, which requires a pull request and the `ci-gate` status check.

- Workflow: `.github/workflows/semgrep.yml` - job name/context `semgrep/ci`,
  runs `semgrep ci` in the `semgrep/semgrep` container on PRs to `main`,
  `master`, and `release/**` (diff-aware), plus push-to-main baseline scans,
  `workflow_dispatch`, and a daily full scan.
- Ruleset config: `.semgrep.yml` (repo-specific overrides only) and
  `.semgrepignore` (excludes build artifacts, vendored/generated code).
- Rule selection, severity gating (Block / Comment / Monitor), and remediation
  policies are managed in the Semgrep AppSec Platform for this repository.
- Findings fail the check (and thus can block merge once `semgrep/ci` is
  added to the required status checks of the `main` ruleset).

**Manual steps (owner):**
- [x] Create a Semgrep AppSec Platform account + organization (free tier: ≤10 contributors)
- [x] Install the `semgrep-app` GitHub App on this repo with read/write access to actions, pull requests, secrets, security events, and workflows
- [ ] Add `SEMGREP_APP_TOKEN` as a repository secret
- [ ] Configure remediation policies in the platform to control which rules leave PR comments
- [ ] (Optional) Configure a custom PR/MR comment footer in **Settings > General > Global > Custom PR/MR comments footers** (max 400 characters; plaintext and markdown links supported) to point to internal docs or your team's channel. Example: "Questions about this issue? Check [our documentation](https://notion.so/appsecdocs) on fixing security issues here or post in #appsec on Slack."
- [ ] Add `semgrep/ci` to the required status checks of the `main` ruleset.

A Semgrep instance also runs on the development server, connected to this repo,
performing checks on merges into `main` and release branches.

## OpenCode skills

[`scripts/request-skills.sh`](scripts/request-skills.sh) installs
[OpenCode skills](https://opencode.ai/v2/docs/skills/) into `.opencode/skills/`
and opens a pull request proposing additions. Open-source entries in
[`skills.yaml`](skills.yaml) are vendored from their upstream repositories;
repository-owned entries such as `dev-server-ssh` use `local_path` and are copied
from [`dev-ops/skills/`](skills/). Do not edit installed copies by hand.

```sh
dev-ops/scripts/request-skills.sh          # install + open a PR
dev-ops/scripts/request-skills.sh --local  # install only, no PR
```

Skills already present are skipped. Each installed skill carries a `.source`
file recording its upstream origin or repository-local path. Review licenses
(where applicable) and content before merging - skills are instructions loaded
by factory agents.

## Agentic Playwright testing (dev/QA only)

A testing agent can drive the UI against the QA/dev environment using Playwright
running inside a Docker container. QA deployments run the application in QA
mode, so sign-in does not require a 6-digit email code and built-in QA users are
seeded.

### Environment variables

- `BOOKING_DEV_SSH` - SSH target for the dev server (e.g. `user@host`), used
  when the script is not running on the dev server itself. Never committed.
- `TEST_USER_EMAIL` - email of an existing QA user account used for tests.
- `DEPLOY_DIR` (optional) - override the deploy checkout path
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
- QA-mode sign-in does not require this step.

### Run Playwright tests

```sh
dev-ops/scripts/run-playwright.sh [--env qa] [spec...]
```

Builds the Playwright image and runs the suite in a container with `BASE_URL`
and `TEST_USER_EMAIL` passed as env vars against the target environment.

### Security

- Dev/QA only. Never enable in production; `prod` env names are rejected.

## Scheduled agent-driven UI/UX audit (dev/QA only)

`dev-ops/scripts/run-ui-audit.sh` runs a recurring, **agent-driven** Playwright
UI/UX audit against a non-production environment. Unlike fixed Playwright specs,
the audit spawns an `opencode` agent session that dynamically explores the
application at runtime, adapts to observed UI state, and records evidence.

### What the audit does

- Runs only against dev/QA environments (environment names matching `prod` are
  rejected).
- Authenticates and exercises three roles in QA mode: basic user, super user,
  and admin user (defaults: `user1@test.local`, `superuser@test.local`,
  `admin@test.local`, overridable with `--basic-email`, `--super-email`, and
  `--admin-email` or `UI_AUDIT_*` environment variables).
- Evaluates the experience against Nielsen's 10 usability heuristics and looks
  for weird rendering errors, broken layouts, missing features, and regressions.
- Writes timestamped artifacts per run: `report.md`, `findings.json`,
  `run.json`, `audit-prompt.md`, `session.log`, and an `evidence/` directory
  (screenshots/logs/notes produced by the agent).
- Uses the prompt template at `dev-ops/ui-audit/AUDIT_PROMPT.md` to instruct the
  dynamic agent.

### Manual run

```sh
dev-ops/scripts/run-ui-audit.sh [--env qa] [--dry-run] [--issue-filing|--no-issue-filing]
```

- Resolves the target base URL from `dev-ops/environments.yaml` (port for the
  selected environment). `--local` runs on the dev server; otherwise the script
  re-executes over SSH using `BOOKING_DEV_SSH` (same pattern as
  `run-playwright.sh`).
- `--dry-run` prepares the artifact skeleton and rendered prompt without starting
  the agent session (useful for validation and configuration checks).
- A real run requires `opencode` (or `UI_AUDIT_AGENT_CMD`) on the execution host.
  `--timeout-minutes` controls the agent session timeout (default: 60; `0`
  disables).
- Artifacts are written to
  `${UI_AUDIT_ARTIFACT_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/booking-ui-audit}/<env>/<run-id>/`
  by default (override with `--artifact-dir` or `UI_AUDIT_ARTIFACT_ROOT`).

### Scheduled job (systemd user timer)

Install or refresh a recurring schedule on the dev/QA host:

```sh
dev-ops/scripts/install-ui-audit-timer.sh [--env qa] [--timezone Europe/Stockholm] [--times 02]
```

This writes `booking-<env>-ui-audit.service` and
`booking-<env>-ui-audit.timer` to
`${XDG_CONFIG_HOME:-~/.config}/systemd/user/`, enables lingering when needed, and
enables/starts the timer (use `--dry-run`, `--no-enable`, or `--no-linger` as
with `install-deploy-timer.sh`). The default schedule is daily at 02:00 local
time; adjust `--times` (comma-separated hours) for a different recurring cadence.
Issue filing for scheduled runs is disabled by default (`--issue-filing` opts in).

On hosts that prefer cron with `CRON_TZ` support, an equivalent recurring entry
can run `dev-ops/scripts/run-ui-audit.sh --env qa --local --no-issue-filing`
(keep stdout/stderr redirected to a user-writable log path).

### Issue filing safeguards

Issue filing is opt-in (`--issue-filing`). When enabled, the audit agent is
instructed to:

- Use a clear automated-origin title marker for every created issue
  (default prefixes: `[agent-playwright-audit]` for findings and
  `[agent-playwright-audit][run]` for the run parent).
- Search and review existing open issues before creating a finding issue to avoid
  duplicates.
- Create one parent tracking issue per audit run that produces filed findings and
  file/link all finding issues from that run under that single parent issue.
- Not add labels at creation time and follow repository issue-writing rules
  (including no em-dashes and no secrets/personal data in public content).

### Safety

- Dev/QA only. Never run against production or use production data.
- Handle credentials, login codes, emails, and session data carefully; avoid
  leaking them into logs, committed artifacts, or public reports.
- Exploration is non-deterministic; review generated reports and any filed issues
  for accuracy before acting on them.

## Self-hosting

- [Self-hosting with Cloudflare Tunnels (HTTPS-compliant)](self-hosting-cloudflare-tunnel.md)
  - repo preparation, deployment config surface, `cloudflared`/Caddy/Authelia
  guidance, and a validation checklist. Keep tunnel tokens, hostnames, and other
  deployment-specific identifiers in `projects/<name>/` config or environment
  variables, not in `product/`.
## Resource budgets (container memory limits)

All compose services in this repo define explicit memory limits (`deploy.resources.limits.memory`) to prevent any single container from exhausting host RAM (see issue #136). Approximate budgets:

| Stack | Service | Memory limit |
|---|---|---|
| signoz | signoz-clickhouse | 1536m (max_memory_usage 1.2GB) |
| signoz | signoz-zookeeper | 512m (JVM -Xmx512m) |
| signoz | signoz-server | 512m |
| signoz | signoz-otel-collector | 512m |
| signoz | signoz-init-clickhouse / migrators | 256m |
| sauna | backend | 512m |
| sauna | postgres | 256m |
| sauna | sidecar | 256m |
| sauna | frontend | 256m |
| sauna | caddy | 128m |
| sauna | authelia | 256m |
| sauna | cloudflared | 128m |

Keep the always-on total (booking + persistent dev-ops services) below ~2.5 GB on the 3.2 GB dev host.

