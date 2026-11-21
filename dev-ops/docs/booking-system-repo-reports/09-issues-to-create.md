# Issues to create

**Source:** the review reports `00-overview.md` to `08-observability-project-insights.md` in this folder, covering 148 findings at commit `45f6ee5` (2026-11-19). · **Result:** 127 recommended issues in 13 epics. Every finding maps to at least one issue; see the [coverage matrix](#coverage-matrix) at the end.

None of these issues has been created. This document only proposes them.

## Before you file anything

1. **File sensitive issues privately.** The repository is public. Issues marked **Sensitive** describe weaknesses that are still exploitable, such as how an outsider can steer the factory or where personal data leaks. Fix them first and then file a neutral record, or file them as a **private security advisory** (*Security → Advisories → New draft advisory*). Start with I-001 and I-016: until those land, anything filed publicly is also input to the factory.
2. **Keep the factory away from issues it must not build.** The planner picks up the oldest *unlabeled* issue that has an acceptance-criteria section. Building requires `owner approved`.
   - Create every **Owner** and **Owner-reviewed PR** issue *with its labels already applied*, so the planner skips it, and never give these issues `owner approved`. Owner-reviewed issues touch the factory's own guardrails, CI or security. The owner implements them, or at least reviews and merges them (FAC-05).
   - **Factory** issues can go through the normal plan → `owner approved` → build path.
3. **File in waves.** The factory plans and builds roughly one issue per hour, so 127 issues at once would flood the queue. Suggested order:
   - **Wave 1:** the 32 *Now* issues. Epics A–C come first.
   - **Wave 2:** *Next*, once wave 1's gates (I-004, I-005, I-016, I-019) are in place.
   - **Wave 3:** *Later*.
4. **Convert to the repo's issue format when filing.** The bodies below are condensed. The factory's gate (`dev-ops/scripts/check-acceptance-criteria.sh`) needs a Markdown **heading** containing "Acceptance Criteria" followed by at least one `- [ ]` checkbox. `/create-github-issue` (`validate-issue-body.sh`) requires eight `##` sections. Map them like this:

| Section in this document | Sections in `dev-ops/issue-templates/agentic.md` |
|---|---|
| **Problem** | `## Problem Statement` and `## Motivation` |
| **Covers** (plus a link to the review report) | `## Relevant Repository Context` |
| **Proposed change** | `## Functional Requirements` and `## Implementation Tasks` |
| **Acceptance criteria** | `## Acceptance Criteria` (keep the checkboxes) and `## Testing and Validation` |
| **Executor**, **Depends on**, the Sensitive note | `## Constraints and Considerations` |

## Field legend

- **Covers:** the review finding IDs the issue resolves. ST = `01-repo-status`, FAC = `02-software-factory`, OPS = `03-devops-qa-cicd`, BE = `04-backend`, FE = `05-frontend-ux`, SEC = `06-security-privacy`, AGT = `07-agentic-compatibility`, OBS = `08-observability-project-insights`.
- **Labels:** only labels that already exist in the repo: an area label (`backend`, `frontend`, `dev-ops`, with `documentation`, `accessibility`, `bug` or `enhancement` where they fit) and a suggested complexity tier. The planner may re-tier an issue. `owner approved` is deliberately never suggested.
- **Priority:**
  - **Now:** this week; containment and cheap high-value fixes.
  - **Next:** this month.
  - **Later:** after the foundations.
- **Executor:**
  - **Owner:** a manual task in GitHub settings, DNS or the host, or a decision.
  - **Owner-reviewed PR:** a change to the factory, CI, agent config or security guardrails. The owner implements it or reviews it, and the factory must not self-merge it.
  - **Factory:** normal product work the factory may build.
- **Depends on:** issues that should land first. IDs refer to this document (I-0NN), not to GitHub numbers.

## Index

127 issues · Now 32 · Next 59 · Later 36 · Sensitive 17 · Executor: Factory 50, Owner 14, Owner + Factory 1, Owner + Owner-reviewed PR 2, Owner-reviewed PR 60

| ID | Title | Priority | Executor | Sensitive | Covers |
|---|---|---|---|---|---|
| I-001 | Pause the factory and limit public interactions until the trust filters ship | Now | Owner | yes | FAC-01, FAC-02, SEC-01, SEC-02 |
| I-002 | Scrub personal data from issue #101 and stop posting raw deploy logs to issues | Now | Owner + Owner-reviewed PR | yes | OPS-02, SEC-06 |
| I-003 | Bind the SigNoz UI and OTLP ports to loopback and claim the SigNoz admin account | Now | Owner | yes | SEC-12, OPS-13, OBS-03 |
| I-004 | Add an always-running `ci-gate` job as the single required check | Now | Owner-reviewed PR |  | ST-04, OPS-09 |
| I-005 | Protect `main` with a ruleset and correct the README's branch-protection claim | Now | Owner |  | ST-01, FAC-03, OPS-05 |
| I-006 | Run the factory as a GitHub App or bot account with a least-privilege token | Next | Owner |  | ST-02, SEC-03, FAC-03 |
| I-007 | Add CODEOWNERS so factory, CI and agent-config changes need owner review | Now | Owner-reviewed PR |  | ST-07, FAC-05 |
| I-008 | Add Dependabot for Go modules, npm, GitHub Actions and Docker | Next | Owner-reviewed PR |  | ST-07, OPS-21, SEC-20, FE-18 |
| I-009 | Pin GitHub Actions to commit SHAs and container images to digests | Next | Owner-reviewed PR |  | SEC-20, OPS-21, OBS-12 |
| I-010 | Make Semgrep scan for real and dependency review blocking | Now | Owner-reviewed PR |  | OPS-05, ST-08 |
| I-011 | Add CI concurrency groups and remove duplicate runs | Next | Owner-reviewed PR |  | OPS-09 |
| I-012 | Add SECURITY.md and enable private vulnerability reporting | Next | Owner |  | ST-07 |
| I-013 | Auto-delete merged branches, remove stale branches and refuse empty PRs | Now | Owner + Owner-reviewed PR |  | ST-06 |
| I-014 | Add a monthly canary that proves the CI gates fail when they should | Later | Owner-reviewed PR |  | ST-08 |
| I-015 | Run Go tests with `-race` and prove the Postgres integration tests run in CI | Next | Owner-reviewed PR |  | BE-14, ST-08 |
| I-016 | Restrict factory discovery to owner-authored issues and comments and same-repository PRs | Now | Owner-reviewed PR | yes | FAC-01, FAC-02, SEC-01, SEC-02 |
| I-017 | Trust factory markers and deploy-failure issues only when authored by the bot identity | Now | Owner-reviewed PR | yes | FAC-09, SEC-21 |
| I-018 | Remove the planner's label-edit power and verify who applied `owner approved` | Now | Owner-reviewed PR | yes | FAC-02, SEC-01, ST-02, AGT-11 |
| I-019 | Move the merge decision from the agent into the orchestrator | Now | Owner-reviewed PR | yes | FAC-03, FAC-07, AGT-04, AGT-10 |
| I-020 | Default-deny OpenCode permission profiles for every agent and settle the config schema | Next | Owner-reviewed PR | yes | FAC-04, SEC-04, AGT-11, AGT-16 |
| I-021 | Run agent sessions in a disposable sandbox by default | Next | Owner-reviewed PR | yes | FAC-16, SEC-03, SEC-26 |
| I-022 | Use separate Unix users for the factory and the deploy, and remove the factory's Docker access | Next | Owner | yes | OPS-16, SEC-03, SEC-26 |
| I-023 | Pin vendored skills to commit SHAs and verify their integrity | Next | Owner-reviewed PR |  | SEC-05, AGT-15, FAC-21 |
| I-024 | Harden the dev-server SSH wrapper | Next | Owner-reviewed PR | yes | SEC-14, OPS-15, OPS-16 |
| I-025 | Give each container only the environment variables it needs | Next | Owner-reviewed PR | yes | SEC-13, OPS-15 |
| I-026 | Redact secrets and personal data from session output and telemetry | Now | Owner-reviewed PR | yes | OBS-11, SEC-12 |
| I-027 | Fix session-ID capture and record the agent on every session event | Now | Owner-reviewed PR |  | FAC-13, OBS-05 |
| I-028 | Limit quota detection to provider errors and stop fallback models from merging | Now | Owner-reviewed PR |  | FAC-07 |
| I-029 | Detect and escalate stalled factory PRs | Next | Owner-reviewed PR |  | FAC-06 |
| I-030 | Remove head-of-line blocking in planning and revisit throughput and prioritisation | Later | Owner-reviewed PR |  | FAC-08, FAC-19 |
| I-031 | Make idempotency checks fail closed and propagate infrastructure failures out of subshells | Next | Owner-reviewed PR |  | FAC-09 |
| I-032 | Fix lock and process-lifecycle hazards in `tick.sh` | Next | Owner-reviewed PR |  | FAC-14 |
| I-033 | Run the factory from a single code version | Next | Owner-reviewed PR |  | FAC-05 |
| I-034 | Fix factory worktree handling | Later | Owner-reviewed PR |  | FAC-20 |
| I-035 | Add a CI workflow for the factory and deploy scripts | Next | Owner-reviewed PR |  | FAC-18, OPS-08, AGT-16, OBS-13 |
| I-036 | Decompose `tick.sh` into a tested orchestrator and delete dead code | Later | Owner-reviewed PR |  | FAC-17 |
| I-037 | Deduplicate the acceptance-criteria checker and align it with the issue validator | Later | Factory |  | FAC-22 |
| I-038 | Feed post-merge CI, QA deploy and e2e results back into the factory | Next | Owner-reviewed PR |  | FAC-15 |
| I-039 | Make each agent role defined in one place, and align markers and labels | Now | Owner-reviewed PR |  | AGT-06, FAC-12 |
| I-040 | Curate per-role skill sets and remove irrelevant skills and caveman from factory sessions | Now | Owner-reviewed PR |  | AGT-05, AGT-12, FAC-21 |
| I-041 | Add a "no human available" rule and headless variants of the interactive skills | Next | Owner-reviewed PR |  | AGT-02 |
| I-042 | Write first-party backend architecture skills | Next | Factory |  | AGT-01 |
| I-043 | Write first-party UI and e2e skills and per-area AGENTS.md files | Next | Factory |  | AGT-01 |
| I-044 | Seed GLOSSARY.md and architecture decision records | Next | Owner + Factory |  | AGT-07 |
| I-045 | Encode the architecture rules as tests and in-repo Semgrep rules | Next | Factory |  | AGT-03, BE-20 |
| I-046 | Add a shared `check.sh` used by agents and CI, and fix `/lint-frontend` | Now | Owner-reviewed PR |  | AGT-09, FE-15 |
| I-047 | Give agents a validated way to propose and create follow-up issues | Now | Owner-reviewed PR |  | AGT-08 |
| I-048 | Add an independent reviewer on a different model family that posts a GitHub review | Next | Owner-reviewed PR |  | ST-03, FAC-11, AGT-10 |
| I-049 | Route models by role and risk and validate model IDs at startup | Next | Owner-reviewed PR |  | FAC-10, AGT-10 |
| I-050 | Move deterministic lifecycle steps out of the LLM session | Later | Owner-reviewed PR |  | AGT-04 |
| I-051 | Add an Architecture Impact section to the issue template | Later | Factory |  | AGT-14 |
| I-052 | Build a replay benchmark for prompt, skill and model changes | Later | Owner-reviewed PR |  | AGT-13, ST-09 |
| I-053 | Install language servers on the factory host and document the resolved OpenCode config | Later | Owner |  | AGT-16 |
| I-054 | Ship factory events through the existing SigNoz collector | Now | Owner-reviewed PR |  | OBS-02, OBS-13 |
| I-055 | Capture tokens, cost, skills, tools and outcomes in factory session telemetry | Next | Owner-reviewed PR |  | OBS-01, FAC-13, ST-09 |
| I-056 | Emit delivery-flow and queue events (lead time, rework, queue depth) | Next | Owner-reviewed PR |  | OBS-01, ST-09 |
| I-057 | Provision SigNoz dashboards, alerts, retention and admin from git | Next | Owner-reviewed PR |  | OBS-03 |
| I-058 | Add a minimal alert set that reaches the owner | Now | Owner-reviewed PR |  | OBS-04, FAC-13, OPS-13, OPS-01 |
| I-059 | Emit deploy events and tag the backend with version and environment | Next | Owner-reviewed PR |  | OBS-06 |
| I-060 | Complete backend APM: route names, DB, sidecar and SMTP spans, log bridge, runtime metrics | Next | Factory |  | OBS-07, BE-17 |
| I-061 | Add event-sourcing and product metrics | Next | Factory |  | OBS-08, BE-17 |
| I-062 | Collect container, Postgres and Caddy metrics | Next | Owner-reviewed PR |  | OBS-09 |
| I-063 | Model factory ticks as traces with resource attributes | Later | Owner-reviewed PR |  | OBS-10 |
| I-064 | Harden SigNoz reproducibility on a fresh host | Later | Owner-reviewed PR |  | OBS-12, OPS-13 |
| I-065 | Add sidecar tracing and optional frontend RUM | Later | Factory |  | OBS-14 |
| I-066 | Make every deploy failure reach the owner | Now | Owner-reviewed PR |  | OPS-01, OPS-20 |
| I-067 | Back up Postgres and `caddy-data` nightly, encrypted and off-box, with a restore test | Now | Owner |  | OPS-03, SEC-26 |
| I-068 | Deploy only CI-green, tagged images with rollback | Next | Owner-reviewed PR |  | OPS-04, OPS-18 |
| I-069 | Record deploy state with GitHub Deployments instead of commits to `main` | Next | Owner-reviewed PR |  | OPS-07, ST-05 |
| I-070 | Make `/healthz` check the database, sidecar and running version | Next | Factory |  | OPS-11, BE-16 |
| I-071 | Add a migration version table and run migrations transactionally | Next | Factory |  | BE-10, OPS-10 |
| I-072 | Fit the shared host: stagger schedules, reclaim disk, set a resource budget | Next | Owner |  | OPS-12 |
| I-073 | Make QA production-like | Next | Owner-reviewed PR |  | OPS-17 |
| I-074 | Refuse log-mode email outside local development | Now | Factory |  | SEC-06 |
| I-075 | Seed QA with synthetic data and a configured admin bootstrap | Next | Factory | yes | OPS-19, SEC-08 |
| I-076 | Add an on-demand deploy trigger and deploy after each merge | Later | Owner-reviewed PR |  | OPS-20 |
| I-077 | Define a promotion path from QA to production | Later | Owner |  | OPS-18 |
| I-078 | Make `setup.sh` safe by default and fix stale documentation | Later | Factory |  | OPS-22, SEC-16, OPS-05 |
| I-079 | Scan container images for vulnerabilities in CI | Later | Owner-reviewed PR |  | OPS-21 |
| I-080 | Validate compose and Caddy config, build every image and smoke-test the stack in CI | Next | Owner-reviewed PR |  | OPS-08 |
| I-081 | Put QA behind an access gate and remove the Authelia stub | Now | Owner | yes | SEC-22, OPS-17, SEC-20 |
| I-082 | Restructure Caddy: loopback health listener, redirect-only port 80, security headers and HSTS | Now | Owner-reviewed PR |  | SEC-24, SEC-11, OPS-14, FE-11 |
| I-083 | Fix client-IP handling: narrow trusted_proxies, pass the real IP, rekey and bound the rate limiter | Now | Owner-reviewed PR | yes | SEC-25, SEC-07, BE-05 |
| I-084 | Monitor the certificate lifecycle and remove the `admin@localhost` ACME contact | Now | Owner-reviewed PR |  | SEC-23 |
| I-085 | Add CAA records and consider a DNS-01 wildcard certificate | Later | Owner |  | SEC-22 |
| I-086 | Record the exposure mode per environment and stop the deploy dropping the tunnel | Next | Owner-reviewed PR |  | SEC-27, SEC-11, OPS-17 |
| I-087 | Stop the projection runner from skipping events | Now | Factory |  | BE-01 |
| I-088 | Fix the create-booking advisory lock | Next | Factory |  | BE-02 |
| I-089 | Add idempotency keys to commands | Next | Factory |  | BE-03 |
| I-090 | Write outbox rows in the same transaction as the event | Next | Factory |  | BE-04 |
| I-091 | Make email delivery retries robust | Next | Factory |  | BE-06 |
| I-092 | Add per-aggregate versioning, optimistic concurrency and event schema versions | Later | Factory |  | BE-07 |
| I-093 | Add an operator-triggered projection rebuild | Later | Factory |  | BE-20 |
| I-094 | Remove backend performance bottlenecks | Later | Factory |  | BE-18 |
| I-095 | Move sessions server-side: HttpOnly cookie, logout, revocation, rotation | Next | Factory |  | SEC-10, BE-11, FE-14 |
| I-096 | Move login codes and sessions out of the event log, and key auth by user ID | Later | Factory |  | BE-11, SEC-15 |
| I-097 | Limit attempts per login and email-change code | Next | Factory |  | SEC-17 |
| I-098 | Restrict `GET /users` by role and minimise the personal data it returns | Next | Factory | yes | SEC-09 |
| I-099 | Make the HTTP layer consistent: body limits, generic 5xx, one error format | Next | Factory |  | BE-12, SEC-18, SEC-19 |
| I-100 | Validate configuration at startup and require `PUBLIC_BASE_URL` | Next | Factory |  | BE-16, SEC-19 |
| I-101 | Fix the backend–sidecar contract | Next | Factory |  | BE-09 |
| I-102 | Send booking emails in Europe/Stockholm time | Next | Factory |  | BE-08 |
| I-103 | Close domain gaps for removed users, blocked periods and the last admin | Later | Factory |  | BE-19 |
| I-104 | Remove the `sample` scaffolding package | Later | Factory |  | BE-15 |
| I-105 | Consolidate drift in backend code | Later | Factory |  | BE-13 |
| I-106 | Share one Postgres test harness and test the key failure modes | Later | Factory |  | BE-14 |
| I-107 | Make session restore resilient and handle 401 responses globally | Next | Factory |  | FE-01, FE-16 |
| I-108 | Confirm destructive actions and show progress and success feedback | Next | Factory |  | FE-02 |
| I-109 | Fix admin selects that send an empty user ID | Now | Factory |  | FE-03 |
| I-110 | Fix dark mode and colour contrast | Next | Factory |  | FE-04, FE-10 |
| I-111 | Re-plan redesign issues #120–#123 before they are built | Now | Owner |  | FE-05 |
| I-112 | Make booking phone-friendly | Next | Factory |  | FE-07 |
| I-113 | Show times in Europe/Stockholm, friendly error messages and i18n-ready strings | Next | Factory |  | FE-08 |
| I-114 | Introduce a data-fetching layer with loading, error and cancellation states | Later | Factory |  | FE-09 |
| I-115 | Fix accessibility issues | Later | Factory |  | FE-10 |
| I-116 | Add asset caching, compression and asset retention across deploys | Later | Factory |  | FE-11 |
| I-117 | Improve the login flow: go back, resend, deep links, autofill | Next | Factory |  | FE-12 |
| I-118 | Show the iCal URL without regenerating it | Later | Factory |  | FE-13 |
| I-119 | Frontend tooling: ESLint, coverage, accessibility checks, time-zone test matrix | Later | Factory |  | FE-15 |
| I-120 | Add a shared route layout, session guard and error boundary | Later | Factory |  | FE-16 |
| I-121 | Remove dead pages and aliases, and fix the theming README | Later | Factory |  | FE-17 |
| I-122 | Upgrade Vite and Vitest, fix overrides and decide on the Chakra version | Later | Factory |  | FE-18 |
| I-123 | Fix the login e2e spec and add a mail sink | Now | Owner-reviewed PR |  | FE-06, OPS-06 |
| I-124 | Cover the core journeys in e2e and run them in CI and after each QA deploy | Next | Owner-reviewed PR |  | FE-06, OPS-06, OPS-08 |
| I-125 | Crypto-shred personal data in events | Later | Factory |  | SEC-15 |
| I-126 | Add retention for login codes, sessions, outbox, logs and telemetry | Later | Factory |  | SEC-15, OBS-11 |
| I-127 | Write the privacy documentation and keep QA on synthetic data | Later | Owner |  | SEC-15 |

## Epic A - Immediate containment

Three owner actions that close exposures that are open today: outsiders can steer the factory, personal data sits in a public issue, and SigNoz listens on all interfaces. They buy time for the permanent fixes in Epics B and C.

### I-001 - Pause the factory and limit public interactions until the trust filters ship

**Covers:** FAC-01, FAC-02, SEC-01, SEC-02 · **Labels:** `dev-ops`, `trivial-task` · **Priority:** Now · **Executor:** Owner · **Depends on:** –

> **Sensitive.** This describes an open path for any GitHub user to run code on the QA host with the owner's token, so do the steps first and file only a neutral "factory paused for maintenance" record, or keep the details in a private security advisory.

**Problem.** The repo is public and factory discovery never checks who wrote an issue, comment or PR. Planning takes the oldest unlabeled issue from any author (`dev-ops/factory/tick.sh:233-234`), the planner may run `"gh issue edit*": allow` (`.opencode/agents/planner.md:18`), and a fork PR on a branch named `factory/issue-N` becomes a fix candidate by name alone (`dev-ops/factory/lib/factory.py:208-211`). The fixer then runs that branch's tests on the QA host with the owner's credentials. Until I-016 and I-018 land, the only safe state is a stopped factory.

**Proposed change.**
- Disable the hourly tick: comment out the `tick.sh` line in the factory user's crontab. Leave the QA deploy timer running.
- Set GitHub interaction limits to "collaborators only" (Settings → Moderation options), or make the repo private while the factory runs unattended (SEC-01, recommendation 5). Interaction limits expire, so note the expiry date here.
- Hide or close any open issue, comment on #120–#125, or PR that comes from a non-owner account or a fork.
- Re-enable the tick only after I-016 and I-018 are merged and the factory checkout has pulled them.

**Acceptance criteria**
- [ ] `crontab -l` for the factory user shows no active `tick.sh` entry, and the factory JSONL log has no `tick_start` event after the pause time.
- [ ] `gh api repos/adamzki99/booking-system/interaction-limits` returns `"limit": "collaborators_only"`, or the repository visibility is private.
- [ ] `gh pr list --state open --json isCrossRepository --jq 'map(select(.isCrossRepository)) | length'` returns `0`.
- [ ] A comment on this issue records the re-enable time, which is after I-016 and I-018 were closed.

### I-002 - Scrub personal data from issue #101 and stop posting raw deploy logs to issues

**Covers:** OPS-02, SEC-06 · **Labels:** `dev-ops`, `bug`, `light-build-task` · **Priority:** Now · **Executor:** Owner + Owner-reviewed PR · **Depends on:** –

> **Sensitive.** It points readers to the exact public comment that holds login-code and booking log lines, so scrub #101 first and then file with neutral wording ("deploy failures should not post logs") and no link to the comment.

**Problem.** When a QA deploy fails, `dev-ops/scripts/deploy-environment.sh` collects `docker compose logs --tail=100` for all services (`:190`, `:360`, `:379`) and `surface_failure` pastes it into a public "QA deployment failed" issue (`:134-151`). QA runs `EMAIL_MODE=log`, which logs every email's recipient and body (`internal/email/log_sender.go:20`). Issue #101, comment 3, holds a login-code line for a test address and booking-confirmation bodies (from GitHub metadata). A live code or a real resident's address would be published and indexed.

**Proposed change.**
- Owner: delete the affected comments on #101 rather than editing them (GitHub keeps the edit history), and check every other "QA deployment failed" issue (`--state all`) for log tails.
- In `surface_failure`, post only the commit SHA, the failing command, the UTC time and the `docker compose ps` status, with no log lines.
- Write the full log tail to a local file such as `~/.local/state/booking-deploy/<ts>.log` and name that path in the issue body. Any excerpt must come from `backend` only, filtered as in OPS-02.
- Requiring `EMAIL_MODE` explicitly and removing the body from `LogSender` output (the backend half of SEC-06) is tracked outside this epic.

**Acceptance criteria**
- [ ] Issue #101 and every other "QA deployment failed" issue contain no `email (log mode` line, no email address and no `Your login code` text.
- [ ] `dev-ops/scripts/tests/test-deploy-environment.sh` feeds a compose log containing an email address and a login-code line, and the stubbed `gh` issue body contains neither.
- [ ] The issue body template in `deploy-environment.sh` has no `Log tail:` section (`grep -n "Log tail" dev-ops/scripts/deploy-environment.sh` returns nothing).
- [ ] After a forced QA deploy failure, a log file exists under `~/.local/state/booking-deploy/` and the issue comment holds only SHA, command, time and service status.

### I-003 - Bind the SigNoz UI and OTLP ports to loopback and claim the SigNoz admin account

**Covers:** SEC-12, OPS-13, OBS-03 · **Labels:** `dev-ops`, `bug`, `trivial-task` · **Priority:** Now · **Executor:** Owner · **Depends on:** –

> **Sensitive.** It tells readers that an unclaimed admin sign-up and unauthenticated telemetry ingestion may be reachable on the QA host, so bind the ports and claim the account first, then file a neutral record.

**Problem.** `dev-ops/signoz/docker-compose.yml:136-137` publishes `"${SIGNOZ_UI_PORT:-3301}:8080"` and `:184-186` publishes `"4317:4317"` and `"4318:4318"`, all on 0.0.0.0, and Docker-published ports bypass `ufw`. SigNoz's first sign-up becomes admin (not verified on this host), and OTLP accepts unauthenticated writes. The collector also mounts `/:/hostfs:ro` (`:173`), which includes `~/.config/gh/hosts.yml`, `~/.ssh` and `projects/sauna/.env`. Internet reachability depends on NAT and firewall rules the review could not see.

**Proposed change.**
- Publish the UI as `"127.0.0.1:${SIGNOZ_UI_PORT:-3301}:8080"` and reach it over an SSH tunnel or Tailscale.
- Bind OTLP to `127.0.0.1:4317`/`127.0.0.1:4318`, or drop the host ports and attach the booking backends to a shared `signoz-net` Docker network (OPS-13 snippet).
- Claim the admin account now. If an account exists that the owner did not create, wipe the `signoz-sqlite` volume and re-create it.
- Narrow the `/:/hostfs:ro` mount to `/proc`, `/sys` and the filesystems the host-metrics scraper needs.
- Provisioning dashboards, alerts and retention as code (rest of OBS-03, OPS-13) is tracked outside this epic; iCal tokens in traces (rest of SEC-12) are I-026.

**Acceptance criteria**
- [ ] `ss -ltnp` on the host shows ports 3301, 4317 and 4318 bound only to `127.0.0.1`, or 4317/4318 not published at all.
- [ ] From a machine outside the host's network, `nc -zv <host> 3301`, `4317` and `4318` all fail to connect.
- [ ] The SigNoz user list contains exactly one admin, the owner's account.
- [ ] `docker compose -f dev-ops/signoz/docker-compose.yml config` shows no volume whose source is `/`.
- [ ] A QA backend request after the change shows up as a SigNoz trace within 5 minutes.

## Epic B - GitHub governance and CI gates

GitHub enforces none of the rules the agents are told to follow. This epic moves the gates from prose into rulesets, CODEOWNERS and CI, so a bad merge is blocked by the platform rather than by a model's reading of `AGENTS.md`.

### I-004 - Add an always-running `ci-gate` job as the single required check

**Covers:** ST-04, OPS-09 · **Labels:** `dev-ops`, `enhancement`, `standard-build-task` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** `backend-ci.yml:4-11`, `frontend-ci.yml:4-13` and `sidecar-ci.yml:4-13` trigger only on matching paths (last 300 runs: Backend 60, Frontend 10, Sidecar 3, versus Security 142). If one of them is marked required, a PR that doesn't touch its paths waits on "Expected - Waiting" forever, and the factory's fixer would loop on PRs it cannot unblock. Without one always-present check, the ruleset in I-005 has nothing it can safely require.

**Proposed change.**
- Add `.github/workflows/ci.yml`, triggered on every `pull_request` and on push to `main`. A `changes` job uses `dorny/paths-filter` (pinned to a SHA) to decide which suites run.
- Make the existing workflows reusable (`on: workflow_call`) and call them from `ci.yml`, gating backend, frontend and sidecar on the filter outputs.
- Add a final job that always runs and fails if any needed job failed or was cancelled; skipped suites pass:
  ```yaml
  ci-gate:
    if: always()
    needs: [changes, backend, frontend, sidecar, security, semgrep]
    runs-on: ubuntu-latest
    steps:
      - run: '[[ "${{ contains(needs.*.result, ''failure'') || contains(needs.*.result, ''cancelled'') }}" == "false" ]]'
  ```
- Document in `.github/workflows/README.md` that `ci-gate` is the only required check and new suites join its `needs:`.

**Acceptance criteria**
- [ ] A docs-only PR gets a green `ci-gate`, with the backend, frontend and sidecar jobs shown as skipped.
- [ ] A PR with a failing Go test under `product/backend/` gets a red `ci-gate`.
- [ ] A PR that touches only `product/frontend/` runs the frontend suite and skips the backend suite.
- [ ] A PR that changes only `dev-ops/**` still reports a `ci-gate` result.
- [ ] When a needed job is cancelled, `ci-gate` concludes `failure`.

### I-005 - Protect `main` with a ruleset and correct the README's branch-protection claim

**Covers:** ST-01, FAC-03, OPS-05 · **Labels:** `dev-ops`, `documentation`, `trivial-task` · **Priority:** Now · **Executor:** Owner · **Depends on:** I-004

**Problem.** `GET .../branches/main/protection` returns 404 and `GET .../rulesets` returns `[]` (from GitHub metadata). The only CI gate is prose in `AGENTS.md:41-44`. PR #141, which changed `tick.sh`, was merged 2 s after it was opened, before any check had started. Meanwhile `dev-ops/README.md:270-272` says "Combined with the repo's *require conversation resolution* branch protection, unresolved findings block merging", and `:291` and `.github/workflows/README.md` describe required checks that don't exist.

**Proposed change.**
- Create a branch ruleset on `~DEFAULT_BRANCH`: require a pull request, require the status check `ci-gate` (I-004) with the branch up to date, and block force-pushes (`non_fast_forward`) and deletion.
- Set required approvals to 0 for now, since the owner cannot approve PRs the factory opens as the owner. Raise it after I-006 and I-007.
- Keep the bypass list empty while the factory uses the owner's token, or the factory bypasses too. After I-006, add the owner only (ST-02).
- `booking-deploy` bookkeeping commits push straight to `main` and will be rejected: move deploy state off `main` first (ST-05, tracked outside this epic) or give the deploy credential a temporary bypass.
- Rewrite the branch-protection and required-check text in `dev-ops/README.md` (`:270-272`, `:291`) and `.github/workflows/README.md` to describe the ruleset exactly as configured.

**Acceptance criteria**
- [ ] `gh api repos/adamzki99/booking-system/rulesets` lists an active ruleset on the default branch with `pull_request`, `required_status_checks` (context `ci-gate`), `non_fast_forward` and `deletion` rules.
- [ ] `git push origin HEAD:main` from the owner's account (with the bypass list empty) is rejected.
- [ ] On a PR whose `ci-gate` is red or pending, `gh pr merge` without `--auto` fails.
- [ ] `grep -rn "branch protection\|required status check" dev-ops/README.md .github/workflows/README.md` returns only statements that match the configured ruleset.

### I-006 - Run the factory as a GitHub App or bot account with a least-privilege token

**Covers:** ST-02, SEC-03, FAC-03 · **Labels:** `dev-ops`, `enhancement`, `standard-build-task` · **Priority:** Next · **Executor:** Owner · **Depends on:** –

**Problem.** All 70 issues and every PR are authored by `adamzki99`, and on #120/#125 both the `owner approved` label and the planner's labels show actor `adamzki99` (from GitHub metadata). GitHub cannot tell owner from factory: there is no audit trail, nothing technical stops self-approval, the owner gets no notifications for factory PRs, and a leaked factory token is a full owner token. That token can change workflows; PRs #127 and #128 added `frontend-ci.yml` and `sidecar-ci.yml`.

**Proposed change.**
- Create a GitHub App (preferred) or a machine user, installed on this repo only: Contents, Issues and Pull requests read/write; Actions and Checks read. No `workflow` permission, no Administration.
- Have `tick.sh` mint a short-lived installation token per tick and pass it to sessions as `GH_TOKEN` (how sessions receive it inside the sandbox is I-021).
- Remove the owner's `gh` login (`~/.config/gh/hosts.yml`) from the factory user and revoke that token.
- Set `FACTORY_LOGIN` to the bot login so I-016, I-017 and I-018 can filter on it.
- After the switch, set the I-005 bypass list to the owner only and raise required approvals.

**Acceptance criteria**
- [ ] `gh pr view <next factory PR> --json author` and its marker comments show the bot login, not `adamzki99`.
- [ ] A push with the factory token that changes a file under `.github/workflows/` is rejected.
- [ ] The factory user's `~/.config/gh/hosts.yml` holds no `adamzki99` credential, and the old token no longer appears in the owner's GitHub token settings.
- [ ] The owner receives a GitHub notification for the next factory PR.

### I-007 - Add CODEOWNERS so factory, CI and agent-config changes need owner review

**Covers:** ST-07, FAC-05 · **Labels:** `dev-ops`, `enhancement`, `light-build-task` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** I-005

**Problem.** There is no `CODEOWNERS` file (ST-07). Builder and fixer have `edit: allow` and can merge, and after `cd "$FACTORY_WORKTREE"` (`tick.sh:936`) OpenCode loads `opencode.jsonc`, `.opencode/agents/*.md` and `AGENTS.md` from the latest `origin/main`. A merged change to `builder.md` therefore widens the next session's permissions with no human in the loop. It has happened: #138–#145 changed `tick.sh`, `factory.py` and the sandbox code on 2026-11-18, each merged within 0–2 minutes, #141 in 2 s.

**Proposed change.**
- Add `.github/CODEOWNERS` (paths from FAC-05 and SEC-03):
  ```
  /.github/                          @adamzki99
  /.opencode/                        @adamzki99
  /opencode.jsonc                    @adamzki99
  /AGENTS.md                         @adamzki99
  /dev-ops/                          @adamzki99
  /projects/**/docker-compose*.yml   @adamzki99
  ```
- Turn on "Require review from Code Owners" in the I-005 ruleset. It binds only once the factory has its own identity (I-006); until then it records intent.
- In `tick.sh`, refuse to start a session when the worktree's guardrail files differ from a `factory-config` tag that only the owner moves: `git diff --quiet factory-config origin/main -- .opencode/agents opencode.jsonc AGENTS.md || { emit_event guardrail_drift; exit 1; }`.
- Pinning which version of `tick.sh` itself runs (the rest of FAC-05) is tracked outside this epic.

**Acceptance criteria**
- [ ] `gh api repos/adamzki99/booking-system/codeowners/errors` returns `"errors": []`.
- [ ] After I-006, a test PR that changes `.opencode/agents/builder.md` shows "Review required" from `@adamzki99` and cannot merge without it.
- [ ] A `tick.sh` test where the worktree's `opencode.jsonc` differs from `factory-config` emits `guardrail_drift`, exits non-zero and starts no OpenCode session.
- [ ] The `factory-config` tag exists, and `dev-ops/factory/README.md` documents how the owner moves it.

### I-008 - Add Dependabot for Go modules, npm, GitHub Actions and Docker

**Covers:** ST-07, OPS-21, SEC-20, FE-18 · **Labels:** `dev-ops`, `enhancement`, `light-build-task` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-004

**Problem.** Neither `.github/dependabot.yml` nor a Renovate config exists (ST-07, OPS-21). Go 1.26, Node and the Docker base images will drift. CI already warns "Node.js 20 is deprecated … actions/checkout@v4" (from GitHub metadata). The frontend lockfile resolves `vite` 5.4.21, `vitest` 2.1.9 and `esbuild` 0.21.5, and esbuild below 0.25 carries GHSA-67mh-4wv8-2f99 (dev-only). `@playwright/test` is pinned at 1.49.0 and unwatched (`dev-ops/testing/package.json:7`). Pinning actions and images (I-009) without a bot to bump the pins only freezes them.

**Proposed change.**
- Add `.github/dependabot.yml`, weekly, grouping minor and patch updates:
  - `gomod`: `/product/backend`, `/projects/sauna/sidecar`
  - `npm`: `/product/frontend`, `/dev-ops/testing`
  - `github-actions`: `/`
  - `docker`: the Dockerfile directories `/product/backend`, `/product/frontend`, `/projects/sauna/sidecar`, `/dev-ops/testing`, plus the compose files in `/projects/sauna` and `/dev-ops/signoz` via the `docker-compose` ecosystem.
- Ignore semver-major updates of `@chakra-ui/*`, following FE-18's advice to stay on Chakra v2 through the redesign.
- Dependabot PRs go through `ci-gate` (I-004) like any other PR.
- Tracked outside this epic: the Vite/Vitest upgrade and `@types/node` alignment (FE-18), `--pull` in the deploy and image scanning (OPS-21), and removing the Authelia skeleton (SEC-20).

**Acceptance criteria**
- [ ] The repository's Dependabot page (Insights → Dependency graph → Dependabot) lists every configured directory with no configuration error.
- [ ] Within 7 days of merge, each configured ecosystem has either an open Dependabot PR or a "last checked, up to date" status.
- [ ] A Dependabot PR runs `ci-gate`, and the ruleset blocks merging it while `ci-gate` is red.
- [ ] No Dependabot PR proposes a new major version of `@chakra-ui/react`.

### I-009 - Pin GitHub Actions to commit SHAs and container images to digests

**Covers:** SEC-20, OPS-21, OBS-12 · **Labels:** `dev-ops`, `enhancement`, `light-build-task` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-008

**Problem.** `backend-ci.yml`, `security.yml` and `semgrep.yml` use tags (`actions/checkout@v4`, `actions/setup-go@v5`, `actions/dependency-review-action@v4`, `gitleaks/gitleaks-action@v2`), while `frontend-ci.yml` and `sidecar-ci.yml` are already SHA-pinned. The `semgrep/semgrep` container is unpinned (`semgrep.yml:28`) and govulncheck is installed `@latest` (`security.yml:43`). Compose uses `caddy:2-alpine`, `postgres:16-alpine`, `authelia/authelia:latest` and `cloudflare/cloudflared:latest`; base images have no digest; SigNoz images are pinned by tag only, and its init downloads `histogram-quantile` with no checksum (`dev-ops/signoz/docker-compose.yml:74-82`). A moved tag changes what CI or QA runs without any commit.

**Proposed change.**
- Pin every `uses:` to a full commit SHA with a version comment, as `frontend-ci.yml:27` already does.
- Pin the Semgrep container, every compose `image:` and every Dockerfile `FROM` to `@sha256:` digests, keeping the tag for readability (`postgres:16-alpine@sha256:…`).
- Pin govulncheck to a release (`@v1.x.y`).
- Verify the SHA-256 of the `histogram-quantile` tarball before extracting it in the SigNoz init step.
- Dependabot (I-008) keeps the pins current. The unstable `host.name` and stale alertmanager target (rest of OBS-12) are tracked outside this epic.

**Acceptance criteria**
- [ ] `grep -rnE 'uses: [^ ]+@v[0-9]' .github/workflows` returns nothing.
- [ ] Every `image:` line in `docker-compose*.yml` files and every external-image `FROM` line in Dockerfiles contains `@sha256:` (checked by a grep in CI or in the PR description).
- [ ] `grep -n '@latest' .github/workflows/*.yml` returns nothing.
- [ ] The SigNoz init step fails when the expected tarball checksum is altered, and succeeds with the correct one.
- [ ] `ci-gate` and the next QA deploy succeed with the pinned versions.

### I-010 - Make Semgrep scan for real and dependency review blocking

**Covers:** OPS-05, ST-08 · **Labels:** `dev-ops`, `bug`, `light-build-task` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** `.github/workflows/semgrep.yml:35-37` runs `semgrep ci` with `SEMGREP_APP_TOKEN`, but the secret isn't set. The 2026-11-19 run logs an empty token, "run 'semgrep login' before using 'semgrep ci'" and "There were errors during analysis but Semgrep will succeed", and the job is green (from GitHub metadata). That explains Semgrep's 0 failures in 82 runs (ST-08). Dependency review has `continue-on-error: true` (`security.yml:21`), so it cannot fail either. Every factory PR shows green security checks, which a model reads as "safe".

**Proposed change.**
- Either add `SEMGREP_APP_TOKEN`, or switch to tokenless OSS rules: `semgrep scan --config p/default --config p/golang --config p/typescript --error --metrics=off`. The container digest pin is in I-009.
- `.semgrep.yml` (a top-level `paths:` with no rules) likely has no effect (moderate confidence, OPS-05): move its excludes to `.semgrepignore` and remove it or give it real rules.
- Remove `continue-on-error: true` from dependency review, and confirm the Dependency Graph is enabled.
- Delete the claim in `dev-ops/README.md:293-294` and `.github/workflows/README.md` that "A Semgrep instance also runs on the development server".

**Acceptance criteria**
- [ ] The Semgrep job log on a PR shows rules loaded and a scanned-file count above 0, and no `semgrep login` message.
- [ ] A test PR that adds a pattern flagged by the chosen ruleset fails the Semgrep job and `ci-gate`.
- [ ] A test PR that adds a dependency with a known high-severity advisory fails dependency review.
- [ ] `grep -n continue-on-error .github/workflows/security.yml` returns nothing.
- [ ] `grep -rn "Semgrep instance also runs" dev-ops .github` returns nothing.

### I-011 - Add CI concurrency groups and remove duplicate runs

**Covers:** OPS-09 · **Labels:** `dev-ops`, `enhancement`, `trivial-task` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-004

**Problem.** `backend-ci.yml:8-11` has a `push` trigger with no branch filter, so every push to a factory branch runs Backend CI twice: for example "Backend CI push factory/issue-118" alongside the PR run (from GitHub metadata). The frontend and sidecar workflows already restrict `push` to `main`. No workflow sets `concurrency:`, so runs for superseded commits keep going. That doubles CI work per push, delays the required `ci-gate` result, and puts duplicate entries in the check list the fixer reads.

**Proposed change.**
- Restrict the `push` trigger in `backend-ci.yml` (and in `ci.yml` from I-004) to `branches: [main]`.
- Add a concurrency group to every workflow, cancelling only PR runs so each merge to `main` keeps a full result:
  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: ${{ github.event_name == 'pull_request' }}
  ```
- Check that scheduled runs (the daily Semgrep scan, the weekly Security scan) still complete after the change.

**Acceptance criteria**
- [ ] After a push to an open factory PR branch, `gh run list --branch factory/issue-N` shows each workflow once, with event `pull_request` and no `push` duplicate.
- [ ] Two pushes to the same PR branch within a minute leave the first run of each workflow `cancelled` and the second completed.
- [ ] Two quick merges to `main` both get completed, uncancelled runs.
- [ ] `grep -L "concurrency:" .github/workflows/*.yml` returns nothing.

### I-012 - Add SECURITY.md and enable private vulnerability reporting

**Covers:** ST-07 · **Labels:** `documentation`, `dev-ops`, `trivial-task` · **Priority:** Next · **Executor:** Owner · **Depends on:** –

**Problem.** The repo is public and has no `SECURITY.md` (ST-07). Someone who finds a weakness has no private channel, so a report would arrive as a public issue. Until I-016 lands, a public issue is also input to the factory's planner, and the details would sit in the open while the owner works on a fix.

**Proposed change.**
- Enable private vulnerability reporting (Settings → Code security).
- Add a short `SECURITY.md`:
  - how to report (Security → "Report a vulnerability"), and not through public issues or PRs;
  - what is in scope: backend, frontend, sidecar, the factory scripts and agent configuration, and the QA deploy;
  - what not to do, for example no testing against residents' data on QA;
  - the response time the owner can realistically commit to.
- Note in `SECURITY.md` that the factory does not act on advisories. They are not issues, so factory discovery never reads them.

**Acceptance criteria**
- [ ] `SECURITY.md` exists at the repo root or in `.github/`, and the repository's Security → Policy page shows it.
- [ ] `gh api repos/adamzki99/booking-system/private-vulnerability-reporting` returns `{"enabled": true}`.
- [ ] Viewed from a non-collaborator account, the Security tab offers "Report a vulnerability".

### I-013 - Auto-delete merged branches, remove stale branches and refuse empty PRs

**Covers:** ST-06 · **Labels:** `dev-ops`, `enhancement`, `light-build-task` · **Priority:** Now · **Executor:** Owner + Owner-reviewed PR · **Depends on:** –

**Problem.** The remote branches `factory/issue-115`, `factory/issue-132-hardening`, `factory/issue-132-hardening-pr`, `factory/relevant-skills` and `fix/factory-backticks-and-worktree` remain after their PRs were merged or closed. PR #45 (`factory/issue-8`) was merged with +0/−0 and 0 files, a duplicate of #44. Issue #132 was delivered as seven PRs (#137–#145) within about 10 minutes. Empty and split PRs inflate the merge count and make the history hard to audit.

**Proposed change.**
- Owner: enable "Automatically delete head branches", then delete the five branches after confirming each is merged or abandoned.
- PR: after each build or fix session, `tick.sh` reads the session's PR with `gh pr view --json changedFiles`. If it is 0, it closes the PR with a comment, emits an `empty_pr_closed` event and never merges it. Put the decision in `lib/factory.py` so it can be unit-tested.
- In `builder.md` and the build prompt, state one PR per issue. If work has to be split, the planner proposes sub-issues instead of the builder opening several PRs.

**Acceptance criteria**
- [ ] `gh api repos/adamzki99/booking-system --jq .delete_branch_on_merge` returns `true`.
- [ ] `git ls-remote --heads origin` lists none of the five branches.
- [ ] A pytest case in `dev-ops/scripts/tests/test-factory-lib.py` shows a PR with `changedFiles: 0` is classified as empty and never as merge-ready.
- [ ] After the next merged factory PR, its head branch no longer exists on the remote.

### I-014 - Add a monthly canary that proves the CI gates fail when they should

**Covers:** ST-08 · **Labels:** `dev-ops`, `enhancement`, `standard-build-task` · **Priority:** Later · **Executor:** Owner-reviewed PR · **Depends on:** I-004, I-010

**Problem.** Backend CI shows 0 failures in 60 runs and Semgrep 0 in 82. That can mean the agents test locally before pushing, or that the gates don't bite. Semgrep was green while scanning nothing (I-010), and dependency review could not fail. Nothing proves that a gate still fails after a workflow refactor such as I-004.

**Proposed change.**
- Add `.github/workflows/ci-canary.yml` (monthly `schedule` plus `workflow_dispatch`). For each gate, push a `canary/<gate>-<date>` branch with one deliberate defect and open a draft PR: gofmt violation, failing Go test, failing frontend test, a Semgrep-flagged pattern, a dependency with a known advisory, a fake secret for gitleaks.
- PRs opened with the default `GITHUB_TOKEN` don't trigger `pull_request` workflows, so use the factory App token (I-006) or a dedicated token.
- The run passes only if every canary `ci-gate` concludes `failure`; then it closes the PRs and deletes the branches. Otherwise it fails and opens a labeled `bug` issue, which the planner skips.
- The `canary/` prefix never matches `factory/issue-N`, so the fixer ignores these PRs.

**Acceptance criteria**
- [ ] `ci-canary.yml` has a monthly `schedule` and a `workflow_dispatch` trigger.
- [ ] A manual run opens one draft PR per gate, and each shows `ci-gate` = `failure`.
- [ ] With one defect removed from the canary set, the run fails and opens a `bug` issue.
- [ ] After every run, no `canary/*` branch and no open canary PR remains.
- [ ] `gh pr list --state merged --search "head:canary/"` returns nothing.

### I-015 - Run Go tests with `-race` and prove the Postgres integration tests run in CI

**Covers:** BE-14, ST-08 · **Labels:** `backend`, `dev-ops`, `enhancement`, `light-build-task` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** Backend CI runs `go test ./...` without `-race` (`.github/workflows/backend-ci.yml:45-46`), although the projection runner, rate limiter, worker and lock code are concurrent (BE-14). ST-08 asks whether the Postgres integration tests actually run in CI. In the clone, `internal/eventstore/store_integration_test.go:19` uses `DATABASE_URL` when set and otherwise starts a `postgres:16` testcontainer, with `t.Fatal` on errors and no `t.Skip` anywhere in the backend tests, so they most likely do run. Nothing in CI proves it, and a future skip would go unnoticed.

**Proposed change.**
- Change the backend and sidecar test steps to `go test -race -shuffle=on ./...`.
- Run the tests with `-json`, save the output, and add a step that fails if any test reports `skip`.
- Write the pass count per package to the job summary, so the integration packages (`auth`, `booking`, `eventstore`, `notification`, `projection`, `registry`, `user`) are visibly present.
- The rest of BE-14 (one shared Postgres test helper, per-test schema isolation, replacing the source-grep guard in `surface_test.go`, and the missing regression tests) is backend work tracked outside this epic.

**Acceptance criteria**
- [ ] The Backend CI and Sidecar CI logs show `go test -race -shuffle=on`.
- [ ] A test PR that adds a `t.Skip` to one test fails the backend job.
- [ ] The job summary lists a non-zero pass count for each of the seven integration packages above.
- [ ] A test PR with an unsynchronized map write across goroutines in a test fails with `WARNING: DATA RACE`.

## Epic C - Factory trust boundary and sandboxing

The factory takes input from anyone, runs agents with the owner's token and no sandbox, and lets the model decide what merges. This epic sets what the factory trusts, what agents may do, and what the host lets them reach.

### I-016 - Restrict factory discovery to owner-authored issues and comments and same-repository PRs

**Covers:** FAC-01, FAC-02, SEC-01, SEC-02 · **Labels:** `dev-ops`, `bug`, `standard-build-task` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

> **Sensitive.** It is a working recipe for any GitHub user to get code run on the QA host and changes merged, so land the fix first (I-001 holds the line meanwhile) and file it afterwards as "restrict factory discovery to trusted authors", or as a private security advisory.

**Problem.** Plan discovery takes the oldest unlabeled issue from any author (`tick.sh:233-234`). Outsiders can't add labels, so their issues always qualify once they include an Acceptance Criteria heading and one checkbox. Fix discovery fetches PRs without `isCrossRepository` or `author` (`discover_fix_candidates.py:14`) and qualifies them by branch name alone (`lib/factory.py:208-211`). A fork can force candidacy by conflicting with `main` (`factory.py:227-229`). Builder and fixer read every comment (`tick.sh:584`, `:640`) and CI logs that a PR author controls (`tick.sh:646-647`).

**Proposed change.**
- Add a trusted-login set, `FACTORY_TRUSTED_LOGINS` (the owner now, plus the bot from I-006). Plan and build discovery (`tick.sh:233`, `discover_build_candidates.py`) keep only issues whose author is in it.
- In fix discovery, add `isCrossRepository,author,headRepositoryOwner` to `--json`, and skip cross-repository PRs and untrusted authors in `fix_candidates_from_prs`. Re-check `isCrossRepository == false` in `tick.sh` just before the session starts.
- Have `tick.sh` build the agent context itself: the body plus comments from trusted authors only, written to the 0600 prompt file. Remove the "read comments" steps from the prompts; denying `gh issue view*`, `gh pr view*` and `gh api*` is part of I-020.

**Acceptance criteria**
- [ ] pytest: a PR with `isCrossRepository: true` and head `factory/issue-9999` is not a fix candidate, nor is a same-repo PR by an untrusted author.
- [ ] A test: an untrusted login's unlabeled issue with valid acceptance criteria is not selected for planning; the owner's is.
- [ ] A test: prompt context built from fixture comments by the owner and an outsider contains only the owner's text.
- [ ] With a stubbed `gh`, a PR whose `isCrossRepository` turns `true` before session start is skipped.
- [ ] `grep -n -- "--comments" dev-ops/factory/tick.sh .opencode/agents/*.md` returns no instruction addressed to an agent.

### I-017 - Trust factory markers and deploy-failure issues only when authored by the bot identity

**Covers:** FAC-09, SEC-21 · **Labels:** `dev-ops`, `bug`, `light-build-task` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** I-006 (interim: the owner login)

> **Sensitive.** It explains how any GitHub user can silently stop an approved issue from ever being built, so fix it first and file it afterwards as "filter factory markers by author".

**Problem.** `has_marker` and `has_pr_marker` accept a marker in any comment by anyone: `[.comments[].body | contains($marker_json)] | any` (`tick.sh:458`). An outsider who posts `<!-- factory:build -->`, invisible when rendered, on an approved issue stops it from ever being built. On a `gh` failure both functions print `false` and return 0 (`tick.sh:457-463`, `:470-476`), which fails open. `INFRA_FAILURE=1` is set inside `$(...)` subshells and lost, so `discovery_failed` at `tick.sh:1118` never fires. `recover_issue` comments on and closes the first open "QA deployment failed" issue, whoever opened it (`deploy-environment.sh:156-163`), and `surface_failure` appends to it.

**Proposed change.**
- Count marker comments only when `.author.login == $FACTORY_LOGIN`. Use the owner login until I-006 provides the bot login.
- Return status codes instead of echoing strings: 0 found, 1 not found, 2 unknown. Callers treat unknown as "skip this candidate" and set `INFRA_FAILURE` themselves. Apply the same pattern to `open_factory_pr_for_issue` (`tick.sh:1099`).
- In `surface_failure` and `recover_issue`, only match issues authored by the deploy's own login (`gh issue list --author "$DEPLOY_LOGIN"`).

**Acceptance criteria**
- [ ] A test shows an issue whose only build marker is in a comment by another login is treated as not built.
- [ ] A test shows that when the stubbed `gh` fails, the candidate is skipped and the tick emits `discovery_failed`.
- [ ] `dev-ops/scripts/tests/test-deploy-environment.sh` shows `recover_issue` leaves an open "QA deployment failed" issue authored by another login untouched.
- [ ] Every marker query in `tick.sh` filters on comment author (`grep -n 'comments\[\]' dev-ops/factory/tick.sh`).

### I-018 - Remove the planner's label-edit power and verify who applied `owner approved`

**Covers:** FAC-02, SEC-01, ST-02, AGT-11 · **Labels:** `dev-ops`, `bug`, `light-build-task` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

> **Sensitive.** It shows how a prompt-injected planner can approve work for the builder, so fix it first and file it afterwards with neutral wording ("planner applies labels through the orchestrator").

**Problem.** The planner is allowed `"gh issue edit*": allow` (`.opencode/agents/planner.md:18`), which covers `--add-label "owner approved"` and `--body` on any issue. "Never add the owner approved label" (`tick.sh:537-539`) and "Only comment on and label the issue you were given" (`planner.md:55`) are prose only. Build discovery accepts any open issue carrying the label (`discover_build_candidates.py`), and the timeline can't tell owner from agent because both act as `adamzki99` (issue #120, from GitHub metadata).

**Proposed change.**
- Remove `gh issue edit*` from `planner.md`. The planner writes its chosen labels to a file in the session directory, such as `plan-labels.txt`.
- `tick.sh` applies only allowlisted labels from that file (the four tier labels plus `backend`, `frontend`, `dev-ops`) and refuses `owner approved` and anything else.
- Build discovery reads the issue timeline and requires that the latest `labeled` event for `owner approved` has `actor.login` equal to the owner and never the factory login (`gh api repos/:o/:r/issues/N/timeline`). The check becomes meaningful once I-006 separates the identities; until then it still rejects approvals by any third login.

**Acceptance criteria**
- [ ] `grep -n "gh issue edit" .opencode/agents/planner.md` returns nothing.
- [ ] A pytest case shows the label allowlist drops `owner approved` and unknown labels and keeps `light-build-task` and `backend`.
- [ ] A pytest case with timeline fixtures shows an issue whose `owner approved` event actor is the factory login, or any non-owner login, is not a build candidate, and one labeled by the owner is.
- [ ] After a real planning session, the session log has no `gh issue edit` call and the issue's labels match `plan-labels.txt`.

### I-019 - Move the merge decision from the agent into the orchestrator

**Covers:** FAC-03, FAC-07, AGT-04, AGT-10 · **Labels:** `dev-ops`, `enhancement`, `heavy-build-task` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** I-004, I-005

> **Sensitive.** It states that merges to `main`, which deploy to QA, are decided only by a model that can be steered, so land it together with I-005 and file it afterwards with neutral wording.

**Problem.** Builder and fixer set `"gh pr merge*": ask` (`builder.md:26`, `fixer.md:28`), but `opencode run --auto` (`tick.sh:707`) approves anything not explicitly denied. `tick.sh` never checks CI or merge state afterwards; exit 0 is logged as `session_ok` regardless (`tick.sh:764-773`). One session handles worktree, PR, CI polling, fix cycles, merge and markers under one timeout (`tick.sh:582-618`, AGT-04). When quota detection misfires, the task reruns on `*-free` backups (`models.yaml:21-38`) with the same merge authority (FAC-07, AGT-10).

**Proposed change.**
- Deny `gh pr merge*` and `gh api*` in `builder.md` and `fixer.md`; remove the merge, CI-wait and marker steps from the prompts and `builder.md`.
- After a session, `tick.sh` checks the `factory/issue-N` PR is same-repository and the approval valid (I-018), then runs `gh pr merge "$pr" --squash --auto --match-head-commit "$sha"`, so GitHub merges only once `ci-gate` passes.
- `tick.sh` posts the build marker and emits `session_outcome` (PR, head SHA, model, auto-merge on or off).
- Never auto-merge backup or free-model work; label it `needs-owner-review` (a new label) for the owner.
- The quota classifier, worktree setup and reviewer models (rest of FAC-07, AGT-04, AGT-10) are tracked outside this epic.

**Acceptance criteria**
- [ ] `builder.md` and `fixer.md` contain `"gh pr merge*": deny` and `"gh api*": deny`, and the prompts in `tick.sh` contain no `gh pr merge`.
- [ ] An orchestration test with a fake `gh` shows `gh pr merge --auto --match-head-commit <sha>` after a primary-model session, and only the `needs-owner-review` label after a fallback-model session.
- [ ] For the next 10 factory PRs, each PR's `mergedAt` is later than its `ci-gate` check's `completedAt`.
- [ ] A PR whose `ci-gate` fails is still open after the tick ends.

### I-020 - Default-deny OpenCode permission profiles for every agent and settle the config schema

**Covers:** FAC-04, SEC-04, AGT-11, AGT-16 · **Labels:** `dev-ops`, `enhancement`, `standard-build-task` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** –

> **Sensitive.** It lists working bypasses for each deny rule the agents run under, so fix it first and file it afterwards as "tighten agent permission profiles".

**Problem.** FAC-04 says the `permissions` array in `opencode.jsonc:26-42` is not OpenCode syntax, so its global denies are off; SEC-04 says it is the V2 form and the agent files' `permission:` maps (`builder.md:5-27`, `fixer.md:5-29`, `planner.md`, `reviewer.md`) are deprecated V1. Neither was tested on the host. Both agree builder and fixer have no `"*"` default, so `curl`, `docker`, `gh api` and `cat .env` run, `--auto` approves `ask`, and `git push --force*` misses `git push -f`. Keys like `compaction.*` and `experimental.*` are unverified too (AGT-16).

**Proposed change.**
- First settle the schema on the host: record `opencode --version`, save the resolved config in `dev-ops/factory/README.md`, and try `rm -rf /tmp/x` in a throwaway session.
- Rewrite `opencode.jsonc` and the four agent files in the confirmed schema: `"*"` deny plus per-role allowlists (FAC-04, SEC-04). Deny `webfetch`, `gh api*`, `gh issue view*` and `gh pr view*` (context comes from I-016), `gh pr merge*` (I-019), `*.env` reads and external directories. The planner's `gh issue edit*` is I-018.
- Add a CI step that validates `opencode.jsonc` against its `$schema` (for example with `ajv`), wired into `ci-gate`.
- Install `gopls` and `typescript-language-server` on the host and list them in the factory README.

**Acceptance criteria**
- [ ] `dev-ops/factory/README.md` records the OpenCode version, the resolved permission config and which key is valid.
- [ ] On the host, builder and fixer sessions deny `rm -fr /tmp/x`, `git push -f`, `git push origin HEAD:main`, `curl https://example.com`, `gh api user` and `cat projects/sauna/.env` (log attached).
- [ ] A builder session can still run `go test ./...` and `git push origin factory/issue-N`.
- [ ] The CI schema check fails on a test PR that adds an unknown key to `opencode.jsonc`.
- [ ] As the factory user, `command -v gopls typescript-language-server` prints both paths.

### I-021 - Run agent sessions in a disposable sandbox by default

**Covers:** FAC-16, SEC-03, SEC-26 · **Labels:** `dev-ops`, `enhancement`, `heavy-build-task` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-022

> **Sensitive.** It lists which credentials and keys an agent session can read on the QA host today, so ship the sandbox first and file it afterwards with neutral wording.

**Problem.** `FACTORY_CONTAINER_MODE` defaults to `0` (`tick.sh:31`), and if `bwrap` is missing the script silently runs on the host (`tick.sh:696-698`). Even in bwrap mode, `--bind "$HOME" "$HOME"` (`tick.sh:694`) exposes `~/.config/gh/hosts.yml`, `~/.ssh` and the OpenCode auth, the network is shared, and a read-only `/` doesn't block `/var/run/docker.sock`. Through Docker a session can read the Caddy volume with the TLS and ACME account keys (SEC-26).

**Proposed change.**
- Run each session in a disposable container or rootless Podman mounting only the worktree and a read-only OpenCode config: no host `$HOME`, no Docker socket. Pass the short-lived token (I-006) and model credentials as environment variables.
- Allow egress only to GitHub, the Go module proxy, the npm registry and the OpenCode endpoint.
- Make the sandbox the default. If it isn't available, end the tick with an event instead of falling back to the host.
- SEC-26: treat the TLS and ACME keys as exposed and re-issue the certificate once this and I-022 are live. Backing up `caddy-data` goes with the database backups (OPS-03), outside this epic.

**Acceptance criteria**
- [ ] `FACTORY_CONTAINER_MODE` defaults to `1`, and a test with the sandbox runtime missing shows `tick.sh` exits non-zero with a `sandbox_unavailable` event and starts no session.
- [ ] Inside a session, `ls ~/.ssh ~/.config/gh`, `test -S /var/run/docker.sock` and `curl https://example.com` all fail (log attached).
- [ ] Inside a session, `go test ./...`, `npm ci` and `git push origin factory/issue-N` succeed.
- [ ] The GitHub token seen inside the session is an App installation token, which expires within one hour.
- [ ] `openssl s_client` against QA shows a certificate issued after the sandbox rollout date.

### I-022 - Use separate Unix users for the factory and the deploy, and remove the factory's Docker access

**Covers:** OPS-16, SEC-03, SEC-26 · **Labels:** `dev-ops`, `enhancement`, `standard-build-task` · **Priority:** Next · **Executor:** Owner · **Depends on:** –

> **Sensitive.** It names the root-equivalent account on the QA host and what it can reach, so make the change first and file it afterwards with neutral wording.

**Problem.** The crontab quoted in #85 (from GitHub metadata) runs `tick.sh` under a user's home directory, and the deploy runs as that same user (`dev-ops/README.md:112,123`) and calls `docker` without sudo (`install-deploy-timer.sh:114`), which is root-equivalent. That the two share one user is inferred and should be confirmed (SEC-03). If so, an agent can `docker exec` into Postgres, read `projects/sauna/.env`, read the Caddy volume with the TLS and ACME keys (SEC-26), and push with the owner's token.

**Proposed change.**
- Create a `booking-deploy` user as the only member of the `docker` group, or give it rootless Docker. Move the deploy timer, the QA checkout under `/opt/booking-system-qa` and its `.env` (mode 0600) to that user.
- Create a `factory` user with no `docker` or `sudo` membership, no deploy credentials and no SSH keys to other hosts. Move the crontab and the factory checkout to it, and give it only the factory credential from I-006.
- Give the deploy its own narrow GitHub credential, separate from the factory's.
- Longer term, move the factory off the QA host (SEC-03).

**Acceptance criteria**
- [ ] `id factory` lists neither `docker` nor `sudo`, and `sudo -u factory docker ps` fails with permission denied.
- [ ] `sudo -u factory cat /opt/booking-system-qa/projects/sauna/.env` fails.
- [ ] `getent group docker` lists only `booking-deploy`.
- [ ] `crontab -l -u factory` contains the tick entry, and the previous user's crontab does not.
- [ ] `systemctl --user list-timers` as `booking-deploy` shows the deploy timer, and its next run deploys QA successfully.

### I-023 - Pin vendored skills to commit SHAs and verify their integrity

**Covers:** SEC-05, AGT-15, FAC-21 · **Labels:** `dev-ops`, `enhancement`, `light-build-task` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** None of the 21 remote skills in `dev-ops/skills.yaml:16-109` has a `ref`, and all 22 `.opencode/skills/*/.source` files record `ref: default`. `dev-ops/scripts/request-skills.sh:52-59` shallow-clones the default branch with no SHA and no hash check. Vendored scripts may run under `--auto`; `caveman-compress/scripts/compress.py:585-588` passes on the full environment and sends file contents to a model provider. `SKILL.md` text instructs a privileged agent, so an upstream change acts as prompt injection. `ultracave` and `megacave` are `disable-model-invocation: true`, yet `AGENTS.md:63-66` and `builder.md:209-210` tell agents to use them (FAC-21).

**Proposed change.**
- Pin every `ref:` in `skills.yaml` to a full commit SHA, and record the SHA plus a tree hash in each `.source`.
- Make `request-skills.sh` verify the hash and print the upstream diff on update. Review skill updates like dependency bumps; CODEOWNERS covers `/.opencode/` and `/dev-ops/` (I-007).
- Add a CI check that recomputes each skill directory's hash and fails on a mismatch.
- Remove `caveman-compress`, `skill-creator`, `pdf`, `ultracave` and `megacave`, and drop their references from `AGENTS.md` and `builder.md`. Removing the remaining caveman instructions and trimming the build prompt's skill list (rest of FAC-21) are tracked outside this epic.

**Acceptance criteria**
- [ ] Every entry in `dev-ops/skills.yaml` has a `ref:` that is a 40-character hex SHA.
- [ ] No `.opencode/skills/*/.source` file contains `ref: default`, and each records a tree hash.
- [ ] The CI check fails on a test PR that changes one line of a vendored `SKILL.md` without updating its hash.
- [ ] `ls .opencode/skills` lists none of the five removed skills, and `grep -rn "ultracave\|megacave\|caveman-compress" AGENTS.md .opencode/agents` returns nothing.

### I-024 - Harden the dev-server SSH wrapper

**Covers:** SEC-14, OPS-15, OPS-16 · **Labels:** `dev-ops`, `bug`, `standard-build-task` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** –

> **Sensitive.** It lists commands that read QA-host secrets without the approval prompt, and how to skip the wrapper entirely, so fix it first and file it afterwards with neutral wording.

**Problem.** `dev-ops/scripts/dev-server-agent.sh:226-228` classifies `uname|df|free|ps|ls|cat|head|tail|grep` as read-only with no path check, so `cat /opt/booking-system-qa/projects/sauna/.env`, `cat ~/.config/gh/hosts.yml` and `ps eww` run without the y/N prompt and their output reaches the agent's model provider. `:262` treats `docker inspect` and `docker logs` as read-only, which exposes env secrets and log-mode login codes. `:286` treats `git diff`/`git log` as read-only although `--output=<file>` writes. `:160-165` opens a `ControlMaster` socket with `ControlPersist=10m`, which any local process can reuse with `ssh -S <path>` to skip the wrapper and its audit log.

**Proposed change.**
- In `classify_command`, refuse arguments matching `\.env|\.ssh|\.config/gh|/proc/.*/environ|\.pem|\.key|secrets`, and classify `docker inspect`, `docker logs`, `ps e*` and `git … --output*` as impactful. Prefer an allowlist of exact commands over an allowlist of binaries.
- Set `ControlPersist=no` (or 30 s) with a per-invocation `ControlPath` in a 0700 directory removed on exit.
- On the server, use a dedicated remote user whose `authorized_keys` entry forces `command="/usr/local/bin/qa-ops-shell",no-port-forwarding,no-pty`, so the server enforces the allowlist.

**Acceptance criteria**
- [ ] `dev-ops/scripts/tests/test-dev-server-agent.sh` shows `cat …/.env`, `cat ~/.config/gh/hosts.yml`, `ps eww`, `docker inspect booking-qa-backend-1` and `git diff --output=/tmp/x` are not classified read-only.
- [ ] The same test still classifies `uname -a` and `df -h` as read-only.
- [ ] `grep -n ControlPersist dev-ops/scripts/dev-server-agent.sh` shows no value above 30 s, and a test shows no control socket remains after the wrapper exits.
- [ ] With the forced-command key, a command outside the `qa-ops-shell` allowlist is refused by the server.

### I-025 - Give each container only the environment variables it needs

**Covers:** SEC-13, OPS-15 · **Labels:** `dev-ops`, `bug`, `light-build-task` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** –

> **Sensitive.** It maps which secrets are readable in which QA container, so fix it first and file it afterwards with neutral wording.

**Problem.** Both `backend` and `postgres` use `env_file: - .env` (`projects/sauna/docker-compose.yml:62-63`, `:99-100`), so every variable reaches both containers. The template puts SMTP credentials (`.env.example:25-26`), `CLOUDFLARE_TUNNEL_TOKEN` (`:40`) and the operator's `DEV_SERVER_KEY` and `DEV_SERVER_PASSWORD` (`:65-77`) in that file, all visible through `docker inspect`, `/proc/1/environ` or any RCE in either service. Defaults are weak: `POSTGRES_PASSWORD=change-me` (`.env.example:9`), compose falls back to `booking`/`booking` (`docker-compose.yml:65,103`), and `setup.sh:49-52` copies the example as-is with only a warning.

**Proposed change.**
- Replace `env_file: .env` with explicit `environment:` keys per service, or Compose `secrets:`. Postgres gets only `POSTGRES_*`; cloudflared gets only the tunnel token.
- Remove the `DEV_SERVER_*` block from `projects/sauna/.env.example` (it already lives in `dev-ops/.env.example`), and the owner removes it from the QA host's `.env`.
- Remove the `booking` password fallbacks so a missing password fails, and make `setup.sh` generate one with `openssl rand -hex 24`.
- Rotate the SMTP password, the tunnel token and the operator SSH credentials after the change.

**Acceptance criteria**
- [ ] `docker compose -f projects/sauna/docker-compose.yml config` shows only `POSTGRES_*` variables on `postgres`, and no `CLOUDFLARE_TUNNEL_TOKEN` or `DEV_SERVER_*` on `backend`.
- [ ] `grep -n DEV_SERVER projects/sauna/.env.example` returns nothing.
- [ ] `grep -nE 'change-me|POSTGRES_PASSWORD:-|booking:booking@' projects/sauna/.env.example projects/sauna/docker-compose.yml` returns nothing.
- [ ] `setup.sh` on a fresh checkout writes a `.env` whose `POSTGRES_PASSWORD` is 48 hex characters.
- [ ] On QA, `docker inspect booking-qa-postgres-1 --format '{{.Config.Env}}'` contains no `SMTP_PASSWORD` or `DEV_SERVER_` entry.

### I-026 - Redact secrets and personal data from session output and telemetry

**Covers:** OBS-11, SEC-12 · **Labels:** `dev-ops`, `backend`, `bug`, `standard-build-task` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

> **Sensitive.** It points to where credentials and residents' data end up in SigNoz, so fix it first and file it afterwards with neutral wording.

**Problem.** `FACTORY_LOG_SESSION_OUTPUT` defaults to `tail` (`tick.sh:37`), so `session_failed` events carry the last 16 KiB of the OpenCode transcript (`tick.sh:814`, `:857`, `:900`) and ship it to SigNoz as a log attribute. That can include `.env` values or residents' data the agent read. The backend wraps every request in `otelhttp.NewHandler` (`internal/server/server.go:90`), and server spans for the feed route `GET /calendar/` (`server.go:76`, e.g. `/calendar/<token>.ics`) likely record the feed token, which is the credential, in the URL path (SEC-12; to be confirmed in SigNoz).

**Proposed change.**
- Ship metadata only: drop `output_tail` from shipped events by default and keep the tail only in the local 0600 session log.
- Add a `transform` or redaction processor to both collectors (`dev-ops/factory/otel-collector.yaml`, `dev-ops/signoz/otel-collector-config.yaml`). It drops `output_tail`, rewrites URL path attributes matching `^/calendar/` to `/calendar/{token}`, and masks `user.email` and email-shaped strings.
- In the backend, replace the span name and URL attributes for `/calendar/` requests with the route template before export.
- SigNoz's network exposure (rest of SEC-12) is I-003. Retention limits are tracked outside this epic.

**Acceptance criteria**
- [ ] A Go test with an in-memory span exporter requests `/calendar/abc123.ics` and asserts that no exported span name or attribute contains `abc123`.
- [ ] A `tick.sh` test of a failing session shows the shipped JSONL event has no `output_tail` field, while the local session log still has the tail.
- [ ] After deploy, a SigNoz search over 24 h for a known test feed token returns no spans or logs.
- [ ] Both collectors start with the new processors, and their startup logs show no configuration error.

## Epic D - Factory orchestration robustness

The hourly orchestrator `dev-ops/factory/tick.sh` has failure modes that silently stall work, rerun sessions on weaker models or lose state, and its own code is never tested in CI. These issues fix the defects, add CI and feedback loops for the factory, and prepare a later move to a tested Python orchestrator.

### I-027 - Fix session-ID capture and record the agent on every session event

**Covers:** FAC-13, OBS-05 · **Labels:** `dev-ops`, `light-build-task`, `bug` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** `tick.sh:763` passes a multi-line program to `python3 -c 'import sys,json\nfor line in sys.stdin:\n try: ...'` inside single quotes, so Python receives a literal backslash-n and fails with `SyntaxError`. The error is hidden by `2>/dev/null`, so `session_id` is empty on every event, although commit `e27f44a` advertises "session id capture". `session_start` also lacks `agent` (`tick.sh:753-755`). Without these two fields no factory event can be joined to OpenCode's own session store (transcript, tokens, tool calls).

**Proposed change.**
- Move the parsing into `dev-ops/factory/lib/factory.py` as `factory.py session-id <logfile>` (first `sessionID` in the `--format json` stream), and call it from `start_session`.
- Add `agent="$agent"` to every `session_*` `emit_event` call, for both the `fix` and the issue branches.
- Add a unit test with a recorded JSON stream.
- The other FAC-13 parts are tracked elsewhere: the `session_outcome` event with PR, merge, model and token/cost fields (OBS-01), the SigNoz alerts (OBS-04) and the `output_tail` default (OBS-11).

**Acceptance criteria**
- [ ] `pytest dev-ops/scripts/tests/test-factory-lib.py` includes a test that feeds a recorded `--format json` stream and asserts the first `sessionID` is returned.
- [ ] A test with a stream that has no `sessionID` returns an empty string and exit code 0.
- [ ] `grep -n "python3 -c 'import sys,json" dev-ops/factory/tick.sh` returns nothing.
- [ ] `dev-ops/factory/validate.sh` passes.
- [ ] After one tick on the host, every `session_start`, `session_ok` and `session_failed` line in the JSONL log has a non-empty `session_id` and `agent`.

### I-028 - Limit quota detection to provider errors and stop fallback models from merging

**Covers:** FAC-07 · **Labels:** `dev-ops`, `standard-build-task`, `bug` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** I-019

**Problem.** `start_session` captures the whole session output (`tick.sh:759`) and on any non-zero exit, including timeout 124, runs `is_usage_filled "$out"` (`tick.sh:777`). That is a substring match for `"rate limit"`, `"limit exceeded"`, `"quota"`+`"exceed"` (`factory.py:127-139`, duplicated in `tick.sh:514-518`) over a transcript that includes tool output, and the product itself contains "exceeded a rate limit" (`product/backend/internal/auth/model.go:21`). A match reruns the whole task on `backup_model` and then `FACTORY_FREE_MODEL` (`tick.sh:785-865`); every backup is a `*-free` model (`models.yaml:21-38`) with the same merge authority. The review could not verify whether `opencode run` exits non-zero on a real quota error.

**Proposed change.**
- Classify quota errors only from structured error events in the JSON stream (provider error name, HTTP 429/402) or from stderr, never from tool output. Keep one implementation in `factory.py` and delete the bash copy.
- Default to `--on-usage-filled=skip` for `build` and `fix`; allow free fallbacks only for `plan`.
- Label any PR produced by a fallback model `factory:fallback-model`. The merge step that I-019 moves into the orchestrator must never merge such a PR.
- On the host, record which exit code `opencode run` returns on a provider quota error, and document it in `dev-ops/factory/README.md`.

**Acceptance criteria**
- [ ] A pytest case where a tool result contains "exceeded a rate limit" and the exit code is 1 is classified as not usage-filled.
- [ ] A pytest case with a recorded provider error event (HTTP 429) is classified as usage-filled.
- [ ] `tick.sh` no longer contains its own `is_usage_filled` substring list.
- [ ] With default settings, a simulated build quota error emits a skip event and no `backup_ok` or `free_retry` event.
- [ ] A PR opened by a fallback model carries `factory:fallback-model` and stays unmerged by the factory.

### I-029 - Detect and escalate stalled factory PRs

**Covers:** FAC-06 · **Labels:** `dev-ops`, `standard-build-task`, `bug` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** Builds always open draft PRs (`tick.sh:600-601`, `builder.md:117`), fix discovery skips drafts (`factory.py:206-207`), and build discovery skips any issue with an open factory PR (`tick.sh:1098-1108`). A build session that times out after opening its draft therefore stalls the issue forever. A green, non-draft PR left unmerged has no fix reason, and neither has `mergeable == "UNKNOWN"`. Fix markers are keyed on `sha:reasons` (`factory.py:234`), so one failed attempt is never retried, while a session that dies before posting its marker is retried every hour with no limit. Nothing comments, labels or notifies, and the owner sees "nothing to do" (`tick.sh:1124-1126`).

**Proposed change.**
- In `fix_candidates_from_prs`, add `stale-draft` (draft older than `FACTORY_SESSION_TIMEOUT`) and `unmerged-green` (all checks green, `MERGEABLE`) reasons; treat `UNKNOWN` as "retry next tick" and count it.
- Have tick.sh, not the agent, post a `factory:attempt` marker before each session, so failed sessions count.
- Add an attempt budget (default 3). When it is used up, apply a `factory-blocked` label, post a summary comment, and skip the PR or issue until a human removes the label.
- Create the `factory-blocked` label and document it in `dev-ops/factory/README.md`.

**Acceptance criteria**
- [ ] Pytest fixtures: a draft PR older than the session timeout yields `stale-draft`; a green non-draft `MERGEABLE` PR yields `unmerged-green`.
- [ ] A PR fixture with 3 `factory:attempt` markers is not a candidate and is reported as blocked.
- [ ] A fixture where the session fails before the agent posts anything still shows one new `factory:attempt` marker.
- [ ] `gh label list` includes `factory-blocked`, and a blocked PR has the label plus a summary comment.
- [ ] Removing the label makes the PR a candidate again (fixture test).

### I-030 - Remove head-of-line blocking in planning and revisit throughput and prioritisation

**Covers:** FAC-08, FAC-19 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Later · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** Plan discovery returns a single issue, `sort_by(.createdAt) | .[0].number` (`tick.sh:234`). If that issue has a plan marker, lacks acceptance criteria, or the checker errors (`tick.sh:952-973`), no planning happens and the next tick picks the same issue, so one old issue blocks all planning. Throughput is also low: one fix, one plan and one build per hourly tick (`tick.sh:1000-1163`), with a worst case of about 3 h per session and about 9 h per tick, during which every tick is `lock_skipped`. Issues #112-#120 were planned about one per hour over 16 h, and builds are ordered only by `createdAt` (`factory.py:240-249`), so #85 was built before #125.

**Proposed change.**
- Return all unlabeled candidates and loop until one passes the gates. Label gate failures `needs-acceptance-criteria` so they leave the pool. Keep the trusted-author filter from FAC-02.
- Plan up to `FACTORY_PLAN_BATCH` issues per tick (default 3).
- Cap tick time: skip backup and free fallbacks when less than 20 minutes remain before the next tick.
- Add a `priority/high` label that sorts before age in build discovery.
- Evaluate 2 concurrent builds in different areas in separate worktrees once I-032 and I-034 are done, and record the decision in the README.

**Acceptance criteria**
- [ ] A test where the oldest unlabeled issue has no AC section and the second has one plans the second issue in the same tick.
- [ ] The failing issue gets `needs-acceptance-criteria` and is not selected on the next tick.
- [ ] With `FACTORY_PLAN_BATCH=3` and 4 eligible issues, a test sees 3 plan sessions start.
- [ ] A test shows a newer `priority/high` approved issue selected before an older one.
- [ ] A fake-clock test shows no fallback session starts with under 20 minutes left, and an event is emitted.

### I-031 - Make idempotency checks fail closed and propagate infrastructure failures out of subshells

**Covers:** FAC-09 · **Labels:** `dev-ops`, `light-build-task`, `bug` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-017

**Problem.** When `gh` fails, `has_marker` and `has_pr_marker` print `false` and return 0 (`tick.sh:457-463`, `470-476`), so an API hiccup reads as "not done" and planning or fixing runs again. These functions run inside command substitutions (`tick.sh:952`, `1026`, `1031`, `1093`, and `open_pr="$(open_factory_pr_for_issue ...)"` at `1099`), so their `INFRA_FAILURE=1` assignments are lost and the `discovery_failed` logic at `tick.sh:1118` never fires. A marker also counts whoever posted it (`[.comments[].body | contains($marker_json)] | any`, `tick.sh:458`), so any GitHub user can post a hidden `<!-- factory:build -->` comment to stop an approved issue from ever being built.

**Proposed change.**
- Return status codes (0 found, 1 not found, 2 unknown) instead of echoing strings; callers skip the item on 2 and set `INFRA_FAILURE` in the parent shell.
- Replace `var="$(func)"` calls with functions that set a global, as `oldest_unlabeled_issue` already does.
- Count only markers written by the factory login: `select(.author.login == $FACTORY_LOGIN)`. The separate factory identity comes from I-017.
- Add a bash test harness with a stub `gh` on `PATH`.

**Acceptance criteria**
- [ ] With a stub `gh` that exits 1, `has_marker` returns 2 and the issue is skipped, not planned.
- [ ] A test that makes `open_factory_pr_for_issue` fail sees `discovery_failed` emitted.
- [ ] A marker comment from a login other than `$FACTORY_LOGIN` is not counted; one from the factory login is.
- [ ] `dev-ops/factory/validate.sh` and the new tests pass.

### I-032 - Fix lock and process-lifecycle hazards in `tick.sh`

**Covers:** FAC-14 · **Labels:** `dev-ops`, `light-build-task`, `bug` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** The lock FD from `exec 9>".../factory-tick.lock"` (`tick.sh:219`) is inherited by `opencode` and anything it starts, so a leftover daemon keeps the `flock` held and every later tick exits 0 with `lock_skipped`. `nightly-cleanup.sh` does not take the lock and runs `git worktree remove --force` on a clean worktree (`nightly-cleanup.sh:118-135`), which can delete a starting session's directory. The SIGTERM trap (`tick.sh:215-216`) cannot run while bash waits on `$(run_opencode ...)`, so stopping a tick waits up to 1 h (about 3 h with fallbacks). The fix loop reads a here-string (`tick.sh:1023-1061`) that `run_opencode` inherits as stdin; the review believes, but did not confirm, that `opencode run` appends piped stdin to the prompt. `nightly-cleanup.sh:70` reads `FACTORY_LOG_DIR` while tick.sh uses `FACTORY_SESSION_LOG_DIR`.

**Proposed change.**
- In `run_opencode`: `timeout ... "${sandbox[@]}" opencode "${args[@]}" </dev/null 9>&-`.
- Take the same lock at the top of `nightly-cleanup.sh` (`flock -w`), and skip the worktree removal if it can't.
- Start the session with `setsid`, and have `on_signal` kill the process group.
- Use one variable name for the log directory in both scripts.

**Acceptance criteria**
- [ ] A test with a stub `opencode` that starts `sleep 600 &` shows the next tick acquiring the lock (no `lock_skipped`).
- [ ] A stub `opencode` that echoes its stdin produces no candidate lines in the session log.
- [ ] Sending SIGTERM to a tick during a stub session that sleeps 600 s ends the stub within 10 s.
- [ ] Running `nightly-cleanup.sh` while the lock is held leaves `$FACTORY_WORKTREE` in place.
- [ ] `grep -rn "FACTORY_LOG_DIR" dev-ops/factory` returns nothing.

### I-033 - Run the factory from a single code version

**Covers:** FAC-05 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** `tick.sh`, `discover_*.py`, `lib/factory.py` and `models.yaml` run from the primary checkout (`tick.sh:12-16`, `1007`, `1071`), which nothing ever pulls. After `cd "$FACTORY_WORKTREE"` (`tick.sh:936`), OpenCode loads `opencode.jsonc`, `.opencode/agents/*.md`, `AGENTS.md`, the skills and `check-acceptance-criteria.sh` (`tick.sh:963`) from the latest `origin/main`. A stale orchestrator and up-to-date agent definitions can disagree on markers or discovery rules. The factory also changes its own guardrails at merge speed: #138-#145 changed `tick.sh`, `factory.py` and the sandbox code, each merged 0-2 minutes after opening (#141 in 2 s).

**Proposed change.**
- Run the orchestrator and the agent configuration from one deliberately updated ref: a deploy checkout at a `factory-config` tag that the owner moves by hand. Don't mix the primary checkout and the worktree.
- Before starting any session, refuse to run if `.opencode/agents`, `opencode.jsonc` or `AGENTS.md` differ between `factory-config` and `origin/main`, and emit `guardrail_drift`.
- Add the orchestrator commit SHA (`factory_sha`) to every event.
- CODEOWNERS and required code-owner review for these paths belong with the ruleset work for FAC-03 and ST-07 and are not repeated here.

**Acceptance criteria**
- [ ] A test with a temporary git repo, where `origin/main` changes `.opencode/agents/builder.md` and the tag has not moved, sees `guardrail_drift` and no session start.
- [ ] After the tag is moved to the new commit, the same test starts a session.
- [ ] Every JSONL event from a tick carries `factory_sha`, equal to the commit the agent files were loaded from.
- [ ] `dev-ops/factory/README.md` documents how the owner updates the tag.

### I-034 - Fix factory worktree handling

**Covers:** FAC-20 · **Labels:** `dev-ops`, `light-build-task`, `bug` · **Priority:** Later · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** If `git worktree add` fails, tick.sh logs "continuing in $REPO_ROOT" (`tick.sh:914-917`) and runs sessions in the primary checkout, breaking the README rule "Never touch the primary checkout" (`README.md:37-38`). A dirty shared worktree makes every later tick skip the reset (`tick.sh:928-935`), so agents run on a stale tree with stale agent definitions forever. `git clean -fdx` every tick (`tick.sh:931`) deletes `node_modules` and build caches. Agents create per-issue worktrees wherever they like (`builder.md:88`), and `nightly-cleanup.sh:118-120` only recognises `$FACTORY_WORKTREE` and `/tmp/opencode`, so others pile up.

**Proposed change.**
- Make a worktree failure fatal (`|| die`), with an event.
- If the shared worktree has been dirty for more than 2 ticks, save it to a `factory/rescue-<ts>` branch, emit an event and reset.
- Have tick.sh create per-issue worktrees at `$FACTORY_WORKTREES/issue-N`, pass the path into the prompt, and update `builder.md:88`.
- Use `git clean -fdx -e node_modules` or keep caches outside the tree; teach `nightly-cleanup.sh` to sweep `$FACTORY_WORKTREES`.

**Acceptance criteria**
- [ ] `grep -n "continuing in" dev-ops/factory/tick.sh` returns nothing, and a test where `git worktree add` fails sees a non-zero exit and no session.
- [ ] A test with a worktree dirty for 3 ticks finds a `factory/rescue-*` branch and a clean worktree afterwards.
- [ ] `product/frontend/node_modules` in the worktree survives a tick.
- [ ] `nightly-cleanup.sh` removes a per-issue worktree under `$FACTORY_WORKTREES` whose PR is merged.

### I-035 - Add a CI workflow for the factory and deploy scripts

**Covers:** FAC-18, OPS-08, AGT-16, OBS-13 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-004

**Problem.** `dev-ops/factory/validate.sh` (bash -n, shellcheck, py_compile, `validate-models`, pytest) and `dev-ops/scripts/tests/test-*.sh` are run by no workflow, and CI is path-filtered to `product/backend/**`, `product/frontend/**` and the sidecar (`backend-ci.yml:4-11`, `frontend-ci.yml:4-13`, `sidecar-ci.yml:4-13`). PRs #153-#155, which fixed deploy-script bugs #85, #86 and #89, ran only Security and Semgrep. Nothing runs shellcheck, `docker compose config` or `caddy validate`, only the backend image is built, `opencode.jsonc` is never validated against its `$schema`, and the collector config (`start_at: end` without `file_storage`, `otel-collector.yaml:15`; a `%f` layout against millisecond timestamps, `:18-20`, unverified) is never tested.

**Proposed change.**
- Add `.github/workflows/factory-ci.yml` on `pull_request` for `dev-ops/**`, `.opencode/**`, `opencode.jsonc`, `AGENTS.md`, `projects/sauna/**` and the Dockerfiles. Run `validate.sh`, every `dev-ops/scripts/tests/test-*.sh`, and shellcheck (missing shellcheck fails).
- Validate `opencode.jsonc` and agent front matter against `https://opencode.ai/config.json` (for example with `ajv`).
- Run `docker compose -f projects/sauna/docker-compose.yml config -q`, `caddy validate`, and build the frontend, sidecar and `dev-ops/testing` images.
- Run `otelcol validate` and feed one `tick.sh` event line through the collector; add `file_storage` and switch to a `gotime` layout so it passes.
- Report into the required gate from I-004. The full-stack `compose up` smoke and Playwright run are OPS-06 work.

**Acceptance criteria**
- [ ] A PR that changes only `dev-ops/factory/tick.sh` shows a `factory-ci` check run.
- [ ] A PR adding an unknown key to `opencode.jsonc` or a shellcheck error in `dev-ops/scripts/` fails the workflow.
- [ ] The job log lists every `test-*.sh` file it ran.
- [ ] The collector fixture yields a record whose timestamp equals the fixture's.
- [ ] Compose config, Caddy validation and the three image builds pass on `main`.

### I-036 - Decompose `tick.sh` into a tested orchestrator and delete dead code

**Covers:** FAC-17 · **Labels:** `dev-ops`, `heavy-build-task`, `enhancement` · **Priority:** Later · **Executor:** Owner-reviewed PR · **Depends on:** I-035

**Problem.** `tick.sh` is 1,170 lines. About 210 of them, `approved_build_candidates` and `fix_pr_candidates` (`tick.sh:243-452`), are dead copies "retained for reference" of logic now in `discover_*.py` and `factory.py`. `start_session` (`tick.sh:735-909`) repeats the fix-or-issue `emit_event` branch 10 times and the run/classify/log sequence three times. `normalize_model` and `is_usage_filled` exist in both bash and Python (`tick.sh:503-521,680-689` vs `factory.py:13-19,127-139`), and `emit_event` starts a Python interpreter per event. The 21 tests cover only `factory.py`, while FAC-06 to FAC-09 are all orchestration bugs.

**Proposed change.**
- Delete the dead heredocs now, in a small first PR.
- Move orchestration into `dev-ops/factory/factory_tick.py` with injectable `GitHub` and `OpenCode` adapters: `discover()`, `gate()`, `run_session()`, `record()`, and one `Session` dataclass with `ref_kind`.
- Keep a bash wrapper of about 30 lines for `flock`, `PATH` and `exec python3 -m factory_tick`.
- Port the fixes and tests from I-028, I-029, I-031 and I-032; test with recorded `gh` JSON fixtures and a fake OpenCode with scripted exit codes and output.

**Acceptance criteria**
- [ ] `grep -c "retained for reference" dev-ops/factory/tick.sh` is 0, and `normalize_model` and `is_usage_filled` are not defined in any shell script.
- [ ] `wc -l dev-ops/factory/tick.sh` is 50 or less.
- [ ] Pytest has orchestration tests for selection order, the gate sequence, the fallback chain and marker/claim interplay.
- [ ] A golden-file test shows the event names and attribute keys for a recorded tick match the pre-rewrite set.
- [ ] `factory-ci` (I-035) is green on the PR.

### I-037 - Deduplicate the acceptance-criteria checker and align it with the issue validator

**Covers:** FAC-22 · **Labels:** `dev-ops`, `light-build-task`, `enhancement` · **Priority:** Later · **Executor:** Factory · **Depends on:** –

**Problem.** Five scripts have the same md5 (`101a540b…`): `dev-ops/factory/ensure-acceptance-criteria.sh`, `dev-ops/factory/hooks/ensure-acceptance-criteria.sh`, and `check-`, `ensure-` and `has-acceptance-criteria.sh` in `dev-ops/scripts/`. Only `check-acceptance-criteria.sh` is called (`tick.sh:963`). The validator disagrees with it: `validate-issue-body.sh:39` accepts a `- [ ]` checkbox anywhere in the body, while the checker requires one inside the AC section and also accepts `[x]` and `*` bullets (`check-acceptance-criteria.sh:72`). `validate-issue-body.sh:46` runs the empty-section check with `|| true` and then again as fatal at `:68`. An issue can pass creation and then fail the planning gate.

**Proposed change.**
- Keep `dev-ops/scripts/check-acceptance-criteria.sh` and delete the other four copies.
- Have `validate-issue-body.sh` call the checker for the AC rule, and remove its own Python AC block and the duplicate non-fatal check.
- Add test cases for the two cases where the scripts disagree today.

**Acceptance criteria**
- [ ] `find . -name '*acceptance-criteria.sh' -not -path './.git/*'` lists only `dev-ops/scripts/check-acceptance-criteria.sh` and its test.
- [ ] A body whose only checkbox is outside the AC section is rejected by both `validate-issue-body.sh` and the checker.
- [ ] A body with `* [x]` items in the AC section is accepted by both.
- [ ] `bash dev-ops/scripts/tests/test-check-acceptance-criteria.sh` passes.

### I-038 - Feed post-merge CI, QA deploy and e2e results back into the factory

**Covers:** FAC-15 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-124, I-066

**Problem.** Discovery only looks at unlabeled issues, approved issues and open `factory/issue-*` PRs (`tick.sh:233`, `discover_*.py`). Nothing reads push-triggered failures on `main` (`backend-ci.yml:8-11`, `security.yml:5-7`), QA deploy outcomes (`booking-deploy` commits such as `33cde20`), Playwright runs, or the factory's own `session_failed` history. A regression merged by the factory stays on `main` until a human notices, and the same mistakes recur, for example the gofmt failure behind commit `fd778fc`.

**Proposed change.**
- Add a `main-health` discovery step: if the latest push run on `main` failed, open or comment on one `factory:main-broken` issue handled under a documented owner policy, and pause new builds until `main` is green.
- Consume the QA deploy and e2e result signals provided by I-066 and I-124 through the same path.
- After each failed session, have tick.sh append a short structured entry (issue, failure class, CI log excerpt) to `dev-ops/factory/LESSONS.md`. The builder reads it; only tick.sh writes it.

**Acceptance criteria**
- [ ] A fixture where the latest `main` push run failed makes the tick skip builds, emit `main_broken`, and create or update exactly one `factory:main-broken` issue across two ticks.
- [ ] A fixture where `main` is green again lets builds resume.
- [ ] A fixture of a failed QA deploy or e2e result triggers the same path.
- [ ] After a forced session failure, `LESSONS.md` gains one entry with issue number, failure class and an excerpt of at most 20 lines.
- [ ] The build prompt or `builder.md` references `LESSONS.md` (grep).

## Epic E - Agent tooling and model routing

The agents run headless on OpenCode Go models with contradictory role definitions, a long list of generic skills, and no project-specific guidance or machine-checked architecture rules. These issues give each role one definition and a curated skill set, add project skills, checks and an independent reviewer, and route models by role and risk.

### I-039 - Make each agent role defined in one place, and align markers and labels

**Covers:** AGT-06, FAC-12 · **Labels:** `dev-ops`, `standard-build-task`, `bug` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** The builder lifecycle lives in three places: `builder.md` (216 lines), `build_prompt` (`tick.sh:549-627`) and `commands/deliver-issue.md`, and they disagree. The planner uses `<!-- factory-plan -->` (`planner.md:29,33`) while tick.sh uses `<!-- factory:plan -->` (`tick.sh:18`), so the planner's duplicate check never matches. The planner asks for `feature/chore`, `size/S|M|L` and `ready-for-build/needs-info` labels (`planner.md:39-41`), which don't exist. `fixer.md:38` says "Only handle PRs labeled `factory`", a label nothing applies. The build prompt says both "Do not mark ready for review automatically" (`tick.sh:601`) and "transition draft to ready if required" (`tick.sh:614-615`). The skill-loading conflict is fixed in I-040 and the issue-creation conflict in I-047.

**Proposed change.**
- Agent files hold role, rules and permissions. Tick prompts hold only parameters: issue or PR number, marker strings, blocking reasons, allowed labels generated from `models.yaml` and the area labels, and the skill list from I-040.
- Fix the marker, remove the `factory`-label rule, replace the planner's label taxonomy, and pick one draft/ready rule consistent with I-019.
- Delete `commands/deliver-issue.md` or make it pass the same parameters.
- Add a test in `dev-ops/scripts/tests/` that every marker and label named in `.opencode/agents/*.md` exists in `tick.sh` or `models.yaml`.

**Acceptance criteria**
- [ ] `grep -rn "factory-plan" .opencode/` returns nothing.
- [ ] `grep -n "labeled \`factory\`" .opencode/agents/fixer.md` returns nothing.
- [ ] The marker/label test passes and fails when an unknown label is added to an agent file.
- [ ] `build_prompt` contains either the "Do not mark ready" rule or `gh pr ready`, not both.
- [ ] `plan_prompt`, `build_prompt` and `fix_prompt` are each 30 lines or less.

### I-040 - Curate per-role skill sets and remove irrelevant skills and caveman from factory sessions

**Covers:** AGT-05, AGT-12, FAC-21 · **Labels:** `dev-ops`, `light-build-task`, `enhancement` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** The build prompt tells every session to "Load and follow" about 16 skills (`tick.sh:555-575`) that contradict each other and the prompt: `implement` commits to the current branch, `caveman` stays on "whole session" against the normal-prose rule, `frontend-design` asks for "aesthetic risk" against approved mockups, and `pr` wants screenshots. `AGENTS.md:63-66` and the agent files mandate caveman for "inter-agent handoffs" that headless sessions don't have, and `builder.md:209-210` names `ultracave`/`megacave`, which are `disable-model-invocation: true`. Factory cost is input context, yet every session lists unused skills such as `pdf` (90 KB) and `skill-creator` (269 KB). `AGENTS.md:23-26` also says to load skills only on explicit user request.

**Proposed change.**
- Have tick.sh pick a small set per role from the area and tier labels: plan `domain-modeling`, `investigate-first`; build the area skill (I-042, I-043) plus `surgical-patch`, `verify-and-stop` and the headless variants from I-041; fix `diagnosing-bugs`, `surgical-patch`, `verify-and-stop`.
- Remove caveman instructions from `AGENTS.md`, the agent files and the prompts. Remove `pdf`, `skill-creator`, `ultracave`, `megacave`, `caveman-compress`, `caveman-commit` and `caveman-review` from `dev-ops/skills.yaml` and `.opencode/skills/`, and move `dev-server-ssh` off the factory skill path.
- Reword `AGENTS.md:23-26` so the factory prompt's list counts as the explicit request.
- Have tick.sh pass only the last 200 lines of the failing CI step to fix sessions.
- Pinning skill refs is AGT-15.

**Acceptance criteria**
- [ ] `grep -rni caveman AGENTS.md .opencode/agents dev-ops/factory/tick.sh` returns nothing.
- [ ] The seven removed skills are absent from `.opencode/skills/` and `dev-ops/skills.yaml`.
- [ ] A test asserts each role prompt names at most 5 skills, all present under `.opencode/skills/` or `dev-ops/skills/`.
- [ ] A test with a 5,000-line failing-job log shows the fix prompt contains at most 200 lines of it.

### I-041 - Add a "no human available" rule and headless variants of the interactive skills

**Covers:** AGT-02 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-040

**Problem.** Sessions run as `opencode run --auto … --file <prompt>` (`tick.sh:707`) with nobody on the other end, but core skills ask for one. `tdd/SKILL.md:22` says to "confirm them with the user. No test is written at an unconfirmed seam"; `code-review/SKILL.md:19` says "ask for it"; `implement` says "If the reference is ambiguous, ask"; `diagnosing-bugs/SKILL.md:16,35` says "ask the user"; `frontend-design/SKILL.md:13` says "confirm with the client". The model then stops or invents the answer, and the literal reading of `tdd` is no tests at all. Neither outcome shows in factory metrics.

**Proposed change.**
- Add `dev-ops/skills/factory-tdd`, `factory-code-review`, `factory-pr` and `factory-diagnosing-bugs`, registered in `dev-ops/skills.yaml` with `local_path`.
- Replace every "ask the user" with a deterministic default: the seams are the public functions and HTTP handlers named in the plan comment, the fixed point is `origin/main`, the spec is the issue body plus the plan comment, and PR evidence is test output, not screenshots.
- Add to the build and fix prompts: "No human is available. Where a skill says to ask the user, follow the factory default in this prompt. If no default exists, post the question as an issue comment, apply `needs-info`, and stop."
- Create the `needs-info` label and switch I-040's lists to the `factory-*` variants.

**Acceptance criteria**
- [ ] `grep -rniE "ask the user|with the user|ask for it|with the client" dev-ops/skills/factory-*` returns nothing.
- [ ] `dev-ops/scripts/request-skills.sh` installs the four `factory-*` skills into `.opencode/skills/`.
- [ ] A test asserts `build_prompt` and `fix_prompt` contain the "No human is available" sentence.
- [ ] `gh label list` includes `needs-info`.

### I-042 - Write first-party backend architecture skills

**Covers:** AGT-01 · **Labels:** `backend`, `standard-build-task`, `documentation` · **Priority:** Next · **Executor:** Factory · **Depends on:** I-044

**Problem.** The only first-party skill is `dev-server-ssh`, which is for operators. `product/backend/README.md` (51 lines) has no "how to add a feature" walkthrough, `AGENTS.md` states rules without examples, and the build prompt relies on generic skills (`tick.sh:555-575`). Each session rediscovers how commands, events and projections are wired, and the code shows the drift: 35 alias declarations and 17 copies of the same command type switch (BE-13), and a Postgres test harness copied 11 times (BE-14). In an event-sourced system a wrongly wired projection or non-idempotent migration is expensive to undo.

**Proposed change.**
- Add under `dev-ops/skills/`, each under 120 lines, pointing to one canonical example file per step and ending with a verification checklist:
  - `es-feature`: command, event, projection, read-model migration, HTTP handler and tests; event naming, payload versioning, registry, checkpoints, "never read the event stream from a query".
  - `db-migration`: numbered files, idempotent DDL (`IF NOT EXISTS`, every file reruns per BE-10), no `UPDATE`/`DELETE` on `events`, how to test.
  - `sidecar-rule`: REST contract, statelessness, Europe/Stockholm time, contract tests on both sides.
  - `notification`: enqueueing to `notification_outbox` and worker retry semantics.
- Use the terms and ADRs from I-044, and register the skills in `dev-ops/skills.yaml` with `local_path`.

**Acceptance criteria**
- [ ] The four `SKILL.md` files exist, each under 120 lines (`wc -l`) and each with a verification checklist section.
- [ ] A test in `dev-ops/scripts/tests/` checks that every repo path the skills reference exists.
- [ ] `db-migration` contains `IF NOT EXISTS` and the no-`UPDATE`/`DELETE`-on-`events` rule (grep).
- [ ] The build prompt for a `backend`-labeled issue names `es-feature` (test).

### I-043 - Write first-party UI and e2e skills and per-area AGENTS.md files

**Covers:** AGT-01 · **Labels:** `frontend`, `standard-build-task`, `documentation` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** UI and e2e work relies on generic skills that don't fit: `frontend-design` pushes "distinctive… aesthetic risk" while the project has approved mockups and a fixed Chakra theme, and `webapp-testing` ships Python Playwright helpers while the e2e suite is TypeScript in `dev-ops/testing/`. There is no `AGENTS.md` in `product/backend`, `product/frontend`, `projects/sauna/sidecar` or `dev-ops/factory`, so agents get no package map or golden-path links. The frontend already shows the drift: dead shim pages and duplicated aliases (FE-17).

**Proposed change.**
- Add `dev-ops/skills/ui-conventions`: Chakra theme tokens from `theme.ts`, the mockups in `projects/sauna/docs/mocks/`, the `api/client.ts` pattern, `test-utils.tsx`, accessibility and mobile rules.
- Add `dev-ops/skills/e2e`: running and extending `dev-ops/testing`, the login-code helper, and the journeys under "Initial test flows" in `projects/sauna/README.md`.
- Keep each under 120 lines, with one canonical example per step and a verification checklist; register both in `dev-ops/skills.yaml`.
- Add short `AGENTS.md` files in the four areas above, with a package map and golden-path links, and link them from the root `AGENTS.md`.
- Replace `frontend-design` and `webapp-testing` in the factory skill lists (I-040).

**Acceptance criteria**
- [ ] `dev-ops/skills/ui-conventions/SKILL.md` and `dev-ops/skills/e2e/SKILL.md` exist, each under 120 lines.
- [ ] The path-existence test from I-042 also covers these skills and the new `AGENTS.md` files.
- [ ] The four area `AGENTS.md` files exist and the root `AGENTS.md` links each one (grep).
- [ ] No tick prompt names `frontend-design` or `webapp-testing` (grep).

### I-044 - Seed GLOSSARY.md and architecture decision records

**Covers:** AGT-07 · **Labels:** `documentation`, `light-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner + Factory · **Depends on:** –

**Problem.** The repo has no `GLOSSARY.md`, `CONTEXT.md` or `docs/adr/`; the only ADR-related file is the skill template `.opencode/skills/domain-modeling/ADR-FORMAT.md`. Yet `tdd`, `pr` and `domain-modeling` all read `GLOSSARY.md`. Real decisions are scattered: the advisory lock in `product/backend/README.md:21-43`, Authelia's role under "Open decisions", the outbox in `AGENTS.md`, the rest in PR bodies and commits. Without a glossary each model names events and APIs its own way, and without ADRs a later session can "simplify away" a deliberate decision such as the advisory lock.

**Proposed change.**
- Factory drafts `GLOSSARY.md` with about 20 terms from `projects/sauna/README.md` and the event names, including booking, slot, blocked period, broadcast, household/address, and super user vs. admin.
- Factory drafts `docs/adr/` in the `ADR-FORMAT.md` format: event sourcing on Postgres, the sidecar contract, passwordless email codes, the notification outbox, create-booking serialization, and the "no deletes" rule with its GDPR consequence (SEC-15).
- Owner confirms each decision and its rationale before merge.
- Update `planner.md` to cite relevant terms and ADRs in plan comments; the "contradicts an ADR" review check goes into the reviewer in I-048.

**Acceptance criteria**
- [ ] `GLOSSARY.md` exists at the repo root with at least 20 terms, including the six named above.
- [ ] `docs/adr/` contains at least 6 ADRs with the headings from `ADR-FORMAT.md` (checked by a test).
- [ ] The PR is approved by the owner.
- [ ] `planner.md` instructs the planner to cite glossary terms and ADRs (grep), and the next plan comment links at least one.

### I-045 - Encode the architecture rules as tests and in-repo Semgrep rules

**Covers:** AGT-03, BE-20 · **Labels:** `backend`, `heavy-build-task`, `enhancement` · **Priority:** Next · **Executor:** Factory · **Depends on:** I-010

**Problem.** The `AGENTS.md` architecture rules are prose only. `.semgrep.yml` has `rules: []` and leaves selection to the Semgrep platform, which per OPS-05 currently scans nothing. No import-boundary or "no deployment identifiers in `product/`" check exists, and the only architecture test is a source grep in `eventstore`. The database does not stop `UPDATE` or `DELETE` on `events` (BE-20). Cheaper models comply with what fails the build, and a failing check gives the fixer a precise signal.

**Proposed change.**
- Go architecture test (or `depguard`/`go-arch-lint`): query-side `internal/*/http.go` must not call `eventstore.Append`, only `command` may append, and `projects/sauna/sidecar` must not import `pgx` or `database/sql`.
- In-repo Semgrep rules: no `UPDATE`/`DELETE` against `events`, no `DELETE FROM` in `product/backend`, no `sauna` (case-insensitive) under `product/`. They run in the Semgrep job fixed by I-010.
- Add a migration with an `events_append_only` trigger (`BEFORE UPDATE OR DELETE ON events ... raise_exception()`), and a test that applies all migrations twice to an empty database.
- Print the matching `AGENTS.md` sentence in each failure message. Add the `no-restricted-imports` ESLint rule for direct `fetch` once ESLint exists (I-119).
- The `-rebuild` mode and transactional `Reset` from BE-20 belong with the projection work (BE-01).

**Acceptance criteria**
- [ ] `go test ./...` includes an architecture test that fails on a testdata package calling `eventstore.Append` from an `http.go`.
- [ ] `semgrep --config .semgrep.yml --error` fails on a fixture containing `DELETE FROM events` and passes on `main`.
- [ ] An integration test shows `UPDATE events ...` returns the trigger's error.
- [ ] The migrations-twice test runs and passes in Backend CI.
- [ ] Each rule's failure message contains its `AGENTS.md` sentence (grep).

### I-046 - Add a shared `check.sh` used by agents and CI, and fix `/lint-frontend`

**Covers:** AGT-09, FE-15 · **Labels:** `dev-ops`, `frontend`, `light-build-task`, `bug` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** `.opencode/commands/lint-frontend.md:8,12` runs `npm run lint` and `npm run typecheck`, but `product/frontend/package.json:6-11` defines only `dev`, `build`, `test` and `preview`, so the command always reports a missing script. The build prompt's local checks are backend-only (`tick.sh:605-606`), and there are no commands for vitest, sidecar tests or the Playwright suite. The frontend has no ESLint and `frontend-ci.yml:39-43` runs only test and build (FE-15). Every frontend or sidecar slip costs a CI round trip plus a fix session.

**Proposed change.**
- Add `dev-ops/scripts/check.sh [backend|frontend|sidecar|e2e|all]`: non-zero on failure, output bounded with `tail`.
- Add `"typecheck": "tsc --noEmit"` and a `lint` script running ESLint with a minimal config to `package.json`. The plugin set (`react-hooks`, `jsx-a11y`), the CI lint step, coverage floor and the remaining FE-15 test-suite work are in I-119.
- Rewrite `/lint-frontend` and `/test-backend` as thin wrappers over `check.sh`, and add `/test-frontend`, `/test-sidecar` and `/e2e`.
- Have the build prompt call `check.sh <area>` from the area label, and the area CI workflows call the same script.

**Acceptance criteria**
- [ ] `cd product/frontend && npm run lint && npm run typecheck` exits 0 on `main`.
- [ ] `dev-ops/scripts/check.sh frontend` exits non-zero when a type error is introduced (test).
- [ ] `dev-ops/scripts/check.sh all` exits 0 on `main`, with at most 200 lines of output per area.
- [ ] `backend-ci.yml`, `frontend-ci.yml` and `sidecar-ci.yml` invoke `dev-ops/scripts/check.sh` (grep).
- [ ] `.opencode/commands/` contains `test-frontend.md`, `test-sidecar.md` and `e2e.md`, each calling `check.sh`.

### I-047 - Give agents a validated way to propose and create follow-up issues

**Covers:** AGT-08 · **Labels:** `dev-ops`, `light-build-task`, `bug` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** `plan_prompt` says "use the /create-github-issue command" (`tick.sh:542`). That command needs a temp file, `validate-issue-body.sh` and `gh issue create`, but the planner has `edit: deny` and `bash: "*": deny` with only `gh issue view/list/comment/edit`, `gh label list`, `gh pr list`, git reads and `ls` allowed (`planner.md:5-20`). Slash commands are user-invoked in OpenCode anyway. The builder's allow-list (`builder.md:7-27`) has neither `gh issue create` nor the validator, so the model fails silently or improvises with `gh issue create` directly, skipping the validator the command was meant to enforce.

**Proposed change.**
- Add `dev-ops/scripts/create-issue.sh --title … --body-file …`, which runs `validate-issue-body.sh` and only then `gh issue create`, exiting non-zero with the validator's message on failure.
- Planner: replace the `/create-github-issue` instruction with a "Follow-ups" section in the plan comment that the owner turns into issues.
- Builder and fixer: allow only `dev-ops/scripts/create-issue.sh*` and deny direct `gh issue create*`, in the permission shape defined by I-020.
- Make `/create-github-issue` call the wrapper.

**Acceptance criteria**
- [ ] A test with a stub `gh` shows `create-issue.sh` exits non-zero on a body without acceptance criteria and makes no `gh` call.
- [ ] With a valid body, the stub `gh` receives `issue create` with the body file.
- [ ] `grep -n "create-github-issue" dev-ops/factory/tick.sh` returns nothing.
- [ ] `builder.md` and `fixer.md` allow `dev-ops/scripts/create-issue.sh*` and deny `gh issue create*` (grep).
- [ ] `planner.md` defines the "Follow-ups" section (grep).

### I-048 - Add an independent reviewer on a different model family that posts a GitHub review

**Covers:** ST-03, FAC-11, AGT-10 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-006, I-019

**Problem.** `.opencode/agents/reviewer.md` defines a read-only reviewer with blocker/major/minor verdicts, but nothing in `tick.sh`, `builder.md`, `fixer.md` or the commands invokes it. The build prompt only says "`code-review` - review changes before landing when available" (`tick.sh:558`), so the builder reviews its own diff with the same model. No agent sets `model:`, so the reviewer and the sub-agents `code-review` spawns inherit the session model (AGT-10). `reviewDecision` is empty on all 81 merged PRs, and #150 has 0 reviews.

**Proposed change.**
- Add a review stage: for a factory PR with green checks and no `factory:review:<sha>` marker, run `--agent reviewer` with a model pinned via `models.yaml` (`review-task`) from a different family than the builder's. Add a `family:` field per model so tick.sh can enforce this.
- The reviewer writes a verdict file; tick.sh posts it with `gh pr review --approve` or `--request-changes` under the separate identity from I-006 (GitHub doesn't let a PR's author approve it).
- The merge step from I-019 merges only after `APPROVE` on the current head SHA. `REQUEST_CHANGES` feeds the existing `changes-requested` fix path.
- PRs labeled `heavy-build-task` or touching `auth`, `eventstore` or `dev-ops/factory` get `needs-owner-review` and are never merged by the factory.
- The reviewer also checks for contradictions with ADRs (I-044).

**Acceptance criteria**
- [ ] On a green factory PR, `gh pr view --json reviews` shows a review for the head SHA from the factory reviewer identity.
- [ ] A test shows tick.sh refuses a review session when the reviewer and builder models share a family.
- [ ] A test with a `REQUEST_CHANGES` verdict shows no merge and the PR becomes a `changes-requested` fix candidate.
- [ ] A new push to the PR triggers a new review (marker keyed by SHA).
- [ ] A PR touching `dev-ops/factory/**` gets `needs-owner-review` and remains unmerged by the factory.

### I-049 - Route models by role and risk and validate model IDs at startup

**Covers:** FAC-10, AGT-10 · **Labels:** `dev-ops`, `standard-build-task`, `bug` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** `models.yaml:20-22` maps `plan-task`, but planning calls `model_for_labels` with no labels (`tick.sh:1130`), so `factory.py:67-70` returns `default`. Model IDs are never checked: `validate-models` checks only the schema (`factory.py:22-52`), commit `c35a381` replaced a backup that silently didn't exist, `light-build-task: opencode-go/claude-haiku-5-5` (`models.yaml:31`) is unconfirmed, and so is the `#high` suffix `normalize_model` adds to `opencode-go/beam-free` (`tick.sh:683-686`). The planner picks the tier (`tick.sh:536-537`) uncapped, and the fixer inherits it (`tick.sh:1045-1046`), so a gofmt fix on a heavy PR uses the most expensive model while risky changes can land on a cheap one.

**Proposed change.**
- Call `model_for_labels plan-task` for planning.
- At tick start, cache `opencode models opencode-go` and `opencode models opencode`. If any configured model or backup (including the `#variant` form) is missing, emit `model_unavailable` and start no session.
- Add a `fix-task` entry on a mid-tier model; use the issue's tier only for `changes-requested`.
- Add a deterministic tier floor: changes to migrations, `eventstore` or `auth` get at least `standard-build-task`; `eventstore`, `projection`, `command` and `dev-ops/factory/**` get the strongest model.
- Record model and tier in the PR body, and check on the host that each model accepts `temperature: 0.1`.
- The reviewer's model is in I-048; fallbacks never merging is in I-028.

**Acceptance criteria**
- [ ] A pytest case shows planning resolves the `plan-task` model.
- [ ] Validation against a model-list fixture missing one ID exits non-zero and names that ID.
- [ ] A test shows a `ci-failed` fix on a `heavy-build-task` PR resolves `fix-task`, and `changes-requested` resolves the heavy model.
- [ ] A test shows a plan proposing `trivial-task` for a change listing a migration resolves to at least `standard-build-task`.
- [ ] New factory PR bodies contain `Model:` and `Tier:` lines.

### I-050 - Move deterministic lifecycle steps out of the LLM session

**Covers:** AGT-04 · **Labels:** `dev-ops`, `heavy-build-task`, `enhancement` · **Priority:** Later · **Executor:** Owner-reviewed PR · **Depends on:** I-019, I-036

**Problem.** `build_prompt` (`tick.sh:582-618`) asks one session to inspect the checkout, create a worktree and branch, keep a JSON state file, implement, commit and push, find or open a draft PR, run `gh pr checks --watch`, remediate up to 3 CI cycles, merge, clean up and post a marker, all under one 3,600 s timeout. `builder.md` repeats the steps in 216 lines. Long stateful tool chains are where mid-tier and free models fail most (skipped steps, wrong markers, early merges), and polling CI inside the session burns wall-clock time and context.

**Proposed change.**
- Have the orchestrator from I-036 own the worktree, branch, state, commit and push, PR creation and update, CI wait, cleanup and markers. Merging is already moved out by I-019.
- Give the model three narrow jobs. Build: implement in the given worktree, run `dev-ops/scripts/check.sh` (I-046), write `PR_BODY.md`. Fix: given the failing job's last 200 lines and the diff, fix the root cause. Review: I-048.
- Shrink `builder.md` and `fixer.md` to match, and remove PR, push and merge permissions from them in line with I-020.

**Acceptance criteria**
- [ ] `builder.md` and `fixer.md` allow none of `gh pr create*`, `gh pr checks*`, `gh pr merge*` or `git push*` (grep).
- [ ] No session prompt contains `gh pr checks --watch` (grep).
- [ ] An orchestrator test with a fake OpenCode that only edits files and writes `PR_BODY.md` sees a commit, a push to a fake remote, and a PR with that body.
- [ ] A test where `PR_BODY.md` is missing marks the session failed and opens no PR.
- [ ] `wc -l .opencode/agents/builder.md` is 100 or less.

### I-051 - Add an Architecture Impact section to the issue template

**Covers:** AGT-14 · **Labels:** `documentation`, `trivial-task`, `enhancement` · **Priority:** Later · **Executor:** Factory · **Depends on:** –

**Problem.** `dev-ops/issue-templates/agentic.md` has generic sections (Problem Statement, Motivation, … Constraints and Considerations). Nothing asks which events or projections change, whether a migration or a sidecar contract change is needed, which UI routes are affected, or what is out of scope. The planner and builder therefore have no structured signal for choosing skills or a model tier for architecture-touching work.

**Proposed change.**
- Add an `## Architecture Impact` checklist to the template: events added or changed (names), projections or read models affected, migration (y/n), sidecar contract change (y/n), UI routes affected, relevant ADRs.
- Add an `## Out of Scope` section.
- Make `validate-issue-body.sh` require both headings.
- Have `planner.md` fill these in the plan comment, so I-040 can pick skills and I-049 can apply the tier floor from them.

**Acceptance criteria**
- [ ] `grep -c "^## Architecture Impact\|^## Out of Scope" dev-ops/issue-templates/agentic.md` returns 2.
- [ ] A test shows `validate-issue-body.sh` rejects a body without `## Architecture Impact` and accepts one with both sections.
- [ ] `planner.md` instructs the planner to fill the Architecture Impact items (grep).

### I-052 - Build a replay benchmark for prompt, skill and model changes

**Covers:** AGT-13, ST-09 · **Labels:** `dev-ops`, `heavy-build-task`, `enhancement` · **Priority:** Later · **Executor:** Owner-reviewed PR · **Depends on:** I-055

**Problem.** Recent commits change models (`c35a381`), skills (#96, #98) and prompts (#94, #132), but no benchmark or replay exists, and success is judged only by whether the PR merged. With several OpenCode Go models and 22 skills, nobody can tell whether a change helped. There are also no delivery metrics (ST-09): no lead time, no rework rate (fix sessions per PR), no escaped defects (`bug` issues after merge), and no model cost per issue.

**Proposed change.**
- Freeze 8-10 closed issues as a benchmark, mixing tiers and areas (for example #115, #117, #118, #119), in `dev-ops/factory/bench/` with base SHAs and hidden tests.
- Add a replay script that runs them in a scratch clone in dry-run/no-push mode, weekly and on changes to `.opencode/**`, `models.yaml` or the prompts, on the factory host.
- Score each run on hidden-test pass rate, `check.sh` pass, diff size against the original, architecture-check violations (I-045), tokens (from the session telemetry in I-055) and wall time. Keep a results table in the repo.
- Add a weekly delivery report: issue lead time, PRs needing fix sessions, `bug` issues traced to a factory PR, and model/tier against success.

**Acceptance criteria**
- [ ] The benchmark manifest lists at least 8 issues covering at least 3 tiers and 2 areas.
- [ ] A replay with a stub `gh` records zero write calls (no push, comment or PR).
- [ ] One run adds a results row with all six scores for each benchmark issue.
- [ ] The weekly report shows the four delivery metrics for the past 7 days.

### I-053 - Install language servers on the factory host and document the resolved OpenCode config

**Covers:** AGT-16 · **Labels:** `dev-ops`, `trivial-task`, `documentation` · **Priority:** Later · **Executor:** Owner · **Depends on:** –

**Problem.** `opencode.jsonc` sets `compaction.keep.tokens`, `compaction.buffer`, `experimental.todo` and `experimental.background_compaction`, plus the disputed `permissions` block (FAC-04 vs. SEC-04). The review could not confirm these keys against the OpenCode version on the host, and unknown keys may be silently ignored. Nothing documents whether `gopls` and `typescript-language-server` are installed on the Ubuntu host, although LSP diagnostics are among the cheapest correctness feedback an agent gets.

**Proposed change.**
- Install `gopls` and `typescript-language-server` for the factory user on the host.
- Run OpenCode's config debug output once and record the resolved config and the OpenCode version in `dev-ops/factory/README.md`.
- List both language servers under the README prerequisites.
- Schema validation of `opencode.jsonc` in CI is in I-035; the permission block rewrite is in I-020.

**Acceptance criteria**
- [ ] `command -v gopls typescript-language-server`, run as the factory user, prints two paths (output pasted in the issue).
- [ ] `dev-ops/factory/README.md` lists both language servers with versions under prerequisites.
- [ ] The README contains the resolved OpenCode config, the OpenCode version and the date it was captured.
- [ ] Every `opencode.jsonc` key missing from the resolved config is listed in the README and either removed or explained.

## Epic F - Observability and project insights

SigNoz runs and the backend exports basic traces, but factory telemetry may never reach it, nothing alerts, and SigNoz content (users, dashboards, alerts, retention) exists only in a Docker volume. These issues get factory events flowing, add the cost, outcome and flow data a project manager needs, put SigNoz configuration in git, and fill the backend APM gaps.

### I-054 - Ship factory events through the existing SigNoz collector

**Covers:** OBS-02, OBS-13 · **Labels:** `dev-ops`, `light-build-task`, `enhancement` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** `dev-ops/factory/otel-collector.yaml:1-4` says the shipper "Runs as a user systemd unit on the cron host", but nothing in the repo installs it: `grep otelcol` finds only the README, and there is no unit file, installer or pinned version. Nobody can tell from the repo whether any factory event has ever reached SigNoz, and a fresh host certainly ships nothing. The config is also fragile: `start_at: end` with no `file_storage` (`:15`) skips every event written while the shipper is down, and the strptime layout `%Y-%m-%dT%H:%M:%S.%fZ` (`:18-20`) may not parse the millisecond timestamps `tick.sh:147` writes (not verified).

**Proposed change.**
- Mount the factory log directory (`tick.sh:29`) read-only into `signoz-otel-collector`, with the host path from an env variable. Don't rely on the `/:/hostfs` mount, which I-064 narrows.
- Add a `filelog/factory` receiver and a `logs/factory` pipeline to `dev-ops/signoz/otel-collector-config.yaml`, keeping `service.name=factory-tick`.
- Add the `file_storage` extension on the receiver and use `start_at: beginning`, so offsets survive restarts and the first start backfills.
- Parse `ts` with `layout_type: gotime`, `layout: "2006-01-02T15:04:05.000Z07:00"`.
- Delete `dev-ops/factory/otel-collector.yaml`, update the factory README, and add a CI step that validates the config with a fixture line (FAC-18).

**Acceptance criteria**
- [ ] `docker compose -f dev-ops/signoz/docker-compose.yml config` shows the factory log directory mounted read-only into `signoz-otel-collector`.
- [ ] A CI job validates the collector config and passes; a fixture line with `ts` `…T11:00:55.123Z` comes out of a `file` exporter with that exact timestamp.
- [ ] On the host, a `tick_start` event appears in SigNoz Logs with `service.name=factory-tick` within 2 minutes of the tick.
- [ ] Events written while the collector was stopped appear in SigNoz after it restarts, with no duplicates.

### I-055 - Capture tokens, cost, skills, tools and outcomes in factory session telemetry

**Covers:** OBS-01, FAC-13, ST-09 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-027, I-054

**Problem.** Session events carry only `kind`, `issue`/`pr`, `model`, `exit_code`, `duration_ms`, `outcome`, `session_id` and an optional `output_tail` (`tick.sh:753-904`). The OpenCode `--format json` stream holds tokens, cost, tool and skill calls (`tick.sh:707,759`), but it is never parsed, and with `FACTORY_PRESERVE_SESSION_LOGS=on-failure` it is deleted after every successful session. So cost per issue, which models and skills deliver, and success by model and tier (ST-09) can't be answered, and `models.yaml` is tuned blind. `output_tail` also ships the last 16 KiB of raw transcript to SigNoz (FAC-13, `tick.sh:900-904`).

**Proposed change.**
- Add `factory.py session-usage <logfile>` to `lib/factory.py`, run at session end before the log is deleted. It sums tokens (input, output, reasoning, cache) and cost from step-finish events, counts tool calls by name, and lists `skill` tool names. Verify field names against the OpenCode version in `tick_start`.
- Add to every `session_*` event: `agent`, `tier_label`, `area_labels`, `fallback_level`, `tokens_*`, `cost`, `tool_calls`, `skills_loaded`, `files_changed`, `pr`, `head_sha`, `prompt_version`. The `session_id` fix is I-027.
- Bump `schema_version` to 2, and default `FACTORY_LOG_SESSION_OUTPUT=metadata` for shipped events.
- Merge and CI outcomes are in I-056, alerts in I-058, dashboards in I-057.

**Acceptance criteria**
- [ ] A pytest for `session-usage` uses a fixture stream captured from the host's OpenCode version and asserts the token sums, cost, tool counts and skill names.
- [ ] After one build session on the host, its `session_ok` event in `tick.jsonl` has non-empty `session_id`, `agent`, `tier_label`, `fallback_level`, `tokens_in`, `cost` and `pr`.
- [ ] `jq -r .schema_version tick.jsonl | sort -u` prints only `2` for events written after the change.
- [ ] Shipped `session_failed` events contain no `output_tail` field by default.
- [ ] A SigNoz query of `sum(cost)` grouped by `model` and `tier_label` over 7 days returns rows.

### I-056 - Emit delivery-flow and queue events (lead time, rework, queue depth)

**Covers:** OBS-01, ST-09 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-054

**Problem.** No factory event records CI results, merges, or the time from approval to merge. `fix_selected` has a PR number, but merge and CI outcomes are never recorded, and GitHub state (queue by label) is never emitted (OBS-01). So lead time, rework rate (fix sessions per PR), stalled PRs and escaped defects (bug issues traced to a factory PR) can't be measured (ST-09). These are the numbers that show where work stalls and whether a cheaper tier causes more rework.

**Proposed change.**
- At the end of each tick (`tick.sh` already queries GitHub), emit `pr_opened`, `ci_result` per required check, `pr_merged` (with `issue_approved_at`, `merged_at`, `lead_time_s`, `fix_attempts`) and `issue_blocked`. A small state file ensures each `pr_merged` is emitted once.
- Emit one `factory_queue` event per tick with counts of infant, planned, approved-not-started, in-PR, blocked and needs-info issues.
- Emit `bug_linked` when a new `bug` issue references a merged factory PR.
- Add a weekly `delivery_summary` event with lead time p50/p90, rework rate, escaped defects and success by model × tier (ST-09).
- Put the logic in `lib/factory.py` with unit tests. The dashboard is in I-057.

**Acceptance criteria**
- [ ] A pytest feeds fixture GitHub JSON for three merged PRs through two consecutive runs and gets exactly three `pr_merged` events with correct `lead_time_s`.
- [ ] Every tick on the host writes one `factory_queue` event; `jq` shows all six count fields present.
- [ ] For a factory PR, `tick.jsonl` contains one `ci_result` event per required check.
- [ ] A weekly `delivery_summary` event appears in SigNoz with lead time p50/p90 and rework rate.

### I-057 - Provision SigNoz dashboards, alerts, retention and admin from git

**Covers:** OBS-03 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-003

**Problem.** SigNoz users, dashboards, alerts, notification channels and retention are stored in SQLite on the `signoz-sqlite` volume (`dev-ops/signoz/docker-compose.yml:140,144`), and none of them exist under `dev-ops/signoz/`. Rebuilding the host or adding an environment gives an empty SigNoz, whatever was set up by hand is lost, and alert thresholds have no review trail. With the UI published on all interfaces (`:137`), the first visitor completes the admin signup; I-003 binds the port, which this issue depends on.

**Proposed change.**
- Add `dev-ops/signoz/provision/` with `dashboards/*.json` (factory overview, delivery flow, models and cost, agent behaviour, QA APM, event sourcing and product, host and containers), `alerts/*.json`, `retention.json` (for example traces 7d, logs 14d, metrics 30d, sized to the disk) and `provision.sh`.
- `provision.sh` is idempotent: wait for `/api/v1/health`, register the admin from `.env` if no user exists, get an API token, upsert dashboards and alerts by title, set retention TTLs, and create the notification channel from `.env`.
- Run it as a one-shot `signoz-provision` service with `depends_on: signoz-server: service_healthy`, so it reconciles on every start.
- Move the alert rules from I-058 under `provision/alerts/`.
- Export dashboards from the UI once and edit them in git afterwards. Pin the API calls to `v0.96.1` and verify them on the box, since endpoints differ between versions.

**Acceptance criteria**
- [ ] Starting the stack on a fresh `signoz-sqlite` volume creates the admin user, and the dashboard count from the API equals the number of files in `provision/dashboards/`.
- [ ] Running `provision.sh` twice leaves the dashboard and alert counts unchanged.
- [ ] Retention TTLs read back from the API match `retention.json`.
- [ ] The notification channel named in `.env` exists after provisioning.
- [ ] The `signoz-provision` container exits 0 on each `docker compose up`.

### I-058 - Add a minimal alert set that reaches the owner

**Covers:** OBS-04, FAC-13, OPS-13, OPS-01 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** I-054

**Problem.** No alert rules exist (`dev-ops/signoz/prometheus.yml:12` has `rule_files: []`, and none are provisioned), so the host metrics added in #146 go unwatched (OPS-13). The only failure notice is a GitHub issue filed under the owner's own account, which GitHub never notifies the owner about (OPS-01). QA deploys were broken from 2026-11-10 to 2026-11-19 (#85, #86, #89) and the factory went six days without planning (FAC-13) with nothing flagging either.

**Proposed change.**
- Create a notification channel the owner reads (email, ntfy or a Slack webhook) from a gitignored `.env`, never a GitHub issue under the owner's identity.
- Add rule files under `dev-ops/signoz/provision/alerts/` and an idempotent apply script (I-057 later absorbs both):
  - Factory silent: no `tick_end` for 2 h.
  - Factory failing: session failures above 50 % over 6 h, any `discovery_failed`, more than 3 `lock_skipped` in a row, or no `session_ok` for 6 h while approved issues exist.
  - Quota: any `usage_filled`, `backup_ok` or `free_retry`.
  - Host: memory above 90 % for 10 min, any filesystem above 85 %, no hostmetrics for 5 min.
- Deploy alerts: `deploy_failed` after I-059; until then I-066. Ports are I-003, the host mount I-064, log export I-060.

**Acceptance criteria**
- [ ] The alert rule files are in the repo and the apply script creates them; the SigNoz API lists each rule after a second run with no duplicates.
- [ ] A test notification sent from SigNoz arrives on the owner's channel.
- [ ] Appending a synthetic `discovery_failed` event to `tick.jsonl` produces a notification within 10 minutes.
- [ ] Temporarily lowering the disk threshold below current usage fires the host disk alert.
- [ ] No alert rule uses a GitHub issue as its channel.

### I-059 - Emit deploy events and tag the backend with version and environment

**Covers:** OBS-06 · **Labels:** `dev-ops`, `backend`, `light-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-054

**Problem.** `deploy-environment.sh` writes no telemetry; its only outputs are a commit to `main` and a GitHub issue on failure. The backend resource sets only `service.name` (`product/backend/internal/telemetry/telemetry.go:36-38`), so the collector's span-metric dimensions `service.version` and `deployment.environment` (`otel-collector-config.yaml:54-59`) fall back to `default`. You can't see whether errors rose after a deploy, tell environments apart, or measure deploy frequency and failure rate.

**Proposed change.**
- In `deploy-environment.sh`, emit `deploy_start`, `deploy_ok` and `deploy_failed` (environment, commit, previous commit, duration, failed step, health result) as JSONL in the factory event format, into a file the I-054 `filelog` receiver includes.
- Pass the version and environment to the backend in `projects/sauna/docker-compose.yml`:
  ```yaml
  OTEL_RESOURCE_ATTRIBUTES: "service.version=${DEPLOY_COMMIT:-unknown},deployment.environment=${ENV_NAME:-local},service.namespace=booking"
  ```
  and have the deploy export `DEPLOY_COMMIT=$DEPLOYED_SHA`.
- In `telemetry.go`, build the resource with `resource.WithFromEnv()`, `WithHost()`, `WithProcess()` and `WithTelemetrySDK()` plus the service name.

**Acceptance criteria**
- [ ] `dev-ops/scripts/tests/test-deploy-environment.sh` asserts one `deploy_start` and one `deploy_ok` line for a successful stubbed run, and a `deploy_failed` line with the failed step for a failing one.
- [ ] A Go test sets `OTEL_RESOURCE_ATTRIBUTES` and asserts the resource contains `service.version` and `deployment.environment`.
- [ ] In SigNoz, QA backend spans show `service.version` equal to the deployed SHA and `deployment.environment=qa`, not `default`.
- [ ] `deploy_ok` and `deploy_failed` events from the QA host are queryable in SigNoz.

### I-060 - Complete backend APM: route names, DB, sidecar and SMTP spans, log bridge, runtime metrics

**Covers:** OBS-07, BE-17 · **Labels:** `backend`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** `server.go:90` wraps the mux as `otelhttp.NewHandler(NewMux(deps), "http")`, so every server span is named `http`. There is no pgx tracer, so the advisory-lock wait in BE-02 is invisible. The sidecar client (`internal/sidecar/client.go:29`) and `/chrome` (`server.go:188`) use plain `http.Client`/`http.DefaultClient`, so traces stop at the backend. `slog` output carries no `trace_id`, logs are not exported, and there are no Go runtime metrics on a 512 MB container.

**Proposed change.**
- Name spans by route: `otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string { return r.Method + " " + r.Pattern })`. This also keeps feed tokens out of span names.
- Add `otelpgx.NewTracer()` to the pgx pool config.
- Use `otelhttp.NewTransport` on both outbound clients, with span attributes for the sidecar rule evaluated and its result.
- Add an SMTP send span in `internal/email/smtp_sender.go`.
- Bridge `slog` to OTLP (`otelslog` plus `otlploghttp`), add `trace_id`/`span_id` to stdout logs too, and wire the collector's `logs` pipeline to `clickhouselogsexporter`.
- Register `go.opentelemetry.io/contrib/instrumentation/runtime`. The `notifications.pending` gauge and projection lag (also BE-17) are in I-061.

**Acceptance criteria**
- [ ] A Go test with an in-memory span exporter asserts a request to a patterned route produces a server span named `<METHOD> <pattern>`.
- [ ] An integration test asserts a database query inside a request creates a child span of the server span.
- [ ] A sidecar client test against `httptest.Server` receives a `traceparent` header.
- [ ] A test asserts an `slog` record written inside a span includes `trace_id`.
- [ ] In QA, SigNoz shows backend logs linked to traces and goroutine and heap metrics for the backend service.

### I-061 - Add event-sourcing and product metrics

**Covers:** OBS-08, BE-17 · **Labels:** `backend`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Factory · **Depends on:** I-087

**Problem.** The only custom metrics are six notification counters (`internal/notification/outbox.go:84-95`). `notifications.pending` is an in-process UpDownCounter that starts at 0 on every boot and goes negative once rows from before a restart are sent (`outbox.go:94-111`). There are no metrics for events appended, projection checkpoint or lag, outbox depth, bookings, rejections or logins. For an event-sourced system, projection lag and appended-vs-applied are the numbers that show the read side is correct, and the runner can skip events silently (BE-01).

**Proposed change.**
- Add a small `internal/metrics` package and record:
  - `events.appended{type}` in `command.Service`
  - `projection.checkpoint{projection}`, `projection.lag{projection}` (head event ID minus checkpoint) and `projection.errors{projection}` in the runner
  - `bookings.created`, `bookings.cancelled`, `bookings.rejected{reason}` (double booking, blocked, sidecar rule)
  - `auth.codes_issued`, `auth.logins{result}`, `ratelimit.rejected{limiter}`
  - `sidecar.requests{result}` with a latency histogram
- Replace `notifications.pending` with an observable gauge that runs `SELECT status, count(*), min(created_at) … GROUP BY status` every 30 s, giving outbox depth and oldest pending age.
- The "Event sourcing and product" dashboard is provisioned in I-057.

**Acceptance criteria**
- [ ] A Go test with a manual metric reader asserts appending three events increments `events.appended` by three for their types.
- [ ] An integration test with pending outbox rows from before a restart shows the pending gauge equal to the database count and never negative.
- [ ] A test with the runner paused asserts `projection.lag` equals head event ID minus checkpoint.
- [ ] A rejected double booking increments `bookings.rejected{reason="double_booking"}` in a test.
- [ ] In QA, SigNoz shows `projection.lag` per projection.

### I-062 - Collect container, Postgres and Caddy metrics

**Covers:** OBS-09 · **Labels:** `dev-ops`, `light-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** The SigNoz collector scrapes host metrics only (`otel-collector-config.yaml:11-21`) on a host with about 3.2 GB of RAM (`signoz/README.md:104`) that runs the factory, QA and SigNoz together (OPS-12). Memory limits were added after OOM pressure (#136). Without per-container metrics, nobody can tell whether OpenCode, ClickHouse or the backend is eating memory during a factory session.

**Proposed change.**
- Add per-container CPU and memory: either the `docker_stats` receiver with the Docker socket mounted read-only (a privilege trade-off to record in the PR), or cAdvisor scraped by the `prometheus` receiver.
- Add a `postgresql` receiver against the QA database with a read-only monitoring role (`pg_monitor`), reached over a shared Docker network rather than a published port.
- Enable Caddy's Prometheus `metrics` endpoint on an internal-only listener and scrape it.
- Add a `process` filter to the `processes` scraper to track `opencode` memory.
- Add the panels to the "Host and containers" dashboard (I-057), and recheck the collector's 512m limit after the change.

**Acceptance criteria**
- [ ] SigNoz shows per-container memory for the QA backend and for ClickHouse.
- [ ] Postgres connection metrics for the QA database appear in SigNoz.
- [ ] Caddy request metrics are scraped, and the metrics endpoint is not reachable from outside the host (`curl` from another machine is refused or 404).
- [ ] `opencode` process memory is visible during a factory session.
- [ ] An `INSERT` attempted as the monitoring role fails with a permission error.

### I-063 - Model factory ticks as traces with resource attributes

**Covers:** OBS-10 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Later · **Executor:** Owner-reviewed PR · **Depends on:** I-055

**Problem.** `emit_event` writes one flat JSON object per event (`tick.sh:131-160`). The shipper parses it into log attributes and upserts only `service.name` on the resource (`otel-collector.yaml:16-20,26-30`), so `deployment.environment` and `host.name` stay log attributes and SigNoz's service and environment filters don't apply. Durations exist only as numbers inside log lines, so there are no histograms without log queries. `emit_event … >/dev/null 2>&1 || true` (`tick.sh:133`) drops events silently when Python fails.

**Proposed change.**
- Cheap path first: in the I-054 factory pipeline, promote `deployment.environment`, `host.name` and `service.name` to resource attributes with the `transform` or `groupbyattrs` processor.
- Then emit a trace per tick from the Python helper (OTel SDK) or with `otel-cli`: root span `factory.tick`, child spans `factory.discovery`, `factory.plan`, `factory.build` and `factory.fix`, each carrying the I-055 attributes.
- Put the trace ID on each JSONL event so logs and traces join.
- Write `emit_event` failures to stderr and add a `telemetry_errors` count to `tick_end`.

**Acceptance criteria**
- [ ] In SigNoz, `factory-tick` can be filtered by `deployment.environment` as a resource attribute.
- [ ] One tick on the host produces one trace with a `factory.tick` root and a child span for each session that ran.
- [ ] Span metrics give p95 session duration grouped by `model` and `kind`.
- [ ] A test that makes the event log unwritable shows a non-zero `telemetry_errors` in `tick_end` and a message on stderr.

### I-064 - Harden SigNoz reproducibility on a fresh host

**Covers:** OBS-12, OPS-13 · **Labels:** `dev-ops`, `light-build-task`, `enhancement` · **Priority:** Later · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** The `histogramQuantile` UDF is downloaded from GitHub at every init with no checksum (`dev-ops/signoz/docker-compose.yml:74-82`). The collector has no `hostname:` and runs `resourcedetection` inside the container, applied to metrics only (`otel-collector-config.yaml:43-45,95-110`), so `host.name` is likely the container ID and changes on recreate (not verified on a running instance). `prometheus.yml:6-10` targets a non-existent `alertmanager:9093`, images are pinned by tag only, and the collector mounts the whole host filesystem (`/:/hostfs:ro`, `:173`), including `~/.config/gh/hosts.yml`, `~/.ssh` and `projects/sauna/.env` (OPS-13).

**Proposed change.**
- Verify the UDF tarball's SHA-256 in the init script, or vendor the binary per architecture.
- Give `host.name` a stable value (`hostname: ${HOST_HOSTNAME:-signoz-host}`, or `OTEL_RESOURCE_ATTRIBUTES=host.name=…`) and add `resourcedetection` to every pipeline.
- Remove the stale alertmanager block.
- Pin images by digest.
- Replace `/:/hostfs:ro` with `/proc`, `/sys` and only the filesystems the scraper needs.
- The other parts of OPS-13 are covered elsewhere: port binding in I-003, alert rules in I-058 and I-057, backend log export in I-060.

**Acceptance criteria**
- [ ] The init container fails when the expected UDF checksum is changed to a wrong value.
- [ ] `host.name` on host metrics is unchanged after `docker compose up -d --force-recreate signoz-otel-collector`.
- [ ] `grep -n alertmanager dev-ops/signoz/prometheus.yml` returns nothing.
- [ ] Every `image:` in `dev-ops/signoz/docker-compose.yml` contains `@sha256:`.
- [ ] The collector has no `/:/hostfs` mount, and filesystem and memory host metrics still arrive in SigNoz.

### I-065 - Add sidecar tracing and optional frontend RUM

**Covers:** OBS-14 · **Labels:** `backend`, `frontend`, `standard-build-task`, `enhancement` · **Priority:** Later · **Executor:** Factory · **Depends on:** I-060

**Problem.** There is no OpenTelemetry code under `projects/sauna/sidecar/` or `product/frontend/src/` (grep). Rule-evaluation latency and failures in the sidecar are invisible, which matters because the sidecar fails open (BE-09). Frontend load and API errors seen by residents are not measured at all.

**Proposed change.**
- Sidecar: wrap the handler with `otelhttp`, initialise telemetry like the backend, and add attributes for the rule evaluated and its result. With the I-060 client transport, traces run end to end.
- Frontend, optional and off by default: the OpenTelemetry web SDK (document-load and fetch) sending to an OTLP path proxied by Caddy with strict CORS and a rate limit, or web-vitals posted to a backend endpoint. Residents are a small, known group, so decide in the PR before building.
- Any RUM endpoint must fit the CSP from I-082 (`connect-src 'self'`).

**Acceptance criteria**
- [ ] A sidecar Go test sends a request with a `traceparent` header and asserts the recorded server span has the same trace ID.
- [ ] Creating a booking on QA shows one trace in SigNoz with spans from both the backend and the sidecar.
- [ ] With RUM disabled (the default), the built frontend makes no request to an OTLP or vitals path (Playwright network check).
- [ ] If RUM is enabled, its ingest path is rate-limited in the Caddyfile and `caddy validate` passes.

## Epic G - QA environment, deploy and operations

QA is the only place merged factory work runs as a whole system, but failed deploys go unnoticed, nothing gates what is deployed, there is no rollback and no backup of the event store. These issues make failures visible, protect the data, deploy only tested images, and make QA closer to production.

### I-066 - Make every deploy failure reach the owner

**Covers:** OPS-01, OPS-20 · **Labels:** `dev-ops`, `light-build-task`, `bug` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** I-058

**Problem.** Deploy alerting is only `gh issue create/comment … >/dev/null 2>&1 || true` (`dev-ops/scripts/deploy-environment.sh:137-153`), filed under the owner's own account, so GitHub sends no notification. Exits through `die()` (`:24`) at `:201`, `:272` and `:306` never alert. A failing `ExecStartPre`, a `TimeoutStartSec=45min` kill, and a timer that was never installed are invisible to the script (`install-deploy-timer.sh:114,117`; #85), and the generated unit has no `OnFailure=` (OPS-20). QA went undeployed from 2026-11-10 to 2026-11-19.

**Proposed change.**
- Add a dead-man's switch: ping an external heartbeat (healthchecks.io, Uptime Kuma or similar) only after a successful deploy, with a 13-hour period, and ping its `/fail` URL from error paths. A missed ping alerts whatever the cause.
- Route every `die` through one `fail()` that alerts, and add `set -E` so the ERR trap covers functions.
- Send alerts to the I-058 channel (ntfy or email), not through `gh` under the owner identity.
- Add `OnFailure=booking-deploy-alert@%n.service` to the unit written by `install-deploy-timer.sh`, with a template unit that pings the `/fail` URL.
- Alert on metadata push failures (`:400-407`) until I-069 removes the push. Removing raw logs from alerts is I-002; the on-demand trigger is I-076.

**Acceptance criteria**
- [ ] `test-deploy-environment.sh` asserts the alert stub is called for each of the `die` exits at `:201`, `:272` and `:306`.
- [ ] `test-install-deploy-timer.sh` asserts the generated service contains `OnFailure=`.
- [ ] With `gh` logged out on the host, a forced deploy failure still produces a notification within 5 minutes that names the SHA and failing step.
- [ ] Disabling the timer causes the heartbeat check to alert once its 13-hour period passes.

### I-067 - Back up Postgres and `caddy-data` nightly, encrypted and off-box, with a restore test

**Covers:** OPS-03, SEC-26 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Now · **Executor:** Owner · **Depends on:** –

**Problem.** Postgres lives in the compose volume `postgres-data` (`projects/sauna/docker-compose.yml:105-106,133`), and a repo-wide search for `pg_dump|pg_basebackup|backup|restore|wal-g|pgbackrest` finds nothing. In an event-sourced design the `events` table is the only source of truth and can't be rebuilt. The `caddy-data` volume holds the TLS private keys and ACME account key (`docker-compose.yml:31,125-131`) and isn't backed up either, so losing it forces re-issuance and can hit the duplicate-certificate rate limit (SEC-26). This compose file is also the production template.

**Proposed change.**
- Add a nightly systemd user timer that runs `pg_dump -Fc` and archives `caddy-data`, plus a dump before each deploy (before `deploy-environment.sh:357`). Keep 14 days locally.
- Ship both off the host with restic (encrypted) to object storage, with the restic password and storage credentials kept off this box.
- Add a monthly job that restores the latest dump into a throwaway container, runs `SELECT count(*) FROM events`, and pings the I-066 heartbeat.
- Write `dev-ops/disaster-recovery.md`: RPO/RTO, backup locations, where secrets live, host rebuild, certificate revocation (treat the key as exposed while agents have Docker access), and PITR for production (I-077).
- Removing Docker access from the factory user (the real SEC-26 fix) is tracked with SEC-03/OPS-16; CAA binding is in I-085.

**Acceptance criteria**
- [ ] `systemctl --user list-timers` shows the backup timer, and a dump exists for each of the last three nights.
- [ ] `restic snapshots` on the off-box repository lists snapshots containing both the database dump and the `caddy-data` archive.
- [ ] One restore test has run, with `SELECT count(*) FROM events` returning a non-zero count, and the heartbeat recorded it.
- [ ] Local dumps older than 14 days are removed.
- [ ] `dev-ops/disaster-recovery.md` exists and covers each item listed above.

### I-068 - Deploy only CI-green, tagged images with rollback

**Covers:** OPS-04, OPS-18 · **Labels:** `dev-ops`, `heavy-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-004, I-070

**Problem.** `deploy-environment.sh:310-319` deploys `origin/main` HEAD whatever its check status, and `:358` runs `docker compose up -d --build --remove-orphans` on untagged images (`build:` with no `image:`, `docker-compose.yml:41,57,79`). A failed health check (`:376-383`) leaves the broken containers running, with no previous version to return to. Images are never built in CI or pushed to a registry (OPS-18), so QA rebuilds from source against whatever base images are current. The timer also runs the script from the checkout it is about to update (`install-deploy-timer.sh:83,115`), so a merged change to the script runs unreviewed on the next tick.

**Proposed change.**
- On merge to `main`, build the backend, frontend and sidecar images once in CI and push `ghcr.io/adamzki99/booking-{backend,frontend,sidecar}:<sha>`, with `packages: write` in that job only.
- Add `image: …:${IMAGE_TAG}` to the compose services. The deploy picks the newest `main` commit whose checks all passed, then runs `docker compose pull` and `up -d --no-build`.
- Take the pre-deploy dump (I-067), gate on `/readyz` and `/version` (I-070), and on failure redeploy the tag in `~/.local/state/booking-deploy-qa.last-good`.
- Run the deploy script from a pinned, reviewed copy. SPA asset retention is in I-116; promotion is in I-077.

**Acceptance criteria**
- [ ] A `test-deploy-environment.sh` case where the stubbed check runs fail for HEAD deploys the newest green parent instead.
- [ ] A test where the health check fails runs `up` with the previous tag and leaves the last-good file unchanged.
- [ ] After a deploy on the host, `docker compose ps --format '{{.Image}}'` shows `ghcr.io/…:<sha>` for all three services.
- [ ] A CI build failure on `main` produces no deploy, and running containers are unchanged.
- [ ] `systemctl --user cat booking-qa-deploy.service` shows an `ExecStart` path outside the deploy checkout.

### I-069 - Record deploy state with GitHub Deployments instead of commits to `main`

**Covers:** OPS-07, ST-05 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-005

**Problem.** `deploy-environment.sh:391-408` commits `dev-ops/environments.yaml` and runs `git push origin main`, so the QA box holds a credential that can write to an unprotected `main` (inferred to be the owner's token). The push races factory merges, and a rejected push leaves a local commit that the next run replays with `git rebase` (`:317`); #101 recorded two rebase failures. Each deploy commit also triggers a `Security` run. `last_deploy_status: "failed"` never reaches git, because the EXIT trap (`:275-279`) checks the file out again.

**Proposed change.**
- Create a GitHub Deployment per run for environment `qa` and post statuses `in_progress`, `success` or `failure`:
  ```bash
  id=$(gh api repos/adamzki99/booking-system/deployments --input - --jq .id <<JSON
  {"ref":"$SHA","environment":"qa","auto_merge":false,"required_contexts":[]}
  JSON
  )
  gh api "repos/adamzki99/booking-system/deployments/$id/statuses" -f state=success
  ```
- Remove the commit-and-push block and the `last_deploy*` fields; keep `environments.yaml` for static config only.
- Replace `checkout` plus `rebase` with `git fetch` plus `git reset --hard origin/main` (or a detached checkout).
- Narrow the box's credential to `deployments:write` and `issues:write` with read-only contents; coordinate with I-005. The running version comes from `/version` (I-070).

**Acceptance criteria**
- [ ] After a successful deploy, the latest `qa` deployment's newest status is `success` with the deployed SHA.
- [ ] After a forced failure, the latest status is `failure`.
- [ ] `grep -nE "git push|rebase" dev-ops/scripts/deploy-environment.sh` returns nothing.
- [ ] No commits by `booking-deploy` appear on `main` after the change is merged.
- [ ] `git push` from the deploy checkout using the box's credential fails with a permission error.

### I-070 - Make `/healthz` check the database, sidecar and running version

**Covers:** OPS-11, BE-16 · **Labels:** `backend`, `dev-ops`, `standard-build-task`, `bug` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** `handleHealthz` returns a constant `{"status":"ok"}` (`internal/server/server.go:108-110`), and the deploy polls it through Caddy's `:80` catch-all (`deploy-environment.sh:366-374`). A deploy passes with the sidecar down, the SPA missing, or an old container still answering, because nothing compares the running SHA with `DEPLOYED_SHA`. Config is loose too (BE-16): an invalid `PORT` or `SMTP_PORT` silently falls back (`config.go:35-46`), `DEV_MODE` has a two-step parse (`:59-67`), an empty `DATABASE_URL` still starts a server that answers "ok", and `Config.PublicBaseURL` is unused because `ical/http.go:187` reads the env directly.

**Proposed change.**
- Keep `/healthz` as liveness. Add `/readyz` (pings Postgres and the sidecar, reports projection checkpoint lag) and `/version` (returns the SHA passed as build arg `GIT_SHA`).
- Change `config.Load()` to `(Config, error)`: validate ports, simplify `DEV_MODE`, and require `DATABASE_URL` and `PUBLIC_BASE_URL` outside dev mode. Pass `PublicBaseURL` into `ical.HandleRegenerateToken`.
- Add compose `healthcheck:` for the backend and sidecar. The images are distroless, so add a `-healthcheck` flag to each binary rather than relying on `curl`.
- In the deploy, use `up --wait` and require `/readyz` 200, `/version == $DEPLOYED_SHA`, and the SPA root in `curl :$PORT/`. The HTTPS check is in I-084.

**Acceptance criteria**
- [ ] Go tests: `/readyz` returns 503 when the DB ping fails, 503 when the sidecar is unreachable, and 200 when both succeed.
- [ ] Go tests: `config.Load` returns an error for `PORT=abc`, and for an empty `DATABASE_URL` with `DEV_MODE` unset.
- [ ] A test shows the regenerated iCal URL uses `PUBLIC_BASE_URL` even when `X-Forwarded-Host` is set.
- [ ] `docker compose ps` on QA shows the backend and sidecar as `healthy`.
- [ ] A `test-deploy-environment.sh` case where `/version` returns a different SHA marks the deploy failed.

### I-071 - Add a migration version table and run migrations transactionally

**Covers:** BE-10, OPS-10 · **Labels:** `backend`, `standard-build-task`, `bug` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** `runMigrations` in `internal/eventstore/eventstore.go:223-253` sorts the embedded `*.sql` files and runs `pool.Exec` for each one on every backend start, with no `schema_migrations` table, no lock and no per-file transaction. It works only because all ten files are `CREATE … IF NOT EXISTS`. The first `ALTER TABLE` or backfill will crash-loop the backend or rerun a data change, a file that fails halfway leaves a partial schema, and replicas starting together would run DDL concurrently. CI tests only from an empty database.

**Proposed change.**
- Track applied migrations in `schema_migrations(version text PRIMARY KEY, applied_at timestamptz)`, take `pg_advisory_lock` around the run, and apply each pending file plus its version row in one transaction. Adopting `pressly/goose` or `golang-migrate` with `embed.FS` is also fine.
- Baseline existing databases: mark 0001–0010 as applied without running them again.
- Add a CI test that starts from the previous release's schema, applies new migrations, and runs projection catch-up.
- Document in `product/backend/README.md` that the `events` table is append-only and never altered destructively.

**Acceptance criteria**
- [ ] An integration test runs migrations twice; the second run executes no files and `schema_migrations` has one row per file.
- [ ] A test with a deliberately broken migration returns an error, leaves no partial schema change, and records no version row.
- [ ] A test running two migrators concurrently completes without errors.
- [ ] A test against a database with 0001–0010 already applied but no version table baselines them without re-executing.
- [ ] The upgrade-path test runs in backend CI.

### I-072 - Fit the shared host: stagger schedules, reclaim disk, set a resource budget

**Covers:** OPS-12 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner · **Depends on:** –

**Problem.** `dev-ops/README.md:366-385` budgets "below ~2.5 GB on the 3.2 GB dev host", but its own table gives SigNoz alone 3 GB of limits (ClickHouse 1536m, ZooKeeper 512m, server 512m, collector 512m), plus 1.4 GB for the booking stack. The deploy fires at `00,12:00` (`install-deploy-timer.sh:76`), the same minute as the hourly factory tick, so a Go and Node build starts together with OpenCode sessions twice a day. Nothing prunes images or build cache, and the booking services have no `logging:` limits, so disk only grows.

**Proposed change.**
- Measure real usage with host metrics (and per-container metrics from I-062), then right-size the limits, move SigNoz off the box, or replace it with a lighter stack. Record the decision.
- Make the README budget and table agree.
- Offset the deploy (add a minute option to `--times`, for example `00,12:30`) or take the factory's lock during deploys.
- Add `logging: { driver: json-file, options: { max-size: 20m, max-file: "3" } }` through an `x-common` anchor in `projects/sauna/docker-compose.yml`.
- Run `docker image prune -f --filter until=72h && docker builder prune -f --keep-storage 5GB` after a successful deploy. Disk and memory alerts are in I-058.

**Acceptance criteria**
- [ ] The sum of container memory limits on the host (from `docker inspect`) is at or below the budget in `dev-ops/README.md`, and the table total matches it.
- [ ] `systemctl --user list-timers` shows the deploy at a minute other than `:00`, or the deploy log shows it waiting on the factory lock.
- [ ] `docker inspect` shows `max-size=20m` on every booking container.
- [ ] After a deploy, `docker images -f dangling=true -q` returns nothing.
- [ ] `journalctl -k` shows no OOM kills during the 7 days after the change.

### I-073 - Make QA production-like

**Covers:** OPS-17 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-086, I-123 (mail sink)

**Problem.** QA runs `EMAIL_MODE=log` (`projects/sauna/.env.example:22`), and the Playwright tooling depends on it (`get-login-code.sh:128`), so the SMTP sender and outbox retry path are never exercised end to end. Host ports `80:80` and `443:443` are fixed (`docker-compose.yml:21-22`), which contradicts `environments.yaml:12-15` and `dev-ops/README.md:147-151` ("Every release branch gets one candidate environment … distinct port"). The parts most likely to break in production (email delivery, TLS, tunnel ingress) are the parts QA never runs.

**Proposed change.**
- Switch QA to `EMAIL_MODE=smtp` against the mail sink from I-123.
- Change `get-login-code.sh` and the Playwright helpers to read codes from the mail sink's API instead of scraping `docker compose logs`.
- Move the fixed `80`/`443` port mappings into an edge override file that only the edge environment lists, using the per-environment compose files from I-086.
- Other parts of OPS-17 are covered elsewhere: the Authelia stub in I-081, the tunnel being removed by the deploy in I-086.

**Acceptance criteria**
- [ ] After a login on QA, `docker compose logs backend` contains no `email (log mode, not sent)` line.
- [ ] A login on QA delivers a message that the mail sink's search API returns for that address.
- [ ] `grep -n "log mode" dev-ops/scripts/get-login-code.sh` returns nothing.
- [ ] With the mail sink stopped briefly, a booking confirmation is retried and arrives after it restarts (`notifications.retried` increases).
- [ ] `docker compose -f projects/sauna/docker-compose.yml config` publishes no fixed `80` or `443`; the edge override does.

### I-074 - Refuse log-mode email outside local development

**Covers:** SEC-06 · **Labels:** `backend`, `light-build-task`, `bug` · **Priority:** Now · **Executor:** Factory · **Depends on:** I-123 (mail sink)

**Problem.** `internal/config/config.go:47-50` defaults `EMAIL_MODE` to `log`, `internal/email/sender.go` accepts it with no environment check, and `.env.example:22` ships `EMAIL_MODE=log`. `log_sender.go:20` then logs the recipient, subject and full body, including login and email-change codes. Anyone with log access can log in as anyone, and when a deploy fails those logs have reached a public issue (#101). A production start without `EMAIL_MODE` would silently run in this mode.

**Proposed change.**
- Require `EMAIL_MODE` to be set explicitly, and allow `log` only with `DEV_MODE=true`:
  ```go
  case "log":
      if !cfg.DevMode { return nil, errors.New("EMAIL_MODE=log is only allowed with DEV_MODE=true") }
  ```
- In `LogSender`, log only `to` (or a hash of it) and `subject`, never `body`.
- Change `projects/sauna/.env.example` to `EMAIL_MODE=smtp` pointing at the I-123 mail sink, so QA keeps working; test logins move to the sink in I-073.
- Removing raw logs from deploy issues and scrubbing #101 are in I-002; `setup.sh` defaults are in I-078.

**Acceptance criteria**
- [ ] A Go test: `EMAIL_MODE=log` with `DEV_MODE` false fails at startup; with `DEV_MODE=true` it succeeds.
- [ ] A Go test: an unset `EMAIL_MODE` fails at startup outside dev mode.
- [ ] A Go test capturing `slog` output from `LogSender` finds no `body` key and no login code.
- [ ] `grep -n "EMAIL_MODE=log" projects/sauna/.env.example` returns nothing.
- [ ] The QA deploy passes its health check with the mail-sink configuration.

### I-075 - Seed QA with synthetic data and a configured admin bootstrap

**Covers:** OPS-19, SEC-08 · **Labels:** `backend`, `dev-ops`, `standard-build-task`, `bug` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

> **Sensitive.** This describes how anyone can take the admin account on any freshly deployed or reset instance; fix it first and file it afterwards with neutral wording ("configure the admin bootstrap explicitly"), or use a private security advisory.

**Problem.** `internal/auth/service.go:69-89` lets any email log in when no users exist (`count == 0`), and `service.go:175-178` then calls `BootstrapAdmin`, which creates that email as `RoleAdmin`. After a first deploy or a QA reset, whoever requests a code first becomes admin. Seeding exists but isn't wired up: `SeedDevUsers` needs `DEV_MODE` and `SEED_USERS_FILE` (`config.go:59,88`; `seed.go:51-57`), neither appears in the QA config, and `run-playwright.sh:75-76` requires a test account nobody documents how to create.

**Proposed change.**
- Bootstrap the admin only from configuration (`BOOTSTRAP_ADMIN_EMAIL` checked in `canLogin`, or a one-off CLI command). With no users and no configured address, nobody can log in and startup logs a warning.
- Commit `projects/sauna/config/seed-users.qa.json` with fictitious `@example.test` accounts for each role, mounted read-only.
- Let QA seed without `DEV_MODE=true`, because I-074 uses `DEV_MODE` to allow log-mode email.
- Document `TEST_USER_EMAIL` as a seeded account in `dev-ops/README.md`. A weekly reset from a fixture dump is optional (it also exercises I-067's restore).

**Acceptance criteria**
- [ ] A Go test: on an empty store with `BOOTSTRAP_ADMIN_EMAIL=a@example.test`, a code request for `b@example.test` is refused, and `a@example.test` logs in as admin.
- [ ] A Go test: on an empty store with no bootstrap address, no email can request a code.
- [ ] After a QA deploy on an empty volume, `GET /users` as the seeded admin lists an account for each role.
- [ ] A CI check fails if the seed file contains an address outside `@example.test`.
- [ ] QA's configuration does not set `DEV_MODE=true`.

### I-076 - Add an on-demand deploy trigger and deploy after each merge

**Covers:** OPS-20 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Later · **Executor:** Owner-reviewed PR · **Depends on:** I-068

**Problem.** The timer fires at only two fixed slots (`install-deploy-timer.sh:127-131`), and the only way to deploy on demand is a manual `systemctl --user start` over SSH. Twenty-nine commits landed on `main` between 2026-11-12 and 2026-11-19, so one deploy can bundle a dozen factory merges, which makes failures hard to bisect. `OnFailure=` is handled in I-066.

**Proposed change.**
- Add a `workflow_dispatch` workflow that creates a pending GitHub Deployment for a given SHA (using the I-069 mechanism). A short-interval timer on the box polls for pending deployments and runs the deploy, so the home box needs no inbound webhook.
- Add a continuously updated "dev" tier that polls every 10 minutes for a new green SHA and deploys it, and keep the twice-daily "QA" tier for human testing. This needs the per-environment ports from I-073/I-086, or a decision to make QA itself deploy after each green merge.
- Deploy only green, tagged images (I-068), at most one SHA per run.

**Acceptance criteria**
- [ ] `gh workflow run` with a green SHA makes `/version` on the target environment return that SHA within 15 minutes, with no SSH.
- [ ] After a green merge to `main`, the continuously updated environment serves that SHA within 20 minutes.
- [ ] A test of the poller shows it skips a SHA whose checks are not green and deploys at most one SHA per run.
- [ ] Deploy events (I-059) over one week show a median of 2 or fewer merges per deploy on the continuously updated environment.

### I-077 - Define a promotion path from QA to production

**Covers:** OPS-18 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Later · **Executor:** Owner · **Depends on:** I-068

**Problem.** `dev-ops/environments.yaml` defines only `qa`; the repo has no git tags and no GitHub releases, and the TLS and tunnel docs describe a "prod" the repo doesn't define. If production rebuilds from source, "tested on QA" doesn't carry over, because it builds at a different time against different base images. There is also no record of what runs where. I-068 builds and pushes images per SHA; this issue decides how a tested image becomes production.

**Proposed change.**
- Decide where production runs (its own host or compose project) and add a `prod` entry to `environments.yaml` with its backup policy, including WAL archiving or PITR (wal-g or pgBackRest, see I-067).
- Promote by retagging the exact digest QA tested (`crane tag … qa-passed`, then `prod`), gated on the post-deploy Playwright suite and a GitHub Environment `production` with required reviewers.
- Create a `release/*` tag and a GitHub release for each promotion.
- Update `tls-letsencrypt.md` and the tunnel doc to describe the defined production setup.

**Acceptance criteria**
- [ ] A GitHub Environment `production` exists with the owner as a required reviewer.
- [ ] After a promotion, `crane digest …:prod` equals the digest of `…:qa-passed` for each image.
- [ ] `environments.yaml` contains a `prod` entry with its backup policy.
- [ ] `git tag -l 'release/*'` and `gh release list` each show the first promotion.
- [ ] The promotion workflow refuses a digest with no passing Playwright run.

### I-078 - Make `setup.sh` safe by default and fix stale documentation

**Covers:** OPS-22, SEC-16, OPS-05 · **Labels:** `dev-ops`, `documentation`, `light-build-task`, `bug` · **Priority:** Later · **Executor:** Factory · **Depends on:** –

**Problem.** `projects/sauna/setup.sh` installs Docker with `curl -fsSL https://get.docker.com | sh` as root (`:36`), copies `.env.example` with `POSTGRES_PASSWORD=change-me` and `EMAIL_MODE=log` and only warns (`:49-51`), then runs `docker compose up -d --build` as project `sauna` (`:60`), which blocks the `booking-qa` ports. The deploy calls it when the checkout is missing (`deploy-environment.sh:267-270`), but it exits unless run as root (`:11-14`). Docs are stale: a cron schedule (`setup.sh:4-8`), "Docker Desktop" (`dev-ops/README.md:149`), a real username (`:112-135`), and protection that doesn't exist (`:270-272`, `:291`, `:293-294`, `.github/workflows/README.md`; OPS-05).

**Proposed change.**
- When `.env` is new, generate `POSTGRES_PASSWORD` with `openssl rand -base64 24`, set `EMAIL_MODE=smtp`, and exit without starting the stack until SMTP is filled in.
- Install Docker from the distro or Docker apt repo with GPG verification.
- Split root host bootstrap from environment provisioning; if `setup.sh` still runs compose, set `COMPOSE_PROJECT_NAME=booking-qa`. Have the deploy print provisioning instructions and alert instead of calling `setup.sh`.
- Fix the stale docs, replace usernames with `<deploy-user>`, and describe only the enforcement that exists. Making Semgrep and dependency review actually gate is not part of this issue.

**Acceptance criteria**
- [ ] `grep -n get.docker.com projects/sauna/setup.sh` returns nothing, and `shellcheck` passes on the script.
- [ ] A stubbed test run creates an `.env` whose `POSTGRES_PASSWORD` is not `change-me` and whose `EMAIL_MODE` is not `log`, and exits non-zero without `docker compose up` while `SMTP_HOST` is empty.
- [ ] A `test-deploy-environment.sh` case with a missing checkout alerts and does not invoke `setup.sh`.
- [ ] `grep -rnE "lasrvr|Docker Desktop|conversation resolution|Semgrep instance also runs" dev-ops/README.md .github/workflows/README.md projects/sauna/setup.sh` returns nothing.

### I-079 - Scan container images for vulnerabilities in CI

**Covers:** OPS-21 · **Labels:** `dev-ops`, `light-build-task`, `enhancement` · **Priority:** Later · **Executor:** Owner-reviewed PR · **Depends on:** I-080

**Problem.** No Trivy or Grype scan runs on any built image. Images float: `caddy:2-alpine` (`projects/sauna/docker-compose.yml:10`), `postgres:16-alpine` (`:94`), `authelia/authelia:latest` (`:115`), `cloudflare/cloudflared:latest` (`docker-compose.cloudflare-tunnel.yml:23`), and base images have no digest. The deploy runs `up --build` without `--pull`, so QA keeps whatever base layers were first cached, and `security.yml:43` installs `govulncheck@latest`.

**Proposed change.**
- After the image builds from I-080, run `aquasecurity/trivy-action@<sha>` on each image with `severity: CRITICAL,HIGH` and `exit-code: 1`.
- Pin compose and base images by `@sha256:` digest. Dependabot's `docker` ecosystem keeps them fresh (ST-07); action SHA-pinning is part of that dependency-hygiene work.
- Add `--pull` to the deploy build, until I-068 pulls prebuilt images by SHA.
- Pin `govulncheck` to an exact version.
- Authelia is removed in I-081.

**Acceptance criteria**
- [ ] The Trivy job runs on every PR that builds images, and a canary PR with a known-vulnerable base image fails it.
- [ ] Every `image:` and `FROM` line under `projects/sauna/` and `product/` contains `@sha256:`.
- [ ] `grep -n "@latest" .github/workflows/*.yml` returns nothing.
- [ ] The deploy build command includes `--pull`, or I-068's pull-by-SHA is in place.

### I-080 - Validate compose and Caddy config, build every image and smoke-test the stack in CI

**Covers:** OPS-08 · **Labels:** `dev-ops`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-004

**Problem.** The deploy-script tests in `dev-ops/scripts/tests/test-*.sh` are run by no workflow (`grep "tests/test-" .github` returns nothing), and PRs #153–#155, which fixed #85, #86 and #89, ran only Security and Semgrep. No workflow runs `shellcheck`, `docker compose config` or `caddy validate`. Only the backend image is built (`backend-ci.yml:51-58`), and no job brings up the stack. Compose, Caddy and Dockerfile regressions surface only at the 00:00/12:00 deploy on the shared host.

**Proposed change.**
- Add `.github/workflows/deploy-ci.yml` with two jobs:
  - `scripts`: `shellcheck` on `dev-ops/scripts/*.sh` and `projects/sauna/*.sh`, then every `dev-ops/scripts/tests/test-*.sh`.
  - `stack`: `docker compose config -q`, `caddy validate` with the compose Caddy image, build all four Dockerfiles (backend, frontend, sidecar, `dev-ops/testing`), `up -d --build --wait` as project `ci`, then check `/healthz` and that `/` contains `<div id="root"`.
- Feed both jobs into the aggregate required check from I-004 so path filters can't deadlock it. Pin actions by SHA.

**Acceptance criteria**
- [ ] A canary PR that breaks one `dev-ops/scripts/tests` test fails `deploy-ci.yml`.
- [ ] A canary PR with an invalid Caddyfile fails the `stack` job.
- [ ] The `stack` job log shows all four images built.
- [ ] On `main`, the `stack` job passes the `/healthz` and SPA-root checks through Caddy.
- [ ] Both jobs are part of the required aggregate check from I-004.

## Epic H - TLS and edge

The Let's Encrypt integration itself is correct, but nothing forces clients onto TLS, nothing notices when renewal fails, and issuing a certificate advertises a QA host that has no access gate. These issues gate QA, make public HTTP redirect-only with security headers, fix proxy trust and client-IP handling, and record the exposure mode per environment.

### I-081 - Put QA behind an access gate and remove the Authelia stub

**Covers:** SEC-22, OPS-17, SEC-20 · **Labels:** `dev-ops`, `standard-build-task`, `bug` · **Priority:** Now · **Executor:** Owner · **Depends on:** –

> **Sensitive.** This explains how the QA host can be found through Certificate Transparency logs and which open doors it has; fix it first and file it afterwards with neutral wording ("add an access gate to QA"), or use a private security advisory.

**Problem.** In direct mode, which the deploy uses, Caddy gets a publicly trusted certificate for `SITE_ADDRESS` (`Caddyfile:47-49`), and the hostname appears in CT logs as soon as it's issued. Nothing in front of QA restricts access: Authelia is a stub (`config/authelia/configuration.yml` sets only `server.address`) behind an opt-in profile using `authelia/authelia:latest` (`docker-compose.yml:114-123`), and the docs call its role "TBD". A scanner then finds the app over plain HTTP, first-signup SigNoz, and first-login admin on an empty database.

**Proposed change.**
- Before `SITE_ADDRESS` gets a public name, set up one gate: Cloudflare Tunnel with Cloudflare Access (email OTP) and no published ports, Tailscale-only access, or Caddy `basic_auth` exempting `/healthz` (and `/calendar/*` if feed testing needs it).
- Remove the Authelia service, its config directory and README references until it has a designed role.
- Keep QA on synthetic data, and close first-login admin (I-075) and SigNoz exposure (I-003) before the first certificate.
- CAA and a DNS-01 wildcard are in I-085; image pinning (rest of SEC-20) is in I-079.

**Acceptance criteria**
- [ ] From a client outside the gate, `curl -sI https://<qa-host>/` returns 401 or a redirect to the access provider, not the app.
- [ ] `grep -rni authelia projects/sauna` returns nothing.
- [ ] `docker compose -f projects/sauna/docker-compose.yml config --profiles` lists no `authelia` profile.
- [ ] `dev-ops/README.md` names the chosen gate, how testers get access, and whether `/calendar/*` is exempt.
- [ ] Testers can reach QA through the gate and log in.

### I-082 - Restructure Caddy: loopback health listener, redirect-only port 80, security headers and HSTS

**Covers:** SEC-24, SEC-11, OPS-14, FE-11 · **Labels:** `dev-ops`, `standard-build-task`, `bug` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** I-084

**Problem.** `projects/sauna/config/Caddyfile:51-53` defines `:80 { import app }`, which serves the SPA, `/api/*` and `/calendar/*` over plain HTTP for any `Host`. `docker-compose.yml:20-21` publishes it on all interfaces as both `${PORT:-8080}` and `80`. It very likely shadows Caddy's automatic HTTP→HTTPS redirect (moderate confidence; check with `curl -sI http://$SITE_ADDRESS/api/healthz`), so login codes and bearer tokens can cross the network in cleartext. The Caddyfile has no `header` directive: no CSP, HSTS, `X-Content-Type-Options`, `Referrer-Policy` or `frame-ancestors`.

**Proposed change.**
- Replace the `:80` catch-all with an internal listener that answers only `/healthz` and returns 404 otherwise. Publish it as `127.0.0.1:${PORT:-8080}`, and keep `80:80` for the redirect and ACME HTTP-01 only.
- Add a `(security_headers)` snippet imported into `(app)`:
  ```caddy
  header {
      Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'"
      X-Content-Type-Options nosniff
      Referrer-Policy no-referrer
      -Server
  }
  ```
  `'unsafe-inline'` is needed for Chakra/Emotion styles.
- Add `Strict-Transport-Security` only after the HTTPS check from I-084 passes; start with a short `max-age` and raise it to a year.
- FE-11's caching, compression and asset retention are in I-116. Tunnel-mode ports and the cloudflared origin are in I-086.

**Acceptance criteria**
- [ ] `caddy validate` passes in CI (I-080).
- [ ] `curl -sI http://<site>/api/healthz` returns a redirect to `https://`, not 200.
- [ ] From another machine, port `${PORT}` is refused. On the host, `curl 127.0.0.1:${PORT}/healthz` returns 200 and `curl 127.0.0.1:${PORT}/` returns 404.
- [ ] `curl -sI https://<site>/` shows CSP, `X-Content-Type-Options`, `Referrer-Policy` and `Strict-Transport-Security`, and no `Server` header.
- [ ] Loading the SPA and logging in produces no CSP violations in the browser console.

### I-083 - Fix client-IP handling: narrow trusted_proxies, pass the real IP, rekey and bound the rate limiter

**Covers:** SEC-25, SEC-07, BE-05 · **Labels:** `backend`, `dev-ops`, `standard-build-task`, `bug` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

> **Sensitive.** This describes a cheap way to lock every resident out of login and a way to exhaust backend memory; fix it first and file it afterwards with neutral wording, or use a private security advisory.

**Problem.** Three copies of `clientIP` use `r.RemoteAddr` (`internal/server/server.go:254-260`, `internal/user/http.go:33-39`, `internal/ical/http.go:109-115`), which behind Caddy is always the Caddy container. So "per-IP" limits are global: about 20 code requests per hour for the whole association, and 30 feed fetches per hour for all subscribers. Per-email buckets charge every attempt (`auth/service.go:97-101,146-150`), and `ratelimit/limiter.go:41-44` never evicts keys. `trusted_proxies static private_ranges` (`Caddyfile:16-21`) in direct mode would let local or bridge-routed clients forge `X-Forwarded-For` once the real IP is passed through.

**Proposed change.**
- Make proxy trust explicit: `trusted_proxies static {$TRUSTED_PROXIES:127.0.0.1/32}` and `client_ip_headers {$CLIENT_IP_HEADER:X-Forwarded-For}`. In the tunnel overlay, give cloudflared a fixed address and use `Cf-Connecting-Ip`.
- Add `header_up X-Real-IP {client_ip}` to each `reverse_proxy`, and replace the three helpers with one `ClientIP(r, trustedProxies)` that trusts the header only from the configured proxy.
- Rekey: per-code attempt counters (invalidate after 5 failures) instead of per-email lockouts, and key the iCal limit on the token at a looser rate.
- Evict expired windows or use a bounded LRU. Requiring `PUBLIC_BASE_URL` is in I-070.

**Acceptance criteria**
- [ ] A Go test: `X-Real-IP` is used from a trusted proxy address and ignored from any other peer.
- [ ] A Go test: 21 code requests from 21 different client IPs within an hour all succeed.
- [ ] A Go test: after 100,000 random keys and window expiry, the limiter map is empty or capped.
- [ ] A Go test: 5 bad verifies invalidate that code, and the same email can still request a new one.
- [ ] On the host, a request with a forged `X-Forwarded-For: 1.2.3.4` through a published port is not logged or rate-limited as `1.2.3.4`.

### I-084 - Monitor the certificate lifecycle and remove the `admin@localhost` ACME contact

**Covers:** SEC-23 · **Labels:** `dev-ops`, `light-build-task`, `bug` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** The ACME contact defaults to `admin@localhost` (`Caddyfile:14`, `docker-compose.yml:27`), and `.env.example:48-50` ships `ACME_EMAIL=` empty. ACME servers reject non-public contact domains, so with a real `SITE_ADDRESS` registration and issuance will likely fail (not tested). The docs say the address receives expiry notices (`.env.example:48`, `tls-letsencrypt.md:24`), but Let's Encrypt stopped sending those in 2025. The deploy health check is plain HTTP and never touches the certificate, and nothing monitors expiry, so a failed renewal goes unnoticed until residents see certificate errors.

**Proposed change.**
- Remove the `admin@localhost` fallback from both files: drop the global `email` option when `ACME_EMAIL` is empty, or fail the deploy when `SITE_ADDRESS` is public and the contact is empty or `@localhost`. Fix the "expiry notices" wording.
- Add an HTTPS step to the deploy health check: `curl -fsS https://$SITE_ADDRESS/healthz` plus an `openssl s_client` expiry check that fails below 14 days, skipped for `localhost` and `http://` addresses.
- Add a daily timer that writes a `cert_expiry` event with `days_left` to the factory JSONL, with an alert at 14 days or fewer (I-058). An external uptime and TLS check is an acceptable alternative.
- Emit an event when Caddy logs `obtain` or `renew` errors, since Docker logs aren't shipped.

**Acceptance criteria**
- [ ] `grep -n "admin@localhost" projects/sauna/config/Caddyfile projects/sauna/docker-compose.yml` returns nothing.
- [ ] A `test-deploy-environment.sh` case where the stubbed HTTPS check fails marks the deploy failed and alerts.
- [ ] A test with a stubbed certificate expiring in 10 days fails the deploy with a message naming the days left.
- [ ] `cert_expiry` events appear in SigNoz daily, and an alert rule fires when `days_left` is 14 or fewer.
- [ ] `grep -rn "expiry/abuse notices" projects/sauna/.env.example dev-ops/tls-letsencrypt.md` returns nothing.

### I-085 - Add CAA records and consider a DNS-01 wildcard certificate

**Covers:** SEC-22 · **Labels:** `dev-ops`, `light-build-task`, `enhancement` · **Priority:** Later · **Executor:** Owner · **Depends on:** I-081

**Problem.** No CAA records are documented, so any CA can issue for the booking domain and any ACME account can request certificates over HTTP-01. Each HTTP-01 certificate also names the QA host in CT logs (`tls-letsencrypt.md:19-23`). The access gate in I-081 is the real fix for exposure; this issue adds the DNS-level hardening on top.

**Proposed change.**
- Add CAA records limiting issuance to Let's Encrypt, bound to the ACME account (RFC 8657 `accounturi`), with the validation method pinned and an `iodef` contact:
  ```dns
  booking.example.com.  CAA 0 issue "letsencrypt.org; accounturi=https://acme-v02.api.letsencrypt.org/acme/acct/<ACCOUNT_ID>; validationmethods=http-01"
  booking.example.com.  CAA 0 issuewild ";"
  booking.example.com.  CAA 0 iodef "mailto:security@example.com"
  ```
- Decide on a DNS-01 wildcard (`*.booking.example.com`) so CT shows only the wildcard. That needs a Caddy image built with a DNS-provider module and a zone-scoped API token kept out of the shared `.env`. If adopted, switch to `validationmethods=dns-01` and allow `issuewild`.
- Record the account ID, the decision and the steps in `dev-ops/tls-letsencrypt.md`.

**Acceptance criteria**
- [ ] `dig CAA booking.<domain>` returns an `issue` record with `accounturi` and `validationmethods`.
- [ ] A certificate request for the domain from a fresh ACME account against Let's Encrypt staging fails with a CAA error.
- [ ] `dev-ops/tls-letsencrypt.md` records the wildcard decision and the ACME account ID.
- [ ] If the wildcard is adopted, a CT search shows new certificates only for `*.booking.<domain>`, and the DNS token is scoped to that one zone.

### I-086 - Record the exposure mode per environment and stop the deploy dropping the tunnel

**Covers:** SEC-27, SEC-11, OPS-17 · **Labels:** `dev-ops`, `standard-build-task`, `bug` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** The deploy runs only the base file with `--remove-orphans` (`deploy-environment.sh:324,358`). If QA was started with `docker-compose.cloudflare-tunnel.yml`, the next timer deploy removes `cloudflared` as an orphan, and Caddy reverts to direct mode with published ports, silently changing the exposure model. Even in tunnel mode the override changes only `SITE_ADDRESS` (`docker-compose.cloudflare-tunnel.yml:14-20`), so Caddy's host ports stay published and the origin is reachable past Cloudflare (SEC-11). Fixed `80:80`/`443:443` (`docker-compose.yml:21-22`) also mean a second environment can't start on the same host.

**Proposed change.**
- Add `compose_files: [...]` and `tls: tunnel|direct|dns01` to each environment in `dev-ops/environments.yaml`, and pass every listed file as `-f` in the deploy.
- Add a preflight that refuses to deploy, and alerts, when the running stack's mode differs from the recorded one (for example, `cloudflared` running but the mode is `direct`).
- In the tunnel override, remove Caddy's published ports (`ports: !reset []`) and point cloudflared at the internal listener from I-082.
- Decide how several environments share a host: one edge Caddy per host with its own `caddy-data`, or DNS-01 per environment. Record it in `tls-letsencrypt.md`. Moving fixed ports into an edge override is in I-073.

**Acceptance criteria**
- [ ] A `test-deploy-environment.sh` case with a tunnel environment asserts compose is called with both `-f` files.
- [ ] A test where `cloudflared` is running but the mode is `direct` aborts before `up` and calls the alert stub.
- [ ] On a host in tunnel mode, `docker ps` still shows `cloudflared` after a timer deploy.
- [ ] In tunnel mode, `docker compose … config` shows no published ports for `caddy`, and `curl http://<host-ip>/` from another machine is refused.
- [ ] `dev-ops/tls-letsencrypt.md` records the multi-environment edge decision.

## Epic I - Backend: event-sourcing integrity

The event log is the system of record, but the event, the projection update, the checkpoint and the email enqueue are four separate writes. These issues make sure no event is skipped, a committed command is never reported as failed, and side effects can be replayed from the log.

### I-087 - Stop the projection runner from skipping events

**Covers:** BE-01 · **Labels:** `backend`, `heavy-build-task`, `bug` · **Priority:** Now · **Executor:** Factory · **Depends on:** –

**Problem.** Event IDs come from `BIGSERIAL` inside the append transaction (`internal/eventstore/eventstore.go:107-131`), so they can commit out of order. The runner skips `if event.ID <= checkpoint { continue }` (`internal/projection/runner.go:147`) and advances every checkpoint (`runner.go:155`). If id 102 publishes before 101, 101 is skipped for good. `handleLocked` returns on the first error in a map loop (`runner.go:128-135`), and `CatchUp` calls `os.Exit(1)` on any error (`cmd/server/main.go:81-85`), which crash-loops on a poison event. A skipped `booking.created` leaves the slot open to a double booking.

**Proposed change.**
- In `PostgresStore.Append`, take `SELECT pg_advisory_xact_lock($1)` right after `Begin` so that ID order matches commit order.
- Make `Handle` pull from the store (`LoadAfter(ctx, checkpoint)`: `WHERE id > $1 ORDER BY id LIMIT n`) instead of trusting the pushed batch.
- Apply each event and its checkpoint `UPDATE` in one transaction (`Apply(ctx, pgx.Tx, Event)`).
- Isolate failures: a failing projection stops at its own checkpoint, logs the event ID and does not block the others. `CatchUp` marks it degraded instead of exiting. Metrics are in I-060/I-061.

**Acceptance criteria**
- [ ] `go test ./internal/projection/...` includes a test where event N+1 commits and publishes before event N, and both are projected.
- [ ] A test makes one projection fail on an event and shows the other projections apply it and advance, while the failing one keeps its checkpoint below that event.
- [ ] A test shows `Apply` and the checkpoint write roll back together when either fails.
- [ ] Starting the server with a poison event in the log does not exit the process. The projection is logged as degraded, with the event ID.
- [ ] The PR is reviewed and approved by the owner before merge, because the event store is the system of record. The factory does not self-merge it.

### I-088 - Fix the create-booking advisory lock

**Covers:** BE-02 · **Labels:** `backend`, `standard-build-task`, `bug` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** `PostgresStore.Lock` holds a pooled connection while blocking on a session-level `SELECT pg_advisory_lock($1)` (`internal/eventstore/eventstore.go:148-171`). The lock holder then needs more connections for the overlap checks, `Append`, 8×`Apply` and 8×`checkpoints.Set` (`internal/booking/commands.go:102-122`, `internal/command/service.go:99-115`). The pool uses pgx defaults (`eventstore.go:256`, no `pool_max_conns` in `projects/sauna/.env.example:11`). With four concurrent bookings on a 2-vCPU host, the holder blocks in `Acquire` and the whole API stalls, since there is no `lock_timeout` and no handler timeout. Only `CreateBooking` implements `LockKey` (`commands.go:42-45`). `BlockTimePeriod` and the cancel commands are not serialized.

**Proposed change.**
- Run the decision in one transaction on one connection: `SET LOCAL lock_timeout = '3s'`, `pg_advisory_xact_lock(CreateBookingLockKey)`, then the overlap, blocked-period and sidecar checks, the event insert and the bookings projection on the same `tx`. This needs a transaction-aware handler signature, e.g. `Handler func(ctx, tx pgx.Tx, cmd)`.
- Delete the session-level `Lock`.
- Return 503 with `Retry-After` when the lock times out.
- Set `pool_max_conns` explicitly in the deployment `DATABASE_URL` (`.env.example`).
- Put `BlockTimePeriod` and the cancel commands under the same lock key.

**Acceptance criteria**
- [ ] A Postgres integration test runs more concurrent `CreateBooking` calls than `pool_max_conns` and all complete or return 503 within 5 s. None hang.
- [ ] A test holding the lock past `lock_timeout` gets HTTP 503 with a `Retry-After` header.
- [ ] A concurrent `BlockTimePeriod` + `CreateBooking` test on the same slot never leaves both recorded.
- [ ] `grep -rn "pg_advisory_lock(" product/backend/internal` returns no matches. Only `pg_advisory_xact_lock` remains.
- [ ] `projects/sauna/.env.example` sets `pool_max_conns` in `DATABASE_URL`.

### I-089 - Add idempotency keys to commands

**Covers:** BE-03 · **Labels:** `backend`, `standard-build-task`, `bug` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** `Execute` appends and then publishes, and it returns the publish error (`internal/command/service.go:105-115`). Any projection, checkpoint or subscriber error becomes a 500, even though the event is already permanent. The dispatcher stops at the first failing subscriber (`internal/dispatcher/dispatcher.go:28-35`), and the runner is first (`internal/registry/registry.go:31`), so a projection error also stops the notifiers. `CreateBooking` makes a new ID on every call (`internal/booking/service.go:59`), and there is no idempotency key. A user who retries after a 500 creates a second booking. A retried broadcast emails every resident again.

**Proposed change.**
- After a successful `Append`, `Execute` returns success with the recorded events. Projection and notifier errors are logged and retried by the runner's catch-up (see I-087), not returned.
- Make the dispatcher call every subscriber and collect the errors, instead of stopping at the first.
- Accept an optional `Idempotency-Key` header on `POST /bookings` and `POST /broadcast`. Store it with the event, with a unique index on `(event_type, idempotency_key)`. A repeated key returns the original result. Where the key lives (column or `metadata`) should match I-092 if that lands first.

**Acceptance criteria**
- [ ] A test with a failing projection shows `POST /bookings` returns 201 and the event is in `events`.
- [ ] A test with a failing first subscriber shows later subscribers (the notifiers) still run.
- [ ] Two `POST /bookings` requests with the same `Idempotency-Key` produce one `booking.created` event and the same response body.
- [ ] The same holds for `POST /broadcast`: one event and one set of outbox rows.
- [ ] A migration adds the unique index, and a test shows a duplicate insert is rejected.

### I-090 - Write outbox rows in the same transaction as the event

**Covers:** BE-04 · **Labels:** `backend`, `standard-build-task`, `bug` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** Notifiers run as dispatcher subscribers after the event transaction has committed (`internal/booking/notify.go:32`, `internal/broadcast/notifier.go:73`). They call `Enqueue` in a separate statement (`internal/notification/postgres.go:15-29`) and only log failures: "an enqueue error is logged and never surfaced" (`notify.go:19-21`). Notifiers have no checkpoint, so `CatchUp` and `RebuildAll` never call them again. A crash between commit and enqueue, or a projection failure first (BE-03), loses the email without a trace. `enqueueCancelled` reads the owner from the bookings projection (`notify.go:79-86`), so a skipped cancel also drops the notice. AGENTS.md requires a "durable `notification_outbox`".

**Proposed change.**
- Insert the outbox rows in the same transaction as the event append. Either reuse the transaction-aware command path (see I-088) or add a hook in `command.Service` that lets a command return outbox rows written on the append `tx`.
- Keep the existing `UNIQUE (event_id, kind, recipient_email)` key so enqueue stays idempotent.
- Add the owner's user ID to `BookingCancelledPayload`, so the cancellation notice needs no projection lookup.
- Remove the post-commit `Enqueue` calls from the dispatcher subscribers.

**Acceptance criteria**
- [ ] A test that makes the append transaction fail after the outbox insert leaves neither the event nor the outbox row.
- [ ] A test with a failing projection still shows the `booking.created` outbox row present.
- [ ] A test cancels a booking whose `bookings` row is missing and still finds a cancellation outbox row for the owner.
- [ ] `grep -n "Enqueue" product/backend/internal/booking/notify.go product/backend/internal/broadcast/notifier.go` shows no post-commit enqueue calls.

### I-091 - Make email delivery retries robust

**Covers:** BE-06 · **Labels:** `backend`, `light-build-task`, `bug` · **Priority:** Next · **Executor:** Factory · **Depends on:** I-090

**Problem.** Retry defaults are `MaxAttempts 5`, `BaseDelay 1s`, `MaxDelay 1m` (`internal/notification/worker.go:14-16`, `internal/config/config.go:51-52`), so a row is marked `failed` (`worker.go:128-135`) within about 30–40 s. A one-minute SMTP outage permanently fails every confirmation sent during it, and nothing re-drives failed rows. `SMTPSender.Send` ignores `ctx` and calls `smtp.SendMail` with no dial or IO timeout (`internal/email/smtp_sender.go:44-55`), so one hung server blocks the single worker. The 30 s lease (`internal/notification/outbox.go:33`) can expire mid-batch of 50 sends, which risks a double send. A permanent `550` is retried like a timeout.

**Proposed change.**
- Change the defaults to about `MaxAttempts 10`, `BaseDelay 30s`, `MaxDelay 1h`, with jitter, which spans about a day.
- Classify SMTP 5xx replies as permanent and fail them at once.
- Dial with `net.Dialer{Timeout: 10*time.Second}` and set `conn.SetDeadline`, or use a context-aware mail library.
- Size the lease to the batch's worst-case send time, or claim one row per send.
- Add an admin endpoint or CLI to list and requeue `failed` rows (`Store.List` exists but has no caller).

**Acceptance criteria**
- [ ] A unit test asserts the default schedule's total retry window is at least 12 h.
- [ ] A test with a fake SMTP server returning `550` marks the row `failed` after one attempt. A `421` reply is retried.
- [ ] A test against a server that accepts TCP and never replies returns within the configured timeout.
- [ ] A test shows a row cannot be re-claimed while its send is still in progress.
- [ ] The requeue path moves a `failed` row back to pending, and a test covers it.

### I-092 - Add per-aggregate versioning, optimistic concurrency and event schema versions

**Covers:** BE-07 · **Labels:** `backend`, `heavy-build-task`, `enhancement` · **Priority:** Later · **Executor:** Factory · **Depends on:** I-087

**Problem.** `events` has no `stream_version` and no per-aggregate uniqueness (`migrations/0001_create_events.sql`), and `Append` takes no expected version (`internal/eventstore/eventstore.go:92`). Every handler checks a read model, so concurrent check-then-append races get through. Two cancels both pass `b.Status != StatusActive` (`internal/booking/commands.go:181,224`). Concurrent `AddUser` with one email both pass (`internal/user/commands.go:238-242`), and the second `user.created` becomes a poison event on `users.email UNIQUE`. One login code can create two sessions. There is no schema version, so payload changes become fallbacks like `Role`/`NewRole` (`internal/user/events.go:81-82`, `internal/user/projection.go:193-196`).

**Proposed change.**
- Add `stream_version INT NOT NULL` with `UNIQUE (aggregate_type, aggregate_id, stream_version)`, backfilled for existing rows.
- Give `Append` an `expectedVersion` and map the unique violation to `ErrConcurrencyConflict` (HTTP 409).
- For cross-aggregate decisions such as email uniqueness, append to a reservation stream (`aggregate_type='email'`) with expected version 0.
- Add `schema_version SMALLINT DEFAULT 1` and `metadata JSONB` (actor, trace ID, idempotency key). Run one `eventstore.Upcast(event)` step before `Apply`, and move the `Role`/`NewRole` fallback into it.
- The migration alters an existing table, so it needs versioned migrations (BE-10) first. BE-10 currently reruns every file on every boot.

**Acceptance criteria**
- [ ] A test of two concurrent cancels of one booking records one `booking.cancelled` event. The other caller gets 409.
- [ ] A test of two concurrent `AddUser` calls with the same email records one `user.created` event.
- [ ] A test inserting a duplicate `(aggregate_type, aggregate_id, stream_version)` fails with `ErrConcurrencyConflict`.
- [ ] `internal/user/projection.go` no longer reads both `Role` and `NewRole`. A test shows the upcaster handles an old payload.

### I-093 - Add an operator-triggered projection rebuild

**Covers:** BE-20 · **Labels:** `backend`, `light-build-task`, `enhancement` · **Priority:** Later · **Executor:** Factory · **Depends on:** I-087

**Problem.** `Runner.Rebuild` and `RebuildAll` exist (`internal/projection/runner.go:75-116`) but only tests call them. There is no CLI flag or admin endpoint, so a projection that skipped an event (BE-01) can't be repaired in operation. `Reset` runs `TRUNCATE` on live tables before the replay (`internal/booking/projection.go:68-73`), so readers briefly see empty data. Append-only is enforced only by a source-grep test (`internal/eventstore/surface_test.go`). Nothing in the database stops `UPDATE` or `DELETE` on `events`.

**Proposed change.**
- Add a one-shot mode, `server -rebuild=<name|all>`, that rebuilds and exits with a non-zero status on failure.
- Wrap `Reset` and the replay in one transaction (using I-087's per-event transaction), or build into a shadow table and swap.
- Add a migration with a `BEFORE UPDATE OR DELETE ON events FOR EACH ROW` trigger that raises an exception.
- Optionally document running the app as a role with only `INSERT, SELECT` on `events`.
- Replace the source-grep guard with a test of the trigger.

**Acceptance criteria**
- [ ] `server -rebuild=bookings` against a test database with a deliberately emptied `bookings` table restores the rows and exits 0.
- [ ] A test shows a concurrent reader never sees an empty `bookings` table during a rebuild.
- [ ] A test running `UPDATE events SET ...` and `DELETE FROM events` fails with the trigger's error.
- [ ] `product/backend/README.md` documents the rebuild command.

### I-094 - Remove backend performance bottlenecks

**Covers:** BE-18 · **Labels:** `backend`, `standard-build-task`, `enhancement` · **Priority:** Later · **Executor:** Factory · **Depends on:** I-087

**Problem.** Every command takes the global `Runner.mu` (`internal/projection/runner.go:57-61`). For each of the 8 projections, it runs `checkpoints.Get`, then `Apply` and `checkpoints.Set` per event (`runner.go:140-159`). That is about 24 sequential round-trips per command, even for a login code request that touches only `login_codes`, and it serializes every write. `CatchUp` and `Rebuild` load the whole log with `LoadAll` (`internal/eventstore/eventstore.go:174-183`). The iCal feed renders every active booking ever made on every poll (`internal/ical/http.go:80`). None of this is urgent at HOA scale, but it matters before the product is reused.

**Proposed change.**
- Let projections declare their event types (`Handles() []string`) and skip both `Apply` and the checkpoint write for other types.
- Batch the checkpoint advance inside the I-087 transaction instead of one `Set` per event per projection.
- Stream catch-up and rebuild in pages (`WHERE id > $1 ORDER BY id LIMIT 1000`) instead of `LoadAll`.
- Bound the iCal feed to `now−30d … now+1y`. The unbounded `GET /bookings` default is in I-099.

**Acceptance criteria**
- [ ] A test counts database round-trips for a login code request and asserts only `login_codes` is touched (no `Apply` or checkpoint write for the other projections).
- [ ] `grep -n "LoadAll" product/backend/internal` shows no callers in catch-up or rebuild.
- [ ] A rebuild test over more than 1000 events passes using the paged loader.
- [ ] A feed test with a booking older than 30 days shows it excluded, and one 6 months ahead included.

## Epic J - Backend: auth, API and domain

These issues fix session handling and authentication storage, close gaps in the HTTP layer and configuration, and fix contract and domain defects that users can see, such as UTC email times and a capacity setting that has no effect.

### I-095 - Move sessions server-side: HttpOnly cookie, logout, revocation, rotation

**Covers:** SEC-10, BE-11, FE-14 · **Labels:** `backend`, `frontend`, `standard-build-task`, `enhancement` · **Priority:** Next · **Executor:** Factory · **Depends on:** – (relates to open issue #125, which shortens the session lifetime to 24 h)

**Problem.** The session token is stored in `localStorage` (`product/frontend/src/api/client.ts:1,15-34`), so any XSS can read it, and there is no CSP. Nothing ever writes `sessions.revoked_at` (`internal/auth/projection.go:162,183`), and there is no logout or revoke endpoint. "Log out" only clears storage (`SessionContext.tsx:67-70`), so a copied token keeps working until expiry (`internal/auth/service.go:16`). On an email change, sessions are re-keyed instead of revoked (`projection.go:154-169`). The middleware accepts a `session` cookie (`middleware.go:66`) that nothing sets, and POST routes have no CSRF or Origin check.

**Proposed change.**
- Issue the session as `Set-Cookie: session=…; HttpOnly; Secure; SameSite=Strict; Path=/api`. Stop storing the token in `localStorage`. Add an Origin check on state-changing routes.
- Add `POST /auth/logout`, which emits `auth.session_revoked` for the presented session, and "log out everywhere" for all of a user's sessions. Call logout from the frontend.
- Revoke other sessions on email or role change instead of re-keying them.
- Rotate the token on use. Absolute lifetime is set by #125. Add an idle timeout on top of it.
- Moving auth state out of the log and keying by user ID is I-096.

**Acceptance criteria**
- [ ] After `POST /auth/logout`, a request with the old token gets 401. A Go test covers this.
- [ ] A frontend test asserts `localStorage` holds no session token after login.
- [ ] The login response carries `HttpOnly`, `Secure` and `SameSite=Strict` on the `session` cookie.
- [ ] A POST with a foreign `Origin` header is rejected with 403.
- [ ] After an email change, a test shows the user's other sessions get 401.

### I-096 - Move login codes and sessions out of the event log, and key auth by user ID

**Covers:** BE-11, SEC-15 · **Labels:** `backend`, `heavy-build-task`, `enhancement` · **Priority:** Later · **Executor:** Factory · **Depends on:** I-095

**Problem.** Every code request appends `auth.login_code_issued` and every login appends `auth.session_created`, both with credential hashes (`internal/auth/commands.go:122-136,186-201`). They are permanent and replayed on rebuild. Identity is the email string: sessions are keyed by email (`migrations/0004_create_auth_tables.sql`), the context carries `email` (`internal/auth/middleware.go:50`), and auth events use the email as `aggregate_id` (`commands.go:95,160`), so PII sits in an indexed key that can never be erased. `login_codes` and `sessions` are never purged, and `notification_outbox` has no retention.

**Proposed change.**
- Write a short ADR: login codes and sessions become ordinary tables with TTL, and only security-relevant facts such as `user.logged_in` are recorded as events, keyed by user UUID. AGENTS.md already allows outbox-style operational tables.
- Key sessions and the request context on `user_id`. Resolve email only for display. Remove `auth.session_identity_changed`.
- Add retention jobs: `login_codes` older than 1 day, expired or revoked `sessions`, and delivered `notification_outbox` rows after a configured 30–90 days.
- In the ADR, record the erasure approach for PII already in `user.*` events (crypto-shredding with per-user keys, per SEC-15). Rewording the AGENTS.md "no deletes" rule changes agent config and needs owner review. The privacy notice, record of processing and DPAs are owner tasks.

**Acceptance criteria**
- [ ] After a login in a test, `events` contains no `auth.login_code_issued` or `auth.session_created` rows and no event with an email as `aggregate_id`.
- [ ] A test changes a user's email and shows the session still resolves to the same `user_id`, without re-keying.
- [ ] Retention tests show expired codes, expired sessions and old delivered outbox rows are removed.
- [ ] The ADR file exists under the repo's docs and covers credentials, identity key and erasure.

### I-097 - Limit attempts per login and email-change code

**Covers:** SEC-17 · **Labels:** `backend`, `light-build-task`, `enhancement` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** `POST /users/me/email/confirm` (`internal/user/http.go:212-242`, `auth.VerifyCodeHash` in `internal/user/commands.go` at about line 466) has no rate limit and no attempt counter during the 15-minute code lifetime (`internal/user/service.go:26`). Each attempt costs one CPU-bound bcrypt comparison. Login verify is rate-limited, but a login code is never invalidated after failed attempts. The report estimates the brute-force odds against 36^6 codes as low (≲10⁻³ per window). The larger risk is CPU pressure from one authenticated user. The proxy-IP limiter defect is handled in I-083.

**Proposed change.**
- Add an `attempts` count to the pending email-change and login-code state, and increment it on each failed verify.
- Invalidate the code after 5 failed attempts, and require a new code.
- Rate-limit `POST /users/me/email/confirm` per user, using the shared limiter.

**Acceptance criteria**
- [ ] A test submits 5 wrong login codes, then the correct one, and gets a rejection.
- [ ] The same test passes for the email-change confirm endpoint.
- [ ] A test shows confirm requests over the per-user limit get 429 without a bcrypt comparison.
- [ ] Requesting a new code after invalidation works, and a test covers it.

### I-098 - Restrict `GET /users` by role and minimise the personal data it returns

**Covers:** SEC-09 · **Labels:** `backend`, `frontend`, `light-build-task`, `bug` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

> **Sensitive.** This describes an authorization gap that is exploitable now on any deployment, so fix it first and file it afterwards with neutral wording, or track it in a private security advisory.

**Problem.** `GET /users` is wrapped only in `protect(...)` (`internal/server/server.go:52`), and `HandleListUsers` (`internal/user/http.go:67-85`) has no role check, unlike `HandleCreateUser` (`:129-133`). `userToMap` returns `email`, `address`, `role`, `active` and `deactivatedAt` (`http.go:321-337`). The frontend `/users` route needs only `RequireSession` (`product/frontend/src/App.tsx:33-41`). Any basic resident, or anyone with a stolen session, can download every resident's email and flat address. That is phishing material and a GDPR data-minimisation problem.

**Proposed change.**
- Require `RoleSuper` in `HandleListUsers` and return 403 otherwise.
- Guard the `/users` frontend route by role, so basic users don't see a page that would fail.
- If residents need a directory, add a separate opt-in projection with minimal fields (display name only). Don't widen `GET /users`.

**Acceptance criteria**
- [ ] A Go test: `GET /users` as a basic user returns 403, and as a super user returns 200.
- [ ] A frontend test: a basic user navigating to `/users` is redirected or shown an access-denied state, and no `/users` request is sent.
- [ ] If a directory endpoint is added, a test asserts its response contains no `email` or `address` keys.

### I-099 - Make the HTTP layer consistent: body limits, generic 5xx, one error format

**Covers:** BE-12, SEC-18, SEC-19 · **Labels:** `backend`, `standard-build-task`, `bug` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** `server.decodeJSON` caps bodies at 1 MiB (`internal/server/server.go:216-225`), but seven handlers use a bare `json.NewDecoder(r.Body).Decode` with no limit (`internal/booking/http.go:84,136`, `internal/broadcast/http.go:41`, `internal/user/http.go:124,186,226,265,301`). Raw `err.Error()` reaches clients, including 500s that wrap pgx and SMTP errors (`server.go:237-239`, `booking/http.go:57,90,112,141,157`, `ical/http.go:82`). The middleware returns plain-text 401s (`internal/auth/middleware.go:33-47`) while handlers return `{"error": …}`. `bookingToMap` emits both `user_id` and `userId` (`booking/http.go:183-201`). There are four JSON writers. `GET /bookings` with no range returns every active booking ever made (`booking/projection.go:127-162`).

**Proposed change.**
- Add `internal/httpx` with `Decode` (`http.MaxBytesReader`, `DisallowUnknownFields`), `JSON`, and `Error(w, err)`, which maps sentinel errors to a status and a stable code and returns `{"error":"internal error","requestId":…}` for everything else, with details logged.
- Use it in all handlers and in the session middleware. Delete the four duplicate writers. The shared `ClientIP` helper is in I-083.
- Choose camelCase (check the frontend first) and remove the duplicate snake_case keys.
- Default `GET /bookings` to `from=now-7d` and reject ranges over 1 year. The `PUBLIC_BASE_URL` part of SEC-19 is in I-100.

**Acceptance criteria**
- [ ] A test posts a 2 MiB body to each JSON endpoint and gets 413 or 400.
- [ ] A test forcing a database error asserts the 500 body is exactly the generic shape, with no driver text.
- [ ] A 401 from the middleware has `Content-Type: application/json` and an `error` field.
- [ ] `grep -rn "json.NewDecoder(r.Body)" product/backend/internal` returns nothing outside `httpx`.
- [ ] A test asserts booking responses contain no snake_case keys, and that the frontend tests still pass.

### I-100 - Validate configuration at startup and require `PUBLIC_BASE_URL`

**Covers:** BE-16, SEC-19 · **Labels:** `backend`, `light-build-task`, `bug` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** An invalid `PORT` or `SMTP_PORT` silently falls back to the default (`internal/config/config.go:35-46`), and `DEV_MODE` has an odd two-step parse (`config.go:59-67`). `Config.PublicBaseURL` is loaded but never used. `ical/http.go:187` reads `os.Getenv("PUBLIC_BASE_URL")` directly and otherwise builds the calendar URL from `X-Forwarded-Proto`/`X-Forwarded-Host`, so a caller can change the URL shown to themselves. If `DATABASE_URL` is empty, the server still starts and every route returns 503 (`cmd/server/main.go:54`). The SMTP password is a plain struct field that is passed around. It isn't logged today. The `/healthz` and `/readyz` part of BE-16 is in I-070.

**Proposed change.**
- Change to `config.Load() (Config, error)`, which rejects invalid ports and booleans, and exit non-zero on error.
- Outside dev mode, require `DATABASE_URL` and `PUBLIC_BASE_URL`.
- Pass `PublicBaseURL` into `ical.HandleRegenerateToken`, and delete the `os.Getenv` and forwarded-header fallback in `baseURL`.
- Wrap the SMTP password in a type whose `String`/`LogValue` returns `[redacted]`.

**Acceptance criteria**
- [ ] Table tests: `PORT=abc`, `SMTP_PORT=-1` and `DEV_MODE=maybe` each make `config.Load` return an error.
- [ ] With `DEV_MODE` off, starting without `DATABASE_URL` or `PUBLIC_BASE_URL` exits non-zero with a message naming the variable.
- [ ] A test sends `X-Forwarded-Host: evil.example` and asserts the returned calendar URL uses the configured base URL.
- [ ] `grep -rn 'Getenv("PUBLIC_BASE_URL")' product/backend/internal` returns nothing.
- [ ] A test asserts `slog` output of the config does not contain the SMTP password.

### I-101 - Fix the backend–sidecar contract

**Covers:** BE-09 · **Labels:** `backend`, `standard-build-task`, `bug` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** After the sidecar check, the backend always rejects any overlap (`HasOverlap`, `internal/booking/projection.go:82`, used at `internal/booking/commands.go:111-117`), so the sidecar's `SAUNA_CAPACITY` setting has no effect (`projects/sauna/sidecar/internal/server/server.go:148-150`). The request is only `{start, end, existing}` (`internal/sidecar/client.go:55-67`), with no user, role, user's bookings or time, so rules like "max N per week" can't be expressed. A 200 with an empty body counts as allowed (`client.go:87-89`), and an unset `SIDECAR_URL` silently disables every rule (`cmd/server/main.go:71-74`). The sidecar rejects a 22:00–00:00 booking as multi-day (`sidecar/.../server.go:142`), and an invalid `BOOKING_TIMEZONE` falls back to UTC (`server.go:189`).

**Proposed change.**
- Add a versioned endpoint, `POST /functions/v1/validate-booking`, with `candidate`, `user` (`id`, `role`), `now`, `existing` and `userBookings`.
- Remove the hard-coded `HasOverlap` rejection, or apply it only as a default when no sidecar is configured.
- Treat an empty or invalid 200 as `ErrSidecarUnavailable`. Log at startup when `SIDECAR_URL` is unset, and refuse to start without it outside dev mode.
- In the sidecar, compare dates using `end.Add(-time.Nanosecond)`, and make an invalid timezone a startup error.

**Acceptance criteria**
- [ ] With `SAUNA_CAPACITY=2`, an integration test books two overlapping slots successfully, and the third is rejected.
- [ ] A sidecar test accepts a 22:00–00:00 booking.
- [ ] A client test shows an empty 200 body results in 503, not an accepted booking.
- [ ] The sidecar exits non-zero with `BOOKING_TIMEZONE=Not/AZone`.
- [ ] A sidecar test receives `user.id` and `userBookings` in the request.

### I-102 - Send booking emails in Europe/Stockholm time

**Covers:** BE-08 · **Labels:** `backend`, `light-build-task`, `bug` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** The frontend sends `new Date(start).toISOString()`, which is always UTC (`product/frontend/src/pages/Calendar.tsx:72-73`). The notifier formats the time without converting it: `payload.Start.Format("2006-01-02 15:04")` (`internal/booking/notify.go:61`). The only timezone setting is in the sidecar (`BOOKING_TIMEZONE`), and the product has no display timezone. A Stockholm resident who books 18:00–19:00 is told "17:00 to 18:00" in winter and "16:00 to 17:00" in summer. This breaks happy-flow step 8 in `projects/sauna/README.md`.

**Proposed change.**
- Add `DISPLAY_TIMEZONE` to `config.Config`. Load it once with `time.LoadLocation`, and fail at startup if it is invalid (alongside I-100's validation).
- Set it to `Europe/Stockholm` in the sauna deployment's `.env.example` and compose file.
- Format email times as `start.In(loc).Format("Mon 2 Jan 15:04 MST")`, with the zone abbreviation, in all booking and cancellation emails.

**Acceptance criteria**
- [ ] A notifier test with `DISPLAY_TIMEZONE=Europe/Stockholm` and a booking at `2026-01-15T17:00:00Z` produces an email containing `18:00 CET`.
- [ ] The same test for `2026-07-15T16:00:00Z` contains `18:00 CEST`.
- [ ] Starting with `DISPLAY_TIMEZONE=Not/AZone` exits non-zero.
- [ ] `projects/sauna/.env.example` contains `DISPLAY_TIMEZONE=Europe/Stockholm`.

### I-103 - Close domain gaps for removed users, blocked periods and the last admin

**Covers:** BE-19 · **Labels:** `backend`, `standard-build-task`, `bug` · **Priority:** Later · **Executor:** Factory · **Depends on:** –

**Problem.** `user.removed` only flips `active` (`internal/user/projection.go:152-163`), so a removed user's future bookings keep blocking slots. A blocked period is never checked against existing bookings, can't be lifted, and can be in the past (`internal/booking/blocked.go:73-119`). Without a sidecar, booking length and horizon have no upper bound (`internal/booking/model.go:95-105`). `ChangeUserRole` lets an admin demote the last admin (including themselves), promote anyone to admin and change roles on deactivated users (`internal/user/commands.go:578-637`). The `STATUS:CANCELLED` feed branch is dead code (`internal/ical/feed.go:25-29`).

**Proposed change.**
- Add an `on user.removed` policy, driven by the checkpointed runner (I-087), that issues `CancelAnyBooking` for the user's future bookings.
- Make `BlockTimePeriod` reject past periods and return conflicting bookings so the super user can choose to cancel them. Add `LiftBlockedPeriod` with a `blocked_period.lifted` event.
- Forbid demoting the last admin and changing roles on deactivated users.
- Remove the dead `STATUS:CANCELLED` branch. Booking-length and horizon limits belong in the sidecar contract (I-101).

**Acceptance criteria**
- [ ] A test removes a user with two future bookings, and both are cancelled.
- [ ] A test blocks a period that overlaps a booking, and the response lists that booking.
- [ ] Lifting a block frees the slot for a new booking, and a test covers it.
- [ ] Demoting the only admin returns an error, and a test covers it.
- [ ] `grep -n "STATUS:CANCELLED" product/backend/internal/ical` returns nothing.

### I-104 - Remove the `sample` scaffolding package

**Covers:** BE-15 · **Labels:** `backend`, `light-build-task`, `enhancement` · **Priority:** Later · **Executor:** Factory · **Depends on:** –

**Problem.** `sample.Register(app)` runs in production `main` (`cmd/server/main.go:68`). Its projection is in every `Handle`, so every event costs an extra checkpoint read and write. Migration `0003_create_sample_items.sql` creates `sample_items`, and `projection_checkpoints` has a `sample_items` row. The sidecar still exposes `POST /functions/echo` (`projects/sauna/sidecar/internal/server/server.go:44`).

**Proposed change.**
- Delete the `sample` package and the `main.go` registration.
- Keep `0003` in place, since migrations must not be deleted. Add a later migration: `DROP TABLE IF EXISTS sample_items; DELETE FROM projection_checkpoints WHERE projection_name='sample_items';`. This touches only derived data, not events.
- Remove the sidecar's `/functions/echo` route and its tests.
- Move the "how to add a projection" example into `product/backend/README.md`.

**Acceptance criteria**
- [ ] `product/backend/internal/sample` no longer exists, and `go build ./...` and `go test ./...` pass.
- [ ] After migrating a test database, `sample_items` does not exist and `projection_checkpoints` has no `sample_items` row.
- [ ] `grep -rn "functions/echo" projects/sauna/sidecar` returns nothing.
- [ ] `product/backend/README.md` contains a section on adding a projection.

### I-105 - Consolidate drift in backend code

**Covers:** BE-13 · **Labels:** `backend`, `standard-build-task`, `enhancement` · **Priority:** Later · **Executor:** Factory · **Depends on:** I-042

**Problem.** `grep -i alias` finds 35 alias declarations in non-test code. `UsersProjection` has seven lookup names (`internal/user/projection.go:269-328`), `ChangeUserRole` has four aliases and takes `role any` (`internal/user/service.go:254-307`), and `ical` exports eight render and handler aliases. Error families like `ErrForbidden = ErrPermissionDenied = ErrNotAuthorized = ErrAccessDenied` (`internal/user/model.go:79-113`) are each checked in `userHTTPStatus`. Other drift: `p.Users = p` (`projection.go:18,123`), three `Deps` fields for one iCal service (`server.go:34-36`), `NewClient(baseURL string, opts ...any)` (`internal/sidecar/client.go:26-40`), mutable package globals (`user/commands.go:120-130`), 17 copies of the command type switch and three `NewID()`s with a non-UUID fallback that would be a poison event.

**Proposed change.**
- Delete the aliases and keep one sentinel error per meaning. Let the compiler find callers.
- Remove `p.Users = p`, the duplicate `Deps` fields, the `opts ...any` switch and the `defaultUsers`/`defaultChanges`/`defaultTokens` globals.
- Replace the 17 type switches with a generic `As[T command.Command]` helper, and the three `NewID()`s with `github.com/google/uuid`.
- Remove leftover musing comments (`config.go:64`, `sidecar/client.go:112`) and fix import grouping.
- Changes to CI lint gates and AGENTS.md belong to I-042. This issue makes the code pass whatever rules it adds.

**Acceptance criteria**
- [ ] `grep -rni "alias" product/backend/internal --include=*.go --exclude=*_test.go` returns no alias declarations.
- [ ] `grep -rn "command is nil" product/backend/internal` returns at most one match.
- [ ] `grep -rn "func NewID" product/backend/internal` returns nothing.
- [ ] `go vet ./...`, `go test ./...` and the lint configuration from I-042 pass.

### I-106 - Share one Postgres test harness and test the key failure modes

**Covers:** BE-14 · **Labels:** `backend`, `standard-build-task`, `enhancement` · **Priority:** Later · **Executor:** Factory · **Depends on:** I-015

**Problem.** The Postgres pool helper is copied 11 times (`newBookingTestPool`, `newAuthTestPool`, `newE2EPool`, …), and each package starts its own `postgres:16` container. With `DATABASE_URL` set, every package shares one database with no schema isolation, so count assertions (`SELECT count(*) FROM bookings …`) can interfere when packages run in parallel. `TestNoUpdateOrDeleteAgainstEvents` greps the source of `eventstore.go` (`internal/eventstore/surface_test.go`), which any other file can bypass. Key failure modes are untested. Adding `-race` to CI is in I-015.

**Proposed change.**
- Extract `internal/testutil/pg.go`: one container per `TestMain` and a fresh schema per test (`CREATE SCHEMA t_<rand>; SET search_path`). Replace the 11 copies with it.
- Add `-shuffle=on` to the test command.
- Add regression tests where they are not already added by their fix issues: out-of-order commits (I-087), one failing projection, publish failure after append (I-089), pool starvation under the lock (I-088), notifier loss (I-090), the sidecar midnight boundary (I-101), email timezone (I-102) and rate limiting behind a proxy (I-083).
- Replace the source-grep guard with the database-trigger test from I-093.

**Acceptance criteria**
- [ ] `grep -rn "func new.*TestPool\|func newE2EPool" product/backend/internal` returns nothing outside `testutil`.
- [ ] `DATABASE_URL=<one db> go test -shuffle=on -p 8 ./...` passes three runs in a row.
- [ ] Each failure mode listed above has a named test, listed in the PR description.
- [ ] `surface_test.go` no longer greps source files.

## Epic K - Frontend

The React SPA covers the happy flow, but it is still a prototype: it signs people out on transient errors, runs destructive actions in one tap, breaks in dark mode and is hard to use on a phone. These issues fix the defects first, then set up the shared structure the redesign (#120–#123) needs before the factory builds it.

### I-107 - Make session restore resilient and handle 401 responses globally

**Covers:** FE-01, FE-16 · **Labels:** `frontend`, `bug`, `light-build-task` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** `product/frontend/src/auth/SessionContext.tsx:39-45` clears the token on every rejected restore (`.catch(() => { // Token expired or revoked: treat as signed out. setToken(null); ...})`), so a network error, or a 502 or 503 during the hourly redeploy, logs the resident out. Logging in again needs a new emailed code (limited to 5 per 15 minutes, `auth/service.go:20-21`). Conversely, `api/client.ts:52-63` only throws `ApiError` and nothing reacts to a 401, so an expired token leaves the user on a page where every action fails. While restoring, `RequireSession.tsx:14-16` renders `null`, which shows a blank screen on slow networks (FE-16).

**Proposed change.**
- In `client.ts`, add `setUnauthorizedHandler(fn)`. On `res.status === 401`, clear the token and call the handler.
- In `SessionContext.tsx`, register the handler (set user to `null`). Clear the token on restore only for `ApiError` with status 401. For other errors, keep the token and expose a `restoreError`.
- When `restoreError` is set, show "Can't reach the server" with a Retry button instead of redirecting to `/login`.
- In `RequireSession.tsx`, show a centred `Spinner` while `loading` instead of `null`. The layout route and error boundary from FE-16 are in I-120. Server-side logout and the cookie path (FE-14) are in I-095.

**Acceptance criteria**
- [ ] A Vitest test where `currentUser()` rejects with a network `TypeError` asserts the token is still in `localStorage` and a Retry control is shown.
- [ ] A test where restore rejects with `ApiError(…, 401)` asserts the token is removed and the user is sent to `/login`.
- [ ] A test where an authenticated page gets a 401 mid-session asserts navigation to `/login`.
- [ ] A test asserts `RequireSession` renders a spinner (role `status` or the Chakra Spinner label) while `loading` is true.
- [ ] `npm test` and `npm run build` pass in `frontend-ci.yml`.

### I-108 - Confirm destructive actions and show progress and success feedback

**Covers:** FE-02 · **Labels:** `frontend`, `bug`, `standard-build-task` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** Cancel booking runs immediately (`pages/Calendar.tsx:84-92, 159-166`: `onClick={() => void onCancel(booking.id)}`), which contradicts `projects/sauna/README.md` alternative flow step 10, "The super user confirms the cancellation." `Remove` deactivates a user in one tap (`Users.tsx:90-97, 179-186`). `Broadcast` emails every basic user in one tap and then just clears the fields (`Users.tsx:137-146`). None of the forms in `Calendar.tsx:68-82` or `Users.tsx:78-146` disables itself while the request runs, so a double tap can create two bookings or send two broadcasts. Because the system is event-sourced with "no deletes", each mis-tap is permanent history and may email a resident. `Block` (`Users.tsx:123-135`) and `Copy` (`Account.tsx:99-106`) give no success feedback either.

**Proposed change.**
- Add a reusable `ConfirmDialog` (Chakra `AlertDialog`) that names the object, for example "Cancel Tue 17 Nov 09:00–10:00 booked by anna@…? They will be emailed."
- Require it for cancelling (your own or someone else's booking), removing a user and broadcasting (show the recipient count).
- Add one mutation helper that disables the trigger while pending and calls `useToast()` on success and failure. Use it for create booking, cancel, add user, remove, block, broadcast and copy. I-114 can later replace it with its data layer.
- Land this before #122 moves cancel into a `Menu`.

**Acceptance criteria**
- [ ] RTL tests for cancel, remove and broadcast assert the API function is not called until the dialog's confirm button is clicked, and is not called after Cancel.
- [ ] The broadcast dialog text includes the number of basic users who will receive it (asserted in a test).
- [ ] A test clicks "Create booking" twice quickly and asserts `createBooking` is called once.
- [ ] Tests assert a success toast appears after create, cancel, remove, block, broadcast and copy.

### I-109 - Fix admin selects that send an empty user ID

**Covers:** FE-03 · **Labels:** `frontend`, `bug`, `accessibility`, `light-build-task` · **Priority:** Now · **Executor:** Factory · **Depends on:** –

**Problem.** `pages/Users.tsx:47` and `:51` initialise `addressUserId` and `roleUserId` to `""`, and the selects at `:231-244` and `:268-281` have no placeholder option. The browser shows the first email as selected while state stays `""`, so submitting without touching the select calls `changeUserAddress("", …)` and builds `PATCH /api/users//address` (`api/users.ts:50`). This breaks the most direct super-user task, "Change the address of a basic user", on first use. The tests always pick an option first (`Users.test.tsx:69, 109, 142`), so they miss it. On the same page, the visible label "User id" is overridden by `aria-label="User"` (`:230-233`) and the list shows emails. Inactive users still get `Remove` (`:177`), the action column has no `<Th>` (`:163-168`), and "Active" renders as raw `true`/`false` (`:176`).

**Proposed change.**
- Add `<option value="" disabled>Choose a member…</option>` to both selects and disable submit until an id is chosen.
- Remove the conflicting `aria-label` and rename the visible label to "Member".
- Hide `Remove` when `!u.active`, add `<Th><VisuallyHidden>Actions</VisuallyHidden></Th>`, and render the status as a `Badge` ("Active"/"Inactive").

**Acceptance criteria**
- [ ] A regression test submits each form without choosing a member and asserts `changeUserAddress` / the role-change call is not made and submit is disabled.
- [ ] `getByLabelText("Member")` finds both selects in a test.
- [ ] A test with an inactive user asserts no `Remove` button is rendered in that row.
- [ ] A test asserts the table has a column header named "Actions" and that status renders as "Active"/"Inactive", not `true`/`false`.

### I-110 - Fix dark mode and colour contrast

**Covers:** FE-04, FE-10 · **Labels:** `frontend`, `bug`, `accessibility`, `light-build-task` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** `theme.ts:41-44` sets `initialColorMode: "system", useSystemColorMode: true` and `index.css:4-6` declares `color-scheme: light dark`, but the semantic tokens only define `default` values (`theme.ts:74-87`) and the body is forced to the light canvas (`theme.ts:99-104`). On a phone in dark mode, Chakra's components switch to dark palettes on a light page. The iCal URL in `Code` (`Account.tsx:175`) renders `gray.200`, and outline red buttons ("Cancel booking", "Remove", "Log out") render `red.200` at about 1.6:1. The report verified these values by reading Chakra v2's default theme, not by rendering. Separately (FE-10 contrast part), the input border `line` #E9DDD5 on white is 1.33:1, below WCAG 1.4.11's 3:1, and the `accentTint` focus halo on white is about 1.2:1. The rest of FE-10 is in I-115.

**Proposed change.**
- Make the app light-only until dark tokens exist: `config: { initialColorMode: "light", useSystemColorMode: false }` and `:root { color-scheme: light; }`.
- Darken the input border token to reach at least 3:1 against white (for example use `muted`), and use `accent` for the focus ring.
- If dark mode is wanted later, every semantic token needs a `_dark` value, tested with Playwright `colorScheme: "dark"` (I-124).

**Acceptance criteria**
- [ ] A test asserts `theme.config.useSystemColorMode === false` and `initialColorMode === "light"`.
- [ ] `index.css` contains `color-scheme: light` and not `dark`.
- [ ] A unit test computes the contrast ratio of the input border token against `#FFFFFF` and asserts it is at least 3:1.
- [ ] A unit test asserts the focus ring colour token against `#FFFFFF` is at least 3:1.

### I-111 - Re-plan redesign issues #120–#123 before they are built

**Covers:** FE-05 · **Labels:** `frontend`, `documentation`, `trivial-task` · **Priority:** Now · **Executor:** Owner · **Depends on:** –

**Problem.** Report 05 found that the `factory:plan` comments on #120–#123 (from GitHub issue) predate the theme work in `8566498` (#152) and the email-change rework in `dbaa86f` (#133). The #123 plan duplicates existing tokens and references a non-existent `updateMyEmail`. The #121 and #122 plans hardcode `bg="#EFE3D6"`, both rewrite `Calendar.tsx` and define `formatDayLabel` differently, and #121 breaks `login.spec.ts:14`. The mockups need data the API lacks (member names, notifications, search). All four are labelled `owner approved`, so the factory may build them as written.

**Proposed change.**
- Remove the `owner approved` label from #120–#123 now and add it back only after re-planning.
- Re-run planning on current `main` and require the existing tokens (`accent`, `accentTint`, `line`, `avatarBg`/`avatarFg`, `bgSubtle`) and recipes.
- Record the sequence I-120 (layout route) → #120 → #121 → #122 → #123, with shared formatters in `src/lib/datetime.ts` (I-113).
- Record decisions: the member display label, notifications (drop or stub), "Search members" as client-side `?q=` only, whether Quick book repeats only your own bookings with targets after today, the booking interaction for I-112, and the header/footer branding (sidecar chrome strings vs mockup).
- Add "`listBookings({ from: now })` for Upcoming" and "update `dev-ops/testing` specs" to the issues that need them.

**Acceptance criteria**
- [ ] `gh issue view 120..123 --json labels` shows no `owner approved` label until new plans are posted.
- [ ] Each of #120–#123 has a new `factory:plan` comment dated after `8566498` that contains no raw hex colours.
- [ ] Only one issue defines `formatDayLabel`, and the others reference `src/lib/datetime.ts`.
- [ ] Each owner decision listed above is recorded as a comment on the affected issue.
- [ ] Every issue that renames a heading, label or nav item has an acceptance criterion to update `dev-ops/testing` specs.

### I-112 - Make booking phone-friendly

**Covers:** FE-07 · **Labels:** `frontend`, `enhancement`, `standard-build-task` · **Priority:** Next · **Executor:** Factory · **Depends on:** I-111

**Problem.** Booking means filling in two independent `datetime-local` inputs with no `min`, no `step` and no default end (`Calendar.tsx:108-125`). On iOS that is two full wheel interactions, and past times are accepted until the backend rejects them. `listBookings()` has no range (`Calendar.tsx:55`), so the list grows forever and past bookings show "Cancel booking". Rows show only a time range, with no owner or "yours" marker (`:155-157`). Blocked periods are never shown although `GET /blocked-periods` exists (`server.go:65`), so residents find taken slots by trial and error (409). On phones the drawer is open by default (`AppShell.tsx:58, 81-114`) and the Users table scrolls horizontally at 390 px (`Users.tsx:160-193`). None of #120–#123 covers this.

**Proposed change.**
- Implement the booking interaction the owner chose in I-111: a date picker plus duration chips (for example 30/60/90 min) or day-slot chips in the deployment time zone (I-113), with `min` set to now.
- Query `listBookings({ from: startOfToday })`. Show "You" or the owner on each row.
- Fetch blocked periods and render them as unavailable. Show a `Skeleton` while loading.
- Close the drawer by default on small screens, and make the Users list readable at 390 px (cards or stacked rows).

**Acceptance criteria**
- [ ] A test asserts the booking form cannot submit a start time before now, and the end defaults to start plus the chosen duration.
- [ ] A test asserts `listBookings` is called with a `from` argument and no past booking is rendered.
- [ ] A test asserts each row shows "You" for the current user's bookings and the owner otherwise.
- [ ] A test with a mocked blocked period asserts it renders as unavailable.
- [ ] A Playwright run at 390×844 (I-124) shows no horizontal scroll on `/` and `/users` (`document.documentElement.scrollWidth <= 390`).

### I-113 - Show times in Europe/Stockholm, friendly error messages and i18n-ready strings

**Covers:** FE-08 · **Labels:** `frontend`, `bug`, `standard-build-task` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** The sidecar applies the single-day rule in `Europe/Stockholm` by default (`projects/sauna/sidecar/internal/server/server.go:143, 181`), but the SPA parses and renders in the browser's zone (`Calendar.tsx:34-43, 72-73`). A resident whose phone is set to another zone books the wrong hour, and the day-boundary rule disagrees with the UI near midnight. There are three date formats (hand-rolled `YYYY-MM-DD HH:mm`, `toLocaleString()` in `AppShell.tsx:48`, and the mockups' en-GB style) and no `Intl` use. Tests pin `TZ=UTC` (`tests.setup.ts:7`). Raw backend strings such as `booking: slot already booked` and `user: duplicate email` reach users. All strings are hardcoded English with `lang="en"`, while the mockups use Swedish branding.

**Proposed change.**
- Add `src/lib/datetime.ts` built on `Intl.DateTimeFormat(locale, { timeZone })`, with `timeZone` (and optionally `locale`) from `/api/chrome`, which the sidecar fills from `BOOKING_TIMEZONE`. Keep `product/` free of sauna defaults.
- Convert `datetime-local` input with that zone, not the browser's, and replace the three formatters.
- Add `describeError(err)` that maps `ApiError.status` and known backend messages to friendly text.
- Ask the owner whether the UI is English, Swedish or both. If it is Swedish or both, add a typed message dictionary before #120–#123 add more strings.

**Acceptance criteria**
- [ ] `/api/chrome` returns a `timeZone` field, covered by a sidecar test.
- [ ] A `datetime.test.ts` case with `TZ=America/New_York` asserts that 09:00 entered for a Stockholm deployment is sent as `07:00Z` or `08:00Z` depending on DST. The CI zone matrix is I-119.
- [ ] `grep -rn "toLocaleString\|toISOString().slice" product/frontend/src --include=*.tsx` finds no display formatting outside `src/lib/datetime.ts`.
- [ ] A test asserts `describeError` turns `booking: slot already booked` (409) into text without the `booking:` prefix.
- [ ] The owner's language decision is recorded on this issue.

### I-114 - Introduce a data-fetching layer with loading, error and cancellation states

**Covers:** FE-09 · **Labels:** `frontend`, `enhancement`, `standard-build-task` · **Priority:** Later · **Executor:** Factory · **Depends on:** –

**Problem.** Each page fetches in its own way. `Calendar.tsx:53-66` uses `useCallback` with no unmount guard, `Users.tsx:65-76` has an effect with missing deps, and `Account.tsx:34-49` refetches `currentUser()` that the session already holds. No authenticated page has a loading state, and `Account.tsx:32` shares one `busy` flag between two forms. `client.ts:68-76` returns `undefined as T` for an empty or unparseable 200 body, so a proxy or captive-portal HTML page later crashes at `list.map` (`bookings.ts:34`). There is no timeout or `AbortController`. #121 and #122 will add more parallel fetches to the same page.

**Proposed change.**
- Adopt `@tanstack/react-query` (or write one `useApi()`/`useMutation()` hook) that standardises `{data, error, isLoading}`, aborts on unmount, and gives each mutation its own busy flag. Invalidate `["bookings"]` after commands.
- Move Calendar, Users and Account to it. Account should read the user from the session.
- In `request()`, throw `ApiError("invalid response", res.status)` on a JSON parse failure, and pass `signal: AbortSignal.timeout(15000)`.
- Replace the interim mutation helper from I-108 if the new layer covers it.

**Acceptance criteria**
- [ ] A `client.test.ts` case where a 200 response has an HTML body asserts `request()` rejects with `ApiError` and message `invalid response`.
- [ ] A test asserts `fetch` receives an `AbortSignal`.
- [ ] Tests for Calendar, Users and Account assert a loading indicator renders before data resolves.
- [ ] A test asserts `Account` makes no `currentUser()` call when a session user exists.
- [ ] `grep -rn "useEffect" product/frontend/src/pages` shows no data-fetching effects.

### I-115 - Fix accessibility issues

**Covers:** FE-10 · **Labels:** `frontend`, `accessibility`, `bug`, `light-build-task` · **Priority:** Later · **Executor:** Factory · **Depends on:** –

**Problem.** `AppShell.tsx:106` renders `<main>`, and `Calendar.tsx:97`, `Account.tsx:109` and `Users.tsx:149` render another `Box as="main"` inside it. Nav links look like plain text and the active route has no visual indicator (`AppShell.tsx:100-102`). The "Toggle drawer" button has no `aria-expanded` or `aria-controls` (`:87-95`). `document.title` stays "Booking" on every route, focus does not move on navigation, and there is no skip link. Form errors are page-level `Alert`s not tied to fields. `size="xs"` Remove (`Users.tsx:180`) is about 24 px, and `size="sm"` (36 px) is used for Cancel, Copy, Regenerate and Log out, below the theme's 44 px target. Contrast is in I-110, the Users label mismatch in I-109, `jsx-a11y` linting in I-119 and axe e2e scans in I-124.

**Proposed change.**
- Render `<main id="main" tabIndex={-1}>` only in AppShell. Pages use `<Box as="section">`. Add a skip link to `#main`.
- Style nav links with `_activeLink`/`aria-current`. Add `aria-expanded` and `aria-controls` to the drawer toggle.
- Add a `usePageTitle(title)` hook that sets `document.title` and focuses the page `h1`.
- Use `isInvalid` + `FormErrorMessage` for field errors, and `size="md"` for all touch actions.

**Acceptance criteria**
- [ ] A test renders each authenticated route and asserts exactly one `main` landmark (`getAllByRole("main")` has length 1).
- [ ] A test asserts the drawer toggle has `aria-expanded` that changes when clicked.
- [ ] A routing test asserts `document.title` differs per route and the `h1` has focus after navigation.
- [ ] No `Button` or `IconButton` in `product/frontend/src/pages` or `src/components` uses `size="xs"` or `size="sm"` (checked by grep in review).
- [ ] A test asserts an invalid email in Login sets `aria-invalid="true"` on the input.

### I-116 - Add asset caching, compression and asset retention across deploys

**Covers:** FE-11 · **Labels:** `frontend`, `dev-ops`, `bug`, `light-build-task` · **Priority:** Later · **Executor:** Factory · **Depends on:** I-082

**Problem.** On start, the frontend container runs `rm -rf /srv/* …; cp -a /www/. /srv/; exec sleep infinity` (`product/frontend/Dockerfile:17-20`), so every deploy deletes the previous hashed `/assets/*.js`. Caddy serves the SPA with `try_files {path} /index.html` + `file_server` (`projects/sauna/config/Caddyfile:41-44`), with no `Cache-Control` and no `encode`. A browser that cached `index.html` heuristically, or an open tab that lazy-loads after a deploy, requests an old asset hash, gets `index.html` as `text/html`, fails to load the module and shows a blank page. With hourly dev/QA redeploys this is likely. The CSP and security headers from FE-11 are in I-082.

**Proposed change.**
- In the Caddyfile:
  ```caddy
  encode zstd gzip
  @assets path /assets/*
  header @assets Cache-Control "public, max-age=31536000, immutable"
  @html not path /assets/*
  header @html Cache-Control "no-cache"
  handle /assets/* { file_server }
  ```
- Stop deleting live assets: copy the new build first and keep the previous build's `/assets` for at least one release. Or build a Caddy image with `dist` baked in and drop the `sleep infinity` container.

**Acceptance criteria**
- [ ] `caddy validate --config projects/sauna/config/Caddyfile --adapter caddyfile` passes.
- [ ] On a running stack, `curl -sI /assets/<file>.js` shows `Cache-Control: public, max-age=31536000, immutable`, and `curl -sI /` shows `Cache-Control: no-cache`.
- [ ] `curl -s -H 'Accept-Encoding: gzip' -o /dev/null -w '%{size_download}' /assets/<file>.js` is smaller than the uncompressed size.
- [ ] `curl -s -o /dev/null -w '%{http_code}' /assets/does-not-exist.js` returns 404.
- [ ] After two consecutive deploys, an asset URL from the first deploy still returns 200.

### I-117 - Improve the login flow: go back, resend, deep links, autofill

**Covers:** FE-12 · **Labels:** `frontend`, `enhancement`, `light-build-task` · **Priority:** Next · **Executor:** Factory · **Depends on:** –

**Problem.** Once a code has been sent (`Login.tsx:67-93`), there is no way to change the email or ask for a new code, so a typo means reloading the page. `RequireSession.tsx:18` stores `state={{ from: location }}`, but `Login.tsx:53` always calls `navigate("/")`, so deep links are lost. The email input (`:100-106`) has no `autoComplete="email"`. The code input (`:75-81`) has no `autoComplete="one-time-code"`, `autoCapitalize="characters"`, `inputMode` or `spellCheck={false}`. The Account code field (`Account.tsx:152-159`) has no `maxLength` or upper-casing, unlike Login. A signed-in user who opens `/login` sees the form again.

**Proposed change.**
- Add a "Use a different email" link-button and a "Send a new code" button with a cooldown. Resend is rate-limited server-side to 5 per 15 minutes.
- After sign-in, navigate to `location.state?.from?.pathname ?? "/"`.
- Extract one `<CodeInput>` with the autofill attributes, `maxLength={6}` and upper-casing, and use it in Login and Account. Add `autoComplete="email"` to the email input.
- Redirect `/login` to `/` when a user is already signed in.

**Acceptance criteria**
- [ ] An RTL test clicks "Use a different email" after a code is sent and asserts the email field is editable and empty.
- [ ] A test asserts "Send a new code" calls `requestCode` and is disabled during the cooldown.
- [ ] A test renders `/account` signed out, signs in, and asserts the location is `/account`.
- [ ] A test asserts the code input in both Login and Account has `autocomplete="one-time-code"` and `maxlength="6"`.
- [ ] A test asserts a signed-in user visiting `/login` is redirected to `/`.

### I-118 - Show the iCal URL without regenerating it

**Covers:** FE-13 · **Labels:** `frontend`, `backend`, `bug`, `light-build-task` · **Priority:** Later · **Executor:** Factory · **Depends on:** –

**Problem.** The Account page's Calendar section shows only a "Regenerate" button. The URL appears only after `POST /api/account/calendar-token` (`Account.tsx:168-193`, `api/calendar.ts:4-5`), and the backend has no read endpoint (`server.go:79` is the only calendar-token route). Each time a resident wants to see their link, the token rotates and the feed already subscribed on their phone silently stops working. Copy gives no feedback (`Account.tsx:99-106`), and there is no `webcal://` link for one-tap subscription.

**Proposed change.**
- Backend: add `GET /api/account/calendar-token` that returns the current URL and creates a token if none exists. Do not log or trace the token in the URL (see I-126).
- Frontend: on load, show the URL with "Add to calendar" (`webcal://…`) and "Copy" (with a toast).
- Move "Regenerate" behind a confirm dialog (from I-108) that says old links will stop working.

**Acceptance criteria**
- [ ] A Go test asserts two calls to `GET /api/account/calendar-token` return the same URL and the old feed URL still serves `.ics`.
- [ ] A Go test asserts the first `GET` for a user with no token creates one.
- [ ] An RTL test asserts the Account page renders the URL without calling the `POST` endpoint.
- [ ] A test asserts the "Add to calendar" link starts with `webcal://`.
- [ ] A test asserts the `POST` call happens only after the Regenerate confirm dialog is accepted.

### I-119 - Frontend tooling: ESLint, coverage, accessibility checks, time-zone test matrix

**Covers:** FE-15 · **Labels:** `frontend`, `enhancement`, `light-build-task` · **Priority:** Later · **Executor:** Factory · **Depends on:** I-046

**Problem.** `product/frontend/package.json` has no ESLint, so missing hook deps (`Users.tsx:65-76`) and a11y mistakes go unflagged. CI (`frontend-ci.yml:39-43`) runs only test and build, with no coverage. `src/theme.test.ts` (236 lines) mostly re-asserts hex constants copied from `theme.ts` (`:43-55, 58-86`), so any palette change needs two edits and catches no behaviour. `tests.setup.ts:7` pins `TZ=UTC`, and the `Calendar.test.tsx:22-24` fixture creates zero-length bookings. Several flows have no tests: SessionContext restore, 401 mid-session, `App` routing, Login deep-link return, Account Regenerate/Copy, and the Users add/block/broadcast forms.

**Proposed change.**
- Add `eslint`, `typescript-eslint`, `eslint-plugin-react-hooks` and `eslint-plugin-jsx-a11y`, an `npm run lint` script and a CI step.
- Add `vitest --coverage` with a modest floor, enforced in CI.
- Run the suite twice in CI: `TZ=UTC` and `TZ=America/New_York`. Fix the zero-length fixture.
- Cut `theme.test.ts` to behavioural checks (Button default uses the accent token, Input height 44 px, light-only config from I-110).
- Add tests for the untested flows above that are not already added by I-107, I-108 and I-117.

**Acceptance criteria**
- [ ] `npm run lint` exits 0 in `product/frontend` and runs as a step in `frontend-ci.yml`.
- [ ] `frontend-ci.yml` fails when line coverage drops below the configured floor.
- [ ] The CI job runs `npm test` under both `TZ=UTC` and `TZ=America/New_York`.
- [ ] `theme.test.ts` has no assertions that compare against literal hex strings.
- [ ] Tests exist for `App` routing redirects, Account Copy, and Users add-user, block and broadcast forms.

### I-120 - Add a shared route layout, session guard and error boundary

**Covers:** FE-16 · **Labels:** `frontend`, `enhancement`, `light-build-task` · **Priority:** Later · **Executor:** Factory · **Depends on:** I-107

**Problem.** `App.tsx:13-42` repeats `<RequireSession><AppShell>…</AppShell></RequireSession>` for every route. There is no error boundary, so any render exception white-screens the app, and `BrowserRouter` cannot use React Router's `errorElement`. #120 needs shell-level state (drawer, CTA, search `?q=`) shared across pages, and a layout route is the natural home for it. The blank screen while restoring is fixed in I-107.

**Proposed change.**
- Use one layout route:
  ```tsx
  <Route element={<RequireSession><AppShell /></RequireSession>}>
    <Route index element={<Calendar />} />
    <Route path="account" element={<Account />} />
    <Route path="users" element={<Users />} />
  </Route>
  ```
  AppShell renders `<Outlet />`.
- Wrap the shell in an `ErrorBoundary` with a "Reload" button, or move to `createBrowserRouter` with `errorElement`.
- Land this as a prep PR before #120 (sequence in I-111).

**Acceptance criteria**
- [ ] `grep -c "<RequireSession>" product/frontend/src/App.tsx` returns 1.
- [ ] A routing test asserts `/`, `/account` and `/users` all render inside a single `AppShell` and redirect to `/login` when signed out.
- [ ] A test renders a child that throws and asserts a "Reload" button is shown instead of an empty document.
- [ ] Existing `RequireSession` and `AppShell` tests pass unchanged or are updated in the same PR.

### I-121 - Remove dead pages and aliases, and fix the theming README

**Covers:** FE-17 · **Labels:** `frontend`, `documentation`, `light-build-task` · **Priority:** Later · **Executor:** Factory · **Depends on:** –

**Problem.** `pages/AccountPage.tsx`, `pages/SuperUser.tsx` and `pages/UserDirectory.tsx` are one-line re-exports (from `4ef24c5`) that nothing imports. `getMe` (`api/auth.ts:43-44`), `updateUserRole`, `setUserRole` and `changeAddress` (`api/users.ts:58-63`) are unused aliases. `Booking` is defined in `api/auth.ts:13-22`, and the `RawUser` comment claims dual key styles that nothing normalises (`users.ts:4-11`). Colours are hardcoded (`gray.600`, `gray.50`, `colorScheme="red"`) next to the semantic tokens (`AppShell.tsx:46, 97`; `Calendar.tsx:143`). `product/frontend/README.md` says deployments extend the theme from `projects/<name>/`, but no such mechanism exists (`main.tsx:7` imports `./theme` directly), and its `extendTheme` example would let the base override deployment colours. These are signs of several models writing without local conventions.

**Proposed change.**
- Delete the three shim pages and the four unused aliases. Move `Booking` to `api/bookings.ts` and fix the `RawUser` comment.
- Replace hardcoded `gray.*` and `colorScheme="red"` with semantic tokens.
- Correct the README to describe how theming works today.
- Add a short `product/frontend/AGENTS.md`: one test style (`userEvent.setup()`), tokens instead of `gray.*`/hex, no alias exports, a single `main`. Because agents read it, the owner should review that file before merge.
- The chrome branding question goes to the redesign re-plan (see I-111).

**Acceptance criteria**
- [ ] `ls product/frontend/src/pages` lists none of `AccountPage.tsx`, `SuperUser.tsx`, `UserDirectory.tsx`.
- [ ] `grep -rn "getMe\|updateUserRole\|setUserRole\|changeAddress\b" product/frontend/src` returns no definitions.
- [ ] `grep -rn "gray\.[0-9]\|colorScheme=\"red\"" product/frontend/src --include=*.tsx` returns nothing outside tests.
- [ ] `product/frontend/README.md` no longer refers to a `projects/<name>/` theme override.
- [ ] `product/frontend/AGENTS.md` exists, and `npm test` and `npm run build` pass.

### I-122 - Upgrade Vite and Vitest, fix overrides and decide on the Chakra version

**Covers:** FE-18 · **Labels:** `frontend`, `enhancement`, `standard-build-task` · **Priority:** Later · **Executor:** Factory · **Depends on:** I-008

**Problem.** The lockfile resolves `vite` 5.4.21, `vitest` 2.1.9 and `esbuild` 0.21.5, two majors behind. esbuild below 0.25 carries the dev-server CORS advisory GHSA-67mh-4wv8-2f99 (dev-only, but scanners flag it). `package.json:34-36` forces `tinypool` to `^2.2.0`, while vitest 2.1.9 declares `^1.0.1`, with no reason given since `ef01a88`. `@types/node` is ^26 while Docker and CI run Node 22 (`Dockerfile:6`, `frontend-ci.yml:32`). `@playwright/test` is pinned at 1.49.0 (`dev-ops/testing/package.json:7`), and no Dependabot config covers npm. Chakra UI v2 is in maintenance, v3 is a breaking rewrite, and the whole redesign is written against v2, so a builder model could "upgrade" mid-issue.

**Proposed change.**
- Upgrade Vite and Vitest together in one PR and remove the `tinypool` override.
- Align `@types/node` with `22.x`.
- Record the decision to stay on Chakra v2 through the redesign: pin `~2.10` and note it in `product/frontend/README.md`.
- Add npm entries for `/product/frontend` and `/dev-ops/testing` to `.github/dependabot.yml`, with minor and patch updates grouped.

**Acceptance criteria**
- [ ] `npm ls esbuild` in `product/frontend` reports 0.25 or later.
- [ ] `package.json` has no `overrides.tinypool`, and `npm test` and `npm run build` pass.
- [ ] `package.json` lists `@types/node` as `^22` and `@chakra-ui/react` as `~2.10`.
- [ ] `.github/dependabot.yml` has `npm` entries for `/product/frontend` and `/dev-ops/testing`.
- [ ] The README states that the Chakra version stays on v2 until the redesign ships.

## Epic L - End-to-end testing

The only browser test cannot pass and nothing runs it, so the SPA, Caddy routing and compose wiring have no automated checks. These issues fix the spec, add a mail sink so email steps can be tested, and run the main user journeys in CI and after every QA deploy.

### I-123 - Fix the login e2e spec and add a mail sink

**Covers:** FE-06, OPS-06 · **Labels:** `dev-ops`, `bug`, `standard-build-task` · **Priority:** Now · **Executor:** Owner-reviewed PR · **Depends on:** –

**Problem.** `dev-ops/scripts/run-playwright.sh:78` fetches a code with `get-login-code.sh … --request`, then `dev-ops/testing/tests/login.spec.ts:9` clicks "Request code", which issues a newer code. Verification only accepts the newest unconsumed code (`product/backend/internal/auth/commands.go:131`, `:141`), so the test should fail every time (the report did not run it). `run-playwright.sh:86` bind-mounts `dev-ops/testing` over `/tests`, which very likely hides the image's `node_modules`. There is no mail sink: `EMAIL_MODE=log` (`projects/sauna/.env.example:22`) and codes are scraped from logs, so the README's email steps (7–8, 11–12) cannot be checked. I-073 and I-074 depend on the mail sink.

**Proposed change.**
- Add Mailpit (`axllent/mailpit`, SMTP 1025, API 8025) to the dev/QA compose on the internal network only. Mail holds login codes, so do not publish its ports publicly. Set `EMAIL_MODE=smtp`, `SMTP_HOST=mailpit`, `SMTP_PORT=1025` and `SMTP_FROM` for QA.
- In the spec, fetch the code after the UI click from Mailpit's API (`GET /api/v1/search?query=to:<email>`). Drop `--request` and `LOGIN_CODE` from `run-playwright.sh`.
- Mount only the specs, read-only: `-v "$REPO_ROOT/dev-ops/testing/tests:/tests/tests:ro"`.
- Update `projects/sauna/README.md:81-83`, which still calls the browser steps a manual checklist.

**Acceptance criteria**
- [ ] `dev-ops/scripts/run-playwright.sh` against a local `docker compose up` exits 0 with `login.spec.ts` passing.
- [ ] `grep -n "LOGIN_CODE\|--request" dev-ops/scripts/run-playwright.sh dev-ops/testing/tests/*.ts` returns nothing.
- [ ] `docker compose -f projects/sauna/docker-compose.yml config` shows a `mailpit` service with no host port bound to `0.0.0.0`.
- [ ] After a login on QA, the code email is visible through Mailpit's API.
- [ ] `dev-ops/scripts/tests/test-get-login-code.sh` (or its replacement) passes.

### I-124 - Cover the core journeys in e2e and run them in CI and after each QA deploy

**Covers:** FE-06, OPS-06, OPS-08 · **Labels:** `dev-ops`, `enhancement`, `heavy-build-task` · **Priority:** Next · **Executor:** Owner-reviewed PR · **Depends on:** I-123

**Problem.** `login.spec.ts` is the only spec, `playwright.config.ts:12` runs only Desktop Chrome, and nothing runs Playwright, although `dev-ops/README.md:23-24` promises "~12 h for Playwright testing on QA". CI also skips the deploy layer (OPS-08): no workflow runs `dev-ops/scripts/tests/test-*.sh`, there is no shellcheck, `docker compose config` or `caddy validate`, only the backend image is built (`backend-ci.yml:51-58`), and no job brings the stack up. The redesign (#120–#123) will change every page with nothing to catch regressions.

**Proposed change.**
- Seed users through a fixture and cover the `projects/sauna/README.md` "Initial test flows" plus the 14 FE-06 journeys: login edge cases, deep link, booking and its rejections, cancellations with emails, user admin, blocked periods, broadcast, email change, iCal, role change, logout, and a mobile/dark-mode smoke test.
- Add Playwright projects `Mobile Safari` (iPhone 13) and `Pixel 7`, plus an `@axe-core/playwright` scan per page.
- Add `deploy-ci.yml`: shellcheck, every `dev-ops/scripts/tests/test-*.sh`, `docker compose config -q`, `caddy validate`, build all images, `docker compose up --wait`, `/healthz` and SPA checks, then the Playwright suite. Run on PRs touching `product/**`, `projects/sauna/**`, `dev-ops/**`.
- Run the suite after each QA deploy. A failure marks the deploy failed and feeds the rollback gate from OPS-04.

**Acceptance criteria**
- [ ] `dev-ops/testing/tests/` has specs for journeys 1–6 and 13 from FE-06 in the first PR, and 7–12 and 14 in a later PR.
- [ ] `deploy-ci.yml` runs on a PR and fails when a `test-*.sh` script, `shellcheck`, `caddy validate` or a Playwright spec fails.
- [ ] CI builds the frontend, sidecar and `dev-ops/testing` images.
- [ ] `npx playwright test --list` shows the Chromium, Mobile Safari and Pixel 7 projects.
- [ ] A QA deploy log shows a Playwright run, and a forced spec failure marks the deploy as failed.

## Epic M - Privacy and GDPR

The event log stores residents' email and address in plaintext forever, and login codes, sessions, outbox rows and telemetry are never purged. These issues add an erasure path that keeps the event log immutable, add retention, and write the paperwork.

### I-125 - Crypto-shred personal data in events

**Covers:** SEC-15 · **Labels:** `backend`, `enhancement`, `heavy-build-task` · **Priority:** Later · **Executor:** Factory · **Depends on:** I-096, I-092

**Problem.** `AGENTS.md:35` says "**No deletes:** not even super users may delete data", and events are append-only (`product/backend/README.md:18`). User events store plaintext `email` and `address` (`internal/user/events.go:35-37`) in `payload JSONB` (`migrations/0001_create_events.sql`). Auth events use the email as `aggregate_id` (`internal/auth/commands.go:95`, `:160`), so PII sits in an indexed key. Removing a user only deactivates them. A resident's erasure request therefore cannot be met without rewriting history.

**Proposed change.**
- Give each user a data-encryption key in a deletable `user_keys` table (or a KMS). Encrypt PII fields (email, address, names) inside event payloads.
- Use the user UUID, not the email, as `aggregate_id` for auth events. Add an `email_hash → user_id` lookup projection (HMAC with a server pepper) for login.
- Erasure deletes the key, and projections rebuild with "[erased]".
- Plan the migration for existing plaintext events in a short ADR before any code.
- Revise `AGENTS.md` to "no deletes except legally required erasure via crypto-shredding" (owner review; see I-127 for the docs).

**Acceptance criteria**
- [ ] The owner has approved the ADR and reviews the PR. The factory does not self-merge it.
- [ ] `SELECT payload FROM events WHERE payload::text ILIKE '%@%'` returns no rows on a test database after the migration.
- [ ] A Go test erases a user, rebuilds all projections, and asserts their email and address read as "[erased]".
- [ ] A Go test asserts login still works for a non-erased user through the `email_hash` lookup.
- [ ] `grep -n "aggregate_id\|AggregateID" product/backend/internal/auth/commands.go` shows no email used as an aggregate id.

### I-126 - Add retention for login codes, sessions, outbox, logs and telemetry

**Covers:** SEC-15, OBS-11 · **Labels:** `backend`, `dev-ops`, `enhancement`, `standard-build-task` · **Priority:** Later · **Executor:** Factory · **Depends on:** –

**Problem.** `login_codes` and `sessions` are never purged, and `notification_outbox` (`migrations/0010`) keeps recipients and message bodies with no retention (SEC-15). Telemetry can also carry secrets and PII (OBS-11). `session_failed` ships `output_tail`, the last 16 KiB of OpenCode output (`tick.sh:816-904`), to SigNoz by default (`FACTORY_LOG_SESSION_OUTPUT=tail`). Server spans for iCal feed URLs likely record the token in the path (not verified). `signoz/README.md:158-159` says host data contains "no secrets", but the factory and backend pipelines are not covered by that statement.

**Proposed change.**
- Add a retention job, expressed as "expired" projections or table cleanup, not event deletes: `login_codes` older than 1 day, revoked or expired `sessions`, and delivered `notification_outbox` rows after 30–90 days.
- Set log retention to 30 days.
- Default `FACTORY_LOG_SESSION_OUTPUT=metadata` for shipping, and keep tails only in the local file. This touches `tick.sh`, so the owner must review it before merge.
- Add a `redaction`/`transform` processor to both collectors to drop `output_tail`, mask `url.full`/`url.path` on iCal routes and `user.email`, and remove token patterns.
- Set SigNoz retention TTLs as part of its provisioning (OBS-03).

**Acceptance criteria**
- [ ] A Go test inserts a 2-day-old login code, an expired session and a delivered outbox row older than the limit, runs the job, and asserts they are gone while newer rows remain.
- [ ] `grep -n "FACTORY_LOG_SESSION_OUTPUT" dev-ops/factory/tick.sh` shows `metadata` as the default.
- [ ] Collector configs contain a processor that removes `output_tail` and masks iCal paths, and `otelcol validate` (or the collector's dry-run) passes.
- [ ] A test request to `/calendar/<token>.ics` produces a span whose URL attributes do not contain the token.
- [ ] SigNoz shows logs and traces retention set to a finite value.

### I-127 - Write the privacy documentation and keep QA on synthetic data

**Covers:** SEC-15 · **Labels:** `dev-ops`, `documentation`, `trivial-task` · **Priority:** Later · **Executor:** Owner · **Depends on:** I-075

**Problem.** The system stores residents' email addresses and home addresses (`internal/user/events.go:35-37`), sends mail through an SMTP provider and ships telemetry to SigNoz, but the repo has no privacy notice, record of processing or data processing agreements. QA may hold real residents' data, because login codes are logged in log mode (SEC-06). The `AGENTS.md:35` "no deletes" rule also conflicts with erasure requests, and agents will follow it literally.

**Proposed change.**
- Write a privacy notice for residents: what is stored, why, for how long (from I-126), and how to request erasure (I-125).
- Keep a record of processing activities in the repo or with the association's records.
- Sign or confirm a DPA with the SMTP provider, and with the SigNoz host if it is hosted elsewhere.
- Adopt a rule that QA uses only synthetic data (for example `@example.test` accounts seeded via I-075). Check the current QA database for real residents' data and remove it.
- Approve the `AGENTS.md` wording change from I-125.

**Acceptance criteria**
- [ ] A privacy notice is committed (for example `projects/sauna/docs/privacy.md`) and linked from the app or README.
- [ ] A record of processing activities exists and lists email, address, booking times and telemetry.
- [ ] DPA status for the SMTP provider and SigNoz is recorded on this issue.
- [ ] `dev-ops/README.md` states QA uses only synthetic data, and a query on the QA database shows only `@example.test` (or other agreed test) addresses.
- [ ] `AGENTS.md` contains the revised erasure wording.

## Coverage matrix

All 148 review findings and the issues that resolve them.

| Finding | Issues | Finding | Issues | Finding | Issues |
|---|---|---|---|---|---|
| ST-01 | I-005 | OPS-20 | I-066, I-076 | SEC-10 | I-095 |
| ST-02 | I-006, I-018 | OPS-21 | I-008, I-009, I-079 | SEC-11 | I-082, I-086 |
| ST-03 | I-048 | OPS-22 | I-078 | SEC-12 | I-003, I-026 |
| ST-04 | I-004 | BE-01 | I-087 | SEC-13 | I-025 |
| ST-05 | I-069 | BE-02 | I-088 | SEC-14 | I-024 |
| ST-06 | I-013 | BE-03 | I-089 | SEC-15 | I-096, I-125, I-126, I-127 |
| ST-07 | I-007, I-008, I-012 | BE-04 | I-090 | SEC-16 | I-078 |
| ST-08 | I-010, I-014, I-015 | BE-05 | I-083 | SEC-17 | I-097 |
| ST-09 | I-052, I-055, I-056 | BE-06 | I-091 | SEC-18 | I-099 |
| FAC-01 | I-001, I-016 | BE-07 | I-092 | SEC-19 | I-099, I-100 |
| FAC-02 | I-001, I-016, I-018 | BE-08 | I-102 | SEC-20 | I-008, I-009, I-081 |
| FAC-03 | I-005, I-006, I-019 | BE-09 | I-101 | SEC-21 | I-017 |
| FAC-04 | I-020 | BE-10 | I-071 | SEC-22 | I-081, I-085 |
| FAC-05 | I-007, I-033 | BE-11 | I-095, I-096 | SEC-23 | I-084 |
| FAC-06 | I-029 | BE-12 | I-099 | SEC-24 | I-082 |
| FAC-07 | I-019, I-028 | BE-13 | I-105 | SEC-25 | I-083 |
| FAC-08 | I-030 | BE-14 | I-015, I-106 | SEC-26 | I-021, I-022, I-067 |
| FAC-09 | I-017, I-031 | BE-15 | I-104 | SEC-27 | I-086 |
| FAC-10 | I-049 | BE-16 | I-070, I-100 | AGT-01 | I-042, I-043 |
| FAC-11 | I-048 | BE-17 | I-060, I-061 | AGT-02 | I-041 |
| FAC-12 | I-039 | BE-18 | I-094 | AGT-03 | I-045 |
| FAC-13 | I-027, I-055, I-058 | BE-19 | I-103 | AGT-04 | I-019, I-050 |
| FAC-14 | I-032 | BE-20 | I-045, I-093 | AGT-05 | I-040 |
| FAC-15 | I-038 | FE-01 | I-107 | AGT-06 | I-039 |
| FAC-16 | I-021 | FE-02 | I-108 | AGT-07 | I-044 |
| FAC-17 | I-036 | FE-03 | I-109 | AGT-08 | I-047 |
| FAC-18 | I-035 | FE-04 | I-110 | AGT-09 | I-046 |
| FAC-19 | I-030 | FE-05 | I-111 | AGT-10 | I-019, I-048, I-049 |
| FAC-20 | I-034 | FE-06 | I-123, I-124 | AGT-11 | I-018, I-020 |
| FAC-21 | I-023, I-040 | FE-07 | I-112 | AGT-12 | I-040 |
| FAC-22 | I-037 | FE-08 | I-113 | AGT-13 | I-052 |
| OPS-01 | I-058, I-066 | FE-09 | I-114 | AGT-14 | I-051 |
| OPS-02 | I-002 | FE-10 | I-110, I-115 | AGT-15 | I-023 |
| OPS-03 | I-067 | FE-11 | I-082, I-116 | AGT-16 | I-020, I-035, I-053 |
| OPS-04 | I-068 | FE-12 | I-117 | OBS-01 | I-055, I-056 |
| OPS-05 | I-005, I-010, I-078 | FE-13 | I-118 | OBS-02 | I-054 |
| OPS-06 | I-123, I-124 | FE-14 | I-095 | OBS-03 | I-003, I-057 |
| OPS-07 | I-069 | FE-15 | I-046, I-119 | OBS-04 | I-058 |
| OPS-08 | I-035, I-080, I-124 | FE-16 | I-107, I-120 | OBS-05 | I-027 |
| OPS-09 | I-004, I-011 | FE-17 | I-121 | OBS-06 | I-059 |
| OPS-10 | I-071 | FE-18 | I-008, I-122 | OBS-07 | I-060 |
| OPS-11 | I-070 | SEC-01 | I-001, I-016, I-018 | OBS-08 | I-061 |
| OPS-12 | I-072 | SEC-02 | I-001, I-016 | OBS-09 | I-062 |
| OPS-13 | I-003, I-058, I-064 | SEC-03 | I-006, I-021, I-022 | OBS-10 | I-063 |
| OPS-14 | I-082 | SEC-04 | I-020 | OBS-11 | I-026, I-126 |
| OPS-15 | I-024, I-025 | SEC-05 | I-023 | OBS-12 | I-009, I-064 |
| OPS-16 | I-022, I-024 | SEC-06 | I-002, I-074 | OBS-13 | I-035, I-054 |
| OPS-17 | I-073, I-081, I-086 | SEC-07 | I-083 | OBS-14 | I-065 |
| OPS-18 | I-068, I-077 | SEC-08 | I-075 |  |  |
| OPS-19 | I-075 | SEC-09 | I-098 |  |  |
