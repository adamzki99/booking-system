#!/usr/bin/env python3
"""Generate generic product Grafana dashboards.

Outputs JSON files into product/monitoring/grafana/dashboards/.
Run: python3 product/monitoring/scripts/generate_dashboards.py
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "grafana" / "dashboards"
PROM = {"type": "prometheus", "uid": "prometheus-product"}
CH = {"type": "grafana-clickhouse-datasource", "uid": "clickhouse-product"}


def var_query(name: str, label: str, query: str, ds=PROM, multi=True, include_all=True) -> dict:
    return {
        "current": {"selected": True, "text": "All" if include_all else "", "value": "$__all" if include_all else ""},
        "datasource": ds,
        "definition": query,
        "hide": 0,
        "includeAll": include_all,
        "label": label,
        "multi": multi,
        "name": name,
        "options": [],
        "query": {"query": query, "refId": "Var"},
        "refresh": 2,
        "regex": "",
        "sort": 1,
        "type": "query",
    }


def variables() -> list[dict]:
    return [
        var_query("deployment_environment", "Deployment environment", "label_values({__name__=~\".+\"}, deployment_environment)"),
        var_query("service_name", "Service", "label_values({__name__=~\".+\", deployment_environment=~\"$deployment_environment\"}, service_name)"),
        var_query("service_version", "Version", "label_values({__name__=~\".+\", deployment_environment=~\"$deployment_environment\", service_name=~\"$service_name\"}, service_version)"),
    ]


def base_dashboard(*, uid: str, title: str, description: str, panels: list[dict], tags: list[str]) -> dict:
    return {
        "annotations": {
            "list": [
                {
                    "builtIn": 1,
                    "datasource": {"type": "grafana", "uid": "-- Grafana --"},
                    "enable": True,
                    "hide": True,
                    "iconColor": "rgba(0, 211, 255, 1)",
                    "name": "Annotations & Alerts",
                    "type": "dashboard",
                },
                {
                    "datasource": PROM,
                    "enable": True,
                    "expr": "changes(process_start_time_seconds{deployment_environment=~\"$deployment_environment\",service_name=~\"$service_name\"}[5m]) > 0",
                    "hide": False,
                    "iconColor": "orange",
                    "name": "Deploy / restart markers",
                    "titleFormat": "restart {{service_name}} {{service_version}}",
                },
            ]
        },
        "editable": False,
        "fiscalYearStartMonth": 0,
        "graphTooltip": 1,
        "links": [],
        "panels": panels,
        "refresh": "30s",
        "schemaVersion": 39,
        "tags": tags,
        "templating": {"list": variables()},
        "time": {"from": "now-6h", "to": "now"},
        "timepicker": {},
        "timezone": "browser",
        "title": title,
        "uid": uid,
        "version": 1,
        "description": description,
    }


def stat_panel(title, expr, gridPos, ds=PROM, unit="short", thresholds=None, desc=""):
    return {
        "datasource": ds,
        "description": desc,
        "fieldConfig": {
            "defaults": {
                "unit": unit,
                "thresholds": thresholds or {"mode": "absolute", "steps": [{"color": "green", "value": None}]},
            },
            "overrides": [],
        },
        "gridPos": gridPos,
        "id": 0,
        "options": {"colorMode": "value", "graphMode": "area", "justifyMode": "auto", "orientation": "auto", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}, "textMode": "auto"},
        "targets": [{"datasource": ds, "editorMode": "code", "expr": expr, "instant": True, "refId": "A"}],
        "title": title,
        "type": "stat",
    }


def ts_panel(title, targets, gridPos, ds=PROM, unit="short", desc="", legend="table"):
    return {
        "datasource": ds,
        "description": desc,
        "fieldConfig": {"defaults": {"unit": unit, "custom": {"drawStyle": "line", "lineInterpolation": "linear", "lineWidth": 1, "fillOpacity": 10, "showPoints": "never", "spanNulls": False}}, "overrides": []},
        "gridPos": gridPos,
        "id": 0,
        "options": {"legend": {"calcs": ["lastNotNull", "max"], "displayMode": legend, "placement": "bottom"}, "tooltip": {"mode": "multi", "sort": "desc"}},
        "targets": targets,
        "title": title,
        "type": "timeseries",
    }


def table_panel(title, targets, gridPos, ds=PROM, desc=""):
    return {
        "datasource": ds,
        "description": desc,
        "fieldConfig": {"defaults": {"custom": {"align": "auto"}}, "overrides": []},
        "gridPos": gridPos,
        "id": 0,
        "options": {"showHeader": True, "cellHeight": "sm"},
        "targets": targets,
        "title": title,
        "type": "table",
    }


def prom_target(expr, refId="A", legend="", instant=False, format_="time_series"):
    return {"datasource": PROM, "editorMode": "code", "expr": expr, "legendFormat": legend, "instant": instant, "range": not instant, "refId": refId, "format": format_}


def ch_target(rawSql, refId="A", format_=1):
    return {
        "datasource": CH,
        "editorType": "sql",
        "format": format_,
        "pluginVersion": "4.23.5",
        "queryType": "table",
        "rawSql": rawSql,
        "refId": refId,
    }


def assign_ids(panels):
    for i, p in enumerate(panels, start=1):
        p["id"] = i
    return panels

ENV_FILTER = 'deployment_environment=~"$deployment_environment",service_name=~"$service_name",service_version=~"$service_version"'
ENV_FILTER_NO_VER = 'deployment_environment=~"$deployment_environment",service_name=~"$service_name"'
HTTP_COUNT = 'http_server_request_duration_seconds_count'
HTTP_BUCKET = 'http_server_request_duration_seconds_bucket'


def overview_dashboard():
    panels = assign_ids([
        stat_panel("Request rate", f'sum(rate({HTTP_COUNT}{{{ENV_FILTER},http_route!~"/healthz|/readyz"}}[5m]))', {"h":4,"w":4,"x":0,"y":0}, unit="reqps", desc="HTTP request rate across selected services."),
        stat_panel("Error rate", f'(sum(rate({HTTP_COUNT}{{{ENV_FILTER},http_response_status_code=~"5.."}}[5m])) / clamp_min(sum(rate({HTTP_COUNT}{{{ENV_FILTER}}}[5m])), 1e-9)) * 100', {"h":4,"w":4,"x":4,"y":0}, unit="percent", thresholds={"mode":"absolute","steps":[{"color":"green","value":None},{"color":"yellow","value":1},{"color":"red","value":2}]}, desc="5xx percentage over selected window."),
        stat_panel("P95 latency", f'histogram_quantile(0.95, sum by (le) (rate({HTTP_BUCKET}{{{ENV_FILTER}}}[5m])))', {"h":4,"w":4,"x":8,"y":0}, unit="s", thresholds={"mode":"absolute","steps":[{"color":"green","value":None},{"color":"yellow","value":0.5},{"color":"red","value":1}]}, desc="P95 HTTP server latency."),
        stat_panel("P99 latency", f'histogram_quantile(0.99, sum by (le) (rate({HTTP_BUCKET}{{{ENV_FILTER}}}[5m])))', {"h":4,"w":4,"x":12,"y":0}, unit="s", desc="P99 HTTP server latency."),
        stat_panel("Last telemetry", f'max(max_over_time(timestamp(sum by (service_name) (rate({HTTP_COUNT}{{{ENV_FILTER_NO_VER}}}[5m])))[24h:]))', {"h":4,"w":4,"x":16,"y":0}, unit="dateTimeAsIso", desc="Last time HTTP telemetry was seen for selected services."),
        stat_panel("Uptime / scrape targets up", f'sum(up{{job=~"prometheus|otel-collector|clickhouse|grafana"}})', {"h":4,"w":4,"x":20,"y":0}, unit="short", desc="Monitoring components reporting up."),
        ts_panel("Request rate by route", [prom_target(f'sum by (http_route) (rate({HTTP_COUNT}{{{ENV_FILTER},http_route!~"/healthz|/readyz"}}[5m]))', legend="{{http_route}}")], {"h":8,"w":12,"x":0,"y":4}, unit="reqps", desc="HTTP request rate per route."),
        ts_panel("Latency quantiles", [
            prom_target(f'histogram_quantile(0.50, sum by (le) (rate({HTTP_BUCKET}{{{ENV_FILTER}}}[5m])))', "A", "p50"),
            prom_target(f'histogram_quantile(0.95, sum by (le) (rate({HTTP_BUCKET}{{{ENV_FILTER}}}[5m])))', "B", "p95"),
            prom_target(f'histogram_quantile(0.99, sum by (le) (rate({HTTP_BUCKET}{{{ENV_FILTER}}}[5m])))', "C", "p99"),
        ], {"h":8,"w":12,"x":12,"y":4}, unit="s", desc="HTTP latency quantiles."),
        table_panel("Top slow routes (p95, 30m)", [prom_target(f'topk(10, histogram_quantile(0.95, sum by (le, http_route) (rate({HTTP_BUCKET}{{{ENV_FILTER},http_route!~"/healthz|/readyz"}}[30m]))))', "A", instant=True, format_="table")], {"h":8,"w":12,"x":0,"y":12}, desc="Slowest routes by p95 latency over 30 minutes."),
        table_panel("Top error routes (5xx, 30m)", [prom_target(f'topk(10, sum by (http_route) (increase({HTTP_COUNT}{{{ENV_FILTER},http_response_status_code=~"5.."}}[30m])))', "A", instant=True, format_="table")], {"h":8,"w":12,"x":12,"y":12}, desc="Routes with most 5xx responses over 30 minutes."),
    ])
    return base_dashboard(uid="product-overview", title="Service overview", description="RED metrics, slow/error routes, deploy markers, and telemetry freshness.", panels=panels, tags=["product", "overview"])

def traces_dashboard():
    panels = assign_ids([
        table_panel("Log volume by level (ClickHouse, 1h)", [ch_target(
            """SELECT toStartOfFiveMinutes(Timestamp) AS time, SeverityText, count() AS logs
FROM otel.otel_logs
WHERE Timestamp >= now() - INTERVAL 1 HOUR
GROUP BY time, SeverityText
ORDER BY time ASC
LIMIT 1000""", "A", 1)], {"h":8,"w":12,"x":0,"y":0}, ds=CH, desc="Log volume by severity from ClickHouse."),
        table_panel("Recent error traces (ClickHouse)", [ch_target(
            """SELECT Timestamp, ServiceName, SpanName, round(Duration/1000000,2) AS DurationMs, StatusMessage, TraceId
FROM otel.otel_traces
WHERE Timestamp >= now() - INTERVAL 6 HOUR
  AND StatusCode = 'STATUS_CODE_ERROR'
ORDER BY Timestamp DESC
LIMIT 100""", "A", 1)], {"h":8,"w":12,"x":12,"y":0}, ds=CH, desc="Recent error traces. Open TraceId in Explore for details."),
        table_panel("Trace search (ClickHouse)", [ch_target(
            """SELECT Timestamp, ServiceName, SpanName, round(Duration/1000000,2) AS DurationMs, StatusCode, TraceId
FROM otel.otel_traces
WHERE Timestamp >= now() - INTERVAL 1 HOUR
ORDER BY Timestamp DESC
LIMIT 100""", "A", 1)], {"h":10,"w":24,"x":0,"y":8}, ds=CH, desc="Recent traces. Filter and pivot by TraceId in Grafana Explore."),
        table_panel("Log search with trace links (ClickHouse)", [ch_target(
            """SELECT Timestamp, ServiceName, SeverityText, Body, TraceId, SpanId
FROM otel.otel_logs
WHERE Timestamp >= now() - INTERVAL 1 HOUR
ORDER BY Timestamp DESC
LIMIT 200""", "A", 1)], {"h":10,"w":24,"x":0,"y":18}, ds=CH, desc="Recent logs with TraceId/SpanId for correlation."),
    ])
    return base_dashboard(uid="product-traces", title="Traces and logs", description="Trace and log search backed by ClickHouse OTel tables.", panels=panels, tags=["product", "traces", "logs"])

def event_sourcing_dashboard():
    panels = assign_ids([
        ts_panel("Events appended by type", [prom_target(f'sum by (type) (rate(events_appended_total{{{ENV_FILTER}}}[5m]))', legend="{{type}}")], {"h":8,"w":12,"x":0,"y":0}, unit="ops", desc="Event append rate by event type."),
        ts_panel("Commands handled by outcome", [prom_target(f'sum by (command, outcome) (rate(commands_handled_total{{{ENV_FILTER}}}[5m]))', legend="{{command}} {{outcome}}")], {"h":8,"w":12,"x":12,"y":0}, unit="ops", desc="Command handling rate by command and outcome."),
        ts_panel("Command duration p95", [prom_target(f'histogram_quantile(0.95, sum by (le, command) (rate(commands_duration_seconds_bucket{{{ENV_FILTER}}}[5m])))', legend="{{command}}")], {"h":8,"w":12,"x":0,"y":8}, unit="s", desc="Command handling duration p95."),
        ts_panel("Projection lag by projection", [prom_target(f'max by (projection) (projection_lag{{{ENV_FILTER_NO_VER}}})', legend="{{projection}}")], {"h":8,"w":12,"x":12,"y":8}, unit="short", desc="Projection lag: event store head minus checkpoint."),
        ts_panel("Projection checkpoint by projection", [prom_target(f'max by (projection) (projection_checkpoint{{{ENV_FILTER_NO_VER}}})', legend="{{projection}}")], {"h":8,"w":12,"x":0,"y":16}, unit="short", desc="Last applied event ID per projection."),
        ts_panel("Projection errors", [prom_target(f'sum by (projection) (increase(projection_errors_total{{{ENV_FILTER_NO_VER}}}[15m]))', legend="{{projection}}")], {"h":8,"w":12,"x":12,"y":16}, unit="short", desc="Projection apply/checkpoint errors."),
        ts_panel("DB span latency p95", [prom_target(f'histogram_quantile(0.95, sum by (le) (rate(db_client_operation_duration_seconds_bucket{{{ENV_FILTER}}}[5m])))', legend="p95")], {"h":8,"w":8,"x":0,"y":24}, unit="s", desc="Database/client operation latency from OTel DB spans/metrics if exported."),
        ts_panel("pgx pool stats", [
            prom_target(f'sum(pgxpool_acquire_count{{{ENV_FILTER_NO_VER}}})', "A", "acquire_count"),
            prom_target(f'sum(pgxpool_idle_conns{{{ENV_FILTER_NO_VER}}})', "B", "idle_conns"),
            prom_target(f'sum(pgxpool_total_conns{{{ENV_FILTER_NO_VER}}})', "C", "total_conns"),
        ], {"h":8,"w":8,"x":8,"y":24}, unit="short", desc="pgx pool stats when pool instrumentation is enabled."),
        ts_panel("Notification outbox", [
            prom_target(f'sum(rate(notifications_enqueued_total{{{ENV_FILTER_NO_VER}}}[5m]))', "A", "enqueued/s"),
            prom_target(f'sum(rate(notifications_sent_total{{{ENV_FILTER_NO_VER}}}[5m]))', "B", "sent/s"),
            prom_target(f'sum(rate(notifications_retried_total{{{ENV_FILTER_NO_VER}}}[5m]))', "C", "retried/s"),
            prom_target(f'sum(rate(notifications_failed_total{{{ENV_FILTER_NO_VER}}}[5m]))', "D", "failed/s"),
            prom_target(f'sum(notifications_pending{{{ENV_FILTER_NO_VER}}})', "E", "pending"),
        ], {"h":8,"w":8,"x":16,"y":24}, unit="short", desc="Notification outbox enqueued, sent, retried, failed, pending."),
    ])
    return base_dashboard(uid="product-event-sourcing", title="Event sourcing and data", description="Events, projections, commands, DB, and notification outbox health.", panels=panels, tags=["product", "event-sourcing"])


def usage_dashboard():
    panels = assign_ids([
        ts_panel("Bookings created", [prom_target(f'sum by (deployment_environment) (rate(bookings_created_total{{{ENV_FILTER_NO_VER}}}[15m]))', legend="{{deployment_environment}}")], {"h":7,"w":8,"x":0,"y":0}, unit="ops", desc="Booking creation rate."),
        ts_panel("Bookings cancelled", [prom_target(f'sum by (deployment_environment) (rate(bookings_cancelled_total{{{ENV_FILTER_NO_VER}}}[15m]))', legend="{{deployment_environment}}")], {"h":7,"w":8,"x":8,"y":0}, unit="ops", desc="Booking cancellation rate."),
        ts_panel("Bookings rejected by reason", [prom_target(f'sum by (reason) (rate(bookings_rejected_total{{{ENV_FILTER_NO_VER}}}[15m]))', legend="{{reason}}")], {"h":7,"w":8,"x":16,"y":0}, unit="ops", desc="Rejected bookings by reason."),
        ts_panel("Logins by result", [prom_target(f'sum by (result) (rate(auth_logins_total{{{ENV_FILTER_NO_VER}}}[15m]))', legend="{{result}}")], {"h":7,"w":8,"x":0,"y":7}, unit="ops", desc="Login attempts by result."),
        ts_panel("Codes issued", [prom_target(f'sum(rate(auth_codes_issued_total{{{ENV_FILTER_NO_VER}}}[15m]))', legend="codes/s")], {"h":7,"w":8,"x":8,"y":7}, unit="ops", desc="Login codes issued."),
        ts_panel("Rate-limit rejections", [prom_target(f'sum by (limiter) (rate(ratelimit_rejected_total{{{ENV_FILTER_NO_VER}}}[15m]))', legend="{{limiter}}")], {"h":7,"w":8,"x":16,"y":7}, unit="ops", desc="Rate-limit rejections by limiter."),
        ts_panel("Sidecar requests by result", [prom_target(f'sum by (endpoint, result) (rate(sidecar_requests_total{{{ENV_FILTER_NO_VER}}}[15m]))', legend="{{endpoint}} {{result}}")], {"h":8,"w":12,"x":0,"y":14}, unit="ops", desc="Sidecar requests by endpoint and result."),
        ts_panel("Sidecar latency p95", [prom_target(f'histogram_quantile(0.95, sum by (le, endpoint) (rate(sidecar_duration_seconds_bucket{{{ENV_FILTER_NO_VER}}}[15m])))', legend="{{endpoint}}")], {"h":8,"w":12,"x":12,"y":14}, unit="s", desc="Sidecar request latency by endpoint."),
        ts_panel("Email send results", [prom_target(f'sum by (result) (rate(email_sent_total{{{ENV_FILTER_NO_VER}}}[15m]))', legend="{{result}}")], {"h":7,"w":24,"x":0,"y":22}, unit="ops", desc="Email send results."),
    ])
    return base_dashboard(uid="product-usage", title="Product usage", description="Generic product usage and integration metrics.", panels=panels, tags=["product", "usage"])


def runtime_dashboard():
    panels = assign_ids([
        ts_panel("Go heap / memory", [
            prom_target(f'sum by (service_name) (go_memory_used_bytes{{{ENV_FILTER_NO_VER},go_memory_type="heap"}})', "A", "{{service_name}} heap"),
            prom_target(f'sum by (service_name) (process_runtime_go_mem_heap_alloc_bytes{{{ENV_FILTER_NO_VER}}})', "B", "{{service_name}} alloc"),
        ], {"h":8,"w":12,"x":0,"y":0}, unit="bytes", desc="Go runtime memory metrics when runtime instrumentation is enabled."),
        ts_panel("Goroutines / GC", [
            prom_target(f'sum by (service_name) (go_goroutine_count{{{ENV_FILTER_NO_VER}}})', "A", "{{service_name}} goroutines"),
            prom_target(f'sum by (service_name) (rate(process_runtime_go_gc_count_total{{{ENV_FILTER_NO_VER}}}[5m]))', "B", "{{service_name}} gc/s"),
        ], {"h":8,"w":12,"x":12,"y":0}, unit="short", desc="Go runtime goroutines and GC rate."),
        ts_panel("Container memory (if available)", [prom_target(f'sum by (name) (container_memory_working_set_bytes{{name=~".+"}})', legend="{{name}}")], {"h":8,"w":12,"x":0,"y":8}, unit="bytes", desc="Container memory if cAdvisor/docker metrics are present. May show No data when not scraped."),
        ts_panel("Host memory (node exporter profile)", [prom_target('node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes', legend="used") , prom_target('node_memory_MemAvailable_bytes', legend="available")], {"h":8,"w":12,"x":12,"y":8}, unit="bytes", desc="Host memory from node-exporter profile. Shows No data when host profile is disabled."),
        ts_panel("Postgres exporter (profile)", [prom_target('pg_up', legend="pg_up"), prom_target('sum(rate(pg_stat_database_xact_commit[5m]))', legend="commits/s")], {"h":8,"w":12,"x":0,"y":16}, unit="short", desc="Postgres metrics when postgres profile is enabled. Shows No data when profile/exporter is not configured."),
        ts_panel("Caddy metrics (profile)", [prom_target('sum(rate(caddy_http_requests_total[5m])) by (server)', legend="{{server}}"), prom_target('sum(rate(caddy_http_request_errors_total[5m])) by (server)', legend="errors {{server}}")], {"h":8,"w":12,"x":12,"y":16}, unit="reqps", desc="Caddy metrics when Caddy metrics are scraped. Shows No data when caddy scrape/profile is not configured."),
    ])
    return base_dashboard(uid="product-runtime", title="Runtime and dependencies", description="Go runtime and optional dependency/profile metrics.", panels=panels, tags=["product", "runtime"])

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    dashboards = [
        overview_dashboard(),
        traces_dashboard(),
        event_sourcing_dashboard(),
        usage_dashboard(),
        runtime_dashboard(),
    ]
    for d in dashboards:
        path = OUT / f"{d['uid']}.json"
        path.write_text(json.dumps(d, indent=2, sort_keys=False) + "\n", encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT.parent.parent)}")


if __name__ == "__main__":
    main()
