# Software Factory and AI Agent Setup Review

**Scope:** `dev-ops/factory/**` (`tick.sh`, `lib/factory.py`, `discover_*.py`, `models.yaml`, `hooks/`, `nightly-cleanup.sh`, `otel-collector.yaml`, `validate.sh`, `README.md`), `.opencode/agents/*.md`, `.opencode/commands/*.md`, `opencode.jsonc`, `AGENTS.md`, `dev-ops/skills.yaml`, `dev-ops/scripts/request-skills.sh`, `dev-ops/issue-templates/agentic.md`, `dev-ops/scripts/{check,has,ensure}-acceptance-criteria.sh`, `dev-ops/scripts/validate-issue-body.sh`, `dev-ops/scripts/tests/test-factory-lib.py`, `.github/workflows/*` (triggers only). I skimmed the vendored `.opencode/skills/*/SKILL.md` files. Early in the review I made a few read-only `gh` queries (PRs #141, #146, #150 and #155, issues #85, #112-#125, labels and timelines); every claim that depends on them is marked "(from GitHub metadata)". All other evidence comes from the local clone and `git log`/`git show`.
**Reviewed:** 2026-11-19 at commit `45f6ee5`

---

## Summary

The factory is a single hourly cron script. `tick.sh` finds work on GitHub, and in each tick it runs at most one fix session, then one planning session, then one build session, all one after another. Each session is a non-interactive `opencode run --auto` call, and the agent in it implements the change, opens the PR and merges it itself. The script is careful in places: it uses a global `flock`, atomic claim directories, idempotency markers, classified and retried `gh` errors, and JSONL events. Most of that care, though, goes into keeping the script from tripping over itself. Very little guards against untrusted input or bad agent output.

The repo is public, and the discovery code never checks who wrote an issue, comment or PR. All agents run with the owner's own GitHub credentials. Unlisted shell commands are allowed by default, because the global permission block in `opencode.jsonc` uses a key OpenCode does not recognize. No branch protection exists, and `--auto` approves the agents' `ask` rule on `gh pr merge`, so whether to merge is decided only by the model's reading of the prompt. In practice, 81 PRs were merged with zero reviews (context provided), and some merged before CI had started: #141 merged 2 s after it was opened, and it changed `tick.sh` itself (from GitHub metadata).

There are also correctness gaps. Some PR states make an issue stall permanently. Quota detection gives false positives, which silently move work to free models. Session-ID capture is broken. The factory's own code is never run in CI.

**What's working well**

- **Structured, classified failure handling:** `gh_run_capture` (`tick.sh:82-122`) retries only `transient` and `rate_limit` errors, using categories from `factory.py:77-115`. The script also tells "nothing to do" apart from "discovery failed" (`tick.sh:1117-1127`), which most hobby factories don't.
- **Overlap protection and idempotency are designed in:** there is a global `flock` (`tick.sh:219-225`), `mkdir`-atomic claims with TTL and dead-PID reclaim (`factory.py:256-315`, unit-tested), and fix markers keyed on head SHA plus the blocking reason (`factory.py:234`), so a new push gets a fresh attempt.
- **Agent prompts are good:** they open PRs as drafts first, cap CI remediation at 3 cycles, say "never weaken gates/disable tests", tell the agent to treat issue and PR text as data (`planner.md:51`, `fixer.md:77`, `reviewer.md:122-124`), and give the planner and reviewer a deny-by-default bash allowlist. The PR bodies are high quality: PR #150 has a sequence diagram, before/after test evidence and a list of local checks run (from GitHub metadata).
- **Work enters through a gate:** there is an acceptance-criteria gate before planning, an issue template plus validator, and an `owner approved` label gate before building.
- **Some pure logic is already testable:** discovery and claim logic was moved into `lib/factory.py`, which has 21 pytest cases. `models.yaml` is checked against its schema at startup (`tick.sh:192`). Prompts are passed to OpenCode in 0600 temp files rather than on the command line (`tick.sh:704-707`). Each session runs under a `timeout`.
- **Logs are retained, rotated and shipped:** session logs are kept on failure and deleted on success, there is a logrotate config and a nightly cleanup that preserves dirty worktrees, and the events are shipped to SigNoz through an OTel `filelog` collector.

---

## Findings

| ID | Severity | Effort | Title |
|---|---|---|---|
| FAC-01 | Critical | S | Fork PRs whose branch is named `factory/issue-N` become fix candidates, so attacker code runs on the QA host with the owner's token |
| FAC-02 | Critical | M | Any GitHub user's issue or comment reaches privileged agents, and the planner can apply `owner approved` and rewrite issue bodies |
| FAC-03 | High | M | The merge gate is the model's judgment alone: no branch protection, owner identity, `ask` auto-approved by `--auto`, PRs merged before CI starts |
| FAC-04 | High | S | `opencode.jsonc` uses a non-OpenCode `permissions` schema, builder and fixer have no default-deny, and the deny rules are trivially bypassed |
| FAC-05 | High | M | The factory changes its own guardrails without review or CI, and runs two different code versions (stale primary checkout vs. `origin/main` worktree) |
| FAC-06 | High | M | Some PR states stall an issue permanently (draft PRs, green-but-unmerged PRs, one fix attempt per SHA) and nothing escalates |
| FAC-07 | High | S | Quota detection scans the whole session transcript, so the product's own "rate limit" code triggers reruns on free models, which auto-merge |
| FAC-08 | Medium | S | Planning has head-of-line blocking: only the oldest unlabeled issue is ever considered |
| FAC-09 | Medium | S | Idempotency markers fail open and can be spoofed; infra-failure flags are lost in subshells |
| FAC-10 | Medium | S | `models.yaml`: `plan-task` is never used, model IDs are unverified (e.g. `opencode-go/claude-haiku-5-5`), no availability check, tier is chosen by the planner |
| FAC-11 | Medium | M | No independent review: the `reviewer` agent is never invoked, and self-review uses the same model |
| FAC-12 | Medium | S | Agent definitions contradict the tick prompts (marker names, label taxonomy, `factory` label, draft/ready, skill rules) |
| FAC-13 | Medium | S | Observability: session-ID capture is a Python `SyntaxError`, there are no outcome/cost metrics and no alerting (a silent 6-day stall) |
| FAC-14 | Medium | S | Lock and lifecycle hazards: lock FD inherited by agent children, cleanup without the lock, deferred SIGTERM, stdin leak in the fix loop |
| FAC-15 | Medium | M | No feedback loops: post-merge `main` CI, QA results and repeated failures are never fed back |
| FAC-16 | Medium | M | Sandbox is opt-in, falls back to the host silently, and binds `$HOME` writable on the same box as QA |
| FAC-17 | Medium | L | `tick.sh` should be decomposed: 1,170 lines, about 210 dead, duplicated branches, orchestration untested |
| FAC-18 | Medium | S | Factory code has no CI: `validate.sh` and the factory tests are not wired to any workflow |
| FAC-19 | Low | M | Throughput and prioritization: one plan and one build per hour, FIFO by creation date, worst-case tick about 9 h |
| FAC-20 | Low | S | Worktree handling: falls back to the primary checkout, a dirty shared worktree never recovers, caches wiped every tick |
| FAC-21 | Low | S | Caveman and skills: non-invokable skills are mandated, Classical-Chinese handoffs, unpinned vendored skills, unused skills in context |
| FAC-22 | Low | S | Acceptance-criteria checker copied 5 times (byte-identical), and the validator's rules are inconsistent with it |

---

### FAC-01 - Fork PRs whose branch is named `factory/issue-N` become fix candidates, so attacker code runs on the QA host with the owner's token (Critical, S)

**Evidence**
- `dev-ops/factory/discover_fix_candidates.py:14` fetches `number,headRefName,headRefOid,mergeable,reviewDecision,statusCheckRollup,isDraft,createdAt`. It does not fetch `isCrossRepository`, `headRepositoryOwner` or `author`.
- `dev-ops/factory/lib/factory.py:208-211` decides which PRs are candidates by the branch name alone: `m = re.match(r"^factory/issue-(\d+)$", head)`. `headRefName` for a fork PR is just the fork's branch name.
- A PR is a candidate if it has failing checks **or** `mergeable == "CONFLICTING"` (`factory.py:216-229`). An attacker can trivially make their PR conflict, even if Actions on fork PRs need approval.
- The only other filter checks whether the referenced issue already has a build marker (`tick.sh:1031`). An attacker just picks an open approved issue, all of which are public (currently #120-#125, context provided).
- The fixer then rebases, runs "the project's tests, lint, and typecheck locally" (`fixer.md:62`) and may merge. Its permissions allow `edit` and every unlisted shell command (see FAC-04). The fixer is told "Only handle PRs labeled `factory`" (`fixer.md:38`), but that label does not exist in the repo's label list (from GitHub metadata), and the prompt is the only control.
- The build path probably also treats the fork PR as "the open factory PR" (`tick.sh:489-490`, `gh pr list --head factory/issue-$1`), which blocks the real build. That is a denial of service even if the fixer refuses the work. I have not confirmed how `gh --head` treats fork heads, so treat this as likely.

**Why it matters:** running `go test`, `npm install` or `npm test` on an attacker's branch executes the attacker's code (`TestMain`, `postinstall` scripts). It runs on the Ubuntu box that also hosts QA, as the user whose `gh` token can push to and merge into `main`, which has no protection. No prompt injection is needed: running the attacker's tests is the exploit.

**Recommendation:** filter in `fix_candidates_from_prs`, and add a test for it:
```python
# discover_fix_candidates.py: add isCrossRepository,author to --json
if pr.get("isCrossRepository"):
    continue
if (pr.get("author") or {}).get("login") not in TRUSTED_AUTHORS:   # factory bot login
    continue
```
Also have tick.sh re-check `isCrossRepository == false` right before it starts the session, so a PR changed between discovery and start is still caught. Long term, give the factory its own GitHub App or bot account (see FAC-03) and require that `author.login == bot`.

---

### FAC-02 - Any GitHub user's issue or comment reaches privileged agents, and the planner can apply `owner approved` and rewrite issue bodies (Critical, M)

**Evidence**
- Planning discovery takes any open unlabeled issue, from any author: `gh issue list --state open --limit 200 --json number,labels,createdAt --jq '[.[] | select((.labels | length) == 0)] ...'` (`tick.sh:233-234`). On a public repo, non-collaborators **cannot** add labels, so every outsider issue is unlabeled by construction. The only gate is a `## Acceptance Criteria` heading with one checkbox (`check-acceptance-criteria.sh`), which an attacker can satisfy trivially.
- The planner's prompt says "Never add the "owner approved" label" (`tick.sh:537-538`). Its permissions, however, allow `"gh issue edit*": allow` (`.opencode/agents/planner.md:18`), and that covers `gh issue edit <any> --add-label "owner approved"` and `gh issue edit <any> --body ...`. The rule "Only comment on and label the issue you were given" (`planner.md:55`) is prose only.
- The builder and fixer read every comment on the issue or PR (`tick.sh:584` `gh issue view $1 --comments`; `tick.sh:640` `gh pr view $1 --comments`). Anyone can comment on an approved public issue.
- Because every action is performed as `adamzki99`, the timeline cannot tell an owner approval from an approval made by an agent. For example, issue #120's `owner approved` event lists actor `adamzki99` (from GitHub metadata). The README invariant "Only the repository owner applies `owner approved`" (`dev-ops/factory/README.md:42-43`) cannot be verified.

**Why it matters:** this is a two-step injection chain. An outsider opens an issue with acceptance criteria. On the next tick the planner, a smaller model running with the owner's token, reads it and can be steered into running `gh issue edit 120 --body "<malicious spec>"`, or into labeling the attacker's own issue `owner approved`. The following tick the builder implements it with full shell access and merges it to `main`. The "untrusted input" sentences in the prompts are the only defense, and open-weight models running non-interactively are not reliable against injection.

**Recommendation**
1. In discovery, only consider issues whose author is trusted (`gh issue list --author adamzki99`, or GraphQL `authorAssociation in [OWNER, MEMBER, COLLABORATOR]`). Treat everything else as triage-only.
2. Never let agents fetch raw comments. Have tick.sh build the context itself and pass it in the prompt file: the issue body plus comments from trusted authors only.
   ```bash
   gh issue view "$n" --json body,comments \
     --jq '{body, comments: [.comments[] | select(.author.login=="adamzki99" or .author.login=="factory-bot") | .body]}'
   ```
   Then deny `gh issue view*`, `gh pr view*` and `gh api*` in the agent permissions.
3. Remove `gh issue edit*` from the planner. Let the planner write its labels to a file, and have tick.sh apply only labels from an allowlist (`*-build-task`, area labels), refusing `owner approved`.
4. Make approval verifiable. Once the factory acts as a separate bot (see FAC-03), build discovery should check through the timeline API that the `owner approved` label event's actor is the owner.

---

### FAC-03 - The merge gate is the model's judgment alone: no branch protection, owner identity, `ask` auto-approved by `--auto`, PRs merged before CI starts (High, M)

**Evidence**
- The only statement of the CI gate is prose: "never merge a pull request ... until all required CI checks and security analyses ... pass" (`AGENTS.md:41-44`). `main` has no branch protection or rulesets (context provided). All PRs are authored by the owner account (context provided).
- The agents set `"gh pr merge*": ask` (`builder.md:26`, `fixer.md:28`), but `opencode run --auto` (`tick.sh:707`) is unattended approval. The project's own skill says "Never use OpenCode `--auto`, unattended approval" (`.opencode/skills/dev-server-ssh/SKILL.md:33`), and `dev-ops/README.md:200` makes the same distinction. So `ask` is effectively `allow`.
- tick.sh never checks CI or merge state after a session. A session that exits 0 is logged as `session_ok` (`tick.sh:764-773`) whatever it actually did.
- In practice (from GitHub metadata): PR #141, which changed `tick.sh` and `factory.py`, was opened at 17:54:18 and merged at 17:54:20, before any check had started (the first check started at 17:54:23). PR #146 was merged 7 s after it was opened, while Semgrep was still running until 18:59:32. These came from `factory/issue-132-*` and similar branches, which don't match the tick naming and were probably interactive sessions, but the same rule is the only control either way. The local `git log` agrees: commits `13bfb9a` through `9579bf6` (#138-#145) all changed factory files on 2026-11-18.
- Path filters mean "all required checks green" can be trivially true. `backend-ci.yml` triggers only on `product/backend/**` (`backend-ci.yml:4-11`), and no workflow targets `dev-ops/**` beyond the unfiltered `security.yml` and `semgrep.yml`. PR #155, which touched only `dev-ops/scripts`, shows only 5 security checks (from GitHub metadata).

**Why it matters:** the decision with the most consequence, merging to `main` (which deploys to QA), is made by the least reliable component, sometimes a free fallback model (FAC-07), and nothing outside the model checks it. Because the factory is the owner, GitHub's "you can't approve your own PR" rule also means the owner can never be a required reviewer of factory work. And GitHub does not notify you about your own actions, so the owner gets no notifications for factory PRs.

**Recommendation**
1. Create a dedicated GitHub App or bot account for the factory, with fine-grained `contents:write, pull_requests:write, issues:write` on this repo only.
2. Protect `main` with a ruleset: require PRs, require one always-running aggregate check (below), and block force pushes. Let the `booking-deploy` metadata commit bypass, or better, move it off `main`.
3. Take the merge away from the agent. Deny `gh pr merge*` and `gh api*` in the agent permissions. After a successful build session, tick.sh itself enables GitHub native auto-merge, which waits for the required checks:
   ```bash
   gh pr merge "$pr" --squash --auto --match-head-commit "$sha"
   ```
4. Add a `ci-gate` job that always runs and fails if any triggered workflow failed, so path-filtered workflows can still be required.
5. For anything touching `.github/`, `dev-ops/factory/`, `.opencode/`, `opencode.jsonc` or `AGENTS.md`, require owner review through CODEOWNERS (see FAC-05).

---

### FAC-04 - `opencode.jsonc` uses a non-OpenCode `permissions` schema, builder and fixer have no default-deny, and the deny rules are trivially bypassed (High, S)

> **The two reviews disagree on the schema.** The security review (SEC-04 in `06-security-privacy.md`) checked the OpenCode docs and concluded that `permissions` with action/resource/effect rules *is* the valid key in OpenCode V2, and that the singular `permission` is the deprecated V1 form. Neither claim was tested against the OpenCode version on the Ubuntu box. To settle it, check what `opencode --version` reports there, then try a denied command such as `rm -rf /tmp/x` in a session. Both reviews agree on the parts that matter: the deny patterns are easy to bypass, builder and fixer have no default-deny, and `--auto` approves `ask` prompts.

**Evidence**
- `opencode.jsonc:26-42` declares `"permissions": [ { "action": "shell", "resource": "git push --force*", "effect": "deny" }, ... ]`. OpenCode's config key is the singular `permission`, an object keyed by tool (`edit`, `bash`, `webfetch`, ...) whose values are `allow|ask|deny` or pattern maps, which is the form the agent files themselves use (`planner.md:5-20`). The `action/resource/effect` array is not OpenCode syntax. Sessions start fine, so OpenCode is evidently ignoring the block rather than rejecting it. Its three global denies (`git push --force*`, `git reset --hard*`, `rm -rf*`) are therefore **not in effect**.
- `builder.md:5-27` and `fixer.md:5-29` list allow and deny patterns but have no `"*"` entry, so every unlisted command falls through to OpenCode's default, which is allow. That covers `gh api`, `gh pr merge --admin`, `curl`, `ssh`, `docker`, `rm -rf` and `gh secret`.
- The deny patterns are bypassable as written:
  - `"git push --force*": deny` does not match `git push -f`, `git push origin +HEAD`, or `git -C . push --force`.
  - `"git push origin main*": deny` does not match `git push origin HEAD:main`, or a bare `git push` while on `main`.
  - `fixer.md:19` only denies the exact string `"git push --force"`.
- Depending on the OpenCode version's rule ordering, `builder.md:17-18` (`--force-with-lease*` allow, then `--force*` deny) may also deny the force-with-lease push that the builder prompt tells it to use. I could not determine which rule wins.

**Why it matters:** the config looks like defense in depth but gives none, which is the "wrong key silently grants everything" failure. Combined with FAC-01 and FAC-02, an injected or confused agent can do anything the owner's shell can.

**Recommendation:** replace the block with the real schema and make the default deny. In `--auto` mode, `ask` means allow, so anything not allowlisted must be `deny`:
```jsonc
"permission": {
  "webfetch": "deny",
  "bash": {
    "*": "deny",
    "git status*": "allow", "git diff*": "allow", "git add*": "allow",
    "git commit*": "allow", "git push origin factory/issue-*": "allow",
    "go test*": "allow", "go vet*": "allow", "gofmt*": "allow", "go build*": "allow",
    "npm ci*": "allow", "npm test*": "allow", "npm run lint*": "allow", "npm run build*": "allow",
    "gh pr create*": "allow", "gh pr checks*": "allow", "gh run view*": "allow"
  }
}
```
Add a CI step that validates `opencode.jsonc` and the agent front matter against `https://opencode.ai/config.json` (for example with `ajv`), so an unknown key fails the build. Put a top-level `"*": "deny"` in builder.md and fixer.md as well.

---

### FAC-05 - The factory changes its own guardrails without review or CI, and runs two different code versions (High, M)

**Evidence**
- tick.sh runs from the primary checkout: `SCRIPT_DIR`, `discover_*.py`, `lib/factory.py` and `models.yaml` (`tick.sh:12-16`, `1007`, `1071`). Nothing ever pulls that checkout; tick.sh only fetches and resets the *worktree* (`tick.sh:921-931`).
- After `cd "$FACTORY_WORKTREE"` (`tick.sh:936`), everything is taken from `origin/main` at the latest version: OpenCode loads `opencode.jsonc`, `.opencode/agents/*.md`, `AGENTS.md` and the skills from there, and `dev-ops/scripts/check-acceptance-criteria.sh` (`tick.sh:963`) runs from there too.
- Builder and fixer have `edit: allow` and can merge (FAC-03). A merged change to `.opencode/agents/builder.md` or `opencode.jsonc` widens the next session's permissions with no human in the loop.
- History shows it happening: `git log -- dev-ops/factory` shows commits `13bfb9a` through `9579bf6` (#138-#145) changing `tick.sh`, `factory.py` and the sandbox code on 2026-11-18. Each of those PRs was merged within 0-2 minutes of being opened, #141 in 2 s (from GitHub metadata).

**Why it matters:** the guardrails can be rewritten by the thing they guard, at merge speed. Separately, the orchestrator (stale) and the agent definitions (latest) can disagree. For example, a change to marker strings or discovery rules can be live in the prompts but not in the script, and that produces subtle idempotency bugs.

**Recommendation**
- Add `.github/CODEOWNERS` entries (`/.opencode/ @adamzki99`, `/opencode.jsonc`, `/AGENTS.md`, `/dev-ops/factory/`, `/.github/`), plus a ruleset requiring code-owner review. This only works once the factory is a separate identity (see FAC-03).
- Have tick.sh refuse to *start* sessions if the agent or config files in the worktree differ from a signed-off ref, for example a `factory-config` tag the owner moves by hand:
  ```bash
  git -C "$FACTORY_WORKTREE" diff --quiet factory-config origin/main -- .opencode/agents opencode.jsonc AGENTS.md \
    || { emit_event guardrail_drift; exit 1; }
  ```
- Pin the orchestrator version explicitly: either run tick.sh from a separate deploy checkout that is updated deliberately, or have it re-exec itself from the worktree after the fetch. Don't mix the two.

---

### FAC-06 - Some PR states stall an issue permanently, and nothing escalates (High, M)

**Evidence**
- Builds are always opened as drafts: "create in draft mode: gh pr create --draft ... Do not mark ready for review automatically" (`tick.sh:600-601`, `builder.md:117`).
- Fix discovery skips drafts (`factory.py:206-207`, `if pr.get("isDraft"): continue`).
- Build discovery skips any issue that has an open factory PR, drafts included (`tick.sh:1098-1108`).
- So if a build session times out (`FACTORY_SESSION_TIMEOUT=3600`) or crashes after opening the draft, the issue can never be picked up again by either path.
- A non-draft PR whose checks are all green but which wasn't merged (the session died between `gh pr ready` and the merge) has no reason in `fix_candidates_from_prs`, so it is also never picked up. `mergeable == "UNKNOWN"` is likewise not a reason.
- Fix markers are keyed on `sha:reasons` (`factory.py:234`). If one fix attempt posts its marker and fails, for example because of a CI flake, the PR is never retried until someone pushes. If the session dies *before* posting the marker, it is retried every hour with no limit.
- No path ever comments, labels or notifies on any of these states, and every action is by the owner, so GitHub sends the owner no notifications either.

**Why it matters:** these are silent permanent stalls in a system that is supposed to run unattended. The owner sees "nothing to do" (`tick.sh:1124-1126`) while approved work sits idle.

**Recommendation:** handle every PR state explicitly in `fix_candidates_from_prs`, and give each issue an attempt budget:
```python
if pr.get("isDraft") and age_minutes(pr) > SESSION_TIMEOUT_MIN: reasons.append("stale-draft")
if not reasons and all_green(rollup) and mergeable == "MERGEABLE": reasons.append("unmerged-green")
```
Count earlier `factory:fix-pr` markers on the PR. After N attempts (say 3), apply a `factory-blocked` label, post a summary, and skip the PR until a human removes the label. Make tick.sh, not the agent, post a `factory:attempt` marker *before* each session, so failed sessions still count against the budget.

---

### FAC-07 - Quota detection scans the whole session transcript, so the product's own "rate limit" code triggers reruns on free models, which auto-merge (High, S)

**Evidence**
- `start_session` captures the whole session's JSON output: `out="$(run_opencode ... 2>&1 | tee "$logfile")"` (`tick.sh:759`). On any non-zero exit, including timeout 124, it runs `is_usage_filled "$out"` (`tick.sh:777`).
- The classifier is a plain substring match over all of that text: `"rate limit" in out`, `"limit exceeded"`, `"quota" and "exceed"`, `"usage" and "exceed"` (`factory.py:127-139`, duplicated in `tick.sh:514-518`). The transcript includes tool output: files the agent read, grep results, CI logs and issue text.
- The product contains these exact phrases: `product/backend/internal/auth/model.go:21` ("exceeded a rate limit"), `internal/ratelimit/limiter.go:1` ("rate limiter") and `server/server.go:71` ("rate limited"). One of the queued approved builds, #125 ("Reduce absolute session lifetime", context provided), works in `internal/auth`.
- On a match in `backup` mode (the default), the *whole task* is rerun first with `backup_model` and then with `FACTORY_FREE_MODEL` (`tick.sh:785-865`). Every backup in `models.yaml` is a `*-free` model (`models.yaml:21-38`), including `heavy-build-task → opencode/hy4-flash-free`. Those reruns have the same merge authority (FAC-03).
- I could not verify whether `opencode run` exits non-zero when it hits a provider quota error. If it exits 0, real quota exhaustion is never detected at all.

**Why it matters:** an ordinary failure on an auth or iCal task becomes up to two more hour-long sessions on weaker free models, which can then merge without review. The quality of shipped code silently drops to the cheapest model, and the JSONL logs it as `backup_ok`.

**Recommendation**
- Classify quota errors only from structured error events. Parse the `--format json` stream and inspect only error objects (provider error name or HTTP 429/402), or only stderr, never tool output.
- For `build` and `fix`, change the default to `--on-usage-filled=skip`: defer to the next tick rather than downgrade the model. Allow free fallbacks only for `plan`, whose output a human approves anyway.
- If you keep the fallbacks, label PRs produced by a fallback model `factory:fallback-model` and never auto-merge them.

---

### FAC-08 - Planning has head-of-line blocking: only the oldest unlabeled issue is ever considered (Medium, S)

**Evidence:** the discovery query returns a single issue: `sort_by(.createdAt) | .[0].number // empty` (`tick.sh:234`). If that issue already has a plan marker (`tick.sh:952-956`), or lacks acceptance criteria (`tick.sh:966-969`), or the checker errors (`tick.sh:970-973`), `plan_issue` is cleared and **no** planning happens that tick. The next tick picks the same issue again.

**Why it matters:** one old unlabeled issue stops all planning permanently. That could be a human-written bug report without an AC section, an issue whose planner run failed to label it, or a spam issue from an outsider (FAC-02). The only symptom is a repeating `plan_skipped` event.

**Recommendation:** return all candidates and loop until one passes the gates. Also apply the trusted-author filter from FAC-02.
```bash
--jq '[.[] | select((.labels|length)==0)] | sort_by(.createdAt) | .[].number'
# then: while read -r n; do has_marker ... && continue; check-ac ... || continue; plan_issue=$n; break; done
```
Consider auto-labeling issues that fail the gate with `needs-acceptance-criteria`, so they leave the unlabeled pool.

---

### FAC-09 - Idempotency markers fail open and can be spoofed; infra-failure flags are lost in subshells (Medium, S)

**Evidence**
- When `gh` fails, `has_marker` and `has_pr_marker` print `false` and return 0 (`tick.sh:457-463`, `470-476`), which means "not done". The fail-open lets planning and fixing run again on an API hiccup. Builds are partly protected by the open-PR check, which fails closed (`tick.sh:1099-1103`).
- These functions are called inside command substitutions (`"$(has_marker ...)"`, `tick.sh:952`, `1026`, `1031`, `1093`) and `open_pr="$(open_factory_pr_for_issue ...)"` (`tick.sh:1099`). The `INFRA_FAILURE=1` assignments inside them run in a subshell and are lost, so the `discovery_failed` logic at `tick.sh:1118` never sees them.
- A marker counts if it appears anywhere in any comment, whoever wrote it: `[.comments[].body | contains($marker_json)] | any` (`tick.sh:458`). Any GitHub user can post `<!-- factory:build -->` (invisible when rendered) on an approved issue to stop it ever being built, or post a fix marker on a PR.

**Recommendation:** make the check fail closed and filter by author:
```bash
gh issue view "$1" --json comments \
  --jq "[.comments[] | select(.author.login==\"$FACTORY_LOGIN\") | .body | contains($marker_json)] | any"
# on failure: echo "unknown"; callers treat unknown as skip
```
Return status codes rather than echoing strings, and set `INFRA_FAILURE` in the caller based on the exit code.

---

### FAC-10 - `models.yaml`: `plan-task` is never used, model IDs are unverified, no availability check, tier is chosen by the planner (Medium, S)

**Evidence**
- `models.yaml:20-22` maps `plan-task → opencode-go/qwen3.7-plus`, and the README says "`plan-task` selects the planning model" (`README.md:203-204`). But planning calls `model_for_labels` with **no labels** (`tick.sh:1130`), so `factory.py:67-70` returns `default` (`opencode-go/deepseek-v4-pro`). The planner model setting does nothing.
- `light-build-task: opencode-go/claude-haiku-5-5` (`models.yaml:31`). OpenCode Go is OpenCode's subscription for open-weight models; I can't confirm that a Claude model is served through the `opencode-go/` provider. Verify it with `opencode models opencode-go` on the host.
- `normalize_model` appends `#high` to `opencode-go/beam-free` (`tick.sh:683-686`, duplicated in `factory.py:13-19`). This is used for `trivial-task` (`models.yaml:34`) and as the last-resort `FREE_MODEL`. I couldn't confirm that `#<variant>` is accepted by `opencode run --model`; if it isn't, every trivial build (#124 is queued) and every free fallback fails.
- `validate-models` checks only the schema, not whether the models exist (`factory.py:22-52`). Commit `c35a381` ("Replace unavailable opencode/glm-5.3-flash-free backups") shows a backup that silently didn't exist until someone noticed.
- The planner chooses the cost tier label (`tick.sh:536-537`) and nothing caps it. The fixer inherits the issue's tier (`tick.sh:1045-1046`), so a gofmt-only CI failure on a `heavy-build-task` PR uses the most expensive model.

**Recommendation**
- Pass the label explicitly: `model_for_labels plan-task`.
- At tick start, cache `opencode models` and fail validation, with an event, if any configured model or backup is missing.
- Put fix sessions on their own `fix-task` entry: a mid-tier model, and the issue's tier only when the reason is `changes-requested`.
- Record `model` and the tier in the PR body, so quality can be compared across tiers later (FAC-15).

---

### FAC-11 - No independent review: the `reviewer` agent is never invoked, and self-review uses the same model (Medium, M)

**Evidence:** `.opencode/agents/reviewer.md:3` (`mode: subagent`) defines a solid read-only reviewer with blocker/major/minor verdicts. Nothing in `tick.sh`, `builder.md`, `fixer.md` or `.opencode/commands/` references it; a grep for `reviewer` turns up only the file itself. The build prompt says only "`code-review` - review changes before landing when available" (`tick.sh:558`), which is a skill the *same* session loads, so the builder reviews its own diff with the same model. None of the 81 merged PRs has a review decision (context provided), and PR #150 has 0 reviews (from GitHub metadata).

**Why it matters:** self-review by the author model catches far fewer defects than review by a different model. With no human review (FAC-03), this is the only check on correctness or security beyond CI.

**Recommendation:** add a `review` stage to the tick. When a factory PR has green checks and no `factory:review:<sha>` marker, run `--agent reviewer` with a **different model family** from the builder (for example `kimi` reviews `deepseek` output and vice versa). tick.sh, not an agent, posts the verdict as a PR review comment. Only enable auto-merge (FAC-03) after `APPROVE`. A `REQUEST_CHANGES` result already plugs into the `changes-requested` fix path, once the bot identity makes `reviewDecision` meaningful.

---

### FAC-12 - Agent definitions contradict the tick prompts (Medium, S)

**Evidence**
- **Marker name:** `planner.md:29,33` uses `<!-- factory-plan -->` ("If one exists, update it instead of posting a second"), while tick.sh uses `<!-- factory:plan -->` (`tick.sh:18`). Real plan comments use the tick.sh form (issues #112-#125, from GitHub metadata), so the planner's own duplicate check never matches.
- **Labels:** `planner.md:39-41` asks for `feature/chore`, `size/S|M|L` and `ready-for-build/needs-info`. These conflict with the taxonomy defined in the repo (`models.yaml` tiers plus the area labels in `dev-ops/factory/README.md:198-204`). The repo's label list contains none of them except `bug` (from GitHub metadata). The tick prompt says to use `gh label list`, so the planner has no way to say "needs info".
- **`factory` label:** `fixer.md:38` says "Only handle PRs labeled `factory`". Nothing in the factory code applies such a label, and PRs #150 and #155 carry no labels (from GitHub metadata).
- **Draft vs. ready:** the build prompt says "Do not mark ready for review automatically" (`tick.sh:601`) and later "transition draft to ready if required (gh pr ready)" (`tick.sh:614-615`).
- **Issue creation:** the plan prompt says to use `/create-github-issue` (`tick.sh:542-545`), but the planner's permissions are `"*": deny` (`planner.md:9`), so it cannot run `validate-issue-body.sh` or `gh issue create`.
- **Skills:** `AGENTS.md:23-26,60-61` says to load a skill "only via the `skill` tool when the user explicitly requests it", but the build prompt tells the agent to load 17 skills on its own judgment (`tick.sh:555-575`). Factory sessions have no user.

**Why it matters:** with weaker models, contradictory instructions lead to inconsistent behavior from run to run: the agent stops ("PR not labeled factory"), posts duplicates, or ignores the skills. The contradictions also make prompt changes hard to reason about.

**Recommendation:** make one source of truth per role. Keep the agent `.md` files as the full specification, and reduce the tick prompts to parameters (issue, PR, reasons, marker). Fix the five contradictions above, and add a test that greps the agent files for the marker constants defined in tick.sh.

---

### FAC-13 - Observability: session-ID capture is a Python `SyntaxError`, there are no outcome/cost metrics and no alerting (Medium, S)

**Evidence**
- `tick.sh:763` runs `python3 -c 'import sys,json\nfor line in sys.stdin:\n try: ...'`. Inside bash single quotes, `\n` is a literal backslash-n, so Python sees one line and fails with `SyntaxError: unexpected character after line continuation character`. I reproduced this with the same string; the error is hidden by `2>/dev/null`. So `session_id` is **always empty** in every event, even though commit `e27f44a` advertises "session id capture".
- No event records what a session *achieved* (PR number, merged or not, marker posted), what it cost (tokens or spend per model, which is in the `--format json` stream), or which fallback tier produced the merge.
- A long session makes the next tick exit 0 with `lock_skipped` (`tick.sh:221-225`), and `nothing_to_do` also exits 0. The collector config only ships logs (`otel-collector.yaml:41-46`), and the repo defines no alert.
- Planning activity in practice (from GitHub metadata): issues #112-#120 were planned on 2026-11-11 by 17:02. The next plan was posted on 2026-11-17 at 19:09 (#121), while #121-#125 had been waiting with acceptance criteria. The local `git log` shows the same gap: no commits on `main` between `e997b0e` (#130, 2026-11-11 17:30) and `d7d6d22` (#131, 2026-11-17 19:36). Nothing in the repo would have flagged a 6-day stall. The cause can't be determined from the repo (the host may simply have been off).
- `output_tail` ships the last 16 KiB of the raw transcript to SigNoz (`tick.sh:900-904`). That can include `.env` contents the agent read on the QA host.

**Recommendation**
- Fix the one-liner: `session_id="$(printf '%s\n' "$out" | jq -r 'select(.sessionID) | .sessionID' | head -1)"`, and add a bats or pytest case for it.
- Emit `session_outcome` with `pr`, `merged`, `head_sha`, `model_used`, `tokens_in/out` and `cost` parsed from the JSON stream.
- Define SigNoz alerts for: no `session_ok` in 6 h while approved issues exist, more than 3 `lock_skipped` in a row, any `free_retry` or `backup_ok`, and `discovery_failed`.
- Default `FACTORY_LOG_SESSION_OUTPUT=metadata` for shipped events, and keep the full tail local.

---

### FAC-14 - Lock and lifecycle hazards (Medium, S)

**Evidence**
- **Inherited lock FD:** `exec 9>".../factory-tick.lock"` (`tick.sh:219`) is inherited by `opencode` and everything it runs. A daemon left behind by an agent (`docker compose up -d` helpers, `npm run dev &`, a stray `gh pr checks --watch`) keeps the `flock` held, and every later tick exits 0 with `lock_skipped`.
- **Cleanup without the lock:** `nightly-cleanup.sh` doesn't take that lock, and it runs `git worktree remove --force "$FACTORY_WORKTREE"` whenever that worktree is clean (`nightly-cleanup.sh:118-135`). If it runs at the moment a session starts, it deletes the session's working directory.
- **Deferred SIGTERM:** the trap at `tick.sh:215-216` can't run while bash waits on `$(run_opencode ...)`, so stopping a tick doesn't stop the session until `timeout` fires (up to 1 h, or about 3 h with fallbacks).
- **stdin leak in the fix loop:** the loop reads candidates from a here-string (`tick.sh:1023-1061`), and `run_opencode` inherits that stdin. If `opencode run` appends piped stdin to the message, which I believe it does but have not confirmed, the remaining candidate lines, including other PRs' markers, are injected into the fixer prompt.
- **Variable mismatch:** `nightly-cleanup.sh:70` reads `FACTORY_LOG_DIR`, while tick.sh uses `FACTORY_SESSION_LOG_DIR`. The defaults match, but overriding one silently breaks the cleanup.

**Recommendation**
```bash
timeout ... "${sandbox[@]}" opencode "${args[@]}" </dev/null 9>&-      # tick.sh run_opencode
flock -n "$(git rev-parse --git-dir)/factory-tick.lock" true || exit 0   # top of nightly-cleanup.sh (or flock -w)
```
Run the session with `setsid`, and in `on_signal` kill the process group. Use one environment variable name for the log directory.

---

### FAC-15 - No feedback loops: post-merge `main` CI, QA results and repeated failures are never fed back (Medium, M)

**Evidence:** discovery only looks at unlabeled issues, approved issues and open `factory/issue-*` PRs (`tick.sh:233`, `discover_*.py`). Nothing reads:
- push-triggered workflow failures on `main` (`backend-ci.yml:8-11` and `security.yml:5-7` run on push);
- QA deploy outcomes (`booking-deploy` commits such as `33cde20` "record qa deploy");
- Playwright runs;
- the factory's own `session_failed` history.

No lessons or memory file is maintained, and failed attempts leave no structured trace on the issue.

**Why it matters:** a regression merged by the factory stays on `main` until a human notices. The same class of mistake (for example gofmt, which prompted the "fix: gofmt iCal PR" commit `fd778fc`) recurs because nothing feeds it back into the prompts.

**Recommendation**
- Add a `main-health` discovery step: if the latest push run on `main` failed, open, or comment on, a `factory:main-broken` issue that the owner pre-approves by policy, and pause new builds until `main` is green.
- Have `deploy-environment.sh` emit a JSONL event or GitHub status on QA smoke failure that the tick consumes.
- After each failed session, append a short structured entry (issue, failure class, what the CI log said) to a `dev-ops/factory/LESSONS.md`. The builder reads it, and only tick.sh writes it.

---

### FAC-16 - Sandbox is opt-in, falls back to the host silently, and binds `$HOME` writable on the same box as QA (Medium, M)

**Evidence:** `FACTORY_CONTAINER_MODE` defaults to `0` (`tick.sh:31`), and if `bwrap` is missing it silently falls back to the host (`tick.sh:696-698`). Even in bwrap mode, `--bind "$HOME" "$HOME"` (`tick.sh:694`) leaves `~/.config/gh/hosts.yml`, `~/.ssh` and the OpenCode auth writable and readable, and the network is shared. The README says this honestly (`README.md:120-125`). The box also hosts the QA environment and its `.env` secrets (context provided).

**Recommendation**
- Run each session in a disposable container or rootless Podman. Mount only the worktree, pass a short-lived installation token (from the GitHub App in FAC-03) as an environment variable, and restrict egress to GitHub, the module proxy, npm and the OpenCode endpoint.
- Make `CONTAINER_MODE=1` with no sandbox available a hard failure, not a fallback.
- Run QA under a different Unix user from the factory.

---

### FAC-17 - `tick.sh` should be decomposed (Medium, L)

**Evidence**
- 1,170 lines. About 210 of them, `approved_build_candidates` and `fix_pr_candidates` (`tick.sh:243-452`), are dead copies "retained for reference" of logic that now lives in `discover_*.py` and `factory.py`.
- `start_session` (`tick.sh:735-909`, 175 lines) repeats `if [[ "$kind" == "fix" ]]; then emit_event ... pr= ...; else ... issue= ...; fi` 10 times, and duplicates the run/classify/log sequence three times (primary, backup, free).
- `normalize_model` and `is_usage_filled` exist in both bash and Python (`tick.sh:503-521,680-689` vs `factory.py:13-19,127-139`).
- `emit_event` starts a new Python interpreter for every event.
- The 21 tests in `test-factory-lib.py` cover only `factory.py`. None of the behavior that matters in tick.sh is tested: selection order, the gate sequence, fallback chains, claim/marker interplay. FAC-06, FAC-07, FAC-08 and FAC-09 would all have been caught by orchestration tests.

**Recommendation:** move the orchestration into a Python module, `dev-ops/factory/factory_tick.py`, with injectable `GitHub` and `OpenCode` adapters. Keep a bash wrapper of about 30 lines for `flock`, `PATH` and `exec python3 -m factory_tick "$@"`. Structure it as
`discover() -> [Candidate]`, `gate(c) -> Decision`, `run_session(kind, ref, models) -> Outcome`, `record(outcome)`,
with a single `Session` dataclass carrying `ref_kind` (issue or pr), so the 10 duplicated branches go away. Test it with recorded `gh` JSON fixtures and a fake OpenCode that returns scripted exit codes and outputs. Delete the legacy heredocs now (S effort) even if the rewrite comes later.

---

### FAC-18 - Factory code has no CI (Medium, S)

**Evidence**
- `dev-ops/factory/validate.sh` runs `bash -n`, shellcheck, py_compile, `validate-models` and pytest, and `dev-ops/scripts/tests/` has shell tests too. No workflow runs any of them: none of the `.github/workflows/*` files mentions `factory`, `validate.sh` or `test-factory-lib`.
- The workflow triggers are path-filtered to `product/backend/**`, `product/frontend-solid/**` and `projects/sauna/sidecar/**` (`backend-ci.yml:4-11`, `frontend-ci.yml:4-13`, `sidecar-ci.yml:4-13`). A PR that changes only `dev-ops/` gets only the security scans from the unfiltered `security.yml` and `semgrep.yml` (PR #155 shows 5 security checks, from GitHub metadata).

**Why it matters:** the most privileged code in the repo is the least tested before merge. The `SyntaxError` in FAC-13 is exactly what a smoke test would catch.

**Recommendation:** add `.github/workflows/factory-ci.yml` (`on: pull_request: paths: ['dev-ops/**', '.opencode/**', 'opencode.jsonc', 'AGENTS.md']`) that runs `dev-ops/factory/validate.sh`, `dev-ops/scripts/tests/*.sh`, shellcheck (treat its absence as a failure), and the JSON-schema check of `opencode.jsonc` from FAC-04. Make it part of the `ci-gate` from FAC-03.

---

### FAC-19 - Throughput and prioritization (Low, M)

**Evidence**
- A tick runs at most 1 fix, then 1 plan, then 1 build, in sequence (`tick.sh:1000-1163`), from an hourly cron (`README.md:158`).
- Worst case per session is the primary run plus backup plus free, each up to `FACTORY_SESSION_TIMEOUT=3600`, so about 3 h. A full tick can therefore take about 9 h, and every tick in that window is `lock_skipped`.
- Planning is one issue per hour: `tick.sh:233-234` selects a single issue. Issues #112-#120, created together on 11-10, were planned about one per hour over 16 h (from GitHub metadata).
- Builds are ordered by GitHub Project "Build order" if a project exists, otherwise by issue `createdAt` (`factory.py:240-249`). There is no priority label. Today #85 (approved 08:49) was built before #125 (approved 08:41) because #85 is older (from GitHub metadata).
- The "later-numbered" work (#132, #136, #144, #147) went through branches not named `factory/issue-N` (for example `chore/factory-model-definitions`, from GitHub metadata), outside the tick. The queue is bypassed whenever the owner works interactively.

**Recommendation**
- Cap each tick's total time: give up on fallbacks if less than 20 minutes remain before the next tick.
- Plan up to N issues per tick on a cheap model; plans are read-only and need owner approval anyway.
- Add a `priority/high` label that sorts before age.
- Since claims and per-issue worktrees already exist, allow 2 concurrent builds in different areas (`backend` vs `frontend` label) under separate worktrees, once FAC-14 is fixed.

---

### FAC-20 - Worktree handling (Low, S)

**Evidence**
- **Fallback to the primary checkout:** if `git worktree add` fails, the script logs "continuing in $REPO_ROOT" (`tick.sh:914-917`) and sessions run in the primary checkout. That breaks the README invariant "Never touch the primary checkout" (`README.md:37-38`).
- **No recovery from a dirty worktree:** if a session leaves the shared worktree dirty, every later tick skips the reset (`tick.sh:928-935`) and runs agents on a stale tree with stale agent definitions, forever.
- **Caches wiped:** `git clean -fdx` every tick (`tick.sh:931`) deletes `node_modules` and build caches inside the tree, so every frontend session reinstalls dependencies.
- **Unmanaged per-issue worktrees:** agents create per-issue worktrees wherever they choose (`builder.md:88`, `git worktree add <path>`). `nightly-cleanup.sh:118-120` only recognizes `$FACTORY_WORKTREE` and paths under `/tmp/opencode`, so others pile up.

**Recommendation**
- Make worktree failure fatal (`|| die`).
- If the shared worktree is dirty for more than 2 ticks, stash it to a `factory/rescue-<ts>` branch, emit an event, and reset.
- Have tick.sh create the per-issue worktree at a fixed path (`$FACTORY_WORKTREES/issue-N`) and pass that path into the prompt.
- Use `git clean -fdx -e node_modules`, or keep caches outside the tree.

---

### FAC-21 - Caveman and skills (Low, S)

**Evidence**
- `AGENTS.md:63-66` tells agents to use `caveman`, `ultracave` and `megacave`, and `builder.md:209-210` mentions `/ultracave` and `/megacave`. Both of those skills are `disable-model-invocation: true` (`.opencode/skills/ultracave/SKILL.md`, `megacave/SKILL.md`), so the model cannot load them.
- `megacave` is "Caveman in Classical Chinese: 文言文 register", which is a poor choice for handoffs between open-weight models working in an English codebase.
- The caveman modes "stay on until 'stop caveman'", which risks leaking terse style into the PR bodies that the rules require in normal prose. I saw no leak so far: the body of #150 is normal prose (from GitHub metadata), and so are the squash-merge commit messages in `git log` (e.g. `b1b1ae1`).
- In `opencode run`, status lines are a negligible share of tokens. The cost is input context: the build prompt lists 17 skills (`tick.sh:555-575`), and every session's available-skills list includes unused vendored skills (`pdf` 90 KB, `skill-creator` 269 KB; neither is referenced).
- Every `dev-ops/skills.yaml` entry lacks a `ref`, so the recorded provenance is `ref: default` (`.opencode/skills/caveman/.source`) and can't be traced to a commit. `caveman-compress` vendors executable Python scripts and "Sends the file's text to the configured model provider."
- The "skill protection" rule (`AGENTS.md:23-26`) is instruction-only, and it conflicts with the build prompt (FAC-12).

**Recommendation**
- Drop the caveman instructions from factory prompts and AGENTS.md, and keep them for interactive use if you like them.
- Remove `pdf`, `skill-creator`, `ultracave`, `megacave` and `caveman-compress` from `skills.yaml` and `.opencode/skills/`.
- Pin every `ref` to a commit SHA, and record the SHA in `.source`.
- Replace the long skill list in the build prompt with 3-4 skills that actually apply (`implement`, `tdd`, `pr`, `diagnosing-bugs`).
- Spend the token budget on real costs instead: limit `gh run view --log-failed` to a tail, and use a cheaper planning model (FAC-10).

---

### FAC-22 - Acceptance-criteria checker copied 5 times, and the validator's rules are inconsistent with it (Low, S)

**Evidence**
- `dev-ops/factory/ensure-acceptance-criteria.sh`, `dev-ops/factory/hooks/ensure-acceptance-criteria.sh`, `dev-ops/scripts/check-acceptance-criteria.sh`, `ensure-acceptance-criteria.sh` and `has-acceptance-criteria.sh` have the same md5 (`101a540b…`). Only `check-` is called (`tick.sh:963`).
- `validate-issue-body.sh:39` accepts a `- [ ]` checkbox *anywhere* in the file. The checker requires it inside the AC section and also accepts `[x]` and `*` bullets (`check-acceptance-criteria.sh:72`).
- `validate-issue-body.sh:46` runs the empty-section check with `|| true` and then runs it again as fatal at `:68`.

**Recommendation:** keep `dev-ops/scripts/check-acceptance-criteria.sh` and delete the other four. Have `validate-issue-body.sh` call it for the AC rule and drop the duplicate Python block.

---

## Prioritized roadmap

**Now (this week): close the doors to untrusted input**
1. FAC-01: filter fork and untrusted-author PRs in `fix_candidates_from_prs`, with a test.
2. FAC-02: add an author/association filter to plan and build discovery; remove `gh issue edit*` from the planner; have tick.sh apply the planner's labels from an allowlist.
3. FAC-04: rewrite `opencode.jsonc` as `permission` with `"*": "deny"`; add `"*": "deny"` and explicit allowlists to builder and fixer; deny `gh pr merge*` and `gh api*`.
4. FAC-07: restrict quota classification to error events; default to `--on-usage-filled=skip` for build and fix.
5. FAC-13 (part): fix the `session_id` one-liner and add an alert for "no successful session in 6 h with approved work".
6. FAC-14 (part): add `</dev/null 9>&-` to the opencode call and take the lock in nightly-cleanup.

**Next (this month): make merges governed and the pipeline self-healing**
1. FAC-03: create a factory GitHub App or bot identity, a ruleset on `main` with a `ci-gate` required check, and have tick.sh enable native auto-merge (`--match-head-commit`).
2. FAC-18: add `factory-ci.yml` that runs `validate.sh` and the shell tests on changes to `dev-ops/**` and `.opencode/**`.
3. FAC-05: add CODEOWNERS for the guardrail files and the config-drift check; run the orchestrator from one deliberate code version.
4. FAC-11: add a reviewer stage that uses a different model family, and auto-merge only on `APPROVE`.
5. FAC-06, FAC-08, FAC-09: handle stale-draft and green-unmerged PRs, add an attempt budget and a `factory-blocked` label, loop over planning candidates, and make markers fail closed and author-filtered.
6. FAC-10, FAC-12: fix the `plan-task` lookup, add a model availability check at startup, add a `fix-task` tier, and reconcile the agent files with the tick prompts.
7. FAC-15: add `main-health` discovery and ingest QA deploy results.

**Later: architecture and efficiency**
1. FAC-17: move orchestration into a tested Python module and delete the dead heredocs (the deletion can happen immediately).
2. FAC-16: run each session in a disposable container with a short-lived token and egress limits, and separate the Unix users for QA and the factory.
3. FAC-19: cap tick time, plan in batches, add a priority label, and run 2 concurrent area-scoped builds.
4. FAC-20, FAC-21, FAC-22: worktree hygiene, pruning and pinning the skills, and removing the duplicate scripts.
