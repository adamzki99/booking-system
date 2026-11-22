# Agentic compatibility: skills, agents, commands and OpenCode Go

**Scope:** `.opencode/agents/*.md` (builder, fixer, planner, reviewer), `.opencode/commands/*.md` (create-github-issue, deliver-issue, lint-frontend, test-backend), all 22 installed skills in `.opencode/skills/`, `dev-ops/skills/`, `dev-ops/skills.yaml`, `dev-ops/scripts/request-skills.sh`, `opencode.jsonc`, `AGENTS.md`, the session prompts in `dev-ops/factory/tick.sh` (`plan_prompt`, `build_prompt`, `fix_prompt`, `run_opencode`), `dev-ops/factory/models.yaml`, `dev-ops/issue-templates/agentic.md`, and the architecture docs agents rely on (`README.md`, `product/README.md`, `product/backend/README.md`, `projects/sauna/README.md`). · **Reviewed** 2026-11-19 at commit `45f6ee5`. Static reading of the local clone only.

**Question answered:** how well does the agent tooling (agents, skills, commands and prompts, run headless through `opencode run --auto` with OpenCode Go models) support this project's architecture and development process?

**Related reports:** this report covers *fit*, meaning whether the tooling helps agents do the right thing. Security of the same tooling is in `06-security-privacy.md` (SEC-01–05), and orchestration robustness is in `02-software-factory.md` (FAC-03, FAC-04, FAC-10–12, FAC-21). Where a topic overlaps, this report gives the fit angle and points to the other finding.

## Summary

The agent layer is thoughtfully designed in places:

- The agents are separated by role and have permission frontmatter.
- The planner and reviewer are default-deny.
- A resumable state file (`.factory-deliver-state.json`) lets work survive compaction and timeouts.
- An agentic issue template, with a gate on measurable acceptance criteria, gives the builder a solid spec.
- The report-only commands bound their output (`tail`, filtered `go test`) to protect the context window.

The **skill set, however, is mostly generic and borrowed, and much of it was written for an interactive Claude Code user rather than a headless factory.** Of the 22 installed skills, only one is first-party (`dev-server-ssh`), and it is deliberately *not* for factory use. **No skill or agent teaches this codebase's architecture.** Nothing explains how to add an event, command and projection pair, how the sidecar contract works, how to write an idempotent migration, how the notification outbox is used, or how UI pages are built on the Chakra theme. Meanwhile the factory prompt tells every build session to load up to 16 generic skills. Several of them ask "the user" questions nobody will answer, contradict each other, or reference tools and files that don't exist here.

With OpenCode Go's mid-tier and free models, this mix produces two of the drift patterns the backend and frontend reviews found (BE-13, FE-17). First, conventions get reinvented per session. Second, quality depends on which model happened to run.

**What's working well**

- **Role-specific agents with permission frontmatter.** The planner (`planner.md:5-20`) and reviewer (`reviewer.md:5-18`) start from `"*": deny` and allow only a list of read commands. This is the right model for weaker models.
- **Resumable lifecycle state.** `builder.md:45-62` keeps a gitignored state file (`.gitignore:22`) and re-checks it against GitHub on resume. This is robust against compaction (`opencode.jsonc` `compaction.auto`) and the 1-hour session timeout.
- **A spec-first issue pipeline.** `dev-ops/issue-templates/agentic.md` has 11 sections. `validate-issue-body.sh` and `check-acceptance-criteria.sh` gate planning, which gives builders measurable acceptance criteria.
- **The prompts treat untrusted text as data** (`planner.md:51-52`, `fixer.md:77-78`, `reviewer.md:59-61`, `test-backend.md:35`).
- **Context-frugal commands.** `test-backend.md` filters passing packages and tails output, and runs as `subtask: true`, which keeps the main context clean.
- **Skills come from a manifest** (`dev-ops/skills.yaml` plus `request-skills.sh`) with a `.source` provenance file per skill. `AGENTS.md` stops agents from bulk-reading `.opencode/skills/`.
- **`formatter: true`** in `opencode.jsonc`, so OpenCode runs gofmt and other formatters after edits. This cheaply removes a whole class of CI failures.

## How well the architecture rules are supported

The table takes each rule from `AGENTS.md` ("Architecture rules (do not violate)") and asks three questions. Is there agent guidance that shows *how* to comply? Is there a mechanical check that *catches* violations? And what is the overall verdict?

| Rule | How-to guidance for agents | Mechanical check | Verdict |
|---|---|---|---|
| Event sourced: record events, never mutate state | None project-specific. `domain-modeling` is a generic glossary/ADR skill. | A source-grep test in `eventstore` (per BE-20) | **Partial.** The check is shallow, and there's no recipe. |
| CQRS: commands write events, queries read projections | None | None (no import or semgrep rule) | **Prose only** |
| Sidecar is stateless; deployment logic stays out of `product/` | None | None (nothing stops `product/` from mentioning `sauna` or the sidecar from importing a DB driver) | **Prose only** |
| No deletes | None | Partial: same grep test | **Partial** |
| Notifications go through a durable outbox | None | Unit tests in `notification/` | **Partial.** BE-04 shows the rule is already violated in substance. |
| Merge only when CI and security pass | Builder and fixer rules, plus the tick prompts | None on GitHub (ST-01) | **Prose only** |
| No secrets | Builder rules | gitleaks in `security.yml` | **Enforced** |
| Measurable acceptance criteria | Template, command, validator | `check-acceptance-criteria.sh` gates planning | **Enforced** |
| Minimal scope | Prompts, plus the `lean-build` and `surgical-patch` skills | None | **Prose only** |

The rules that *are* enforced are the ones agents comply with. The domain-architecture rules, the ones that matter most for an event-sourced system, rely entirely on a cheap model remembering a sentence from `AGENTS.md`.

## Skill inventory: fit for headless factory use

| Skill | Source | Size (SKILL.md / dir) | Works headless? | Fits this project? | Recommendation |
|---|---|---|---|---|---|
| `tdd` | mattpocock | 38 / 180 | **No.** "confirm them with the user" (`SKILL.md:22-24`) | Good intent. References `codebase-design`, which isn't installed (`:26`), and a `GLOSSARY.md` that doesn't exist | **Adapt** into a factory version |
| `code-review` | mattpocock | 89 / 116 | **No.** "If they didn't specify one, ask for it" (`:19`); "tell the user to run `/setup-matt-pocock-skills`" (`:13`) | Two-axis spec/standards review is valuable | **Replace** with the `reviewer` agent and a pinned fixed point |
| `implement` | mattpocock | 17 / 46 | `disable-model-invocation: true` (intended for user invocation only); "If the reference is ambiguous, ask." | Duplicates the build prompt | **Remove from the factory prompt** |
| `pr` | mattpocock | 170 / 179 | Partly. Asks for "screenshot" evidence (`:21-22`) and `GLOSSARY.md` | A useful PR structure | **Adapt.** Evidence means test output. |
| `diagnosing-bugs` | mattpocock | 138 / 188 | Partly. "ask the user" (`:16`); HITL script (`:35`) | Good for fix sessions | **Keep for fixer**, without the HITL branch |
| `domain-modeling` | mattpocock | 74 / 187 | Yes | High, *but* no `GLOSSARY.md` or `docs/adr/` exists yet | **Keep** and seed the files (AGT-07) |
| `frontend-design` | anthropics | 71 / 251 | Yes, but "confirm with the client" (`:13`) | **Conflicts.** Pushes "distinctive… aesthetic risk" (`:9`), but the project has approved mockups and a fixed Chakra theme (#119) | **Replace** with a project `ui-conventions` skill |
| `webapp-testing` | anthropics | 95 / 509 | Yes | **Mismatch.** Python Playwright helpers; the project's e2e suite is TypeScript in `dev-ops/testing/` | **Replace** with a project `e2e` skill |
| `pdf` | anthropics | 314 / 1,840 | Yes | None | **Remove** |
| `skill-creator` | anthropics | 485 / 5,657 | **No.** Its scripts shell out to `claude -p` (`scripts/run_eval.py:26,46,80`), which is Claude Code, not OpenCode | Not for the factory | **Remove** from the factory skill path |
| `caveman` | caveman | 89 / 160 | Yes | Stays on for the whole session ("Every response, whole session", `:17`), which conflicts with the "persisted artifacts in normal prose" rule. Refers to hooks the host doesn't have. | **Drop from the factory** (AGT-05) |
| `ultracave`, `megacave` | caveman | 63 / 65 | `disable-model-invocation: true`; `megacave` writes Classical Chinese | None | **Remove** |
| `caveman-commit`, `caveman-review` | caveman | 63 / 52 | Yes | Low; the `pr` skill and `reviewer` cover these | **Remove** |
| `caveman-compress` | caveman | 114 / 2,467 | Yes | Risky: it rewrites memory files such as `AGENTS.md` | **Remove** from the factory |
| `investigate-first`, `lean-build`, `surgical-patch`, `safe-refactor`, `verify-and-stop` | caveman | 16–18 each | Yes | Small, cheap and compatible | **Keep 2–3** (`investigate-first`, `surgical-patch`, `verify-and-stop`) |
| `migration` | caveman | 17 / 24 | Yes | Generic. The project's migrations need repo-specific rules (BE-10: every file reruns on every boot, so SQL must be idempotent) | **Replace** with a project `db-migration` skill |
| `dev-server-ssh` | first-party | 88 | **No, by design** ("Never use OpenCode `--auto`") | Operator-only | **Keep, but move it out** of the factory's skill path |

The tally: **5 of 22 skills are headless-safe and relevant as they stand. 6 need adapting and 11 should leave the factory.** No project-specific skill exists.

## Findings

| ID | Severity | Effort | Title |
|---|---|---|---|
| AGT-01 | High | M | No skill or guide teaches the project's own architecture, so every session reinvents the patterns |
| AGT-02 | High | S | Core skills assume an interactive user and break or improvise in headless `--auto` runs |
| AGT-03 | High | M | The architecture rules are prose only, with no machine-checkable guardrails for agents to hit |
| AGT-04 | High | M | The model owns deterministic lifecycle steps that mid-tier models do least reliably |
| AGT-05 | Medium | S | The build prompt requires up to 16 skills, which contradict each other and the prompt |
| AGT-06 | Medium | M | Three sources of truth for each role (agent file, tick prompt, command), and they disagree |
| AGT-07 | Medium | S | Domain knowledge isn't in agent-readable form: no glossary, no ADRs |
| AGT-08 | Medium | S | Agents are told to use tools they can't run (slash commands, denied scripts) |
| AGT-09 | Medium | S | `/lint-frontend` is broken and the check commands cover only the backend |
| AGT-10 | Medium | M | The OpenCode Go model routing doesn't match role risk; the reviewer inherits the builder's model |
| AGT-11 | Medium | S | Permission profiles don't match the roles they serve |
| AGT-12 | Medium | S | Caveman token-saving targets output tokens, but factory cost is in input context |
| AGT-13 | Medium | M | There is no evaluation harness, so prompt, skill or model changes are never measured |
| AGT-14 | Low | S | The issue template has no architecture-impact section |
| AGT-15 | Low | S | Skill provenance isn't pinned or reproducible |
| AGT-16 | Low | S | `opencode.jsonc` keys and the LSP setup are unverified; no config validation |

### AGT-01 - No skill or guide teaches the project's own architecture, so every session reinvents the patterns (High, M)

**Evidence**
- The only first-party skill is `dev-server-ssh` (`dev-ops/skills.yaml`), and it is for operators.
- `product/backend/README.md` (51 lines) describes responsibilities and the advisory lock, but has no "how to add a feature" walkthrough. `AGENTS.md` (69 lines) states rules without examples. There is no `AGENTS.md` in `product/backend`, `product/frontend-solid`, `projects/sauna/sidecar` or `dev-ops/factory`.
- The build prompt relies on generic skills instead (`tick.sh:555-575`).
- The result is visible in the code: 35 alias declarations and 17 copies of the same command type switch (BE-13), a Postgres test harness copied 11 times (BE-14), and dead shim pages and duplicated aliases in the frontend (FE-17).

**Why it matters:** each session, on whatever model tier, rediscovers how commands, events and projections are wired by reading code. Weaker models copy the nearest example, including its mistakes, or invent a new variant. In an event-sourced system, a wrongly wired projection or a non-idempotent migration is expensive to undo.

**Recommendation:** add first-party skills under `dev-ops/skills/` and register them in `skills.yaml` with `local_path`. Each skill should be short (under 120 lines), point to **one canonical example file** for every step, and end with a verification checklist.

| Skill | Teaches |
|---|---|
| `es-feature` | Adding a command, event, projection, read-model migration, HTTP handler and tests. Event naming, payload versioning, registry registration, checkpoint behaviour, and the "never read the event stream from a query" rule. |
| `db-migration` | Numbered SQL files, idempotent DDL (`IF NOT EXISTS`, because every file reruns per BE-10), no `UPDATE`/`DELETE` on `events`, and how to test a migration |
| `sidecar-rule` | The backend-to-sidecar REST contract, the statelessness rule, Europe/Stockholm time handling, and contract tests on both sides |
| `notification` | Enqueueing to `notification_outbox` and the worker retry semantics |
| `ui-conventions` | The Chakra theme tokens from `theme.ts`, the mockups in `projects/sauna/docs/mocks/`, the `api/client.ts` pattern, `test-utils.tsx`, accessibility and mobile rules |
| `e2e` | Running and extending `dev-ops/testing` (TypeScript Playwright), the login-code helper, and the user journeys from `projects/sauna/README.md` "Initial test flows" |

Also add short per-area `AGENTS.md` files (for example `product/backend/AGENTS.md`) with the package map and "golden path" links. Reference them from the root `AGENTS.md` so they load whichever way OpenCode resolves instruction files.

### AGT-02 - Core skills assume an interactive user and break or improvise in headless `--auto` runs (High, S)

**Evidence**
- Sessions run as `opencode run --auto … --file <prompt>` (`tick.sh:707`). There is no human on the other end.
- `tdd/SKILL.md:22`: "write down the seams under test and **confirm them with the user**. No test is written at an unconfirmed seam."
- `code-review/SKILL.md:19`: "If they didn't specify one, **ask for it**." Line 13 says "tell the user to run `/setup-matt-pocock-skills`" (not installed).
- `implement/SKILL.md`: "If the reference is ambiguous, ask." It also carries `disable-model-invocation: true`, which marks it as intended for user invocation only. Note that OpenCode's documented skill frontmatter doesn't list this key, so it may simply be ignored. Either way it was written for another harness.
- `diagnosing-bugs/SKILL.md:16,35`: "ask the user", and a human-in-the-loop script.
- `frontend-design/SKILL.md:13`: "confirm with the client".

**Why it matters:** in a headless run, the model either stops (and the session ends without a result), or more often invents the user's answer and carries on. With `tdd`, the literal reading is "no tests at all", because no seam was ever confirmed. Neither outcome is visible in the factory's metrics.

**Recommendation:**
- Make factory-specific versions of `tdd`, `code-review`, `pr` and `diagnosing-bugs` (vendored copies under `dev-ops/skills/factory-*`). Replace every "ask the user" with a deterministic rule. For example: *the seams are the public functions and HTTP handlers named in the plan comment; the fixed point is `origin/main`; the spec is the issue body and the factory plan comment.*
- Add one line to the build and fix prompts: "No human is available. Where a skill says to ask the user, follow the factory default in this prompt. If no default exists, post the question as an issue comment, apply `needs-info`, and stop."

### AGT-03 - The architecture rules are prose only, with no machine-checkable guardrails for agents to hit (High, M)

**Evidence**
- See the table above. `.semgrep.yml` has `rules: []` and leaves rule selection to the Semgrep platform, which per OPS-05 currently scans nothing.
- No import-boundary or "no deployment identifiers in `product/`" check exists.
- The only architecture test is a source grep in `eventstore` (BE-20).

**Why it matters:** agents, especially cheaper models, comply with what fails the build, not with what's written in `AGENTS.md`. A failing check also gives the fixer a precise, actionable signal; a vague architecture violation gives nothing.

**Recommendation:** encode the rules as tests and lint, run them in CI and in the local check script (AGT-09), and print each rule's `AGENTS.md` sentence in the failure message.

- **Go architecture test or `go-arch-lint`/`depguard`:** packages under `internal/*/http.go` (the query side) must not call `eventstore.Append`. Only `command` may append. `projects/sauna/sidecar` must not import `pgx` or `database/sql`.
- **In-repo Semgrep rules:** no `UPDATE`/`DELETE` against `events`; no `DELETE FROM` anywhere in `product/backend` (the no-deletes rule); no string `sauna` (case-insensitive) under `product/`.
- **A migration test:** apply all migrations twice against an empty database, which proves idempotency.
- **ESLint with `no-restricted-imports`:** pages must use `api/*`, not `fetch` directly.

### AGT-04 - The model owns deterministic lifecycle steps that mid-tier models do least reliably (High, M)

**Evidence:** `build_prompt` (`tick.sh:582-618`) asks one session to do all of the following:

1. inspect the primary checkout;
2. create a worktree and branch;
3. maintain a JSON state file;
4. implement;
5. commit and push;
6. detect an existing PR, or open a draft one;
7. run `gh pr checks --watch`;
8. remediate up to 3 CI cycles;
9. check readiness and merge;
10. clean up the worktree;
11. post a marker comment.

All of this happens under a single 3,600-second timeout (`FACTORY_SESSION_TIMEOUT`). `builder.md` repeats the same steps in 216 lines.

**Why it matters:** long, stateful tool chains are where mid-tier and free models fail most: skipped steps, wrong markers, a forgotten state-file update, or a merge attempted early. All of these steps are deterministic and need no intelligence. Waiting on CI inside the LLM session also burns wall-clock budget and fills the context with polling output.

**Recommendation:** have `tick.sh`, or a small Python orchestrator (see FAC-17), own the worktree, branch, PR creation, CI wait, merge and markers. Give the model three narrow jobs:

- **Build:** implement the issue in this worktree, run `dev-ops/scripts/check.sh`, and write `PR_BODY.md`.
- **Fix:** here is the failing job's log excerpt (last 200 lines) and the diff; fix the root cause.
- **Review:** a separate session (AGT-10).

This roughly halves the prompt, and the scaffolding cost is no longer paid in tokens. It also removes the need for `gh pr merge*` permission inside the agent, which FAC-03 and SEC-03 recommend anyway.

### AGT-05 - The build prompt requires up to 16 skills, which contradict each other and the prompt (Medium, S)

**Evidence:** `tick.sh:555-576` says "Load and follow these OpenCode skills". The list includes `implement`, `tdd`, `code-review`, `diagnosing-bugs`, `domain-modeling`, `frontend-design`, `webapp-testing`, `pr`, `caveman`, six work-pattern skills, and `caveman-commit`, `caveman-review` and `caveman-compress`. The contradictions:

- `implement` says "Commit your work to the current branch", while the prompt mandates a new `factory/issue-N` worktree branch.
- `tdd` says "Refactoring is not part of the loop", while `safe-refactor` and `code-review` (Fowler smells) push toward refactoring, and the prompt says "smallest change".
- `caveman` stays on for the whole session (`caveman/SKILL.md:17`), while the prompt requires normal prose for PRs and comments.
- `frontend-design` asks for "aesthetic risk", while the open issues #120–#123 require matching the mockups.
- `pr` wants screenshots, which a headless run cannot take.
- `code-review` spawns two sub-agents, which inherit the session model (AGT-10).

**Why it matters:** each skill load adds hundreds to thousands of tokens of instruction to the context, and the model must resolve the contradictions on its own. Different models resolve them differently, which is exactly the nondeterminism the factory metrics can't explain.

**Recommendation:** curate one small set per role, selected by `tick.sh` from area and tier labels, and resolve every conflict in the skill text rather than at runtime:

- **plan:** `domain-modeling` (read mode) and `investigate-first`
- **build:** `es-feature` / `ui-conventions` / `sidecar-rule` (whichever matches the area label), `factory-tdd`, `surgical-patch`, `verify-and-stop`, `factory-pr`
- **fix:** `factory-diagnosing-bugs`, `surgical-patch`, `verify-and-stop`

### AGT-06 - Three sources of truth for each role (agent file, tick prompt, command), and they disagree (Medium, M)

**Evidence:** the builder lifecycle exists in `builder.md` (216 lines), `build_prompt` in `tick.sh:549-627`, and `commands/deliver-issue.md`. Where they disagree:

- The planner's marker is `<!-- factory-plan -->` in `planner.md:29,33`, but the tick prompt uses `PLAN_MARKER='<!-- factory:plan -->'` (`tick.sh:18`).
- The planner's label taxonomy is `bug`/`feature`/`chore`, `size/S|M|L`, `ready-for-build`/`needs-info` (`planner.md:39-41`). None of these labels exist; the factory uses `trivial-task`…`heavy-build-task` (`models.yaml`). The plan prompt only mentions `heavy-build-task` (`tick.sh:537`).
- The fixer is told to "Only handle PRs labeled `factory`" (`fixer.md:38`), but no such label exists.
- These are the same contradictions FAC-12 lists; this report covers their effect on model behaviour.

**Why it matters:** the agent file is loaded as the system prompt (`--agent planner`) and the tick prompt as the user message. When the two disagree, models differ in which one they obey. That gives you inconsistent markers (which break idempotency) and labels that never select the intended model tier.

**Recommendation:**
- The agent file holds the **role, rules and permissions**. The tick prompt holds **only the parameters**: issue or PR number, marker strings, blocking reasons, allowed labels (generated from `models.yaml`), and the curated skill list.
- Delete `deliver-issue.md`, or make it pass the same parameters.
- Add a test in `dev-ops/scripts/tests/` asserting that every marker and label named in `.opencode/agents/*.md` exists in `tick.sh` or `models.yaml`.

### AGT-07 - Domain knowledge isn't in agent-readable form: no glossary, no ADRs (Medium, S)

**Evidence**
- There is no `GLOSSARY.md`, `CONTEXT.md` or `docs/adr/` in the repo. The only ADR-related file is the skill's own template, `.opencode/skills/domain-modeling/ADR-FORMAT.md`.
- `tdd`, `pr` and `domain-modeling` all read `GLOSSARY.md`.
- Real architecture decisions are scattered: the advisory lock in `product/backend/README.md:21-43`, Authelia's role under "Open decisions", the outbox in `AGENTS.md`, and the rest in PR bodies and commit messages.

**Why it matters:** domain terms such as booking, slot, blocked period, broadcast, household/address, and super user vs. admin drive naming in events and APIs. Without a glossary, each model names things its own way. Without ADRs, a later session can "simplify away" a deliberate decision such as the advisory lock.

**Recommendation:** seed `GLOSSARY.md` with about 20 terms taken from `projects/sauna/README.md` and the event names. Seed `docs/adr/` with 5–6 ADRs covering event sourcing on Postgres, the sidecar contract, passwordless email codes, the notification outbox, create-booking serialization, and the "no deletes" rule plus its GDPR consequence (SEC-15). Make the planner cite the relevant terms and ADRs in each plan comment, and add a reviewer check for "contradicts an ADR".

### AGT-08 - Agents are told to use tools they can't run (slash commands, denied scripts) (Medium, S)

**Evidence**
- `plan_prompt` says "use the /create-github-issue command" (`tick.sh:542`). But that command needs a temp file written (step 4), `validate-issue-body.sh` run (step 5) and `gh issue create` (step 7). The planner has `edit: deny` and `bash: "*": deny`, with only `gh issue view/list/comment/edit`, `gh label list`, `gh pr list`, `git` reads and `ls` allowed (`planner.md:5-20`). So the planner can't follow the instruction.
- Slash commands are user-invoked in OpenCode; an agent can read the file but can't "run the command".
- The builder's allow-list (`builder.md:7-27`) doesn't include `gh issue create` or the validator. Whether those run depends on OpenCode's default for unlisted commands plus `--auto`.

**Why it matters:** the model either fails silently or improvises with `gh issue create` directly, skipping the validator, which is exactly what the command was meant to prevent.

**Recommendation:** provide one wrapper script, `dev-ops/scripts/create-issue.sh --title … --body-file …`, that validates and creates the issue, and allow only that script for the roles that need it. For the planner, it's simpler to put proposed follow-ups in a "Follow-ups" section of the plan comment and let the owner create them.

### AGT-09 - `/lint-frontend` is broken and the check commands cover only the backend (Medium, S)

**Evidence**
- `.opencode/commands/lint-frontend.md:8,12` runs `npm run lint` and `npm run typecheck`. `product/frontend-solid/package.json:6-11` defines only `dev`, `build`, `test` and `preview`, so the command always reports "missing script", and there's no ESLint at all (FE-15).
- The build prompt's local checks are backend-only: "gofmt -l ., go vet ./..., go test ./..., go build ./cmd/server for backend" (`tick.sh:605-606`).
- There are no commands for frontend tests (`vitest`), sidecar tests, or the Playwright e2e suite. `test-backend` runs the Postgres integration tests with no hint about how to start a database. Its `${PIPESTATUS[0]}` also assumes bash for command shell interpolation (not verified).

**Why it matters:** frontend and sidecar changes are only checked in CI, so every slip costs a CI round trip plus a fix session. That's the most expensive feedback loop the factory has.

**Recommendation:** add one entry point that both agents and CI call, so they can never disagree:

```sh
dev-ops/scripts/check.sh [backend|frontend|sidecar|e2e|all]   # exit non-zero on failure, bounded output
```

- Add `lint` (ESLint) and `typecheck` (`tsc --noEmit`) scripts to `package.json`.
- Rewrite `/lint-frontend` and `/test-backend` as thin wrappers, and add `/test-frontend`, `/test-sidecar` and `/e2e`.
- Reference `check.sh <area>` in the build prompt, picking the area from the issue's area label.

### AGT-10 - The OpenCode Go model routing doesn't match role risk; the reviewer inherits the builder's model (Medium, M)

**Evidence**
- `models.yaml` maps tiers to `opencode-go/*` models, with backups mostly on `opencode/*-free`. `FACTORY_FREE_MODEL` defaults to `opencode-go/beam-free`, and `normalize_model` appends `#high` to it (`tick.sh:690-699`).
- **The planner picks the tier, and the tier picks the builder model**, so a cheap model decides how much model the work gets. The `plan-task` entry is never used for planning sessions (FAC-10).
- Backup and free models run the **same full lifecycle, including merge** (FAC-07).
- No agent file sets `model:`. The `reviewer` subagent, and the sub-agents `code-review` spawns, therefore inherit the session's model, so review is same-model self-review (FAC-11).
- `light-build-task → opencode-go/claude-haiku-5-5` is unusual for a provider aimed at open models. I could not verify any model ID offline (the factory validates only that IDs are non-empty).
- `temperature: 0.1` is set on every agent. Some reasoning models ignore or reject sampling parameters; whether that applies here depends on the models currently in OpenCode Go.

**Why it matters:** the riskiest decisions (merging, reviewing, architecture-touching changes) can end up on the cheapest model. The review step adds little when it shares the builder's blind spots.

**Recommendation:**
- Route by **role and risk**, not just size. Pin `model:` in `reviewer.md` to a *different model family* from the builder tiers. Use the strongest available model for anything labeled `backend` that touches `eventstore`, `projection` or `command`, and for `dev-ops/factory/**`.
- Backup and free models may plan and may open PRs, but **never merge**. Label such PRs `needs-owner-review`.
- Have `tick.sh` check every `models.yaml` ID at startup against `opencode models opencode-go` (and `opencode models opencode` for the free backups), and fail fast with a clear event.
- Have the planner *propose* a tier, and let a deterministic rule raise it: any change to migrations, eventstore or auth gets at least `standard-build-task`.

### AGT-11 - Permission profiles don't match the roles they serve (Medium, S)

**Evidence**
- `builder.md` and `fixer.md` list allowed `git`/`gh` patterns but have **no `"*"` default**. Unlisted commands (`go`, `npm`, `curl`, `docker`, `cat .env`…) fall to OpenCode's default, and `--auto` approves anything set to `ask`.
- Neither builder nor fixer restricts `webfetch`.
- `"gh pr merge*": ask` combined with `--auto` means the model merges unprompted.
- The planner allows `gh issue edit*` (labels and bodies), which is far more than "apply labels" needs.
- `fixer.md:19` denies `"git push --force"` without the `*` that the builder uses, so `git push --force origin x` is not caught.
- Details and the schema question are in FAC-04 and SEC-04.

**Why it matters (fit angle):** a weaker model given broad permissions is likelier to "solve" a blocker by an off-path action, such as editing CI or calling the API directly. Narrow profiles are guardrails *for the model*, not just security.

**Recommendation:** for builder and fixer, use `"*": deny` and then allow `check.sh`, `go`/`npm` within the worktree, read-only `git`/`gh`, and `git push origin HEAD`. Deny `webfetch` and `gh api*`, and remove merge entirely (AGT-04). For the planner, replace `gh issue edit*` with `gh issue edit * --add-label*` and deny `--add-label "owner approved"` explicitly. Pattern semantics differ between OpenCode versions, so test the deny rules on the box (see the note at the top of FAC-04).

### AGT-12 - Caveman token-saving targets output tokens, but factory cost is in input context (Medium, S)

**Evidence**
- `AGENTS.md` ("Concise reporting") and every agent file mandate the caveman voice "for status lines and inter-agent handoffs".
- Factory sessions are single-agent headless runs: there are **no inter-agent handoffs**, and nobody reads the status lines.
- The large token consumers are all input: the 79-line build prompt plus the 216-line builder file plus `AGENTS.md`, each loaded skill, file reads, `gh run view --log-failed` output, and `gh pr checks --watch` polling.
- `caveman/SKILL.md:17` keeps the voice on "whole session", which works against the rule that PRs and comments stay in normal prose. It also refers to a hook mechanism (`Caveman mode:`) that OpenCode doesn't provide.

**Why it matters:** OpenCode Go is a usage-limited subscription, and the effective limit is driven by total tokens per session. Compressing the model's prose saves little. Compressing what the model reads saves a lot. Terse self-talk also measurably hurts reasoning on weaker models.

**Recommendation:**
- Drop caveman from the factory.
- Cut input instead: the shorter prompts from AGT-04 and AGT-06, the curated skills from AGT-05, CI logs pre-trimmed by `tick.sh` to the failing step's last 200 lines, and `check.sh` output bounded the way `test-backend.md` already does.
- Log input and output tokens per session (FAC-13) so the saving is measured.

### AGT-13 - There is no evaluation harness, so prompt, skill or model changes are never measured (Medium, M)

**Evidence:** recent commits change models (`c35a381 chore(factory): update model definitions`), skills (#96, #98) and prompts (#94, #132). No benchmark or replay exists, and success is judged only by whether the PR merged.

**Why it matters:** with several OpenCode Go models and 22 skills, you can't tell whether a change helped. The 0-failure CI history (ST-08) says nothing about rework or architecture drift.

**Recommendation:**
- Pick 8–10 closed issues as a frozen benchmark, mixing tiers and areas (for example #115, #117, #118 and #119).
- Weekly, or on any change to `.opencode/**`, `models.yaml` or the prompts, replay them in a scratch clone in dry-run/no-push mode.
- Score each run: hidden-test pass rate, `check.sh` pass, diff size against the original, architecture-check violations (AGT-03), tokens and wall time.
- Keep a results table in the repo to inform `models.yaml`.

### AGT-14 - The issue template has no architecture-impact section (Low, S)

**Evidence:** `dev-ops/issue-templates/agentic.md` has generic sections (Problem Statement, Motivation, … Constraints). Nothing asks which events or projections change, whether a migration or a sidecar contract change is needed, or what is out of scope.

**Recommendation:** add an `## Architecture Impact` checklist covering: events added or changed (names), projections or read models affected, migration (y/n), sidecar contract change (y/n), UI routes affected, ADRs relevant. Add an `## Out of Scope` section too. Have the planner fill these in its plan and use them to pick skills (AGT-05) and the tier floor (AGT-10).

### AGT-15 - Skill provenance isn't pinned or reproducible (Low, S)

**Evidence:**
- Every vendored skill's `.source` says `ref: default`, and no `ref:` is set in `dev-ops/skills.yaml`.
- `request-skills.sh:49-59` clones the default branch HEAD and records no commit SHA or content hash. Updates silently take whatever upstream changed.
- Supply-chain details are in SEC-05.

**Recommendation:** pin `ref:` to a commit SHA per skill. Record `sha:` and a tree hash in `.source`. Have CI fail when installed content doesn't match the recorded hash. Review upstream diffs as normal PRs.

### AGT-16 - `opencode.jsonc` keys and the LSP setup are unverified; no config validation (Low, S)

**Evidence:**
- `opencode.jsonc` sets `compaction.keep.tokens`, `compaction.buffer`, `experimental.todo` and `experimental.background_compaction`, plus the disputed `permissions` block (FAC-04 vs. SEC-04). I couldn't confirm the keys against the OpenCode version on the box, and unknown keys may be ignored silently.
- Nothing documents whether `gopls` and `typescript-language-server` are installed on the Ubuntu host. OpenCode's LSP diagnostics are among the cheapest correctness feedback an agent can get.

**Recommendation:** in factory CI, validate `opencode.jsonc` against the `$schema` it declares. On the box, run OpenCode's config debug output once and keep the resolved config in `dev-ops/factory/README.md`. Install the Go and TypeScript language servers and mention them in the factory README's prerequisites.

## Target setup (what "agent-compatible" would look like)

```
.opencode/
  agents/
    planner.md      # role + rules only; "*": deny; label-only edits; proposes tier + skills
    builder.md      # implement + check.sh + PR_BODY.md; no merge, no PR mgmt; "*": deny + allowlist
    fixer.md        # given trimmed failure log + diff; same allowlist
    reviewer.md     # model: <different family>; posts verdict file read by tick.sh
  commands/         # thin wrappers over dev-ops/scripts/check.sh (+ create-issue.sh)
dev-ops/skills/     # first-party, versioned with the code they describe
  es-feature/  db-migration/  sidecar-rule/  notification/  ui-conventions/  e2e/
  factory-tdd/ factory-review/ factory-pr/ factory-diagnosing-bugs/
GLOSSARY.md, docs/adr/0001-…   # domain + decisions, cited by planner and reviewer
product/backend/AGENTS.md, product/frontend-solid/AGENTS.md, projects/sauna/sidecar/AGENTS.md
```

In this setup, `tick.sh` owns the worktree, PR, CI wait, merge and markers, chooses the skills per area and tier, routes models by role and risk, and measures every session against the benchmark.

## Prioritized roadmap

**Now (this week)**
1. AGT-05 / AGT-12: shrink the build prompt's skill list. Drop the caveman family, `implement`, `pdf`, `skill-creator`, `webapp-testing` and `frontend-design` from factory prompts. Add the "no human available" rule (AGT-02).
2. AGT-06: make the planner's markers and labels match `tick.sh` and `models.yaml`, and add the consistency test.
3. AGT-09: add `lint` and `typecheck` scripts (with ESLint), and a `check.sh <area>` used by both prompts and CI.
4. AGT-08: give the planner a "Follow-ups" section instead of `/create-github-issue`.

**Next (this month)**
5. AGT-01: write the `es-feature`, `db-migration`, `ui-conventions` and `e2e` skills, plus per-area `AGENTS.md` files.
6. AGT-03: add architecture tests and in-repo Semgrep rules for CQRS, no-deletes, sidecar statelessness and `product/` neutrality.
7. AGT-07: seed `GLOSSARY.md` and 5–6 ADRs.
8. AGT-10 / AGT-11: pin the reviewer to a different model family, stop backup and free models from merging, check model IDs at startup, and tighten permission profiles to default-deny.
9. AGT-02: make factory variants of `tdd`, `code-review`, `pr` and `diagnosing-bugs`.

**Later**
10. AGT-04: move the deterministic lifecycle into the orchestrator, leaving the model to implement, fix and review.
11. AGT-13: a replay benchmark for prompt, skill and model changes.
12. AGT-14 to AGT-16: the issue-template architecture section, pinned skills, and config and LSP validation.

## Limitations

- **Static reading only.** I read the local clone and its git history. Nothing was run, and no GitHub or web lookups were made for this report.
- **OpenCode behaviour is inferred from the repo's files.** That covers how unknown frontmatter keys are handled, the default for unlisted bash commands, and whether slash commands or nested `AGENTS.md` files load. None of it was confirmed against the OpenCode version on the Ubuntu box.
- **OpenCode Go model availability is unverified.** That includes which model IDs exist and whether they accept a `temperature` setting.
- **Factory tests:** `dev-ops/scripts/tests/test-factory-lib.py` was not executed.
