-- Dashboard and alert support views. Idempotent (CREATE OR REPLACE VIEW).
-- All dashboard queries must still filter by time to stay cheap.

-- Latest queue snapshot per factory.
CREATE OR REPLACE VIEW factory.queue_latest AS
SELECT
    factory_id,
    infant,
    planned,
    approved_waiting,
    in_pr,
    blocked_pr,
    needs_info,
    fromUnixTimestamp64Milli(ts_ms, 'UTC') AS ts
FROM (
    SELECT
        factory_id,
        argMax(toInt64OrNull(attrs['infant']), ts) AS infant,
        argMax(toInt64OrNull(attrs['planned']), ts) AS planned,
        argMax(toInt64OrNull(attrs['approved_waiting']), ts) AS approved_waiting,
        argMax(toInt64OrNull(attrs['in_pr']), ts) AS in_pr,
        argMax(toInt64OrNull(attrs['blocked_pr']), ts) AS blocked_pr,
        argMax(toInt64OrNull(attrs['needs_info']), ts) AS needs_info,
        argMax(toUnixTimestamp64Milli(ts), toUnixTimestamp64Milli(ts)) AS ts_ms
    FROM factory.events FINAL
    WHERE event = 'factory.queue'
    GROUP BY factory_id
);

-- Pull request outcomes (one row per PR, deduped).
CREATE OR REPLACE VIEW factory.pr_outcomes AS
SELECT
    repo,
    pr_number,
    argMax(issue_id, ts) AS issue_id,
    minIf(ts, event = 'pr.created') AS created_at,
    maxIf(ts, event = 'pr.merged') AS merged_at,
    maxIf(ts, event = 'pr.closed') AS closed_at,
    argMaxIf(toInt64OrNull(attrs['commits']), ts, event = 'pr.merged') AS commits,
    argMaxIf(toInt64OrNull(attrs['additions']), ts, event = 'pr.merged') AS additions,
    argMaxIf(toInt64OrNull(attrs['deletions']), ts, event = 'pr.merged') AS deletions,
    argMaxIf(toInt64OrNull(attrs['changed_files']), ts, event = 'pr.merged') AS changed_files,
    argMaxIf(toInt64OrNull(attrs['review_comments']), ts, event = 'pr.merged') AS review_comments,
    argMaxIf(toInt64OrNull(attrs['human_commits']), ts, event = 'pr.merged') AS human_commits,
    countIf(event = 'pr.review' AND attrs['state'] = 'approved') AS approvals,
    countIf(event = 'pr.review' AND attrs['state'] = 'changes_requested') AS changes_requested,
    countIf(event = 'pr.review' AND attrs['state'] = 'commented') AS review_comments_events,
    argMaxIf(attrs['conclusion'], ts, event = 'pr.checks') AS last_checks_conclusion,
    argMaxIf(attrs['failed_checks'], ts, event = 'pr.checks') AS last_failed_checks
FROM factory.events FINAL
WHERE pr_number IS NOT NULL
  AND event IN ('pr.created', 'pr.merged', 'pr.closed', 'pr.review', 'pr.checks')
GROUP BY repo, pr_number;

-- Tool call stats from agent.tool.called events.
CREATE OR REPLACE VIEW factory.tool_calls AS
SELECT
    factory_id,
    tick_id,
    run_id,
    agent_id,
    model,
    kind,
    ts,
    ifNull(attrs['tool'], '') AS tool,
    ifNull(attrs['status'], '') AS status,
    toInt64OrNull(attrs['duration_ms']) AS duration_ms,
    ifNull(attrs['skill_name'], '') AS skill_name,
    attrs
FROM factory.events FINAL
WHERE event = 'agent.tool.called';

-- Latest tick status per factory (for "factory silent" / telemetry health).
CREATE OR REPLACE VIEW factory.tick_status AS
SELECT
    factory_id,
    maxIf(ts, event = 'tick_start') AS last_tick_start_at,
    maxIf(ts, event = 'tick_end') AS last_tick_end_at,
    argMaxIf(toInt64OrNull(attrs['telemetry_errors']), ts, event = 'tick_end') AS last_telemetry_errors,
    argMaxIf(exit_code, ts, event = 'tick_end') AS last_tick_exit_code,
    maxIf(ts, event = 'tick_end' AND (exit_code = 0 OR exit_code IS NULL)) AS last_successful_tick_at
FROM factory.events FINAL
WHERE event IN ('tick_start', 'tick_end')
GROUP BY factory_id;
