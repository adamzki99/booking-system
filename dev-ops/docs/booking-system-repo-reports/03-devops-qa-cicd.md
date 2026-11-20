# QA Environment, Deployment, CI/CD and Observability Review

**Scope:** `dev-ops/scripts/{deploy-environment,install-deploy-timer,dev-server-agent,get-login-code,run-playwright}.sh`, `dev-ops/scripts/tests/*.sh`, `dev-ops/environments.yaml`, `dev-ops/.env.example`, `dev-ops/README.md`, `dev-ops/skills/dev-server-ssh/SKILL.md`, `dev-ops/testing/**`, `dev-ops/signoz/**`, `dev-ops/self-hosting-cloudflare-tunnel.md`, `dev-ops/tls-letsencrypt.md`, `.github/workflows/*`, `.semgrep.yml`, `.semgrepignore`, `projects/sauna/{docker-compose*.yml,setup.sh,config/Caddyfile,config/authelia/configuration.yml,.env.example,scripts/,README.md}`, the Dockerfiles under `product/` and `projects/sauna/sidecar`, and `product/backend/migrations` plus `internal/eventstore` as they relate to deploy. I also looked at GitHub workflow runs and logs, issues #85, #86, #89 and #101, and PRs #153–#155, using read-only `gh`. The factory (`dev-ops/factory/**`, `.opencode/**`) is out of scope and is mentioned only where it affects the QA host.
**Reviewed:** 2026-11-19 at commit 45f6ee5

> **Note:** This was a static review. I ran no scripts and touched nothing on the QA host. Claims about the host's runtime state, such as firewalling, the `.env` contents or whether TLS is enabled, are inferred from the repo, issue bodies and logs. Each such claim is marked as inferred. Evidence taken from GitHub issues, PRs, workflow runs and logs (gathered read-only before the review switched to local-clone-only) is marked **(from GitHub metadata)**. Everything else was checked against the local clone at 45f6ee5.

---

## Summary

QA is a single Docker Compose stack: Caddy, a frontend volume publisher, the Go backend, the sidecar, Postgres 16 and an optional Authelia. It runs on the same 3.2 GB Ubuntu box as the hourly AI factory and a persistent SigNoz stack. A systemd user timer runs `deploy-environment.sh` at 00:00 and 12:00 Europe/Stockholm. The script does `git fetch` and `rebase` to `origin/main`, then `docker compose up -d --build`, polls `/healthz` for 120 s, and pushes a `chore(dev-ops): record qa deploy` commit straight to `main`.

The scripts are carefully written and have stubbed tests, but the operating model around them is weak:

- **Failed deploys go unnoticed.** Alerts are GitHub issues filed with the owner's own token, so GitHub does not notify the owner. Several failure paths never alert at all. QA was not deployed from 2026-11-10 to 2026-11-19: #85, #86 and #89 were all opened on 11-10 and closed on 11-19 (from GitHub metadata).
- **Nothing gates what reaches QA.** No branch protection, a Semgrep job that silently scans nothing, and a single Playwright test that cannot pass and is never run.
- **No rollback, no versioned images and no backups.** The Postgres event store is the system of record and is not backed up.
- **The failure-alert mechanism leaks data.** It has already posted raw backend logs, including a login code and email address, to a public issue (#101, from GitHub metadata).
- **No path to production exists.** There is no prod environment, no image registry, no tags and no releases.

**What's working well**
- **Deploy locking is solid and tested.** It uses `flock` with ordered, user-writable fallbacks (`deploy-environment.sh:216-265`), and the stubbed suite (`dev-ops/scripts/tests/test-deploy-environment.sh`) reproduces each reported bug shape.
- **The timer is well designed.** It uses an IANA-timezone `OnCalendar` that is correct across DST, `Persistent=true`, a wait for the Docker daemon, and an idempotent installer with `--dry-run` (`install-deploy-timer.sh:76-135`).
- **Every container has a memory limit.** Images are multi-stage, with distroless `nonroot` runtimes for the backend and sidecar. SigNoz images are version-pinned and have log rotation.
- **Backend CI is strong.** It runs gofmt, vet and tests, including testcontainers integration tests and API-level e2e flows in `product/backend/internal/e2e/`, plus a Docker build. Workflows default to `permissions: contents: read`, and gitleaks and govulncheck actually run.
- **The SSH wrapper has sensible controls.** `dev-server-agent.sh` enforces `StrictHostKeyChecking=yes`, requires TTY approval for anything not on its read-only list, redacts secrets, and appends to a JSONL audit log.
- **Failure issues close themselves on recovery.** The QA header shows a redeploy countdown (`REDEPLOY_TIMES`), so testers know when the stack will restart.

---

## Findings

| ID | Severity | Effort | Title |
|---|---|---|---|
| OPS-01 | High | S | Deploy-failure alerting reaches no one, and several failure paths never alert |
| OPS-02 | High | S | Failure alerts post raw compose logs (login codes, emails) to a public GitHub issue |
| OPS-03 | High | M | No backups or restore procedure for the Postgres event store (system of record) |
| OPS-04 | High | M | Deploy ships `main` HEAD with no CI gate, no rollback and no versioned images |
| OPS-05 | High | S | Semgrep is a silent no-op, dependency review cannot fail, and the docs claim gating that doesn't exist |
| OPS-06 | High | M | The only browser e2e test cannot pass and nothing runs it |
| OPS-07 | Medium | M | Recording deploy state by pushing to `main` needs a write token on the QA box, races the factory, and never records failures |
| OPS-08 | Medium | M | CI skips the deploy scripts, compose/Caddy config, two of three images and a full-stack smoke test |
| OPS-09 | Medium | S | Path-filtered workflows will deadlock once checks become required |
| OPS-10 | Medium | M | Migrations re-execute every file on every boot, with no version table and no transactions |
| OPS-11 | Medium | S | The health check is shallow: static `/healthz` via the Caddy catch-all, with no DB, sidecar, SPA or version check |
| OPS-12 | Medium | M | The 3.2 GB host is overcommitted; deploys collide with factory ticks; disk is never reclaimed |
| OPS-13 | Medium | S | SigNoz publishes UI and OTLP on all interfaces, mounts host `/`, and has no alert rules |
| OPS-14 | Medium | S | The Caddy `:80` catch-all probably serves the app over plain HTTP alongside HTTPS |
| OPS-15 | Medium | S | The whole `.env` is injected into containers, and the "read-only" SSH class can read secrets without approval |
| OPS-16 | Medium | M | Agents on the QA host have root-equivalent access; the SSH approval gate is advisory |
| OPS-17 | Medium | M | QA is not production-like: log-mode email, a stub Authelia, a tunnel the deploy would delete, fixed host ports |
| OPS-18 | Medium | L | No promotion path to production: no prod environment, registry, tags or release process |
| OPS-19 | Low | S | QA data and test accounts are unmanaged; an empty DB lets the first login become admin |
| OPS-20 | Low | S | The timer has no `OnFailure=`, no on-demand trigger, and batches many merges into each deploy |
| OPS-21 | Low | S | Floating container tags, no `--pull`, and no image vulnerability scanning |
| OPS-22 | Low | S | Provisioning (`setup.sh`) conflicts with the deploy path; several docs are stale |

---

### OPS-01 - Deploy-failure alerting reaches no one, and several failure paths never alert
**Severity:** High · **Effort:** S

**Evidence**
- `dev-ops/scripts/deploy-environment.sh:137-153`: alerting is only `gh issue create/comment ... >/dev/null 2>&1 || true`. If `gh` is not authenticated in the systemd user session, the alert is dropped silently.
- The previous failure issue, #101 "QA deployment failed", was authored by `adamzki99`, the owner's own account (from GitHub metadata). GitHub does not notify users about their own activity, so the alert produces no email or notification.
- Several exits go through `die()` (`:24`), which never calls `surface_failure`:
  - `:201` "failed to read environment config"
  - `:272` "deploy checkout missing"
  - `:306` "deploy checkout has unexpected local changes"
- Some failures are invisible to the script entirely:
  - A failing `ExecStartPre` Docker wait (`install-deploy-timer.sh:114`).
  - A `TimeoutStartSec=45min` kill (`:117`), which arrives as SIGTERM and never reaches the ERR trap.
  - A timer that is not installed at all (#85).
- Metadata commit and push failures go only to stderr in the journal (`deploy-environment.sh:400-407`).
- Outcome (from GitHub metadata): #85 (timer not installed), #86 ("Permission denied aborts every deploy … the outage is silent except for the log file") and #89 were all opened 2026-11-10 and closed 2026-11-19. #85 records that QA was "16 commits behind `origin/main`".

**Why it matters:** QA is the only place merged factory work runs as a whole system. If deploys fail silently, the owner tests stale code and the 12-hour test window in `dev-ops/README.md:23-24` means nothing. Push-style alerts cannot catch the "it never ran" failure mode.

**Recommendation**
1. **Add a dead-man's switch.** Ping an external check (healthchecks.io, Uptime Kuma or Cronitor) only after a successful deploy, with a 13-hour period. A missed ping alerts regardless of why: timer missing, host down, or a lock bug.
   ```bash
   # end of deploy-environment.sh, after the health check passes
   curl -fsS -m 10 --retry 3 "${DEPLOY_HEARTBEAT_URL:?}" >/dev/null || log "WARNING: heartbeat ping failed"
   # in on_error / die paths
   curl -fsS -m 10 "${DEPLOY_HEARTBEAT_URL}/fail" --data-raw "$FAILED_CMD" >/dev/null || true
   ```
2. **Route every `die` through one `fail()` function** that alerts, and add `set -E` so the ERR trap also covers functions.
3. **Use a bot identity for alerts.** File issues as a GitHub App or second account so the owner gets notified, or send a push alert (ntfy or email) directly.
4. **Add `OnFailure=` to the service unit** (see OPS-20).

---

### OPS-02 - Failure alerts post raw compose logs (login codes, emails) to a public GitHub issue
**Severity:** High · **Effort:** S

**Evidence**
- `deploy-environment.sh:189-190` and `:360`/`:378-379` collect `docker compose logs --tail=100` for **all** services. `surface_failure` pastes that into the issue body (`:139-148`).
- QA runs `EMAIL_MODE=log` (`projects/sauna/.env.example:22`), so the backend logs each email's recipient and body.
- Issue #101, comment 3, on the public repo contains exactly that (from GitHub metadata):
  `"msg":"email (log mode, not sent)","to":"email@test","subject":"Your login code","body":"CFL7Q7"`
  It also includes booking-confirmation bodies with booking UUIDs.

**Why it matters:** The repo is public. Any tester's email address, any login code still inside its 10-minute TTL, and any future PII or secret that reaches a log is published and indexed. GitHub comments keep their edit history even after a cleanup.

**Recommendation**
- Never post logs to the public tracker. Post only the SHA, the failing step and `docker compose ps` status.
- Keep logs on the host, for example `journalctl --user -u booking-qa-deploy` or a file under `~/.local/state/booking-deploy/<ts>.log`, and link to SigNoz.
- If a log excerpt is essential, take it from `backend` only and filter it:
  ```bash
  docker compose -f "$COMPOSE_FILE" logs --tail=50 backend 2>&1 \
    | grep -vE '"msg":"email \(log mode' | sed -E 's/[[:alnum:]._%+-]+@[[:alnum:].-]+/<redacted>/g'
  ```
- Delete or minimise the affected comments on #101.

---

### OPS-03 - No backups or restore procedure for the Postgres event store (system of record)
**Severity:** High · **Effort:** M

**Evidence**
- `projects/sauna/docker-compose.yml:105-106,133` store Postgres in the compose-managed volume `postgres-data` (`booking-qa_postgres-data`).
- A repo-wide search for `pg_dump|pg_basebackup|backup|restore|wal-g|pgbackrest` finds nothing outside the factory's model "backup" settings.
- The volume is lost to `docker compose down -v`, `docker volume prune`, disk failure, or a destructive migration (see OPS-10). The `dev-server-ssh` skill forbids deleting volumes in prose only (`SKILL.md` "Prohibited operations"); nothing enforces it.

**Why it matters:** In an event-sourced design, the `events` table is the only source of truth, and every projection is derived from it. Losing it loses all history, and it cannot be rebuilt. QA data is low-value today, but this compose file is the production template (`dev-ops/tls-letsencrypt.md` describes prod using the same stack), so production would ship with no backups.

**Recommendation**
- **Add a nightly logical dump timer and a dump before every deploy** (`deploy-environment.sh`, before line 357):
  ```bash
  BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/booking-$ENV_NAME}"; mkdir -p "$BACKUP_DIR"
  docker compose -f "$COMPOSE_FILE" exec -T postgres \
    pg_dump -U "${POSTGRES_USER:-booking}" -Fc "${POSTGRES_DB:-booking}" \
    > "$BACKUP_DIR/pre-deploy-$(date -u +%Y%m%dT%H%MZ)-${DEPLOYED_SHA:0:12}.dump"
  find "$BACKUP_DIR" -name '*.dump' -mtime +14 -delete
  ```
- **Ship dumps off the host** with restic or rclone to object storage. The box also runs the factory, so it is a single point of failure.
- **Test restores monthly.** A scheduled job restores the latest dump into a throwaway container and runs `SELECT count(*) FROM events`, then pings the dead-man's switch from OPS-01.
- **For production, add WAL archiving or PITR** (wal-g or pgBackRest), and write a short `dev-ops/disaster-recovery.md` covering RPO/RTO, where the backups and secrets live, and how to rebuild the host.

---

### OPS-04 - Deploy ships `main` HEAD with no CI gate, no rollback and no versioned images
**Severity:** High · **Effort:** M

**Evidence**
- **No CI gate:** `deploy-environment.sh:310-319` fetches and deploys `origin/main` regardless of check status. `main` has no branch protection and factory PRs merge in 2–5 minutes.
- **No rollback:**
  - `:358` runs `docker compose up -d --build --remove-orphans`, which rebuilds in place. Images are untagged: `build:` with no `image:` in `docker-compose.yml:41,57,79`.
  - When the health check fails (`:376-383`), the script records failure and exits. The broken containers stay up, and nothing restores the previous build.
- **Downtime on every deploy:**
  - Compose recreates the backend while the deploy is running.
  - The frontend container runs `rm -rf /srv/*` and then copies into the shared volume (`product/frontend/Dockerfile:20`). The SPA is briefly missing, and any open browser tab that lazy-loads an old hashed chunk gets a 404.
- **The deploy executes code from `main` it has never vetted:** `ExecStart` runs the script from the deploy checkout itself (`install-deploy-timer.sh:83,115`). Any merged change to `deploy-environment.sh` runs unreviewed on the next tick as a user with Docker access.

**Why it matters:** One bad factory merge leaves QA down until a human notices, and per OPS-01 nobody is told. Without image tags there is no "last good" version to return to, and a rollback that rebuilds from an older SHA rebuilds against whatever base images are current.

**Recommendation**
1. **Gate on green.** Deploy the newest `main` commit whose checks all passed, not HEAD:
   ```bash
   bad=$(gh api "repos/adamzki99/booking-system/commits/$SHA/check-runs" \
     --jq '[.check_runs[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral")] | length')
   [[ "$bad" == 0 ]] || { log "checks not green for $SHA; trying parent"; ... }
   ```
2. **Tag images per SHA and keep the previous tag.**
   ```yaml
   backend:
     build: ../../product/backend
     image: booking-backend:${IMAGE_TAG:-dev}
   ```
   Build with `IMAGE_TAG=$SHA`, write the last good tag to `~/.local/state/booking-deploy-qa.last-good`, and on health failure run `IMAGE_TAG=$PREV docker compose up -d --no-build`. Run the pre-deploy DB dump (OPS-03) before migrating.
3. **Build first, then swap.** Run `docker compose build` before `up` so a build failure never touches running containers.
4. **Serve the SPA from inside the image.** Use a Caddy image with the dist baked in, or copy to `/srv/<sha>` and switch a symlink, instead of `rm -rf` on a shared volume.
5. **Run the deploy script from a pinned path.** Run it from a separate, reviewed copy, for example one only updated by a release tag, rather than from the checkout it is about to change. At minimum, re-exec the script after the rebase so a new version takes effect in the same run rather than the next one.

---

### OPS-05 - Semgrep is a silent no-op, dependency review cannot fail, and the docs claim gating that doesn't exist
**Severity:** High · **Effort:** S

**Evidence**
- **Semgrep scans nothing:**
  - `.github/workflows/semgrep.yml:35-37` runs `semgrep ci` with `SEMGREP_APP_TOKEN: ${{ secrets.SEMGREP_APP_TOKEN }}`.
  - The 2026-11-19 run (44511607501, PR for #89; from GitHub metadata) logs `SEMGREP_APP_TOKEN: ` (empty), then `run 'semgrep login' before using 'semgrep ci' …` and `There were errors during analysis but Semgrep will succeed`. The job is green.
  - `dev-ops/README.md:288` still has the "Add `SEMGREP_APP_TOKEN`" checkbox unticked.
- **`.semgrep.yml` likely has no effect.** `semgrep ci` takes its rules from the platform, and a top-level `paths:` with `rules: []` is not a meaningful rules file. Moderate confidence.
- **Dependency review cannot fail:** `.github/workflows/security.yml:21` sets `continue-on-error: true`.
- **The docs describe protection that doesn't exist:**
  - `dev-ops/README.md:270-272` says "Combined with the repo's *require conversation resolution* branch protection, unresolved findings block merging."
  - `:291` and `.github/workflows/README.md` talk about required checks, but `main` has no protection and no rulesets.
  - `.github/workflows/README.md` ("Code scanning") and `dev-ops/README.md:293-294` say "A Semgrep instance also runs on the development server". Nothing in the repo configures that.

**Why it matters:** Every factory PR shows a green "Semgrep" check, which looks like SAST coverage. An AI factory that reads check status as "safe" will merge on it. False assurance is worse than a missing check.

**Recommendation**
- **Make Semgrep real:**
  - Either add the token, or switch to tokenless OSS rules:
    ```yaml
    - run: semgrep scan --config p/default --config p/golang --config p/typescript --error --metrics=off
    ```
  - Pin the container (`semgrep/semgrep:1.xx.x@sha256:…`) and drop `continue-on-error` from dependency review.
- **Turn on branch protection or a ruleset for `main`:** required checks (see OPS-09 for path filters), "require branches up to date", and block force-push. Also allow the deploy identity to bypass it, or better, remove its write access (OPS-07).
- **Correct the README** so it describes what is actually enforced.

---

### OPS-06 - The only browser e2e test cannot pass and nothing runs it
**Severity:** High · **Effort:** M

**Evidence**
- **The test always submits a stale login code:**
  - `dev-ops/scripts/run-playwright.sh:78` fetches a code with `get-login-code.sh … --request`, which POSTs `/api/auth/request-code`. That code is passed to the test as `LOGIN_CODE`.
  - `dev-ops/testing/tests/login.spec.ts:9` then clicks **Request code** in the UI, which issues a **second** code.
  - Verification only accepts the newest unconsumed code: `product/backend/internal/auth/commands.go:131` (`codes.LatestUnconsumed`) and `:141` (`VerifyCodeHash`). The test fills the older `LOGIN_CODE`, so verification fails every time.
- **The container probably cannot load the test framework:**
  - `run-playwright.sh:86` bind-mounts `$REPO_ROOT/dev-ops/testing` over `/tests`. This hides the `node_modules` that `npm ci` installed in the image (`dev-ops/testing/Dockerfile:5-6`).
  - The deploy checkout has no `node_modules` (it is gitignored), so `@playwright/test` very likely fails to resolve.
- **It is not maintained or run:**
  - One spec exists. It has been untouched since 2026-11-08 (#80), while the frontend has since been re-themed (#152).
  - No workflow, timer or factory step runs it.
  - `projects/sauna/README.md:81-83` still says browser steps "remain a manual verification checklist until Playwright … are added".
- **The QA test window is unused:** `dev-ops/README.md:23-24` promises "~12 h for Playwright testing on QA", but nothing consumes that window.

**Why it matters:** The backend's API e2e tests (`internal/e2e`) are good, but nothing checks the built SPA, Caddy routing or the compose wiring. Those are exactly the layers the factory changes without review.

**Recommendation**
- **Fix the test.** Either drop the UI "Request code" click and use the pre-fetched code, or, better, fetch the code *after* the click from inside the test. With a mail sink (OPS-17) the test can read the code from Mailpit's API:
  ```ts
  await page.getByRole("button", { name: "Request code" }).click();
  const code = await latestCodeFromMailpit(email); // GET http://mailpit:8025/api/v1/search?query=to:...
  ```
- **Fix the mount.** Mount only specs, read-only: `-v "$REPO_ROOT/dev-ops/testing/tests:/tests/tests:ro"`.
- **Write a minimum smoke suite:** login, create a booking, cancel it, the admin users page, and the iCal feed. The last can reuse `projects/sauna/scripts/smoke-calendar-feed.sh`.
- **Run it in two places:**
  - In CI, on every PR, against an ephemeral `docker compose up` (see OPS-08).
  - After every QA deploy, as part of the health gate. A failure triggers rollback (OPS-04).

---

### OPS-07 - Recording deploy state by pushing to `main` needs a write token on the QA box, races the factory, and never records failures
**Severity:** Medium · **Effort:** M

**Evidence**
- **Direct push to `main`:** `deploy-environment.sh:391-408` commits `dev-ops/environments.yaml` and runs `git push origin main`. Recent examples: `33cde20`, `bd09de3` and `9a57a4c` by `booking-deploy <deploy@booking-system.local>`.
- **The QA box needs a broad credential.** The clone URL is HTTPS (`setup.sh:16`), so the push needs a credential with `contents: write` on an unprotected `main`. Inferred from the issue authorship, it is the owner's personal `gh` token.
- **The push races factory merges:**
  - The build plus the 2-minute health check gives a window of several minutes in which the factory merges (2–5 minute PRs).
  - A rejected push leaves an unpushed local commit, which the next run replays with `git rebase origin/main` (`:317`).
  - On 2026-11-10, #101 recorded two deploy failures at `git -C "$DEPLOY_DIR" rebase "origin/$BRANCH"` (from GitHub metadata).
- **CI noise:** each deploy commit triggers a `Security` run on `main` (run 44510929304 at 11:00:59 UTC, 4 s after `33cde20`; from GitHub metadata) and shows up in factory PR "behind main" status. `security.yml:4-7` confirms it triggers on every push to `main`.
- **`last_deploy_status: "failed"` can never reach git:**
  - On failure, `update_yaml "failed"` edits the file (`:185`, `:361`, `:380`).
  - Then `die`/`exit` fires the EXIT trap `cleanup_deploy_metadata` (`:275-279`), which runs `git checkout -- dev-ops/environments.yaml` and discards the edit.
  - The field therefore only ever says `success`.
- **Recorded SHA ≠ running tree:** `DEPLOYED_SHA` is `origin/$BRANCH` (`:319`), while HEAD may carry a replayed local metadata commit.

**Why it matters:** The QA host is also the AI factory host (OPS-16), and it holds a token that can rewrite the default branch with no review. The bookkeeping adds merge churn and failure modes, which caused #89 and the 11-10 rebase failures. It also reports only good news.

**Recommendation**
- **Switch to the GitHub Deployments API.** It has native "qa" environment history in the UI and creates no commits:
  ```bash
  id=$(gh api repos/adamzki99/booking-system/deployments --input - <<JSON | jq .id
  {"ref":"$SHA","environment":"qa","auto_merge":false,"required_contexts":[]}
  JSON
  )
  gh api repos/adamzki99/booking-system/deployments/$id/statuses -f state=success -f environment_url="https://qa.example"
  ```
- **Narrow the box's credential.** Use a fine-grained token or GitHub App limited to `deployments:write` and `issues:write`, with read-only contents. Use `git fetch` plus `git reset --hard origin/main` (or a detached checkout) instead of `checkout` plus `rebase`, so the deploy checkout can never diverge.
- **Expose the running version** at `GET /version` (build arg `GIT_SHA`) as the source of truth. Keep `environments.yaml` for static config (branch and port) only.

---

### OPS-08 - CI skips the deploy scripts, compose/Caddy config, two of three images and a full-stack smoke test
**Severity:** Medium · **Effort:** M

**Evidence**
- **Deploy-script tests never run in CI.** `dev-ops/scripts/tests/test-{deploy-environment,install-deploy-timer,dev-server-agent,get-login-code,check-acceptance-criteria}.sh` are run by no workflow; `grep "tests/test-" .github` returns nothing. PRs #153–#155, which fixed #85, #86 and #89, ran only "Security" and "Semgrep" (run list for 2026-11-19 09:07–11:07 UTC; from GitHub metadata).
- **No shellcheck, `docker compose config` or `caddy validate`.** None of these appears anywhere in the workflows.
- **Only the backend image is built in CI** (`backend-ci.yml:51-58`). Nothing builds `product/frontend/Dockerfile`, `projects/sauna/sidecar/Dockerfile` or `dev-ops/testing/Dockerfile`.
- **No job brings up the compose stack** to hit `/healthz`, `/api/...` through Caddy, and the SPA.

**Why it matters:** The last three production-impacting fixes were all in deploy shell scripts, and the repo already had tests for them, but CI never ran those tests. Compose, Caddy and Dockerfile regressions only surface at the 00:00/12:00 deploy on the shared host.

**Recommendation:** Add a `deploy-ci.yml`:
```yaml
on:
  pull_request:
    paths: ['dev-ops/scripts/**','projects/sauna/**','product/**/Dockerfile','dev-ops/testing/**']
jobs:
  scripts:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha>
      - run: sudo apt-get install -y shellcheck && shellcheck dev-ops/scripts/*.sh projects/sauna/*.sh
      - run: for t in dev-ops/scripts/tests/test-*.sh; do bash "$t"; done
  stack:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha>
      - run: cp projects/sauna/.env.example projects/sauna/.env
      - run: docker compose -f projects/sauna/docker-compose.yml config -q
      - run: docker run --rm -v $PWD/projects/sauna/config:/c caddy:2.10-alpine caddy validate --config /c/Caddyfile
      - run: COMPOSE_PROJECT_NAME=ci docker compose -f projects/sauna/docker-compose.yml up -d --build --wait
      - run: curl -fsS localhost:8080/healthz && curl -fsS localhost:8080/ | grep -q '<div id="root"'
      # then: run the Playwright suite against localhost:8080 (OPS-06)
```

---

### OPS-09 - Path-filtered workflows will deadlock once checks become required
**Severity:** Medium · **Effort:** S

**Evidence**
- `backend-ci.yml:4-11`, `frontend-ci.yml:4-13` and `sidecar-ci.yml:4-13` trigger only on matching paths.
- `backend-ci.yml:8-11` has a `push` trigger with no branch filter, so every factory branch push runs it twice: for example "Backend CI push factory/issue-118" alongside the PR run (from GitHub metadata).
- No workflow sets `concurrency:`.
- The README's plan is to "wire `semgrep/ci` as a required status check" (`dev-ops/README.md:291`).

**Why it matters:** When branch protection is enabled (OPS-05), a required check that a path filter skipped stays "Expected - Waiting" forever. For example, a docs-only PR would wait on Backend CI. The factory's fix agent would then loop on PRs it cannot unblock.

**Recommendation:** Keep path filtering inside a single always-run workflow and require one aggregate job:
```yaml
jobs:
  changes:
    outputs: { backend: ${{ steps.f.outputs.backend }} }
    steps: [ { uses: dorny/paths-filter@<sha>, id: f, with: { filters: "backend: ['product/backend/**']" } } ]
  backend: { needs: changes, if: needs.changes.outputs.backend == 'true', ... }
  ci-ok:
    if: always()
    needs: [backend, frontend, sidecar, scripts]
    steps: [ { run: '[[ "${{ contains(needs.*.result, ''failure'') }}" == "false" ]]' } ]
```
Also add `concurrency: { group: ${{ github.workflow }}-${{ github.ref }}, cancel-in-progress: true }`, and restrict `push` to `main`.

---

### OPS-10 - Migrations re-execute every file on every boot, with no version table and no transactions
**Severity:** Medium · **Effort:** M

**Evidence**
- `product/backend/internal/eventstore/eventstore.go:223-253` sorts the embedded `*.sql` files and runs `pool.Exec(ctx, string(b))` for **each file on every start** (`:247`).
- There is no `schema_migrations` table and no per-file transaction. It is called from `registry.New` (`internal/registry/registry.go:26`) on each backend boot.
- All ten current files are `CREATE … IF NOT EXISTS`, so this works today.
- No CI job tests an upgrade from the previous schema, only from an empty database (testcontainers).

**Why it matters:** The first `ALTER TABLE`, backfill or `DROP`, which projections will need, either fails on the second boot and crash-loops the backend, or silently re-runs a data change. A file that fails halfway leaves a partially applied schema. Because the deploy has no rollback (OPS-04), a bad migration means manual SQL on the event store's database.

**Recommendation:** Track applied migrations, apply each in a transaction, and serialise with an advisory lock (or adopt `golang-migrate` or `goose` with `embed.FS`):
```go
_, _ = conn.Exec(ctx, `SELECT pg_advisory_lock(7262001)`)
conn.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations(version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`)
for _, f := range files {
    if applied[f] { continue }
    tx, _ := conn.Begin(ctx)
    if _, err := tx.Exec(ctx, sql); err != nil { tx.Rollback(ctx); return err }
    tx.Exec(ctx, `INSERT INTO schema_migrations(version) VALUES($1)`, f)
    tx.Commit(ctx)
}
```
Add a CI test that boots the previous release's schema, applies the new migrations, and runs projection catch-up. Add a policy that the `events` table is append-only and never altered destructively.

---

### OPS-11 - The health check is shallow: static `/healthz` via the Caddy catch-all, with no DB, sidecar, SPA or version check
**Severity:** Medium · **Effort:** S

**Evidence**
- `deploy-environment.sh:366-374` polls `http://127.0.0.1:${PORT}/healthz`.
- `PORT` maps to Caddy's `:80` catch-all (`docker-compose.yml:20`, `Caddyfile:51-53`), which proxies to the backend.
- `handleHealthz` returns a constant `{"status":"ok"}` (`product/backend/internal/server/server.go:108-110`).
- The backend has no compose healthcheck: Caddy `depends_on: backend: service_started` (`docker-compose.yml:36-37`).
- If `DATABASE_URL` were empty, the backend would start without an event store and still report healthy (`cmd/server/main.go`, the `if cfg.DatabaseURL != ""` branch).

**Why it matters:** A deploy is marked successful even if the sidecar is down, so bookings fail. It also passes with a missing SPA, the HTTPS site block broken, or an old container still answering, because nothing compares the running SHA with `DEPLOYED_SHA`.

**Recommendation**
- Add `GET /readyz`, which pings Postgres, the sidecar and the projection checkpoint lag, and `GET /version`, which returns the build-arg SHA.
- In the deploy script, require `/readyz` to return 200 and `/version == $DEPLOYED_SHA`. Also require `curl -fsS :$PORT/` to contain the SPA root, and `https://$SITE_ADDRESS/healthz` to succeed when TLS is configured.
- Add compose `healthcheck:` entries for the backend and sidecar, and use `docker compose up --wait`.

---

### OPS-12 - The 3.2 GB host is overcommitted; deploys collide with factory ticks; disk is never reclaimed
**Severity:** Medium · **Effort:** M

**Evidence**
- **Memory limits exceed host RAM:**
  - `dev-ops/README.md:366-385` budgets "below ~2.5 GB on the 3.2 GB dev host".
  - In the same table, SigNoz alone is ClickHouse 1536m + ZooKeeper 512m + server 512m + collector 512m = **3 GB**. The booking stack adds 1.4 GB.
  - ClickHouse `max_memory_usage` is 1.2 GB (`signoz/clickhouse/users.xml:5`).
- **The deploy starts at the same minute as the factory:**
  - The deploy runs at `*-*-* 00,12:00:00 Europe/Stockholm` (`install-deploy-timer.sh:76`).
  - The factory cron is `0 * * * *`, quoted in #85 (from GitHub metadata); `dev-ops/README.md:7-8` also says the tick runs hourly.
  - So twice a day a Go+Node `docker compose up --build` starts together with OpenCode sessions.
- **Disk is never reclaimed:**
  - No `docker image prune` or `builder prune` runs anywhere, and twice-daily `--build` leaves dangling layers.
  - The booking services have no `logging:` options (`docker-compose.yml` vs `signoz/docker-compose.yml:22-27`), so `json-file` logs grow without bound. `get-login-code.sh` also depends on those logs.

**Why it matters:** OOM kills and full disks are the most likely way a single-box QA environment dies, and nothing on the box alerts on them (OPS-13).

**Recommendation**
- Measure real usage with SigNoz host metrics and either right-size the limits, move SigNoz off the box, or replace it with a lighter stack such as an OTel collector feeding Grafana Cloud's free tier.
- Fix the README so the budget and the table agree.
- Offset the deploy time (`--times` takes hours only, so add a minute option such as `00,12:30`) or take the factory's lock during deploys.
- Add `logging: { driver: json-file, options: { max-size: 20m, max-file: "3" } }` to an `x-common` anchor in `projects/sauna/docker-compose.yml`.
- Add `docker image prune -f --filter until=72h && docker builder prune -f --keep-storage 5GB` after a successful deploy.
- Alert on disk usage above 80% and memory pressure (OPS-13).

---

### OPS-13 - SigNoz publishes UI and OTLP on all interfaces, mounts host `/`, and has no alert rules
**Severity:** Medium · **Effort:** S

**Evidence**
- **Ports published on all interfaces:** `dev-ops/signoz/docker-compose.yml:136-137` (`"${SIGNOZ_UI_PORT:-3301}:8080"`) and `:184-186` (`"4317:4317"`, `"4318:4318"`) publish on `0.0.0.0`. Docker-published ports bypass UFW.
- **The host is probably internet-reachable.** It also publishes 80/443 for Let's Encrypt HTTP-01 (`projects/sauna/docker-compose.yml:21-22`). Whether the host is actually reachable depends on NAT and firewall rules, which I could not verify.
- **The collector can read the whole host filesystem:** `:173` mounts `/:/hostfs:ro` into the collector. That includes `~/.config/gh/hosts.yml`, `~/.ssh` and `projects/sauna/.env`.
- **No alerting is configured:** there are no alert rules or notification channels in the repo (`SIGNOZ_ALERTMANAGER_PROVIDER=signoz` only). The backend sends traces and metrics only. Logs stay in Docker (`internal/telemetry` has no log exporter).

**Why it matters:** OTLP accepts unauthenticated writes, and the SigNoz UI's first visitor can register as admin. A compromised collector can read the host's secrets. Meanwhile, observability raises no alerts: the host metrics added in #146 go unwatched.

**Recommendation**
- Publish the UI on `127.0.0.1:3301:8080` and reach it over SSH tunnel or Tailscale.
- Remove the OTLP host ports. Attach the booking backends to an external network instead:
  ```yaml
  # signoz compose
  networks: { default: { name: signoz-net } }
  # sauna compose
  networks: { signoz: { external: true, name: signoz-net } }
  # backend: OTEL_EXPORTER_OTLP_ENDPOINT=http://signoz-otel-collector:4318
  ```
- Narrow the host mount to `/proc`, `/sys` and the specific filesystems the scraper needs.
- Provision alert rules as code, for example via the SigNoz API in a setup script: disk above 80%, memory above 90%, backend 5xx rate, and no backend traces for 30 minutes. Route them to email or ntfy.
- Export backend logs over OTLP (with redaction, see OPS-02) so failures can be investigated without shell access.

---

### OPS-14 - The Caddy `:80` catch-all probably serves the app over plain HTTP alongside HTTPS
**Severity:** Medium · **Effort:** S

**Evidence**
- `projects/sauna/config/Caddyfile:47-53` defines both `{$SITE_ADDRESS:localhost} { import app }` and `:80 { import app }`.
- Host port 80 is published (`docker-compose.yml:21`).
- Caddy appends its automatic HTTP→HTTPS redirect routes **after** user-defined routes on an existing `:80` server, so a catch-all `:80` site very likely shadows them.
- The result would be that `http://<SITE_ADDRESS>/` serves the full app, including `/api/auth/verify` and session cookies, in cleartext. No HSTS header is set.
- Confidence is moderate; verify with `curl -sI http://$SITE_ADDRESS/api/healthz`.
- A Caddy log from 11-07 in #101 (from GitHub metadata) shows QA then ran **HTTP only** ("server is listening only on the HTTP port, so no automatic HTTPS will be applied").

**Why it matters:** Login codes and bearer session tokens can cross the network unencrypted, and the QA setup does not match the HTTPS-only production behaviour that `tls-letsencrypt.md` promises.

**Recommendation:** Move the internal health listener off the public port and let Caddy redirect port 80:
```caddyfile
{$SITE_ADDRESS:localhost} {
	header Strict-Transport-Security "max-age=31536000"
	import app
}
:8080 {          # internal: deploy health check + cloudflared origin
	import app
}
```
```yaml
ports:
  - "127.0.0.1:${PORT:-8080}:8080"
  - "80:80"
  - "443:443"
```
For the tunnel override, point cloudflared at `http://caddy:8080`.

---

### OPS-15 - The whole `.env` is injected into containers, and the "read-only" SSH class can read secrets without approval
**Severity:** Medium · **Effort:** S

**Evidence**
- **The full `.env` reaches two containers:** `projects/sauna/docker-compose.yml:62-63` (backend) and `:99-100` (postgres) use `env_file: .env`.
- **That `.env` holds unrelated secrets:** `projects/sauna/.env.example:40` (`CLOUDFLARE_TUNNEL_TOKEN`), `:25-26` (SMTP), and `:65-77` (operator-only `DEV_SERVER_PASSWORD`, `DEV_SERVER_KEY`, …).
- **Weak defaults:** `POSTGRES_PASSWORD=change-me` (`:9`). The compose fallback is `booking:booking` (`docker-compose.yml:65,103`). `setup.sh:49-52` copies the example file as-is and only prints a warning.
- **The wrapper auto-runs secret-reading commands:**
  - `dev-server-agent.sh:226-227` classifies `cat|head|tail|grep` with any arguments as `read-only`.
  - `:262` does the same for `docker inspect`.
  - So `cat /opt/booking-system-qa/projects/sauna/.env` and `docker inspect booking-qa-backend-1` (which shows the full env) run **without the approval prompt**, and their output goes into the agent's context and model provider logs.
  - `git diff --output=<file>` is also classed read-only but writes a file (`:286`).

**Why it matters:** Every container, and every agent with "read-only" access, can see every secret. A leak through one path, such as the backend logs, SigNoz or the agent transcript, exposes all of them.

**Recommendation**
- Replace `env_file: .env` with explicit `environment:` keys per service, and keep only `POSTGRES_*` for postgres.
- Remove the `DEV_SERVER_*` block from `projects/sauna/.env.example`; it already lives in `dev-ops/.env.example`.
- Make `setup.sh` generate a random password (`openssl rand -hex 24`) instead of copying `change-me`.
- In `classify_command`, deny or require approval for paths matching `*.env*|*/.ssh/*|*/.config/gh/*|*.pem|*.key`, for `docker inspect`, and for `git diff --output*`. Consider an allow-list of exact read-only commands instead of an allow-list of binaries.

---

### OPS-16 - Agents on the QA host have root-equivalent access; the SSH approval gate is advisory
**Severity:** Medium · **Effort:** M

**Evidence**
- **The factory and the deploy share one Unix user:**
  - #85 (from GitHub metadata) quotes the crontab of `lasrvr`: `0 * * * * /home/lasrvr/booking-system/dev-ops/factory/tick.sh`.
  - The deploy runs as the same user (`dev-ops/README.md:112,123`) and needs Docker access, which is root-equivalent.
  - Inferred: the same user's `gh` credentials file the deploy issues as `adamzki99`.
- **The optional sandbox leaves the important doors open:** `dev-ops/factory/tick.sh:693-694` uses `bwrap` with `--ro-bind / /` and `--bind "$HOME" "$HOME"`, and only when `FACTORY_CONTAINER_MODE=1`. A read-only bind does not block connecting to `/var/run/docker.sock`, and `$HOME` (with `~/.config/gh` and `~/.ssh`) is writable. The factory reviewer covers this in depth.
- **The SSH wrapper is advisory, by its own description:**
  - It runs OpenCode on the operator's machine with a full local shell; the README says the wrapper is "not a sandbox" (`dev-ops/README.md:203-204`).
  - It opens a `ControlMaster` socket with `ControlPersist=10m` (`dev-server-agent.sh:163-165`). Any local process, including the agent, can reuse that socket with `ssh -S <path> host <cmd>` and skip both the classifier and the approval prompt.

**Why it matters:** The "human approval for mutations" control applies only to the remote-operator path. The factory agents that actually run on the QA box can already `docker exec` into Postgres, read `.env`, and push to `main` with the owner's token.

**Recommendation**
- Run the deploy and the QA stack as a dedicated `booking-deploy` user, which is the only member of the `docker` group (or use rootless Docker for it).
- Run the factory as a separate user with no Docker access and no deploy credentials.
- Give each identity its own narrow GitHub credential (see OPS-07).
- For remote agent sessions, drop `ControlPersist`, or set `ControlPath` in a directory the agent process cannot reach. Better, use a forced-command `authorized_keys` entry on the server (`command="/usr/local/bin/qa-ops-shell",no-port-forwarding,no-pty`) so the server enforces the allow-list rather than the client.

---

### OPS-17 - QA is not production-like: log-mode email, a stub Authelia, a tunnel the deploy would delete, fixed host ports
**Severity:** Medium · **Effort:** S

**Evidence**
- **Email is never sent:** `EMAIL_MODE=log` (`projects/sauna/.env.example:22`), which the Playwright tooling depends on (`get-login-code.sh:128`). The SMTP sender and the outbox retry path are never exercised end to end on QA.
- **Authelia is a stub:**
  - `config/authelia/configuration.yml` is a 9-line skeleton with only `server.address`. Real Authelia also requires secrets, storage and an authentication backend, so it would not start.
  - The compose service is `authelia/authelia:latest` behind a profile (`docker-compose.yml:114-123`).
  - The docs call its role "TBD" (`self-hosting-cloudflare-tunnel.md:160`).
- **The deploy would delete the tunnel:** the deploy uses only the base compose file with `--remove-orphans` (`deploy-environment.sh:324,358`). If QA were started with `docker-compose.cloudflare-tunnel.yml`, the next timer deploy would remove the `cloudflared` container as an orphan of project `booking-qa`.
- **Only one environment can run per host:**
  - Host ports `80:80` and `443:443` are fixed (`docker-compose.yml:21-22`).
  - That contradicts `environments.yaml:12-15` ("release-1-0 … port: 8081") and `dev-ops/README.md:147-151` ("Every release branch gets one candidate environment … distinct port").

**Why it matters:** The parts most likely to break in production (TLS, email delivery, tunnel ingress, SSO) are the parts QA never runs.

**Recommendation**
- Run Mailpit in QA (`axllent/mailpit`, SMTP 1025, API 8025), set `EMAIL_MODE=smtp` and `SMTP_HOST=mailpit`, and have the Playwright helpers read codes from its API instead of scraping logs.
- Make `COMPOSE_FILES` per-environment config in `environments.yaml` (for example `compose_overrides: [docker-compose.cloudflare-tunnel.yml]`) and pass every `-f` in the deploy.
- Make ports 80/443 an override used only by the edge environment.
- Either finish Authelia, with config, secrets and a forward_auth route, or delete it until it has a role.

---

### OPS-18 - No promotion path to production: no prod environment, registry, tags or release process
**Severity:** Medium · **Effort:** L

**Evidence**
- `dev-ops/environments.yaml` defines only `qa`; release environments are commented out (`:12-15`).
- The repo has no git tags (`git tag` is empty in the clone) and no GitHub releases (`gh release list` was empty; from GitHub metadata).
- Images are built on the host from source (`build:` only) and never pushed to a registry.
- The TLS and tunnel docs describe a "prod" that the repo does not define.

**Why it matters:** "Tested on QA" cannot carry over to production, because production would rebuild from source at a different time against different base images. There is also no artifact to roll back to and no record of what is running where.

**Recommendation**
- Build images once in CI on merge to `main`. Push them to GHCR as `ghcr.io/adamzki99/booking-{backend,frontend,sidecar}:<sha>` with `permissions: packages: write` in that one job.
- Have QA pull by SHA (OPS-04).
- Promote by retagging the exact digest QA tested (`crane tag … qa-passed` → `prod`), gated on the post-deploy Playwright suite and a manual approval through a GitHub Environment with required reviewers.
- Add `release/*` tags, and keep a separate `prod` entry in `environments.yaml` with its own host or compose project and backup policy.

---

### OPS-19 - QA data and test accounts are unmanaged; an empty DB lets the first login become admin
**Severity:** Low · **Effort:** S

**Evidence**
- **Seeding exists but is not wired up:** `user.SeedDevUsers` needs `DEV_MODE` and `SEED_USERS_FILE` (`internal/config/config.go:59,88`; `internal/user/seed.go:51-57`). Neither variable appears in `projects/sauna/.env.example` or the compose file, and no seed file is mounted.
- **The test account is undocumented:** `run-playwright.sh:75-76` requires `TEST_USER_EMAIL` to be "an existing QA user account" (`dev-ops/README.md:325`) but does not say how that account is created.
- **The first login on an empty DB becomes admin:** `internal/auth/service.go:69-88` (`count == 0` → allow) plus `BootstrapAdmin`. A wiped or new QA database therefore makes the first email to log in the admin.
- **QA data is never reset:** the volume persists across deploys, so test data accumulates without limit.

**Why it matters:** Tests are not reproducible, accounts depend on manual setup, and after a restore or rebuild the admin is whoever logs in first.

**Recommendation**
- Commit `projects/sauna/config/seed-users.qa.json` with fictitious `@example.test` accounts covering each role, mount it read-only, and set `DEV_MODE=true` and `SEED_USERS_FILE=/config/seed-users.json` in the QA `.env`.
- Optionally add a weekly "reset QA" job that restores a known fixture dump. That also exercises the restore path from OPS-03.
- In production, require an explicit `BOOTSTRAP_ADMIN_EMAIL` instead of first-come-first-served.

---

### OPS-20 - The timer has no `OnFailure=`, no on-demand trigger, and batches many merges into each deploy
**Severity:** Low · **Effort:** S

**Evidence**
- The generated service (`install-deploy-timer.sh:103-119`) has no `OnFailure=`.
- The timer fires at only two fixed slots (`:127-131`).
- Twenty-nine commits landed on `main` between 2026-11-12 and today, so a single deploy can bundle a dozen unreviewed factory merges, which makes bisecting failures hard.
- The only way to deploy on demand is a manual `systemctl --user start`.

**Recommendation**
- Add an `OnFailure=` hook:
  ```ini
  [Unit]
  OnFailure=booking-deploy-alert@%n.service
  ```
  with a template unit that runs `curl -d "deploy failed on %H" https://ntfy.sh/<private-topic>` or pings the heartbeat `/fail` URL.
- Consider two tiers:
  - A continuously updated "dev" environment, polled every 10 minutes for a new green SHA.
  - The twice-daily "QA" environment for human testing.
- Add a path unit or `workflow_dispatch` → webhook trigger so a hotfix can be deployed without SSH.

---

### OPS-21 - Floating container tags, no `--pull`, and no image vulnerability scanning
**Severity:** Low · **Effort:** S

**Evidence**
- **Floating tags:**
  - `caddy:2-alpine` (`docker-compose.yml:10`), `postgres:16-alpine` (`:94`), `authelia/authelia:latest` (`:115`), `cloudflare/cloudflared:latest` (`docker-compose.cloudflare-tunnel.yml:23`).
  - `semgrep/semgrep` (`semgrep.yml:28`), `go install …govulncheck@latest` (`security.yml:43`).
  - Base images `golang:1.26-alpine`, `alpine:3.21` and distroless with no digest.
- **The deploy runs `up --build` without `--pull`,** so QA keeps whatever base layers were first cached, and runtime images are never updated.
- **Actions pinning is inconsistent:** frontend and sidecar workflows pin by SHA, while backend, security and semgrep use `@v4`/`@v5`/`@v2`. Runs warn "Node.js 20 is deprecated … actions/checkout@v4" (from GitHub metadata).
- **There is no `.github/dependabot.yml` or Renovate config,** and no Trivy or Grype scan of the built images.

**Recommendation**
- Pin images by digest and let Renovate or Dependabot update them. Use one `dependabot.yml` covering the `github-actions`, `gomod` (two modules), `npm` (two modules) and `docker` ecosystems, grouped weekly. Factory and Dependabot PRs then go through the same CI gate.
- Add `--pull` to the deploy build, or pull-by-digest once images are built in CI (OPS-18).
- Add `aquasecurity/trivy-action@<sha>` on the built images with `severity: CRITICAL,HIGH` and `exit-code: 1`.
- Pin `govulncheck@v1.x.y`.

---

### OPS-22 - Provisioning (`setup.sh`) conflicts with the deploy path; several docs are stale
**Severity:** Low · **Effort:** S

**Evidence**
- **The deploy cannot provision a host:**
  - `deploy-environment.sh:267-270` calls `projects/sauna/setup.sh` when the checkout is missing.
  - `setup.sh:11-14` exits unless the caller is root, but the deploy runs as a non-root user timer.
  - If an operator runs it with sudo instead, `/opt/booking-system-qa` becomes root-owned, which is the same class of bug as #86.
- **`setup.sh` starts a conflicting stack:** `setup.sh:60` runs `docker compose up -d --build` with the default project name (`sauna`), which binds 80/443/8080 and blocks the `booking-qa` project the deploy starts next.
- **Docker is installed with `curl … | sh`** (`setup.sh:36`).
- **Stale docs:**
  - `setup.sh:4-8` still describes a cron schedule.
  - `dev-ops/README.md:149` says "Everything runs via Docker Desktop".
  - `projects/sauna/README.md:81-83` says Playwright is not yet added.
  - `dev-ops/README.md:112-135` hard-codes the host username `lasrvr`.

**Recommendation**
- Split host bootstrap (root: packages, Docker, users, linger, firewall) from environment provisioning (deploy user: clone, `.env` from a secret store, first deploy).
- Make `setup.sh` export `COMPOSE_PROJECT_NAME=booking-qa`, or stop running compose at all.
- Capture host setup as a small Ansible playbook or cloud-init file so the box can be rebuilt (OPS-03 DR).
- Refresh the READMEs and replace real usernames with `<deploy-user>`.

---

## Prioritized roadmap

**Now (this week)**
1. **OPS-02:** Stop posting compose logs to public issues, and scrub #101.
2. **OPS-01:** Add a dead-man's-switch heartbeat for deploys, route every `die` through alerting, and file alerts from a non-owner identity so notifications arrive.
3. **OPS-03:** Add a pre-deploy `pg_dump` plus a nightly dump copied off the host.
4. **OPS-05:** Make Semgrep actually scan (token or OSS rules with `--error`), drop `continue-on-error`, and correct the README claims about branch protection.
5. **OPS-13 / OPS-14:** Bind the SigNoz UI and OTLP to localhost or a Docker network, and move the internal health listener off public `:80` so HTTPS redirects work.
6. **OPS-15:** Stop `env_file: .env` from injecting every secret, and tighten the wrapper's read-only classification for secret paths and `docker inspect`.

**Next (this month)**
1. **OPS-04 / OPS-11:** Deploy only green SHAs, tag images per SHA with automatic rollback on failed `/readyz` + `/version` checks, and build before swapping.
2. **OPS-06 / OPS-17 / OPS-19:** Add Mailpit, fix the Playwright login flow and mount, seed QA accounts, and run the smoke suite after every deploy.
3. **OPS-08 / OPS-09:** Add `deploy-ci.yml` (shellcheck, the script tests, compose and Caddy validation, all image builds, a compose-up smoke run), an aggregate `ci-ok` job and concurrency groups. Then enable branch protection or a ruleset on `main`.
4. **OPS-07:** Replace commits to `main` with the Deployments API and a `/version` endpoint, give the box a narrowly scoped token, and use `reset --hard` instead of `rebase`.
5. **OPS-10:** Add versioned, transactional, advisory-locked migrations and an upgrade-path test.
6. **OPS-12 / OPS-20:** Right-size SigNoz or move it off the box, offset the deploy from the factory tick, add log rotation and image pruning, and add `OnFailure=`.

**Later**
1. **OPS-18:** Build once in CI, push to GHCR, and promote by digest to a defined `prod` environment behind GitHub Environment approvals. Add PITR backups for prod and a written DR runbook with periodic restore drills.
2. **OPS-16:** Separate Unix users and credentials for the factory and the deploy, and enforce the SSH allow-list server-side with forced commands.
3. **OPS-17 / OPS-22:** Per-environment compose overrides (tunnel, ports), a decision on Authelia, and an Ansible or cloud-init host bootstrap.
4. **OPS-21:** Dependabot or Renovate for actions, Go, npm and Docker, digest-pinned images, and Trivy image scanning.
