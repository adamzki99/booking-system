#!/usr/bin/env python3
"""Generate Grafana-managed alert provisioning files for the product monitoring stack.

Thresholds and the contact point come from environment variables with defaults
matching product/monitoring/.env.example. Run from repo root or any directory;
output paths are relative to this script.

Usage:
  python3 product/monitoring/scripts/generate_alert_rules.py
  ALERT_HIGH_ERROR_RATE_PERCENT=5 python3 .../generate_alert_rules.py
"""
from __future__ import annotations

import os
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
ALERTING = ROOT / "grafana" / "provisioning" / "alerting"


def env(name: str, default: str) -> str:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return value


def env_float(name: str, default: str) -> float:
    return float(env(name, default))


def env_int(name: str, default: str) -> int:
    return int(float(env(name, default)))


def prom_expr_datasource(uid: str = "prometheus-product") -> dict:
    return {"type": "prometheus", "uid": uid}


def ch_datasource(uid: str = "clickhouse-product") -> dict:
    return {"type": "grafana-clickhouse-datasource", "uid": uid}


def expr_datasource() -> dict:
    return {"type": "__expr__", "uid": "__expr__"}


def static_rule(
    *,
    uid: str,
    title: str,
    expr: str,
    threshold: float,
    op: str,
    for_duration: str,
    summary: str,
    description: str,
    no_data_state: str = "NoData",
    exec_err_state: str = "Error",
    datasource_uid: str = "prometheus-product",
    datasource_type: str = "prometheus",
    query_type: str = "prometheus",
    extra_model: dict | None = None,
) -> dict:
    model = {
        "datasource": {"type": datasource_type, "uid": datasource_uid},
        "editorMode": "code",
        "expr": expr if query_type == "prometheus" else None,
        "instant": True,
        "intervalMs": 1000,
        "maxDataPoints": 43200,
        "range": False,
        "refId": "A",
    }
    if query_type == "clickhouse":
        model.pop("expr", None)
        model.update(
            {
                "editorType": "sql",
                "format": 1,
                "pluginVersion": "4.23.5",
                "queryType": "table",
                "rawSql": expr,
            }
        )
    if extra_model:
        model.update(extra_model)
    # Remove None values
    model = {k: v for k, v in model.items() if v is not None}

    return {
        "uid": uid,
        "title": title,
        "condition": "C",
        "data": [
            {
                "refId": "A",
                "relativeTimeRange": {"from": 600, "to": 0},
                "datasourceUid": datasource_uid,
                "model": model,
            },
            {
                "refId": "B",
                "relativeTimeRange": {"from": 0, "to": 0},
                "datasourceUid": "__expr__",
                "model": {
                    "conditions": [
                        {
                            "evaluator": {"params": [0], "type": "gt"},
                            "operator": {"type": "and"},
                            "query": {"params": ["A"]},
                            "reducer": {"params": [], "type": "last"},
                            "type": "query",
                        }
                    ],
                    "datasource": expr_datasource(),
                    "expression": "A",
                    "intervalMs": 1000,
                    "maxDataPoints": 43200,
                    "reducer": "last",
                    "refId": "B",
                    "type": "reduce",
                },
            },
            {
                "refId": "C",
                "relativeTimeRange": {"from": 0, "to": 0},
                "datasourceUid": "__expr__",
                "model": {
                    "conditions": [
                        {
                            "evaluator": {"params": [threshold], "type": op},
                            "operator": {"type": "and"},
                            "query": {"params": ["B"]},
                            "reducer": {"params": [], "type": "last"},
                            "type": "query",
                        }
                    ],
                    "datasource": expr_datasource(),
                    "expression": "B",
                    "intervalMs": 1000,
                    "maxDataPoints": 43200,
                    "refId": "C",
                    "type": "threshold",
                },
            },
        ],
        "noDataState": no_data_state,
        "execErrState": exec_err_state,
        "for": for_duration,
        "annotations": {
            "summary": summary,
            "description": description,
        },
        "labels": {
            "project": "{{ $labels.project }}",
            "deployment_environment": "{{ $labels.deployment_environment }}",
        },
        "isPaused": False,
    }

def build_rules() -> dict:
    silent_minutes = env_int("ALERT_BACKEND_SILENT_MINUTES", "10")
    error_rate_pct = env_float("ALERT_HIGH_ERROR_RATE_PERCENT", "2")
    error_rate_min_requests = env_int("ALERT_HIGH_ERROR_RATE_MIN_REQUESTS", "20")
    latency_seconds = env_float("ALERT_HIGH_LATENCY_SECONDS", "1")
    projection_lag = env_int("ALERT_PROJECTION_LAG_THRESHOLD", "100")
    notification_pending = env_int("ALERT_NOTIFICATION_PENDING_THRESHOLD", "50")
    notification_pending_minutes = env_int("ALERT_NOTIFICATION_PENDING_MINUTES", "30")
    sidecar_error_rate_pct = env_float("ALERT_SIDECAR_ERROR_RATE_PERCENT", "5")
    telemetry_dropped_minutes = env_int("ALERT_TELEMETRY_DROPPED_MINUTES", "10")
    disk_pct = env_float("ALERT_DISK_USAGE_PERCENT", "85")

    rules = []

    rules.append(
        static_rule(
            uid="product-backend-silent",
            title="Backend silent",
            expr=(
                f"(time() - max by (project, deployment_environment) ("
                f"max_over_time(timestamp("
                f'sum by (project, deployment_environment) (rate({{__name__=~"http_server_request_duration_seconds_count|http_server_duration_milliseconds_count|http_server_requests_total|commands_handled_total"}}[5m]))'
                f")[{max(silent_minutes, 15)}m:]))) > {silent_minutes * 60} "
                f"and on (project, deployment_environment) "
                f"(max by (project, deployment_environment) (max_over_time(timestamp("
                f'sum by (project, deployment_environment) (rate({{__name__=~"http_server_request_duration_seconds_count|http_server_duration_milliseconds_count|http_server_requests_total|commands_handled_total"}}[5m]))'
                f")[24h:]))) > 0"
            ),
            threshold=0.5,
            op="gt",
            for_duration=f"{silent_minutes}m",
            summary="No telemetry from booking backend for an active deployment environment.",
            description=(
                f"No backend telemetry received for more than {silent_minutes} minutes in an environment that reported in the last 24h. "
                "Likely causes: backend crashed, OTLP endpoint misconfigured, collector down, or network/DNS issue. "
                "First checks: check backend container logs/health, verify OTEL_EXPORTER_OTLP_ENDPOINT, check otel-collector health and refused/dropped metrics, confirm Prometheus has recent samples for commands_handled_total or HTTP metrics."
            ),
            no_data_state="OK",
        )
    )

    rules.append(
        static_rule(
            uid="product-high-error-rate",
            title="High error rate",
            expr=(
                f"(sum by (project, deployment_environment) (rate({{__name__=~\"http_server_request_duration_seconds_count|http_server_duration_milliseconds_count\",http_response_status_code=~\"5..\"}}[5m])) "
                f"/ clamp_min(sum by (project, deployment_environment) (rate({{__name__=~\"http_server_request_duration_seconds_count|http_server_duration_milliseconds_count\"}}[5m])), 1e-9)) * 100 > {error_rate_pct} "
                f"and sum by (project, deployment_environment) (increase({{__name__=~\"http_server_request_duration_seconds_count|http_server_duration_milliseconds_count\"}}[10m])) >= {error_rate_min_requests}"
            ),
            threshold=0.5,
            op="gt",
            for_duration="10m",
            summary=f"Backend 5xx error rate above {error_rate_pct}% for 10 minutes.",
            description=(
                f"5xx responses are above {error_rate_pct}% over 10 minutes with at least {error_rate_min_requests} requests. "
                "Likely causes: recent deploy regression, database/projection failure, sidecar outage causing 5xx, or panic. "
                "First checks: inspect Traces and logs dashboard for error traces, check backend logs by trace_id, compare with deploy markers, check projection.errors and DB health."
            ),
            no_data_state="OK",
        )
    )

    rules.append(
        static_rule(
            uid="product-high-latency",
            title="High latency",
            expr=(
                f"histogram_quantile(0.95, sum by (le, project, deployment_environment) (rate({{__name__=~\"http_server_request_duration_seconds_bucket|http_server_duration_milliseconds_bucket\"}}[5m]))) "
                f"> {latency_seconds}"
            ),
            threshold=0.5,
            op="gt",
            for_duration="10m",
            summary=f"Backend p95 latency above {latency_seconds}s for 10 minutes.",
            description=(
                f"HTTP p95 latency is above {latency_seconds}s for 10 minutes. "
                "Likely causes: slow DB queries, projection lock contention, sidecar latency, GC pressure, or host resource contention. "
                "First checks: inspect slow routes in Service overview, check DB span latency and pgx pool stats, check sidecar duration, inspect Go runtime/GC metrics and host memory."
            ),
            no_data_state="OK",
        )
    )

    rules.append(
        static_rule(
            uid="product-projection-lag",
            title="Projection lag or errors",
            expr=(
                f"max by (project, deployment_environment) (projection_lag) > {projection_lag} "
                f"or sum by (project, deployment_environment) (increase(projection_errors_total[10m])) > 0"
            ),
            threshold=0.5,
            op="gt",
            for_duration="5m",
            summary="Projection lag is above threshold or projection errors occurred.",
            description=(
                f"Projection lag is above {projection_lag} events for 5 minutes, or projection errors increased. "
                "Likely causes: projection handler bug, bad event shape, DB write failure, or long-running projection blocking checkpoint. "
                "First checks: inspect projection.errors and projection.lag by projection name, check backend logs for projection apply/checkpoint errors, verify event store head and projection checkpoints, determine if projection is rebuildable before taking action."
            ),
            no_data_state="OK",
        )
    )

    rules.append(
        static_rule(
            uid="product-notifications-failing",
            title="Notifications failing",
            expr=(
                f"sum by (project, deployment_environment) (increase(notifications_failed_total[15m])) > 0 "
                f"or max by (project, deployment_environment) (notifications_pending) > {notification_pending}"
            ),
            threshold=0.5,
            op="gt",
            for_duration=f"{notification_pending_minutes}m",
            summary="Notification outbox failures or pending backlog detected.",
            description=(
                f"notifications.failed increased, or notifications.pending is above {notification_pending} for {notification_pending_minutes} minutes. "
                "Likely causes: SMTP outage/misconfiguration, invalid recipient handling, persistent outbox delivery errors, or worker stalled. "
                "First checks: inspect notifications.enqueued/sent/retried/failed/pending metrics, check backend logs for SMTP/outbox errors, verify SMTP connectivity and credentials, inspect outbox rows in the database with read-only access."
            ),
            no_data_state="OK",
        )
    )

    rules.append(
        static_rule(
            uid="product-sidecar-failing",
            title="Sidecar failing",
            expr=(
                f"(sum by (project, deployment_environment) (rate(sidecar_requests_total{{result=~\"unavailable|error\"}}[5m])) "
                f"/ clamp_min(sum by (project, deployment_environment) (rate(sidecar_requests_total[5m])), 1e-9)) * 100 > {sidecar_error_rate_pct}"
            ),
            threshold=0.5,
            op="gt",
            for_duration="10m",
            summary=f"Sidecar error rate above {sidecar_error_rate_pct}% for 10 minutes.",
            description=(
                f"Sidecar requests are failing above {sidecar_error_rate_pct}% for 10 minutes. The sidecar fails open, so booking behavior may be degraded or permissive depending on rules. "
                "Likely causes: sidecar crash, network issue, bad sidecar response, or deployment mismatch. "
                "First checks: check sidecar logs/health, inspect sidecar.requests and sidecar.duration by endpoint/result, verify booking-stack to sidecar connectivity, confirm recent deploys."
            ),
            no_data_state="OK",
        )
    )

    rules.append(
        static_rule(
            uid="product-telemetry-pipeline",
            title="Telemetry pipeline degraded",
            expr=(
                f"sum by (project) (rate(otelcol_exporter_send_failed_spans{{job=\"otel-collector\"}}[5m])) > 0 "
                f"or sum by (project) (rate(otelcol_exporter_send_failed_log_records{{job=\"otel-collector\"}}[5m])) > 0 "
                f"or sum by (project) (rate(otelcol_exporter_send_failed_metric_points{{job=\"otel-collector\"}}[5m])) > 0 "
                f"or sum by (project) (rate(otelcol_processor_refused_spans{{job=\"otel-collector\"}}[5m])) > 0 "
                f"or sum by (project) (rate(otelcol_processor_refused_metric_points{{job=\"otel-collector\"}}[5m])) > 0 "
                f"or sum by (project) (rate(otelcol_processor_refused_log_records{{job=\"otel-collector\"}}[5m])) > 0"
            ),
            threshold=0.5,
            op="gt",
            for_duration=f"{telemetry_dropped_minutes}m",
            summary="OTel collector is refusing or failing to export telemetry.",
            description=(
                f"Collector refused or failed exports above zero for {telemetry_dropped_minutes} minutes. "
                "Likely causes: ClickHouse/Prometheus unavailable, collector memory limiter pressure, schema/export errors, or network issues. "
                "First checks: inspect otel-collector logs, check collector health endpoint, review refused/dropped/send_failed metrics, check ClickHouse and Prometheus health and disk."
            ),
            no_data_state="OK",
        )
    )

    rules.append(
        static_rule(
            uid="product-disk-retention",
            title="Disk / retention pressure",
            expr=(
                f"max(100 * (1 - node_filesystem_avail_bytes{{fstype!~\"tmpfs|overlay|squashfs\",mountpoint=\"/\"}} / node_filesystem_size_bytes{{fstype!~\"tmpfs|overlay|squashfs\",mountpoint=\"/\"}})) > {disk_pct} "
                f"or max(clickhouse_disk_used_bytes / clamp_min(clickhouse_disk_total_bytes, 1)) * 100 > {disk_pct}"
            ),
            threshold=0.5,
            op="gt",
            for_duration="15m",
            summary="Disk usage above retention safety threshold.",
            description=(
                f"Disk usage is above {disk_pct}% where measurable. "
                "Likely causes: ClickHouse data growth, Prometheus TSDB growth, container logs, or insufficient retention. "
                "First checks: inspect ClickHouse and Prometheus volume sizes, verify TTL/retention settings, check node-exporter filesystem metrics, reduce retention or move monitoring to a larger disk before outage."
            ),
            no_data_state="OK",
        )
    )

    return {
        "apiVersion": 1,
        "groups": [
            {
                "orgId": 1,
                "name": "product-alerts",
                "folder": "Product",
                "interval": "1m",
                "rules": rules,
            }
        ],
    }

def build_contact_points() -> dict:
    url = env("ALERT_CONTACT_POINT_URL", "http://127.0.0.1:1/product-monitoring-alert")
    return {
        "apiVersion": 1,
        "contactPoints": [
            {
                "orgId": 1,
                "name": "product-monitoring-default",
                "receivers": [
                    {
                        "uid": "product-monitoring-webhook",
                        "type": "webhook",
                        "disableResolveMessage": False,
                        "settings": {
                            "url": url,
                            "httpMethod": "POST",
                        },
                    }
                ],
            }
        ],
    }


def build_policies() -> dict:
    return {
        "apiVersion": 1,
        "policies": [
            {
                "orgId": 1,
                "receiver": "product-monitoring-default",
                "group_by": ["alertname", "project", "deployment_environment"],
                "group_wait": "30s",
                "group_interval": "5m",
                "repeat_interval": "4h",
                "routes": [],
            }
        ],
    }


def dump_yaml(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=False, width=120), encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT.parent.parent)}")


def main() -> None:
    dump_yaml(ALERTING / "rules.yaml", build_rules())
    dump_yaml(ALERTING / "contact-points.yaml", build_contact_points())
    dump_yaml(ALERTING / "policies.yaml", build_policies())


if __name__ == "__main__":
    main()
