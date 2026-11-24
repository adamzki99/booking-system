# Software factory

The automation that turns GitHub issues into merged PRs.

## Set up a new factory host

Run the guided installer from a checkout of this repository:

```sh
dev-ops/factory/setup-bot.sh
```

The installer asks for the GitHub App id, private key file, repository, trusted
human login(s), cron schedule, worktree location, session timeout (1 to 3300
seconds), and sandbox preference. It then:

- validates a short-lived installation token and derives the exact `[bot]` login,
- stores the private key and generated environment outside the checkout with
  restrictive permissions,
- creates a dedicated Python environment with PyJWT and PyYAML,
- configures HTTPS Git authentication and bot commit attribution,
- runs `tick.sh --dry-run`, and
- installs or refreshes one marked entry in the current user's crontab.

Create the GitHub App first at <https://github.com/settings/apps> and install it
on this repository only. Grant Contents, Issues, and Pull requests read/write,
plus Actions, Checks, and Metadata read. Do not grant Workflows or
Administration. Only the repository owner applies `owner approved`.

The Linux host needs `git`, `gh`, `opencode`, Python 3 with venv support,
`flock`, `timeout`, and cron. OpenCode must already be authenticated for the
model provider used by [`models.yaml`](models.yaml).

Use `--dry-run` to inspect the plan without writing files or contacting GitHub.
Use `--non-interactive` with explicit flags for automated provisioning. Cron
schedules use the host's local time. The generated files default to:

- `${XDG_CONFIG_HOME:-$HOME/.config}/booking-system-factory/`
- `${XDG_DATA_HOME:-$HOME/.local/share}/booking-system-factory/venv/`
- `${XDG_STATE_HOME:-$HOME/.local/state}/factory/`

Prefer running the scheduled job as a dedicated Unix user without personal
GitHub, SSH, Docker, or deployment credentials.

## How it works

1. [`tick.sh`](tick.sh) runs on a 1-hour interval (e.g. via cron) and fetches
   issues and pull requests from GitHub.
2. Per tick, it may start:
   - **up to two planning sessions** - one in the normal planning slot, plus one
     in the build slot when no build is selected. Discovery scans all unlabeled
     ("infant") issues oldest first and skips candidates with a trusted plan
     marker, missing acceptance criteria, or a failed gate without blocking later
     issues. Eligible issues must have an `## Acceptance Criteria` section with
     at least one measurable checkbox (gated by
     `dev-ops/scripts/check-acceptance-criteria.sh`). A planner agent posts the
     implementation plan as a comment and categorizes the issue with labels. It
     never applies `owner approved`.
   - **build-path sessions** (fixes, then optionally a new build):
     - **fix sessions** - for open factory PRs (head `factory/issue-*`) that are
       blocked from merge (failing/status checks, changes requested, or merge
       conflicts/non-mergeable). A fixer resumes the builder lifecycle to make
       the PR mergeable. Up to `--max-fix-sessions` /
       `FACTORY_MAX_FIX_SESSIONS` per tick (default: 1). Fix execution is
       serialized per tick to avoid shared-worktree races.
     - **one building session** - for the highest-priority `owner approved`
       issue with no build marker and no open factory PR, selected by build
       priority: issues in a GitHub Project (v2) come before others; among
       project issues, the oldest project (by `createdAt`) wins, then the
       numeric `Build order` project field ascending (from 1). Fallback is
       issue age.
     - **empty-PR guard** - after each build or fix session, tick reads the
       session's PR with `gh pr view --json changedFiles`. A factory PR (head
       `factory/issue-*`) with `changedFiles == 0` gets a short comment and is
       closed with an `empty_pr_closed` event instead of being left for merge.
       Human PRs are never touched. The guard runs even when a session failed;
       under `--dry-run` it only logs the intended action.
3. Labels select the model for the session, per [`models.yaml`](models.yaml)
   (fix sessions use the related issue's labels).

The total number of sessions is not limited - only the rate at which they are
created. The system owner steers the project by interacting with issues only.

## Invariants

- **Never touch the primary checkout.** Factory work runs in an isolated git
  worktree (`FACTORY_WORKTREE`, default sibling `<repo>-factory-worktree`).
- **Idempotent ticks.** Finished work carries `<!-- factory:plan -->` /
  `<!-- factory:build -->` markers; fix attempts carry
  `<!-- factory:fix-pr:<sha>:<reasons> -->` PR markers. Plan markers count only
  when their comment author matches `FACTORY_LOGIN`; an unset `FACTORY_LOGIN`
  trusts no plan marker.
- **Owner-approved gate is respected.** Only the repository owner applies
  `owner approved`; build selection requires it.
- **Trusted authors only.** Plan/build discovery accepts issues only from
  `FACTORY_TRUSTED_LOGINS` (plus `FACTORY_LOGIN` when set). Fix discovery also
  requires a same-repository PR from a trusted author and re-checks that trust
  immediately before the session. Prompt context includes comments only from
  trusted authors. An empty trusted set discovers nothing and trusts no comments.
- **No auto-merge bypass.** Sessions must not disable tests, weaken gates, edit
  CI to bypass failures, or merge around required checks/protections/reviews.

## CLI, flags, and environment

```
tick.sh [--dry-run] [--on-usage-filled=backup|skip|fail] [--max-fix-sessions=N]
tick.sh --help
```

| Flag / env | Default | Meaning |
|---|---|---|
| `--dry-run` | off | Select/log actions without starting sessions or acquiring run claims. |
| `--on-usage-filled=MODE` / `FACTORY_ON_USAGE_FILLED` | `backup` | On quota/usage-filled failure: retry configured backup, then `FACTORY_FREE_MODEL` if distinct; or `skip`; or `fail`. |
| `--max-fix-sessions=N` / `FACTORY_MAX_FIX_SESSIONS` | `1` | Max fix sessions per tick (serialized). |
| `FACTORY_FREE_MODEL` | `opencode-go/beam-free` | Last-resort model in backup mode. |
| `FACTORY_SESSION_TIMEOUT` | `3600` | Per-session timeout seconds (0 disables). |
| `FACTORY_GH_RETRIES` | `3` | Bounded retries for transient/rate-limited gh/git operations. |
| `FACTORY_CLAIM_TTL` | `7200` | Claim lease TTL seconds. |
| `FACTORY_CLAIM_DIR` | `/tmp/factory-claims` | Atomic lease directory. |
| `FACTORY_WORKTREE` | sibling `<repo>-factory-worktree` | Isolated factory worktree. |
| `FACTORY_CONFIG_TAG` | `factory-config` | Owner-moved git tag holding the signed-off guardrail snapshot. |
| `FACTORY_LOG_FILE` | `${XDG_STATE_HOME:-~/.local/state}/factory/tick.jsonl` | JSONL event log. |
| `FACTORY_ENV` | `dev` | `deployment.environment` field. |
| `FACTORY_ID` | `factory-1` | `factory_id` field on every event; one scheduler host = one factory id. |
| `FACTORY_METRICS_DIR` | `${XDG_STATE_HOME:-~/.local/state}/factory/metrics` | Directory for the atomic `factory_tick.prom` Prometheus textfile (written each tick in the EXIT trap). |
| `FACTORY_SESSION_LOG_DIR` | `/tmp/opencode` | Session logs and prompt temp files. |
| `FACTORY_LOG_SESSION_OUTPUT` | `tail` | `tail` retains last 16 KiB in failure events and writes session logs; `metadata` suppresses retained output. |
| `FACTORY_PRESERVE_SESSION_LOGS` | `on-failure` | `on-failure` (delete on success), `always`, `never`. |
| `FACTORY_CONTAINER_MODE` | `0` | `1` enables bwrap per-session sandbox; falls back to host if bwrap unavailable. |
| `FACTORY_LOGIN` | (unset) | Login of the factory bot/app identity. Plan markers from other authors are ignored; when unset, no plan marker is trusted. Also used to attribute factory work. |
| `FACTORY_TRUSTED_LOGINS` | (unset) | Comma/whitespace separated GitHub logins whose issues, PRs, and comments may drive the factory. Includes `FACTORY_LOGIN` when set. Empty discovers nothing and trusts no comments (fail closed). |
| `FACTORY_GITHUB_APP_ID` | (unset) | GitHub App id used to mint a short-lived least-privilege installation token per tick. |
| `FACTORY_GITHUB_APP_PRIVATE_KEY_FILE` | (unset) | Path to the app private key PEM (preferred over inline key). |
| `FACTORY_GITHUB_APP_PRIVATE_KEY` | (unset) | Inline app private key PEM (avoid; prefer file). |
| `FACTORY_GITHUB_INSTALLATION_ID` | (unset) | Installation id; auto-discovered from the repository when unset. |
| `MODELS_CONFIG` | `dev-ops/factory/models.yaml` | Label→model config. |

OpenCode invocation uses `opencode run --auto --format json --file <prompt-file>`
for robust prompt delivery and session ID capture. Each invocation is a
distinct run (new `run_id`) and reports its own `session_id`.

## Claims, leases, isolation, and timeouts

- **Global tick lock:** `flock -n` on `$(git rev-parse --git-dir)/factory-tick.lock`
  prevents overlapping ticks.
- **Fix claims (atomic leases):** before starting a fix session, tick acquires
  `$FACTORY_CLAIM_DIR/fix-<pr>-<head_sha>-<reasons>.claim` via atomic `mkdir`.
  Claims store the holder PID, are skipped on active conflict, and stale/dead-PID
  claims are reclaimed after `FACTORY_CLAIM_TTL`. Claim conflicts emit
  `claim_conflict` events. Fix execution is serialized per tick.
- **Plan/build claims:** selected plan and build issues acquire
  `plan-<issue>.claim` / `build-<issue>.claim` leases (same TTL/conflict
  semantics) before non-dry-run sessions. Combined with the global flock and
  marker/PR checks, this provides a sufficient single-host lease strategy and
  guards against stale concurrent processing.
- **Idempotency gates:** plan/build marker checks, open-factory-PR checks, and
  fix PR marker checks remain authoritative for "already done/attempted" skips.
- **Worktree isolation:** the primary checkout is never modified by tick;
  sessions run from `FACTORY_WORKTREE`. Dirty worktrees are preserved and emit
  `dirty_worktree_skipped_reset`.
- **Timeouts/interrupts:** each session runs under `timeout` when
  `FACTORY_SESSION_TIMEOUT>0`; signals emit `tick_interrupted`.
- **Guardrail drift gate:** `tick.sh` starts no session when the guardrail files
  it loads from `origin/main` differ from the owner-moved `factory-config` tag
  (see below).

## Guardrail drift gate

The agent and config files that OpenCode loads in the worktree
(`.opencode/agents/`, `opencode.jsonc`, `AGENTS.md`) are guardrails for every
session. Before issue discovery, `tick.sh` compares those files in `origin/main`
against the owner-moved `factory-config` tag. On drift it emits `guardrail_drift`
and exits non-zero, so no session starts. A missing or unfetchable tag also fails
closed. A clean comparison emits `guardrail_ok`. Override the tag name with
`FACTORY_CONFIG_TAG`.

**How the owner moves the tag.** Only the repository owner moves
`factory-config`. After reviewing and merging a change to any guardrail file,
move the tag to the signed-off commit on the default branch and replace the
remote tag:

```
git fetch origin main
git tag -f factory-config origin/main
git push -f origin refs/tags/factory-config
```

The force update is required because the tag is moved deliberately. Do this in
the same review window as the guardrail change: until the tag is moved, tick
fails closed and starts no sessions. `CODEOWNERS` (`.github/CODEOWNERS`) plus the
`protect-main` ruleset option "Require review from Code Owners" make those
guardrail changes owner-reviewed on GitHub.

## Failure classification, retry, and exit semantics

- `gh`/git failures are classified as `auth`, `permission`, `rate_limit`,
  `transient`, `not_found`, `conflict`, `empty`, or `other`.
- Idempotent discovery/read/fetch operations use bounded retries with backoff
  for `transient` and `rate_limit` categories (`FACTORY_GH_RETRIES`, attempt
  numbers/events emitted). Non-retryable classes fail fast with classification.
- "No candidates" is distinct from infra/auth failures: if selection/discovery
  cannot be completed due to infra/auth/permission/rate-limit/transient errors,
  tick emits `discovery_failed` and exits non-zero instead of `nothing_to_do`.
- `project priority unavailable` is a degraded but non-fatal fallback to issue
  age (event emitted) unless underlying discovery failed.
- Aggregated tick exit is non-zero on session failures, fix failures, or
  discovery/infra failures as above.

## Sandbox and runtime/log/state semantics

- **Host mode (default):** sessions run on the host in `FACTORY_WORKTREE`.
- **bwrap mode (`FACTORY_CONTAINER_MODE=1`):** best-effort per-session process
  sandbox (`--unshare-pid/ipc/uts`, `--cap-drop ALL`, read-only root bind with
  explicit writable binds for worktree/home/tmp/session-log dir). If `bwrap` is
  unavailable, tick falls back to host and emits `container_mode reason=fallback-host`.
- **bwrap vs disposable containers:** bwrap is not a disposable container/VM. It
  provides namespace/capability hardening but shares the host kernel, selected
  host paths (home/worktree/tmp/log dirs), host network namespace, and host
  credentials/tools available in bound paths. It does **not** provide
  image-level immutability, independent package/runtime state, or strong
  filesystem isolation equivalent to ephemeral containers.
- **Per-session isolation:** each opencode session is a separate process with
  timeout; fix/build/plan sessions are not run concurrently in one tick. Runtime
  worktrees/state created by agents under the factory worktree are per-issue
  artifacts managed by the session prompts and preserved on failure/interruption.
- **Prompt files:** written with restrictive permissions under the session log
  dir and deleted after the session attempt (ephemeral runtime input).
- **Session logs:** `FACTORY_SESSION_LOG_DIR/factory-<kind>-<ref>.log`.
  `FACTORY_LOG_SESSION_OUTPUT=metadata` disables retained log content.
  `FACTORY_PRESERVE_SESSION_LOGS` controls success-delete/failure-preserve
  semantics (`on-failure` default). Preserved logs and stale claims are a
  retention/debug path cleaned by `nightly-cleanup.sh` (age-based).

## Observability

`tick.sh` appends one JSON object per event to `FACTORY_LOG_FILE` (default
`${XDG_STATE_HOME:-$HOME/.local/state}/factory/tick.jsonl`). Human output on
stdout/stderr remains separate.

The event model is **schema version 2** (SCHEMA_VERSION = 2 in
`lib/factory.py`). Every event carries `schema_version`, `event_id` (UUIDv4),
`event`, `ts` (RFC 3339 UTC with milliseconds), `service.name`, `factory_id`,
`deployment.environment`, `host.name`, `tick_id`, `dry_run` and
`on_usage_filled`. `tick_id` identifies one scheduler invocation; it is the
analysis model's `schedule_id`. `factory_id` identifies one factory host
(default `factory-1`).

Documentation: [`EVENTS.md`](EVENTS.md) is the single source of truth for the
event model. It lists every event name `tick.sh` can emit, common and
run-scoped fields, lifecycle events, usage/cost fields parsed from the
opencode JSON stream, reconciled GitHub outcome events, deploy events, and a
legacy-to-v2 mapping.

At the end of every tick (in the EXIT trap, so it also runs on failure),
tick writes a Prometheus textfile atomically to
`${FACTORY_METRICS_DIR}/factory_tick.prom` (`factory_tick_last_run_timestamp_seconds`,
`factory_tick_last_success_timestamp_seconds`, `factory_tick_last_duration_seconds`,
`factory_tick_last_exit_code`, `factory_tick_runs_last{kind,outcome}` and
`factory_telemetry_errors_last`). The metrics directory is mode `0755` and the
textfile is mode `0644` so node-exporter can read it. The event JSONL remains
private. Mount this directory into a node-exporter textfile collector.

Events never contain raw session output, regardless of
`FACTORY_LOG_SESSION_OUTPUT`. The 16 KiB tail is kept only in the local
session log file. See `EVENTS.md` for `failure_reason` and
`error_fingerprint` (sha256 of the normalised last error line, first 12 hex
chars).

### Factory monitoring stack

The persistent factory monitoring stack lives in
[`monitoring/`](monitoring/README.md). It runs ClickHouse, Prometheus, Grafana,
node-exporter, and an OpenTelemetry Collector that tails factory JSONL and
exports logs/traces to ClickHouse. Start it on the factory host with:

```sh
cd dev-ops/factory/monitoring
cp .env.example .env
# fill required secrets and paths
docker compose up -d
```

How events reach it:
- Same host: bind-mount `FACTORY_LOG_DIR` read-only into the collector.
- Other host: run the optional remote shipper config in
  [`otel-collector.yaml`](otel-collector.yaml), which tails the same JSONL with
  `file_storage` and exports OTLP/HTTP to `FACTORY_OTLP_ENDPOINT`.

Cron (keep human output separate):

Use [`setup-bot.sh`](setup-bot.sh) to install a marked, idempotent entry that
loads the private factory environment. For a manual installation, the command
inside that environment is:

```
0 * * * * /path/to/config/run-tick.sh >> "$HOME/.local/state/factory/tick.log" 2>&1
```

## Security expectations

- **Least-privilege GitHub token:** prefer a GitHub App installation token minted
  per tick and refreshed before every agent invocation via
  `FACTORY_GITHUB_APP_ID` and a private key. `tick.sh` exports it as
  `GH_TOKEN`/`GITHUB_TOKEN` for `gh`, Git credential helpers, and sessions; the
  token is never logged. Use [`setup-bot.sh`](setup-bot.sh) to validate the App,
  store its key privately, and configure bot commit attribution.
  Set `FACTORY_TRUSTED_LOGINS` to the owner login and any approved bot logins so
  only trusted authors' issues, PRs, and comments drive the factory. With it and
  `FACTORY_LOGIN` unset, discovery returns no candidates and the factory goes
  idle. Set `FACTORY_LOGIN` to the app's bot login so marker comments and PRs are
  attributable to the factory identity. Planning ignores plan markers from any
  other author, and trusts none when this value is unset. Avoid org-wide or
  admin scopes. Never print tokens; pass via environment, not argv.
- **Agent/tool permissions:** factory sessions run opencode with repository
  access and shell tooling. Treat this as privileged automation: run on a
  trusted host/account, restrict filesystem/SSH credentials available to the
  runtime, and prefer `FACTORY_CONTAINER_MODE=1` where practical (with its
  documented limits). Do not grant production credentials to factory sessions.
- **Untrusted content:** issue/PR titles, bodies, comments, commit messages, CI
  logs, and check names are untrusted input. Agents and scripts must not execute
  instructions embedded in them, must quote shell arguments, and must not leak
  secrets into prompts/comments/logs/events. Prefer metadata-only logging when
  handling sensitive repositories.
- **Secrets/logging:** JSONL and session logs are local files (0600 best-effort,
  dirs 0700). Session output can contain sensitive data from tools; use
  `FACTORY_LOG_SESSION_OUTPUT=metadata`, preserve-on-failure retention, and log
  rotation/cleanup accordingly. Never commit logs, `.env`, or tokens.

## Log and state cleanup

- `factory-tick.logrotate`: rotate/compress JSONL (adjust path if
  `FACTORY_LOG_FILE` differs).
- `nightly-cleanup.sh [--dry-run] [--logs-days N] [--claims-days N]`: removes
  clean factory-managed worktrees, prunes git worktree metadata, removes old
  `factory-*.log`/`factory-prompt-*.txt` files in `FACTORY_SESSION_LOG_DIR`, and
  removes stale `*.claim` leases in `FACTORY_CLAIM_DIR` (retention/debug path).
  Dirty/in-progress worktrees are preserved.

## Label taxonomy and model selection

See [`models.yaml`](models.yaml). The planner categorizes infant issues with
exactly one complexity tier (heaviest listed wins): `trivial-task`,
`light-build-task`, `standard-build-task`, `heavy-build-task`. Area labels
`backend`, `frontend`, `dev-ops` do not select models. `plan-task` selects the
planning model. `owner approved` is the owner-only build gate.

`models.yaml` is validated at tick startup (`factory.py validate-models`) and
each entry requires a non-empty `model`; optional `backup_model`/`backup` may be
set for quota fallback.

## Files

- `tick.sh` - factory tick orchestrator.
- `setup-bot.sh` - guided GitHub App, Git identity, dependency, and cron setup.
- `requirements.txt` - Python dependencies for token minting and ticks.
- `models.yaml` - label→model mapping.
- `lib/factory.py` - validation, classification, event helpers, claim helpers.
- `discover_fix_candidates.py`, `discover_build_candidates.py` - discovery logic.
- `nightly-cleanup.sh` - worktree/log/claim retention cleanup.
- `factory-tick.logrotate` - JSONL logrotate example.
- `otel-collector.yaml` - optional remote shipper config for factory JSONL events.
