# Repository status and delivery process

**Scope:** GitHub state of `adamzki99/booking-system` (issues, PRs, CI runs, branches, settings) and the overall delivery process · **Reviewed** 2026-11-19 at commit `45f6ee5`

## Summary

The repository is 14 days old (created 2026-11-05) and is very active: 104 commits, 81 merged PRs and 63 completed issues, almost all of them delivered by the OpenCode software factory (`factory/issue-*` branches). There are no open PRs. CI on `main` is green. The six open issues (#120–#125) all have a factory plan, and the owner approved them this morning (2026-11-19, 08:41–09:06 UTC), so they are queued for the hourly build ticks rather than stuck.

The main structural weakness is that **all quality gates are conventions, not enforcement.** `main` has no branch protection or rulesets. No PR has ever had a review decision. The factory merges with the owner's own GitHub identity. A typical PR is open for only 2–5 minutes. The project is moving fast and the code has a lot of tests, but nothing on GitHub stops a bad merge.

**What's working well**

- A clear issue → plan → owner approval → build → fix → merge pipeline, with idempotency markers (`<!-- factory:plan -->`) visible on issues.
- Issues are well structured, with measurable acceptance criteria enforced by `dev-ops/scripts/check-acceptance-criteria.sh` and `validate-issue-body.sh`.
- Strong test volume for a two-week-old codebase: 212 Go `Test*` functions and 62 frontend test cases.
- Security tooling exists from day one: gitleaks, dependency review, govulncheck-style checks (the `Security` workflow) and Semgrep. Some actions are already SHA-pinned.
- Clear separation of `product/`, `projects/<name>/` and `dev-ops/`, documented in `AGENTS.md`.
- The factory has repaired its own QA deploy bugs (#85, #86, #89) through the normal issue flow.

## Key metrics

| Metric | Value |
|---|---|
| Age | 14 days (2026-11-05 → 2026-11-19) |
| Commits on `main` | 104 (99 by the owner identity, 5 by `booking-deploy`) |
| PRs | 81 merged, 1 closed, 0 open |
| Issues | 63 completed, 1 not planned, 6 open |
| Issue authors | 70/70 `adamzki99` |
| Median issue lead time (created → closed) | ~23 h (max ~209 h) |
| PR time-to-merge | typically 2–5 min; several merged in the same minute they were opened (#139–#143, #146) |
| PRs with an approving review | 0 |
| Code size | backend ~15.0k lines (110 files), frontend ~3.1k (37), sidecar ~0.6k (9), dev-ops ~7.9k (52), `.opencode/` ~12.9k (122, mostly vendored skills) |
| Tests | 212 Go test functions, 62 frontend `it/test` cases, **1** Playwright e2e test (login) |
| CI history (last 300 runs) | Backend CI 60/0 failed · Frontend CI 10/1 · Sidecar CI 3/0 · Security 142/6 · Semgrep 82/0 |
| Activity | bursty: 10–20 commits/day on Nov 5–10 and Nov 18–19, almost nothing on Nov 12–16 |

## Findings

| ID | Severity | Effort | Title |
|---|---|---|---|
| ST-01 | High | S | `main` has no branch protection, rulesets or required checks |
| ST-02 | High | S | The factory acts as the owner: there is no separation between the human and the bot |
| ST-03 | High | M | No independent review before merge |
| ST-04 | Medium | S | Path-filtered CI cannot simply become required checks |
| ST-05 | Medium | S | QA deploy bookkeeping commits straight to `main` |
| ST-06 | Medium | S | Stale branches and duplicate/empty PRs |
| ST-07 | Medium | S | No Dependabot/Renovate, CODEOWNERS or SECURITY.md |
| ST-08 | Low | S | Suspiciously clean CI history may mean weak gates |
| ST-09 | Low | M | Delivery metrics are not tracked |

### ST-01 — `main` has no branch protection, rulesets or required checks

**Evidence:** `GET /repos/adamzki99/booking-system/branches/main/protection` returns 404 and `GET /rulesets` returns `[]`. `AGENTS.md` says: *"never merge a pull request … until all required CI checks and security analyses (Backend CI, Security, Semgrep) pass"*. That rule exists only as prose for the agents to follow.

**Why it matters:** A model that misreads its instructions, a prompt injection, or a bug in `tick.sh` can merge red or unchecked code, or push directly to `main`. Cheaper models are more likely to drift from prose rules.

**Recommendation:** Add a ruleset on `main` that requires a PR, the status checks (see ST-04), linear history and branch up to date, and blocks force-push and deletion. GitHub Free supports rulesets on public repos.

```bash
gh api -X POST repos/adamzki99/booking-system/rulesets --input ruleset.json
# ruleset.json: target "branch", include ["~DEFAULT_BRANCH"], rules:
#   pull_request (required_approving_review_count: 0 or 1),
#   required_status_checks [{context:"ci-gate"}], non_fast_forward, deletion
```

### ST-02 — The factory acts as the owner: there is no separation between the human and the bot

**Evidence:** All 70 issues and every PR are authored by `adamzki99`. The `owner approved` label on #120/#125 and the planner's labels on the same issues are both applied by `adamzki99` (issue timelines). `dev-ops/factory/README.md` says *"Only the repository owner applies `owner approved`"*, but GitHub cannot tell owner and factory apart.

**Why it matters:** There is no audit trail of what the AI did versus what the human decided. Nothing stops the factory from approving its own work (applying `owner approved`), and a leaked factory token is a full owner token.

**Recommendation:** Run the factory as a **GitHub App** (preferred) or a dedicated machine user with a fine-grained token limited to this repo (Contents, Issues and PRs read/write; Actions and Checks read). Then:

- have the build selector require that the `owner approved` labeled-event actor is the owner login, read from the issue timeline;
- set the ruleset bypass list so that only the owner can bypass.

### ST-03 — No independent review before merge

**Evidence:** `reviewDecision` is empty on all 81 PRs. Time-to-merge is minutes. `.opencode/agents/reviewer.md` exists, but none of its output shows up as a GitHub review.

**Why it matters:** For AI-written code, an independent review (a different model or a human spot check) is the cheapest defect filter available.

**Recommendation:** Have the reviewer agent run as a separate session with a different model family from the builder, and post a real GitHub review (`gh pr review --approve/--request-changes`). Make one approving review required in the ruleset, with the factory App as reviewer. For heavy-build-task and security-sensitive areas (`auth`, `eventstore`, `dev-ops/factory`), require owner review instead. See `02-software-factory.md` for more.

### ST-04 — Path-filtered CI cannot simply become required checks

**Evidence:** `backend-ci.yml`, `frontend-ci.yml`, `sidecar-ci.yml` and `semgrep.yml` use `paths:` filters (run counts: Backend 60, Frontend 10, Sidecar 3, versus Security 142). If a path-filtered workflow is marked required, GitHub waits forever on PRs that don't touch those paths.

**Recommendation:** Add a single always-running `ci-gate` job, using `dorny/paths-filter` or a final job with `needs:` and `if: always()`. It decides which suites to run and fails if any suite that ran failed. Make only `ci-gate` required.

### ST-05 — QA deploy bookkeeping commits straight to `main`

**Evidence:** 5 commits by `booking-deploy` ("chore(dev-ops): record qa deploy <sha>") update `dev-ops/environments.yaml` `last_deploy*`. Issues #86 and #89 were about this path failing silently.

**Why it matters:** Runtime state ends up in the source of truth, and the QA box needs push credentials to `main`. Deploy commits interleave with factory merges, which risks rejected pushes and rebase churn. They will also conflict with the ruleset in ST-01.

**Recommendation:** Record deploy state with GitHub **Deployments/Environments** (`gh api repos/.../deployments`), a git tag (`qa-current`), or a local state file exposed through a `/version` endpoint. Then remove push rights from the QA box. Details are in `03-devops-qa-cicd.md`.

### ST-06 — Stale branches and duplicate/empty PRs

**Evidence:** Remote branches `factory/issue-115`, `factory/issue-132-hardening`, `factory/issue-132-hardening-pr`, `factory/relevant-skills` and `fix/factory-backticks-and-worktree` remain after merge or close. PR #45 (`factory/issue-8`) merged with +0/−0 and 0 files, a duplicate of #44. Issue #132 was delivered as seven PRs (#137–#145) within about 10 minutes.

**Recommendation:** Enable *Automatically delete head branches*. Make the factory refuse to open a PR when there is no diff from the merge base. Prefer one PR per issue, or require a parent and sub-issue structure when work is split.

### ST-07 — No Dependabot/Renovate, CODEOWNERS or SECURITY.md

**Evidence:** None of `.github/dependabot.yml`, `renovate.json`, `CODEOWNERS` or `SECURITY.md` exists. The only dependency signal is GitHub's "Graph Update" runs. Go 1.26, Node and the Docker base images will drift.

**Recommendation:** Add `dependabot.yml` covering `gomod` (backend and sidecar), `npm` (frontend and `dev-ops/testing`), `github-actions` and `docker`, grouped weekly. Dependabot PRs are good factory fodder: let the fixer handle any that go red. Add `CODEOWNERS` so `dev-ops/factory/**`, `.github/**` and `opencode.jsonc` always require owner review, and a short `SECURITY.md` because the repo is public.

### ST-08 — Suspiciously clean CI history may mean weak gates

**Evidence:** Backend CI shows 0 failures in 60 runs and Semgrep 0 in 82. That is possible if the agents run tests locally before pushing, which the builder prompt asks them to do. It could also mean the integration tests are skipped in CI or Semgrep doesn't fail on findings.

**Recommendation:** Check that the Postgres-backed integration tests actually run in CI (look for `t.Skip` on a missing DSN), and that Semgrep runs with `--error`. Run a deliberately broken PR once a month as a canary to prove the gates bite. See `04-backend.md` and `03-devops-qa-cicd.md`.

### ST-09 — Delivery metrics are not tracked

**Evidence:** The factory emits JSONL events to SigNoz, but no metric covers outcomes such as lead time, rework rate (fix sessions per PR), escaped defects (bug issues opened after merge), or model cost per issue.

**Recommendation:** Build a small weekly report (a GitHub Action or factory job) covering issue lead time, PRs needing fix sessions, `bug` issues traced to a factory PR, and model/tier used against success. Use it to tune `models.yaml`, for example to see whether `light-build-task` on a cheaper model leads to more rework.

## Prioritized roadmap

**Now (this week)**

- ST-01 + ST-04: a `ci-gate` job and a ruleset on `main`.
- ST-06: auto-delete head branches and clean up the 5 stale branches.
- ST-07: add Dependabot and CODEOWNERS.

**Next (this month)**

- ST-02: move the factory to a GitHub App or machine user, and verify the actor on `owner approved`.
- ST-03: a real independent review step, posted as a GitHub review.
- ST-05: stop committing deploy state to `main`.

**Later**

- ST-08: periodic gate canaries.
- ST-09: delivery and cost metrics feeding back into model selection.
