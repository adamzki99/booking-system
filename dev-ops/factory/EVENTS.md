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

| Field | Type | Notes |
|---|---|---|
| `schema_version` | int | `2` |
| `event_id` | string | UUIDv4 for live emissions; deterministic (prompt 02) for reconciled GitHub events. Used for idempotent loading into ClickHouse. |
| `event` | string | event name (see "Lifecycle events" below) |
| `ts` | string | RFC 3339 UTC with milliseconds, `Z` suffix |
| `service.name` | string | `factory-tick` |
| `factory_id` | string | `FACTORY_ID` env, default `factory-1`; identifies one factory host |
| `deployment.environment` | string | `FACTORY_ENV` env, default `dev` |
| `host.name` | string | hostname of the factory host |
| `tick_id` | string | one scheduler invocation; this is the analysis model's `schedule_id` |
| `dry_run` | bool | `true` when `tick.sh --dry-run` |
| `on_usage_filled` | string | `backup` | `skip` | `fail` (`FACTORY_ON_USAGE_FILLED`) |
| `repo` | string | `owner/name` from `gh repo view` or the git remote; omitted when unknown |

## Run-scoped fields (every `agent.run.*` event)

| Field | Type | Notes |
|---|---|---|
| `run_id` | string | UUIDv4, one per opencode invocation; a backup or free retry is a new run |
| `attempt` | int | 1, 2, 3 within one session request |
| `fallback_level` | string | `primary` | `backup` | `free` |
| `kind` | string | `plan` | `build` | `fix` |
| `agent_id` | string | `planner` | `builder` | `fixer` |
| `agent_version` | string | first 12 hex chars of sha256 of `.opencode/agents/<agent>.md` as checked out in the factory worktree (`unknown` when unreadable) |
| `prompt_version` | string | sha256 prefix (first 12 hex chars) of the rendered prompt template before issue-specific substitution |
| `model` | string | model used for the session |
| `issue_id` | int | for fix sessions, derived from the `factory/issue-<n>` head branch |
| `pr_number` | int | when known |
| `session_id` | string | opencode session id, parsed from the JSON stream |
| `trace_id` | string | 32 hex chars W3C trace id, generated per run (propagated into OpenCode in prompt 05) |
| `tier_label` | string | selected model tier label |
| `area_labels` | array of strings | area labels for the session |

Usage and cost are emitted on `agent.run.completed` and `agent.run.failed`:
`duration_ms`, `steps`, `input_tokens`, `output_tokens`, `reasoning_tokens`,
`cache_read_tokens`, `cache_write_tokens`, `cost_usd` (as reported by
OpenCode; may be 0 for subscription models, never invented),
`tool_calls` (int), `tool_errors` (int), `skills_loaded` (array of strings),
`files_changed` (int, when determinable cheaply, otherwise omitted).

Missing fields are omitted, never a crash. A malformed stream yields an empty
summary.

## Lifecycle events

| Event | Emitted when |
|---|---|
| `issue.detected` | an issue is selected as eligible for planning or building in this tick |
| `issue.assigned` | a claim is acquired and an agent will run on it (`kind`, `agent_id`) |
| `agent.run.started` | an opencode invocation starts |
| `agent.tool.called` | one per tool call, parsed from the opencode JSON stream after the run (fields: `run_id`, `tool`, `status`, `duration_ms` if available; skill loads as `tool=skill` with `skill_name`) |
| `agent.run.completed` | opencode exited 0 |
| `agent.run.failed` | non-zero exit, timeout, interruption or usage-filled (`failure_reason`, `exit_code`) |

`pr.created`, `pr.merged`, `pr.closed`, `issue.closed` and friends come from
GitHub reconciliation in prompt 02. They are not faked here.

## Operational events

Kept with their current names, now typed: `tick_start`, `tick_end`,
`tick_result`, `tick_interrupted`, `lock_skipped`, `gh_op_retry`,
`gh_op_failed`, `claim_conflict`, `guardrail_ok`, `guardrail_drift`,
`usage_filled`, `backup_retry`, `free_retry`, `marker_skip`,
`empty_pr_closed`, `nothing_to_do`, `discovery_failed`, `fix_discovery_error`,
`build_discovery_error`, `project_priority_fallback`, `plan_skipped`,
`fix_selected`, `build_selected`, `plan_selected`, `container_mode`,
`git_fetch_failed`, `dirty_worktree_skipped_reset`.

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

| Legacy event (removed) | v2 replacement |
|---|---|
| `session_start` | `agent.run.started` |
| `session_ok` | `agent.run.completed` |
| `session_failed` | `agent.run.failed` |
| `backup_ok` | `agent.run.completed` (fallback_level=backup) |
| `free_retry` (as session start) | `agent.run.started` (fallback_level=free) |
| `session_skipped_usage` | `agent.run.failed` (failure_reason=usage_filled_skipped) |
| `usage_filled` (standalone) | folded into `agent.run.failed` (failure_reason=usage_filled) |

## Typed fields

All `k=v` fields passed from `tick.sh` are coerced to real JSON types in
`factory.py`:

- ints: `schema_version`, `exit_code`, `duration_ms`, `attempt`,
  `pr_number`, `issue_id`, `tool_calls`, `tool_errors`, `files_changed`,
  `input_tokens`, `output_tokens`, `reasoning_tokens`, `cache_read_tokens`,
  `cache_write_tokens`, `steps`.
- floats: `cost_usd`.
- bools: `dry_run`.
- arrays: `skills_loaded`, `area_labels` (comma-separated or JSON array).

## Telemetry errors

Emission is non-fatal. Failures are counted in `TELEMETRY_ERRORS`, reported
with one warning line to stderr per failure, and surfaced on the final
`tick_end` event as `telemetry_errors` (int).

## Events emitted by tick.sh (authoritative list)

`agent.run.completed`, `agent.run.failed`, `agent.run.started`,
`agent.tool.called`, `build_discovery_error`, `build_selected`,
`claim_conflict`, `container_mode`, `dirty_worktree_skipped_reset`,
`discovery_failed`, `dry_run`, `fix_discovery_error`, `fix_selected`,
`gh_op_failed`, `gh_op_retry`, `git_fetch_failed`, `guardrail_drift`,
`guardrail_ok`, `issue.assigned`, `issue.detected`, `lock_skipped`,
`marker_skip`, `nothing_to_do`, `plan_selected`, `plan_skipped`,
`project_priority_fallback`, `tick_end`, `tick_interrupted`, `tick_result`,
`tick_start`.

This list must stay in sync with `grep -o 'emit_event [a-z_.]*' dev-ops/factory/tick.sh | sort -u`.
