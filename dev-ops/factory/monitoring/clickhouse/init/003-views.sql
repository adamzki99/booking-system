-- Views for dashboards. Use FINAL/argMax to avoid double-counting ReplacingMergeTree duplicates.

CREATE OR REPLACE VIEW factory.runs AS
SELECT
    run_id,
    argMax(factory_id, ts) AS factory_id,
    argMax(tick_id, ts) AS tick_id,
    argMax(kind, ts) AS kind,
    argMax(agent_id, ts) AS agent_id,
    argMax(agent_version, ts) AS agent_version,
    argMax(prompt_version, ts) AS prompt_version,
    argMax(model, ts) AS model,
    argMax(tier_label, ts) AS tier_label,
    argMax(fallback_level, ts) AS fallback_level,
    argMax(attempt, ts) AS attempt,
    argMax(issue_id, ts) AS issue_id,
    argMax(pr_number, ts) AS pr_number,
    argMax(repo, ts) AS repo,
    argMax(session_id, ts) AS session_id,
    argMax(trace_id, ts) AS trace_id,
    minIf(ts, event = 'agent.run.started') AS started_at,
    maxIf(ts, event IN ('agent.run.completed', 'agent.run.failed')) AS ended_at,
    argMaxIf(status, ts, event IN ('agent.run.completed', 'agent.run.failed')) AS outcome,
    argMaxIf(failure_reason, ts, event = 'agent.run.failed') AS failure_reason,
    argMaxIf(duration_ms, ts, event IN ('agent.run.completed', 'agent.run.failed')) AS duration_ms,
    argMaxIf(input_tokens, ts, event IN ('agent.run.completed', 'agent.run.failed')) AS input_tokens,
    argMaxIf(output_tokens, ts, event IN ('agent.run.completed', 'agent.run.failed')) AS output_tokens,
    argMaxIf(reasoning_tokens, ts, event IN ('agent.run.completed', 'agent.run.failed')) AS reasoning_tokens,
    argMaxIf(cache_read_tokens, ts, event IN ('agent.run.completed', 'agent.run.failed')) AS cache_read_tokens,
    argMaxIf(cache_write_tokens, ts, event IN ('agent.run.completed', 'agent.run.failed')) AS cache_write_tokens,
    argMaxIf(cost_usd, ts, event IN ('agent.run.completed', 'agent.run.failed')) AS cost_usd,
    argMaxIf(tool_calls, ts, event IN ('agent.run.completed', 'agent.run.failed')) AS tool_calls,
    argMaxIf(tool_errors, ts, event IN ('agent.run.completed', 'agent.run.failed')) AS tool_errors,
    argMaxIf(files_changed, ts, event IN ('agent.run.completed', 'agent.run.failed')) AS files_changed,
    argMaxIf(exit_code, ts, event IN ('agent.run.completed', 'agent.run.failed')) AS exit_code,
    argMaxIf(error_fingerprint, ts, event = 'agent.run.failed') AS error_fingerprint
FROM factory.events FINAL
WHERE run_id != '' AND event IN ('agent.run.started', 'agent.run.completed', 'agent.run.failed')
GROUP BY run_id;

CREATE OR REPLACE VIEW factory.issues AS
WITH
    issue_runs AS (
        SELECT
            issue_id,
            min(started_at) AS first_run_at,
            count() AS runs_count,
            countIf(kind = 'fix') AS fix_runs,
            sumIf(coalesce(cost_usd, toDecimal64(0, 6)), outcome IN ('completed', 'failed')) AS total_cost_usd,
            sumIf(coalesce(input_tokens, 0) + coalesce(output_tokens, 0) + coalesce(reasoning_tokens, 0) + coalesce(cache_read_tokens, 0) + coalesce(cache_write_tokens, 0), outcome IN ('completed', 'failed')) AS total_tokens,
            argMaxIf(pr_number, started_at, pr_number IS NOT NULL) AS last_pr_number
        FROM factory.runs
        WHERE issue_id IS NOT NULL
        GROUP BY issue_id
    ),
    issue_events AS (
        SELECT
            issue_id,
            minIf(ts, event = 'issue.detected') AS first_seen_at,
            minIf(ts, event = 'issue.approved') AS approved_at,
            maxIf(ts, event = 'issue.closed') AS closed_at,
            maxIf(ts, event = 'issue.reopened') AS reopened_at
        FROM factory.events FINAL
        WHERE issue_id IS NOT NULL AND event IN ('issue.detected', 'issue.approved', 'issue.closed', 'issue.reopened')
        GROUP BY issue_id
    ),
    pr_events AS (
        SELECT
            issue_id,
            argMaxIf(pr_number, ts, event IN ('pr.created', 'pr.merged', 'pr.closed') AND pr_number IS NOT NULL) AS pr_number,
            maxIf(ts, event = 'pr.merged') AS merged_at,
            maxIf(ts, event = 'pr.closed') AS pr_closed_at,
            sumIf(toInt64OrNull(attrs['human_commits']), event = 'pr.merged') AS human_commits
        FROM factory.events FINAL
        WHERE issue_id IS NOT NULL
        GROUP BY issue_id
    )
SELECT
    r.issue_id AS issue_id,
    e.first_seen_at AS first_seen_at,
    e.approved_at AS approved_at,
    r.first_run_at AS first_run_at,
    r.runs_count AS runs_count,
    r.fix_runs AS fix_runs,
    r.total_cost_usd AS total_cost_usd,
    r.total_tokens AS total_tokens,
    coalesce(p.pr_number, r.last_pr_number) AS pr_number,
    p.merged_at AS merged_at,
    e.closed_at AS closed_at,
    multiIf(
        p.merged_at IS NOT NULL AND p.merged_at > toDateTime64('1970-01-01 00:00:00', 3, 'UTC'), 'completed',
        p.pr_closed_at IS NOT NULL AND p.pr_closed_at > toDateTime64('1970-01-01 00:00:00', 3, 'UTC') AND (p.merged_at IS NULL OR p.merged_at = toDateTime64('1970-01-01 00:00:00', 3, 'UTC')), 'abandoned',
        e.closed_at IS NOT NULL AND e.closed_at > toDateTime64('1970-01-01 00:00:00', 3, 'UTC') AND (p.merged_at IS NULL OR p.merged_at = toDateTime64('1970-01-01 00:00:00', 3, 'UTC')), 'abandoned',
        r.runs_count > 0 AND r.fix_runs = r.runs_count AND (p.merged_at IS NULL OR p.merged_at = toDateTime64('1970-01-01 00:00:00', 3, 'UTC')), 'failed',
        r.runs_count > 0, 'in_progress',
        'unknown'
    ) AS state,
    dateDiff('second', coalesce(e.approved_at, r.first_run_at), p.merged_at) AS lead_time_seconds,
    r.fix_runs = 0 AND p.merged_at IS NOT NULL AND p.merged_at > toDateTime64('1970-01-01 00:00:00', 3, 'UTC') AS first_pass,
    coalesce(p.human_commits, 0) > 0 AS human_intervention
FROM issue_runs r
LEFT JOIN issue_events e ON e.issue_id = r.issue_id
LEFT JOIN pr_events p ON p.issue_id = r.issue_id;

CREATE OR REPLACE VIEW factory.daily AS
SELECT
    toDate(started_at) AS day,
    factory_id,
    agent_id,
    model,
    count() AS runs,
    countIf(outcome = 'completed') AS successes,
    countIf(outcome = 'failed') AS failures,
    uniqExactIf(issue_id, outcome = 'completed' AND kind = 'build') AS merged_prs_proxy,
    sum(coalesce(cost_usd, toDecimal64(0, 6))) AS cost_usd,
    sum(coalesce(input_tokens, 0) + coalesce(output_tokens, 0) + coalesce(reasoning_tokens, 0) + coalesce(cache_read_tokens, 0) + coalesce(cache_write_tokens, 0)) AS tokens,
    sum(coalesce(duration_ms, 0)) / 3600000 AS run_hours
FROM factory.runs
WHERE started_at IS NOT NULL
GROUP BY day, factory_id, agent_id, model;

CREATE OR REPLACE VIEW factory.stuck_runs AS
SELECT
    r.run_id,
    r.factory_id,
    r.tick_id,
    r.kind,
    r.agent_id,
    r.model,
    r.issue_id,
    r.pr_number,
    r.session_id,
    r.trace_id,
    r.started_at,
    dateDiff('second', r.started_at, now64(3, 'UTC')) AS age_seconds
FROM factory.runs r
WHERE r.started_at IS NOT NULL
  AND (r.ended_at IS NULL OR r.ended_at = toDateTime64('1970-01-01 00:00:00', 3, 'UTC'))
  AND dateDiff('second', r.started_at, now64(3, 'UTC')) > 3900;
