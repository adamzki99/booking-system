# Software factory

The automation that turns GitHub issues into merged PRs.

## How it works

1. [`tick.sh`](tick.sh) runs on a 1-hour interval (e.g. via cron) and fetches
   issues and pull requests from GitHub.
2. Per tick, it may start:
   - **one planning session** - for the oldest unlabeled ("infant") issue, but
     only if it has an `## Acceptance Criteria` section with at least one
     measurable checkbox (gated by
     `dev-ops/scripts/check-acceptance-criteria.sh`).
     A planner agent posts the implementation plan as a comment and categorizes
     the issue with labels. It never applies `owner approved`.
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
  `<!-- factory:fix-pr:<sha>:<reasons> -->` PR markers.
- **Owner-approved gate is respected.** Only the repository owner applies
  `owner approved`; build selection requires it.
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
| `FACTORY_SESSION_LOG_DIR` | `/tmp/opencode` | Session logs and prompt temp files. |
| `FACTORY_LOG_SESSION_OUTPUT` | `tail` | `tail` retains last 16 KiB in failure events and writes session logs; `metadata` suppresses retained output. |
| `FACTORY_PRESERVE_SESSION_LOGS` | `on-failure` | `on-failure` (delete on success), `always`, `never`. |
| `FACTORY_CONTAINER_MODE` | `0` | `1` enables bwrap per-session sandbox; falls back to host if bwrap unavailable. |
| `FACTORY_LOGIN` | (unset) | Login of the factory bot/app identity used to filter marker comments and attribute factory work. |
| `FACTORY_TRUSTED_LOGINS` | (unset) | Comma/whitespace separated set of trusted GitHub logins whose issues, PRs and comments may drive the factory. Empty keeps nothing (fail closed). Includes `FACTORY_LOGIN` when set. |
| `FACTORY_GITHUB_APP_ID` | (unset) | GitHub App id used to mint a short-lived least-privilege installation token per tick. |
| `FACTORY_GITHUB_APP_PRIVATE_KEY_FILE` | (unset) | Path to the app private key PEM (preferred over inline key). |
| `FACTORY_GITHUB_APP_PRIVATE_KEY` | (unset) | Inline app private key PEM (avoid; prefer file). |
| `FACTORY_GITHUB_INSTALLATION_ID` | (unset) | Installation id; auto-discovered from the repository when unset. |
| `MODELS_CONFIG` | `dev-ops/factory/models.yaml` | Label→model config. |

OpenCode invocation uses `opencode run --auto --format json --file <prompt-file>`
for robust prompt delivery and session ID capture.

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

Common event fields: `schema_version` (currently 1), `ts`, `service.name`,
`deployment.environment`, `host.name`, `tick_id`, `dry_run`, `on_usage_filled`,
`event`, plus event-specific fields (reason/category, attempt numbers, counts,
durations, model/agent, `session_id`, PR/issue refs, quota reason, etc.).

Representative events include `tick_start/end/result/interrupted`,
`lock_skipped`, `gh_op_retry/gh_op_failed`, `fix_discovery_error`,
`build_discovery_error`, `discovery_failed`, `project_priority_fallback`,
`claim_conflict`, `dirty_worktree_skipped_reset`, `git_fetch_failed`,
`guardrail_drift/guardrail_ok`, `session_*`, `usage_filled`, `backup_retry/ok`,
`free_retry`, `dry_run`,
`marker_skip`, `empty_pr_closed`, and `nothing_to_do`.

Cron (keep human output separate):
```
0 * * * * /path/to/repo/dev-ops/factory/tick.sh >> "$HOME/.local/state/factory/tick.log" 2>&1
```

Ship factory tick events to SigNoz using one of these same-host options:

- **SigNoz collector integration (preferred when SigNoz runs on the same host):**
  `dev-ops/signoz/otel-collector-config.yaml` includes a `filelog/factory`
  receiver that tails `/var/log/factory/tick.jsonl` inside the collector
  container. Set `FACTORY_LOG_DIR` to the directory containing `tick.jsonl`
  (default `${XDG_STATE_HOME:-$HOME/.local/state}/factory`) when starting
  `dev-ops/signoz/docker-compose.yml`.
- **Standalone shipper:** run `otelcol-contrib` as a user systemd unit on the
  cron host using `dev-ops/factory/otel-collector.yaml` (`filelog` receiver →
  OTLP/HTTP). Required env: `FACTORY_LOG_FILE`, `SIGNOZ_OTLP_ENDPOINT`, optional
  `SIGNOZ_INGESTION_KEY`.

## Security expectations

- **Least-privilege GitHub token:** prefer a GitHub App installation token minted
  per tick via `FACTORY_GITHUB_APP_ID` and a private key. `tick.sh` exports it as
  `GH_TOKEN`/`GITHUB_TOKEN` for `gh` and sessions; the token is never logged.
  Set `FACTORY_TRUSTED_LOGINS` to the owner login (and the bot login from I-006) so only trusted authors' issues, PRs and comments drive the factory. With it unset, discovery returns no candidates and the factory goes idle.\n  Set `FACTORY_LOGIN` to the app's bot login so marker comments and PRs are
  attributable to the factory identity. Avoid org-wide or admin scopes. Never
  print tokens; pass via environment, not argv.
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
- `models.yaml` - label→model mapping.
- `lib/factory.py` - validation, classification, event helpers, claim helpers.
- `discover_fix_candidates.py`, `discover_build_candidates.py` - discovery logic.
- `nightly-cleanup.sh` - worktree/log/claim retention cleanup.
- `factory-tick.logrotate` - JSONL logrotate example.
- `otel-collector.yaml` - optional SigNoz/log shipping config.
