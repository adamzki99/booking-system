# booking-system improvement review: overview

**Repository:** `adamzki99/booking-system` (public) · **Commit reviewed:** `45f6ee5` (2026-11-19) · **Method:** static reading only (see *Method and limitations*)

The system is a sauna booking app for a homeowner association: a Go CQRS/event-sourced backend, a React SPA and a stateless sauna sidecar. In 14 days, an OpenCode "software factory" on a single Ubuntu machine built almost all of it. That factory is an hourly `tick.sh` cron that plans, builds, fixes and merges GitHub issues using OpenCode Go models. The same machine also runs the QA environment and SigNoz.

## Bottom line

For two weeks of work the output is impressive: 81 merged PRs, 212 Go tests, a coherent architecture, and security scanners from day one. **The weak spot is not the code. It is the trust and control layer around the factory.**

1. **The factory trusts the whole internet.** The repo is public, and nothing in issue, comment or PR discovery filters by author or rejects fork PRs. Agents then run unsandboxed with `--auto` and the owner's GitHub token on the QA host. *I verified this against `tick.sh:233` and `discover_fix_candidates.py`.*
2. **Every quality gate is prose.** "Don't merge until CI passes", "never apply `owner approved`" and "use the reviewer" are instructions to a model. GitHub enforces none of them: there is no branch protection, no separate bot identity, and no independent review. Semgrep scans nothing.
3. **The data layer has integrity gaps.** The projection runner can skip events permanently, retries can duplicate bookings, emails can be lost, and the event store, the only system of record, has no backups.
4. **QA doesn't produce a quality signal.** Deploys go out without a gate or rollback, the health check is a constant, failure alerts reach nobody, and the only e2e test cannot pass and never runs.

## Findings at a glance

| Report | Area | Critical | High | Medium | Low | Total |
|---|---|---:|---:|---:|---:|---:|
| [01-repo-status.md](01-repo-status.md) | GitHub state and delivery process | – | 3 | 4 | 2 | 9 |
| [02-software-factory.md](02-software-factory.md) | `tick.sh`, OpenCode agents, models, skills | 2 | 5 | 11 | 4 | 22 |
| [03-devops-qa-cicd.md](03-devops-qa-cicd.md) | QA deploy, CI/CD, observability, hosting | – | 6 | 12 | 4 | 22 |
| [04-backend.md](04-backend.md) | Go backend and sidecar contract | 1 | 4 | 9 | 6 | 20 |
| [05-frontend-ux.md](05-frontend-ux.md) | React SPA, UX, e2e, redesign issues | – | 6 | 9 | 3 | 18 |
| [06-security-privacy.md](06-security-privacy.md) | Security and GDPR across everything, plus Let's Encrypt/TLS (addendum) | 3 | 5 | 13 | 6 | 27 |
| [07-agentic-compatibility.md](07-agentic-compatibility.md) | Skills, agents and commands vs. the architecture, under OpenCode Go | – | 4 | 9 | 3 | 16 |
| [08-observability-project-insights.md](08-observability-project-insights.md) | SigNoz determinism, APM, factory and project-management telemetry | – | 4 | 7 | 3 | 14 |
| **Total** | | **6** | **37** | **74** | **31** | **148** |

Some findings appear in more than one report on purpose. Each report stands alone, and the security report owns the security angle of all of them. The cross-references are in the themes below.

**Actionable follow-up:** [09-issues-to-create.md](09-issues-to-create.md) turns all 148 findings into 127 ready-to-file issues in 13 epics. Each has a title, a description with evidence, a proposed change and measurable acceptance criteria. The document includes a filing order, sensitivity markings and a coverage matrix.

## Cross-cutting themes

| # | Theme | Related findings |
|---|---|---|
| T1 | **Untrusted input reaches privileged agents.** Any GitHub user can feed issues, comments or fork PRs (branch `factory/issue-N`) to agents that hold the owner token and run with host access. Marker comments can be spoofed. | FAC-01, FAC-02, FAC-09, FAC-16, SEC-01, SEC-02, SEC-03, SEC-21 |
| T2 | **Gates exist in prose, not enforcement.** There is no ruleset or required checks. The merge decision belongs to the model. The factory edits its own guardrails without CI. Semgrep is a no-op, the reviewer agent is never invoked, and path-filtered workflows can't simply become required checks. | ST-01–04, FAC-03, FAC-05, FAC-11, FAC-18, OPS-05, OPS-09 |
| T3 | **Agent permissions are thin.** The deny rules are easy to bypass, `--auto` auto-approves, builder and fixer have no default-deny, third-party skills (with Python) are unpinned, and the bwrap sandbox is opt-in and falls back silently. | FAC-04, FAC-16, FAC-21, SEC-04, SEC-05, OPS-15, OPS-16, SEC-14 |
| T4 | **Event-store integrity.** Projections can skip events, a command errors after its event is committed so retries create duplicates, the outbox is written after the commit, there is no optimistic concurrency, migrations rerun every file on every boot, and there are no backups. | BE-01, BE-02, BE-03, BE-04, BE-07, BE-10, OPS-10, OPS-03 |
| T5 | **QA gives no signal.** Deploys of `main` HEAD aren't gated, the health check is a constant, alerts are filed under the owner's own identity, the e2e test is broken and never run, QA isn't production-like, and nothing feeds QA results back to the factory. | OPS-01, OPS-04, OPS-06, OPS-11, OPS-17, OPS-20, FE-06, FAC-15 |
| T6 | **Residents' personal data leaks.** Login codes and emails reach public issues (#101), every resident can read all emails and addresses, SigNoz is open on 0.0.0.0, and the append-only event log stores PII in plaintext with no erasure path. | OPS-02, SEC-06, SEC-09, SEC-12, OPS-13, SEC-15 |
| T7 | **Rate limiting behind a proxy.** Limits are keyed on Caddy's IP, so one shared bucket covers every resident's logins and iCal fetches. | BE-05, SEC-07 |
| T8 | **Sessions and auth UX.** Tokens sit in `localStorage` with a 24-hour TTL, there is no server-side logout or revocation, a network blip wipes the session, the first requester becomes admin, and codes have no attempt limits. | BE-11, FE-01, FE-14, SEC-08, SEC-10, SEC-17, OPS-19 |
| T9 | **Drift from many models writing the code.** There are dozens of aliases, a switch copied 17 times, test harnesses copied 11 times, a script copied 5 times, dead pages, and agent definitions that contradict the tick prompts. | BE-13, BE-14, FE-17, FAC-12, FAC-17, FAC-22 |
| T10 | **Time zones.** Emails show UTC and the UI uses the browser's zone, while the sidecar's rules are in Europe/Stockholm. | BE-08, FE-08 |
| T11 | **Agent tooling doesn't teach the architecture.** None of the 22 skills is project-specific: 11 should leave the factory and 6 need adapting. Several assume an interactive user, and the build prompt mandates up to 16 contradictory skills. The architecture rules have no machine checks, and the role definitions disagree across three files. | AGT-01–09, FAC-12, FAC-21 |
| T12 | **Observability can't answer management questions.** Factory telemetry has no tokens, cost, skills, outcomes or `session_id`, and the shipper isn't installed by the repo. SigNoz dashboards, alerts, users and retention aren't code. No alerts exist, deploys emit nothing, and APM lacks DB and sidecar spans, logs, version tags and event-sourcing metrics. | OBS-01–14, FAC-13, BE-17, OPS-13 |
| T13 | **OpenCode Go model strategy.** Quota detection misfires on the product's own "rate limit" text and reruns the session on free models, which can auto-merge. `plan-task` is never used, model IDs aren't checked, and the planner picks the tier that selects its own builder. | FAC-07, FAC-10, FAC-19 |

## Time-sensitive item

**Issues #120–#123 (the frontend redesign) were approved this morning and the hourly tick will start building them, one per hour.** The frontend review (FE-05) found them not build-ready: their plans predate the theme and email-change merges, #121 and #122 both rewrite `Calendar.tsx`, and the mockups need data the API doesn't return. Consider removing `owner approved` and re-planning them before the factory picks them up.

## Recommended roadmap

### Now: this week, mostly small changes

| # | Action | Fixes |
|---|---|---|
| 1 | **Close the public-input hole.** In discovery, accept only issues and comments whose author is the owner (or has `authorAssociation` OWNER/MEMBER). Drop PRs where `isCrossRepository` is true. Remove `gh issue edit` (label rights) from the planner. Until that's in place, consider pausing the tick timer or making the repo private. | FAC-01, FAC-02, SEC-01, SEC-02 |
| 2 | **Take the merge out of the model.** Agents may only open PRs. `tick.sh` merges, and only when the `ci-gate` check is green and the issue's `owner approved` label was applied by the owner (checked in the issue timeline). Never auto-merge work done by a backup or free model. | FAC-03, FAC-07, ST-02 |
| 3 | **Enforce on GitHub.** Add an always-running `ci-gate` job, a ruleset on `main` (PR required, `ci-gate` required, no force-push), and CODEOWNERS for `dev-ops/factory/**`, `.github/**`, `opencode.jsonc` and `.opencode/**`. Also enable auto-delete of head branches. | ST-01, ST-04, ST-06, FAC-05, OPS-09 |
| 4 | **Clean up the leaked data.** Scrub issue #101. Stop posting raw compose logs to issues; post a redacted summary and keep the logs on the host. | OPS-02, SEC-06 |
| 5 | **Protect the system of record.** Add a nightly `pg_dump` of the event store to off-box storage and run one restore test. | OPS-03 |
| 6 | **Fix the projection-runner skip bug.** Track the checkpoint per projection, detect gaps in event IDs, and stop on a poison event instead of skipping it. | BE-01 |
| 7 | **Fix rate limiting.** Configure trusted-proxy handling (Caddy `trusted_proxies`, or read `X-Forwarded-For` only from Caddy), key login limits per email as well as per IP, and cap limiter memory. | BE-05, SEC-07 |
| 8 | **Make the scanners real.** Give Semgrep a token or run the OSS CLI with `--error`, make dependency review blocking, and fix the README's claim of branch protection. | OPS-05 |
| 9 | **Close exposed services.** Bind the SigNoz UI and OTLP ports to `127.0.0.1`, and redirect `:80` to HTTPS with HSTS. Put QA behind an access gate *before* a Let's Encrypt certificate publishes its hostname in CT logs. Drop the `admin@localhost` ACME contact, and make the deploy health check test HTTPS and certificate expiry. | OPS-13, OPS-14, SEC-11, SEC-12, SEC-22, SEC-23, SEC-24 |
| 10 | **Hold the redesign.** Re-plan #120–#123 before they're built (see the time-sensitive item above). | FE-05 |

### Next: this month

- **Factory identity and isolation:** run the factory as a GitHub App or machine user with a fine-grained token limited to this repo. Make the sandbox the default, run it as a dedicated Unix user without Docker group membership or `$HOME` secrets, and separate the factory and QA workloads. Settle the `permissions` schema question (FAC-04 vs. SEC-04), then default-deny with allowlists. Pin vendored skills to commit SHAs. (ST-02, SEC-03, FAC-16, OPS-16, FAC-04, SEC-04, SEC-05)
- **Independent review:** run the reviewer agent as its own session, on a different model family from the builder, posting a real GitHub review. Require owner review for `auth`, `eventstore` and factory code. (ST-03, FAC-11)
- **Factory robustness:** add a factory CI workflow (validate.sh, shell tests, shellcheck), fix the stall states (draft or green-but-unmerged PRs) with escalation to the owner, scope quota detection to provider errors only, and fix session-ID capture. (FAC-06, FAC-07, FAC-13, FAC-18)
- **Data correctness:** write the event and the outbox row in one transaction, add idempotency keys to commands, add a migration version table, and fix the advisory-lock pool exhaustion. (BE-02, BE-03, BE-04, BE-10)
- **A real QA pipeline:** CI builds tagged images, and the deploy pulls a specific green tag. Add a real `/healthz` (DB, sidecar, version), automatic rollback, alerts that reach the owner, and deploy state recorded through GitHub Deployments instead of commits to `main`. (OPS-01, OPS-04, OPS-07, OPS-11, ST-05)
- **E2E that gates:** fix the login spec and add the core journeys: book, cancel, blocked period, admin user management and iCal. Use a mail sink and run on mobile and desktop viewports after every QA deploy. Feed failures back as factory `bug` issues. (OPS-06, FE-06, FAC-15)
- **Frontend fixes:** session restore and global 401 handling, confirmations for destructive actions, the empty-id selects, dark-mode contrast, and Europe/Stockholm time formatting via `Intl`. (FE-01–04, FE-08, BE-08)
- **Agent tooling that teaches the architecture:** trim the build prompt's skill list, drop caveman from the factory, and add a "no human available" rule. Write first-party skills (`es-feature`, `db-migration`, `ui-conventions`, `e2e`) plus `GLOSSARY.md` and ADRs. Add a shared `check.sh` for agents and CI, and architecture tests or Semgrep rules. Pin the reviewer to a different model family. (AGT-01–12)
- **Observability as code:** ship factory events through the existing SigNoz collector, fix `session_id`, and parse OpenCode usage, skills and tools into session events. Provision dashboards, alerts and retention from git, and emit deploy events plus `service.version` and `deployment.environment`. (OBS-01–08)
- **Dependency hygiene:** add Dependabot for gomod, npm, actions and docker. Pin actions to SHAs and images to digests. (ST-07, OPS-21, SEC-20, FE-18)

### Later

- **GDPR:** crypto-shredding (a per-user key for the PII in events), a retention policy and an erasure procedure. Also restrict `GET /users`. (SEC-15, SEC-09)
- **Sessions:** server-side sessions in an HttpOnly cookie with CSRF protection, shorter TTL, and revocation on logout or deactivation. (BE-11, FE-14, SEC-10)
- **Event-store maturity:** per-aggregate versioning with optimistic concurrency, event schema versioning, and operator-triggered projection rebuilds. (BE-07, BE-20)
- **Production path:** an image registry, release tags, and a promotion path from QA to production with its own host and secrets. (OPS-18, OPS-17)
- **Factory scale and economics:** split `tick.sh` into a tested Python orchestrator. Track outcome metrics (lead time, rework, escaped defects, cost per tier) and use them to tune `models.yaml`. Remove the planner's head-of-line blocking. (FAC-08, FAC-10, FAC-17, FAC-19, ST-09)
- **Convention enforcement against model drift:** golangci-lint plus ESLint with project rules, shared test helpers, and one "how we write X" section in AGENTS.md per pattern. Delete the dead code, the `sample` package and the duplicated scripts. (T9)

## Method and limitations

- **What was read:** a local `git clone` of the repo and its local git history. Nothing from the repo was built, installed, tested or run, and **nothing on GitHub was created, edited, labeled or commented on.**
- **GitHub API reads:** before you restricted us to reading repo contents only, some read-only GitHub API queries were made (issues, PRs, CI runs, branch protection, a few issue timelines and run logs). Findings that depend on those are marked "(from GitHub metadata)" in reports 02–06. Report 01 is built mostly on them. The security review also looked up OpenCode's public config documentation to check the permission schema.
- **Verification:** five reviewers wrote reports 02–06 independently. I spot-checked the two Critical factory findings (FAC-01/02, SEC-01/02) in the code myself. Other claims are evidenced with `path:line` but were not executed. Claims about runtime behavior (whether the e2e test fails, whether Caddy serves plain HTTP, how OpenCode treats the config) are inferences from the code.
- **Known disagreement:** FAC-04 and SEC-04 disagree on whether `permissions` (action/resource/effect) is valid OpenCode config. A note in FAC-04 explains how to settle it on the Ubuntu host.
