# Factory event model v2

Single source of truth for the structured, typed, uniquely identified,
idempotent JSONL events emitted by `dev-ops/factory/tick.sh`. Implemented in
`dev-ops/factory/lib/factory.py` (SCHEMA_VERSION = 2) and linked from
`dev-ops/factory/README.md`.

## Schema version

Every event carries `"schema_version": 2`. `validate_event` accepts v2 and
rejects any other version (including v3 and non-integer values). Bumping the
schema again requires a new major version and a new `validate_event` check.

## Common fields (every event)

| Field                    | Type   | Notes                                                                                                                                                              |
| ------------------------ | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `schema_version`         | int    | `2`                                                                                                                                                                |
| `event_id`               | string | UUIDv4 for live emissions; deterministic (prompt 02) for reconciled GitHub events. Used for idempotent loading into ClickHouse.                                    |
| `event`                  | string | event name (see "Lifecycle events" below)                                                                                                                          |
| `ts`                     | string | RFC 3339 UTC with milliseconds, `Z` suffix                                                                                                                         |
| `service.name`           | string | `factory-tick`                                                                                                                                                     |
| `factory_id`             | string | `FACTORY_ID` env, default `factory-1`; identifies one factory host                                                                                                 |
| `deployment.environment` | string | For factory events, `FACTORY_ENV` env, default `dev`, identifying the factory host. For `deploy.*` events, the target `ENV_NAME` from `dev-ops/environments.yaml`. |
| `host.name`              | string | hostname of the factory host                                                                                                                                       |
| `tick_id`                | string | one scheduler invocation; this is the analysis model's `schedule_id`                                                                                               |
| `dry_run`                | bool   | `true` when `tick.sh --dry-run`                                                                                                                                    |
| `on_usage_filled`        | string | `backup`                                                                                                                                                           | `skip` | `fail` (`FACTORY_ON_USAGE_FILLED`) |
| `repo`                   | string | `owner/name` from `gh repo view` or the git remote; omitted when unknown                                                                                           |

## Run-scoped fields (every `agent.run.*` event)

| Field            | Type             | Notes                                                                                                                            |
| ---------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `run_id`         | string           | UUIDv4, one per opencode invocation; a backup or free retry is a new run                                                         |
| `attempt`        | int              | 1, 2, 3 within one session request                                                                                               |
| `fallback_level` | string           | `primary`                                                                                                                        | `backup`  | `free`  |
| `kind`           | string           | `plan`                                                                                                                           | `build`   | `fix`   |
| `agent_id`       | string           | `planner`                                                                                                                        | `builder` | `fixer` |
| `agent_version`  | string           | first 12 hex chars of sha256 of `.opencode/agents/<agent>.md` as checked out in the factory worktree (`unknown` when unreadable) |
| `prompt_version` | string           | sha256 prefix (first 12 hex chars) of the rendered prompt template before issue-specific substitution                            |
| `model`          | string           | model used for the session                                                                                                       |
| `issue_id`       | int              | for fix sessions, derived from the `factory/issue-<n>` head branch                                                               |
| `pr_number`      | int              | when known                                                                                                                       |
| `session_id`     | string           | opencode session id, parsed from the JSON stream                                                                                 |
| `trace_id`       | string           | 32 hex chars W3C trace id, generated per run (propagated into OpenCode in prompt 05)                                             |
| `tier_label`     | string           | selected model tier label                                                                                                        |
| `area_labels`    | array of strings | area labels for the session                                                                                                      |

Usage and cost are emitted on `agent.run.completed` and `agent.run.failed`:
`duration_ms`, `steps`, `input_tokens`, `output_tokens`, `reasoning_tokens`,
`cache_read_tokens`, `cache_write_tokens`, `cost_usd` (as reported by
OpenCode; may be 0 for subscription models, never invented),
`tool_calls` (int), `tool_errors` (int), `skills_loaded` (array of strings),
`files_changed` (int, when determinable cheaply, otherwise omitted).

Missing fields are omitted, never a crash. A malformed stream yields an empty
summary. A structured OpenCode `type: "error"` record makes the invocation fail
even when the CLI exits 0, so usage fallback and failure reporting still run.
Quota fallback uses the structured error type or HTTP 402/429 status as well as
message text. `exit_code` is the effective status: a structured error record is
normalized to a non-zero value.

## Lifecycle events

| Event                 | Emitted when                                                                                                                                                                          |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `issue.detected`      | an issue is selected as eligible for planning or building in this tick                                                                                                                |
| `issue.assigned`      | a claim is acquired and an agent will run on it (`kind`, `agent_id`)                                                                                                                  |
| `agent.run.started`   | an opencode invocation starts                                                                                                                                                         |
| `agent.tool.called`   | one per tool call, parsed from the opencode JSON stream after the run (fields: `run_id`, `tool`, `status`, `duration_ms` if available; skill loads as `tool=skill` with `skill_name`) |
| `agent.run.completed` | opencode exited 0 and its JSON stream contained no error record                                                                                                                       |
| `agent.run.failed`    | non-zero exit, structured OpenCode error record, timeout, interruption or usage-filled (`failure_reason`, `exit_code`)                                                                |

## Reconciled GitHub outcome events

Emitted by `dev-ops/factory/reconcile_outcomes.py` at the end of every
non-dry-run tick (best-effort; failure emits `reconcile_failed` and never
changes the tick exit code) and standalone for backfill. These events describe
GitHub facts that may be observed many times.

**Deterministic id rule:** `event_id` is the first 32 hex chars of
`sha256("<event>|<repo>|<github node id or number>|<state-defining field>")`.
Re-running the reconciler produces identical ids so ClickHouse
(`ReplacingMergeTree(event_id)`, prompt 03) deduplicates them.

**Timestamps:** use GitHub timestamps (`merged_at`, `closed_at`, ...) as `ts`
for these events, not the time of observation. Add `observed_at` (RFC 3339 UTC)
for when the reconciler saw the fact.

**No free text:** numbers, ids, states, timestamps and label names only. PR/issue
titles, bodies and comments are treated as untrusted and never copied into events.

| Event            | Fields (in addition to common fields)                                                                                                                                                                                                                            |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pr.created`     | `pr_number` (int), `issue_id` (int), `created_at` (string), `head_branch` (string), `draft` (bool)                                                                                                                                                               |
| `pr.review`      | `pr_number` (int), `review_id` (string), `state` (`approved`\|`changes_requested`\|`commented`), `reviewer_is_owner` (bool), `submitted_at` (string)                                                                                                             |
| `pr.checks`      | `pr_number` (int), `head_sha` (string), `conclusion` (`success`\|`failure`\|`pending`\|`mixed`), `failed_checks` (array of check names) for the PR head when it changes                                                                                          |
| `pr.merged`      | `pr_number` (int), `issue_id` (int), `merged_at` (string), `commits` (int), `additions` (int), `deletions` (int), `changed_files` (int), `review_comments` (int), `human_commits` (int, commits not authored by `FACTORY_LOGIN`; a proxy for human intervention) |
| `pr.closed`      | `pr_number` (int), `issue_id` (int), `closed_at` (string, closed without merge)                                                                                                                                                                                  |
| `issue.approved` | `issue_id` (int), `approved_at` (string, time the `owner approved` label was added, from the issue timeline)                                                                                                                                                     |
| `issue.closed`   | `issue_id` (int), `closed_at` (string), `state_reason` (string, when present)                                                                                                                                                                                    |
| `issue.reopened` | `issue_id` (int), `reopened_at` (string)                                                                                                                                                                                                                         |

## Deploy events

Emitted by `dev-ops/scripts/deploy-environment.sh` via `factory.py emit` (the
same emitter). Deploys may run in a different systemd unit than tick; they use
`FACTORY_LOG_FILE` with the same default so both land in one file. Concurrent
appends are safe because each event is a single `write()` of one JSON line in
append mode.

For deploy events, `deployment.environment` is the selected `ENV_NAME` (`qa` or
a configured release environment name), not `FACTORY_ENV`. `FACTORY_ENV`
continues to identify the factory host on tick, agent run, trace, and reconciled
events. `env_name` remains in `attrs` for compatibility. The collector promotes
`deployment.environment` to a resource attribute, and ClickHouse maps that
resource value to `deployment_environment`, so both representations identify the
same deployment target for new events. Existing events remain unchanged.

| Event              | Fields (in addition to common fields)                                                               |
| ------------------ | --------------------------------------------------------------------------------------------------- |
| `deploy.started`   | `env_name` (string), `branch` (string), `commit` (string), `previous_commit` (string)               |
| `deploy.completed` | `env_name` (string), `commit` (string), `duration_ms` (int), `health` (string, health check result) |
| `deploy.failed`    | `env_name` (string), `commit` (string), `duration_ms` (int), `failed_step` (string)                 |

The deploy script exports `DEPLOY_COMMIT` and `ENV_NAME` so prompt 06 can pass
them to the backend as `service.version` and `deployment.environment`.

## Operational events

Kept with their current names, now typed: `tick_start`, `tick_end`,
`tick_result`, `tick_interrupted`, `lock_skipped`, `gh_op_retry`,
`gh_op_failed`, `claim_conflict`, `guardrail_ok`, `guardrail_drift`,
`usage_filled`, `backup_retry`, `free_retry`, `marker_skip`,
`empty_pr_closed`, `nothing_to_do`, `discovery_failed`, `fix_discovery_error`,
`build_discovery_error`, `project_priority_fallback`, `plan_skipped`,
`fix_selected`, `build_selected`, `plan_selected`, `container_mode`,
`git_fetch_failed`, `dirty_worktree_skipped_reset`, `factory.queue`,
`reconcile_failed`.

Guardrail attestation events carry `approved_ref` and `manifest_path`.
`guardrail_ok` is emitted when `origin/main` matches the approved manifest.
`guardrail_drift` carries `reason` (`approved_ref_fetch_failed`,
`manifest_missing`, `manifest_unreadable`, `manifest_invalid`,
`current_unreadable`, or `manifest_mismatch`) and may include `detail` with a
short changed-path summary.

`factory.queue` is emitted once per tick (also in dry-run) with integer counts:
`infant` (open, no labels), `planned` (has plan marker, not approved),
`approved_waiting` (approved, no factory PR), `in_pr` (open factory PR),
`blocked_pr` (open factory PR that discovery would consider for fixing),
`needs_info` (omitted when no such label exists in the label taxonomy).

A skipped-for-usage session is `agent.run.failed` with
`failure_reason=usage_filled_skipped`.

## Failure reporting (no raw output in events)

Raw session output is never placed into a JSONL event. Failure analysis uses:

- `failure_reason`: one of `timeout`, `usage_filled`, `exit_nonzero`,
  `opencode_error`, `interrupted`, `usage_filled_skipped`; classified by
  `factory.classify_failure`.
- `error_fingerprint`: sha256 of the normalised last error line, first 12 hex
  chars (`factory.error_fingerprint`); omitted when there is no usable error
  line.
- `session_id`: parsed from the opencode JSON stream (`factory.session_id_from_stream`).

The 16 KiB output tail remains only in the local session log file
(`FACTORY_SESSION_LOG_DIR/factory-<kind>-.log`), governed by
`FACTORY_LOG_SESSION_OUTPUT` and `FACTORY_PRESERVE_SESSION_LOGS`.

## Legacy-to-v2 mapping

| Legacy event (removed)          | v2 replacement                                               |
| ------------------------------- | ------------------------------------------------------------ |
| `session_start`                 | `agent.run.started`                                          |
| `session_ok`                    | `agent.run.completed`                                        |
| `session_failed`                | `agent.run.failed`                                           |
| `backup_ok`                     | `agent.run.completed` (fallback_level=backup)                |
| `free_retry` (as session start) | `agent.run.started` (fallback_level=free)                    |
| `session_skipped_usage`         | `agent.run.failed` (failure_reason=usage_filled_skipped)     |
| `usage_filled` (standalone)     | folded into `agent.run.failed` (failure_reason=usage_filled) |

## Typed fields

All `k=v` fields passed from `tick.sh` or `factory.py emit` are coerced to
real JSON types in `factory.py`:

- ints: `schema_version`, `exit_code`, `duration_ms`, `attempt`,
  `pr_number`, `issue_id`, `tool_calls`, `tool_errors`, `files_changed`,
  `input_tokens`, `output_tokens`, `reasoning_tokens`, `cache_read_tokens`,
  `cache_write_tokens`, `steps`, `telemetry_errors`, `fix_failures`,
  `commits`, `additions`, `deletions`, `changed_files`, `review_comments`,
  `human_commits`, `infant`, `planned`, `approved_waiting`, `in_pr`,
  `blocked_pr`, `needs_info`.
- floats: `cost_usd`.
- bools: `dry_run`, `draft`, `reviewer_is_owner`.
- arrays: `skills_loaded`, `area_labels`, `failed_checks` (comma-separated or JSON array).

## Telemetry errors

Emission is non-fatal. Failures are counted in `TELEMETRY_ERRORS`, reported
with one warning line to stderr per failure, and surfaced on the final
`tick_end` event as `telemetry_errors` (int).

## Events emitted by tick.sh (authoritative list)

`agent.run.completed`, `agent.run.failed`, `agent.run.started`,
`agent.tool.called`, `build_discovery_error`, `build_selected`,
`claim_conflict`, `container_mode`, `dirty_worktree_skipped_reset`,
`discovery_failed`, `dry_run`, `factory.queue`, `fix_discovery_error`,
`fix_selected`, `gh_op_failed`, `gh_op_retry`, `git_fetch_failed`,
`guardrail_drift`, `guardrail_ok`, `issue.assigned`, `issue.detected`,
`lock_skipped`, `marker_skip`, `nothing_to_do`, `plan_selected`,
`plan_skipped`, `project_priority_fallback`, `reconcile_failed`,
`tick_end`, `tick_interrupted`, `tick_result`, `tick_start`.

This list must stay in sync with `grep -o 'emit_event [a-z_.]*' dev-ops/factory/tick.sh | sort -u`.

## State-defining fields for reconciled events

| Event            | GitHub node id or number        | State-defining field                                          |
| ---------------- | ------------------------------- | ------------------------------------------------------------- |
| `pr.created`     | PR node id (or PR number)       | `created_at`                                                  |
| `pr.review`      | review id                       | mapped `state` (`approved`\|`changes_requested`\|`commented`) |
| `pr.checks`      | PR number                       | `head_sha:conclusion`                                         |
| `pr.merged`      | PR node id (or PR number)       | `merged_at`                                                   |
| `pr.closed`      | PR node id (or PR number)       | `closed_at`                                                   |
| `issue.approved` | timeline event id (or fallback) | `approved_at`                                                 |
| `issue.closed`   | timeline event id (or fallback) | `closed_at`                                                   |
| `issue.reopened` | timeline event id (or fallback) | `reopened_at`                                                 |

## Derived metrics

Defined in words and as field arithmetic. Prompt 03/04 build these from
ClickHouse/Grafana.

| Metric                  | Definition                                                                                                   |
| ----------------------- | ------------------------------------------------------------------------------------------------------------ |
| Issue throughput        | `issue.closed` with a merged factory PR, per day                                                             |
| First-pass success      | issues whose first factory PR merged with no `kind=fix` run / all completed issues                           |
| Agent efficiency        | merged PRs / sum of `agent.run.*` `duration_ms` in hours                                                     |
| Cost efficiency         | sum `cost_usd` of all runs for an issue / merged PRs                                                         |
| Rework rate             | completed issues that needed more than one build/fix run / completed issues                                  |
| Lead time               | `issue.approved.approved_at` (or first `agent.run.started`) to `pr.merged.merged_at`                         |
| Pickup to merge         | first `agent.run.started` for the issue to `pr.merged`                                                       |
| PR acceptance rate      | `pr.merged` / (`pr.merged` + `pr.closed`)                                                                    |
| Human intervention rate | merged PRs with `human_commits > 0` or an owner `changes_requested` review / merged PRs                      |
| Factory utilisation     | sum of run `duration_ms` / available time (tick interval times concurrent session slots, a Grafana variable) |
| Abandoned issues        | issues with at least one run, no open PR and no activity for N days, or whose PR was closed unmerged         |
