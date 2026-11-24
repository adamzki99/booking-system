CREATE TABLE IF NOT EXISTS factory.events
(
    event_id String,
    event LowCardinality(String),
    ts DateTime64(3, 'UTC'),
    observed_at Nullable(DateTime64(3, 'UTC')),
    schema_version UInt16,
    factory_id LowCardinality(String),
    tick_id String,
    run_id String,
    session_id String,
    trace_id String,
    repo LowCardinality(String),
    issue_id Nullable(Int64),
    pr_number Nullable(Int64),
    agent_id LowCardinality(String),
    agent_version LowCardinality(String),
    prompt_version LowCardinality(String),
    model LowCardinality(String),
    kind LowCardinality(String),
    fallback_level LowCardinality(String),
    attempt Nullable(Int32),
    status LowCardinality(String),
    failure_reason LowCardinality(String),
    duration_ms Nullable(Int64),
    input_tokens Nullable(Int64),
    output_tokens Nullable(Int64),
    reasoning_tokens Nullable(Int64),
    cache_read_tokens Nullable(Int64),
    cache_write_tokens Nullable(Int64),
    cost_usd Nullable(Decimal(18, 6)),
    tool_calls Nullable(Int64),
    tool_errors Nullable(Int64),
    files_changed Nullable(Int64),
    exit_code Nullable(Int32),
    error_fingerprint String,
    tier_label LowCardinality(String),
    dry_run UInt8,
    on_usage_filled LowCardinality(String),
    deployment_environment LowCardinality(String),
    host_name LowCardinality(String),
    service_name LowCardinality(String),
    attrs Map(String, String)
)
ENGINE = ReplacingMergeTree(ts)
PARTITION BY toYYYYMM(ts)
ORDER BY (event_id)
TTL toDateTime(ts) + INTERVAL __CLICKHOUSE_TTL_DAYS__ DAY
SETTINGS index_granularity = 8192;

-- Materialized view: parse typed factory events from otel_logs attributes.
-- The otel collector json_parser puts JSON fields into LogAttributes.
DROP VIEW IF EXISTS factory.events_mv;
CREATE MATERIALIZED VIEW factory.events_mv TO factory.events AS
SELECT
    ifNull(LogAttributes['event_id'], '') AS event_id,
    ifNull(LogAttributes['event'], '') AS event,
    coalesce(parseDateTime64BestEffortOrNull(ifNull(LogAttributes['ts'], ''), 3, 'UTC'), toDateTime64(Timestamp, 3, 'UTC')) AS ts,
    parseDateTime64BestEffortOrNull(ifNull(LogAttributes['observed_at'], ''), 3, 'UTC') AS observed_at,
    toUInt16OrZero(ifNull(LogAttributes['schema_version'], '0')) AS schema_version,
    ifNull(ResourceAttributes['factory_id'], ifNull(LogAttributes['factory_id'], '')) AS factory_id,
    ifNull(LogAttributes['tick_id'], '') AS tick_id,
    ifNull(LogAttributes['run_id'], '') AS run_id,
    ifNull(LogAttributes['session_id'], '') AS session_id,
    ifNull(LogAttributes['trace_id'], '') AS trace_id,
    ifNull(LogAttributes['repo'], '') AS repo,
    toInt64OrNull(ifNull(LogAttributes['issue_id'], '')) AS issue_id,
    toInt64OrNull(ifNull(LogAttributes['pr_number'], '')) AS pr_number,
    ifNull(LogAttributes['agent_id'], '') AS agent_id,
    ifNull(LogAttributes['agent_version'], '') AS agent_version,
    ifNull(LogAttributes['prompt_version'], '') AS prompt_version,
    ifNull(LogAttributes['model'], '') AS model,
    ifNull(LogAttributes['kind'], '') AS kind,
    ifNull(LogAttributes['fallback_level'], '') AS fallback_level,
    toInt32OrNull(ifNull(LogAttributes['attempt'], '')) AS attempt,
    multiIf(
        event = 'agent.run.completed', 'completed',
        event = 'agent.run.failed', 'failed',
        event = 'agent.run.started', 'started',
        ''
    ) AS status,
    ifNull(LogAttributes['failure_reason'], '') AS failure_reason,
    toInt64OrNull(ifNull(LogAttributes['duration_ms'], '')) AS duration_ms,
    toInt64OrNull(ifNull(LogAttributes['input_tokens'], '')) AS input_tokens,
    toInt64OrNull(ifNull(LogAttributes['output_tokens'], '')) AS output_tokens,
    toInt64OrNull(ifNull(LogAttributes['reasoning_tokens'], '')) AS reasoning_tokens,
    toInt64OrNull(ifNull(LogAttributes['cache_read_tokens'], '')) AS cache_read_tokens,
    toInt64OrNull(ifNull(LogAttributes['cache_write_tokens'], '')) AS cache_write_tokens,
    toDecimal64OrNull(ifNull(LogAttributes['cost_usd'], ''), 6) AS cost_usd,
    toInt64OrNull(ifNull(LogAttributes['tool_calls'], '')) AS tool_calls,
    toInt64OrNull(ifNull(LogAttributes['tool_errors'], '')) AS tool_errors,
    toInt64OrNull(ifNull(LogAttributes['files_changed'], '')) AS files_changed,
    toInt32OrNull(ifNull(LogAttributes['exit_code'], '')) AS exit_code,
    ifNull(LogAttributes['error_fingerprint'], '') AS error_fingerprint,
    ifNull(LogAttributes['tier_label'], '') AS tier_label,
    if(lower(ifNull(LogAttributes['dry_run'], 'false')) IN ('1','true','yes','on'), 1, 0) AS dry_run,
    ifNull(LogAttributes['on_usage_filled'], '') AS on_usage_filled,
    ifNull(ResourceAttributes['deployment.environment'], ifNull(LogAttributes['deployment.environment'], '')) AS deployment_environment,
    ifNull(ResourceAttributes['host.name'], ifNull(LogAttributes['host.name'], '')) AS host_name,
    ifNull(ResourceAttributes['service.name'], ifNull(LogAttributes['service.name'], '')) AS service_name,
    mapFilter((k, v) -> k NOT IN (
        'event_id','event','ts','observed_at','schema_version','factory_id','tick_id','run_id',
        'session_id','trace_id','repo','issue_id','pr_number','agent_id','agent_version',
        'prompt_version','model','kind','fallback_level','attempt','failure_reason','duration_ms',
        'input_tokens','output_tokens','reasoning_tokens','cache_read_tokens','cache_write_tokens',
        'cost_usd','tool_calls','tool_errors','files_changed','exit_code','error_fingerprint','tier_label','dry_run','on_usage_filled',
        'deployment.environment','host.name','service.name'
    ), LogAttributes) AS attrs
FROM otel.otel_logs
WHERE ifNull(LogAttributes['event_id'], '') != '';
