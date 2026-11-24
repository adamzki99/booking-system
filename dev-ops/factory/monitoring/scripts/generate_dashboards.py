#!/usr/bin/env python3
"""Generate provisioned Grafana dashboards for the factory monitoring stack.

Commit both this generator and the generated JSON files. validate.sh checks that
the output is up to date.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "grafana" / "dashboards"

DS_CH = {"type": "grafana-clickhouse-datasource", "uid": "clickhouse-factory"}
DS_PROM = {"type": "prometheus", "uid": "prometheus-factory"}


def ch_target(ref_id: str, sql: str, query_type: str = "table", format_: int | None = None):
    if format_ is None:
        format_ = 0 if query_type == "timeseries" else 1
    return {
        "datasource": DS_CH,
        "editorType": "sql",
        "format": format_,
        "meta": {"builderOptions": {"columns": [], "database": "factory", "limit": 1000, "mode": "list", "queryType": query_type}},
        "pluginVersion": "4.23.5",
        "queryType": query_type,
        "rawSql": sql.strip(),
        "refId": ref_id,
    }


def prom_target(ref_id: str, expr: str, legend: str = "", instant: bool = False):
    return {
        "datasource": DS_PROM,
        "editorMode": "code",
        "expr": expr.strip(),
        "instant": instant,
        "legendFormat": legend,
        "range": not instant,
        "refId": ref_id,
    }


def base_dashboard(uid: str, title: str, description: str, panels, tags=None, extra_vars=None, time_from="now-24h"):
    return {
        "annotations": {"list": [{"builtIn": 1, "datasource": {"type": "grafana", "uid": "-- Grafana --"}, "enable": True, "hide": True, "iconColor": "rgba(0, 211, 255, 1)", "name": "Annotations & Alerts", "type": "dashboard"}]},
        "editable": False,
        "fiscalYearStartMonth": 0,
        "graphTooltip": 0,
        "links": [
            {"asDropdown": False, "icon": "external link", "includeVars": True, "keepTime": True, "tags": ["factory"], "targetBlank": False, "title": "Factory dashboards", "type": "dashboards"}
        ],
        "panels": panels,
        "refresh": "30s",
        "schemaVersion": 39,
        "tags": ["factory"] + (tags or []),
        "templating": {"list": templating(extra_vars=extra_vars)},
        "time": {"from": time_from, "to": "now"},
        "timepicker": {},
        "timezone": "utc",
        "title": title,
        "uid": uid,
        "version": 1,
        "weekStart": "",
        "description": description,
    }


def templating(extra_vars=None):
    def query_var(name, label, sql, multi=True, include_all=True):
        return {
            "current": {"selected": True, "text": "All" if include_all else "", "value": "$__all" if include_all else ""},
            "datasource": DS_CH,
            "definition": sql,
            "hide": 0,
            "includeAll": include_all,
            # Grafana inserts a custom all value verbatim, even with :singlequote.
            # Keep it a SQL literal so "All" renders as '*' rather than *.
            "allValue": "'*'" if include_all else None,
            "label": label,
            "multi": multi,
            "name": name,
            "options": [],
            "query": sql,
            "refresh": 2,
            "regex": "",
            "skipUrlSync": False,
            "sort": 1,
            "type": "query",
        }

    vars = [
        query_var("factory_id", "Factory", "SELECT DISTINCT factory_id FROM factory.events WHERE $__timeFilter(ts) AND factory_id != '' ORDER BY factory_id"),
        query_var("agent_id", "Agent", "SELECT DISTINCT agent_id FROM factory.events WHERE $__timeFilter(ts) AND agent_id != '' ORDER BY agent_id"),
        query_var("model", "Model", "SELECT DISTINCT model FROM factory.events WHERE $__timeFilter(ts) AND model != '' ORDER BY model"),
        query_var("kind", "Kind", "SELECT DISTINCT kind FROM factory.events WHERE $__timeFilter(ts) AND kind != '' ORDER BY kind"),
    ]
    if extra_vars:
        vars.extend(extra_vars)
    return vars


def filters_for(alias: str = "") -> str:
    """Render the shared filters, qualifying columns without changing variables."""
    prefix = f"{alias}." if alias else ""
    return f"""
  AND ('*' IN (${{factory_id:singlequote}}) OR {prefix}factory_id IN (${{factory_id:singlequote}}))
  AND ('*' IN (${{agent_id:singlequote}}) OR {prefix}agent_id IN (${{agent_id:singlequote}}))
  AND ('*' IN (${{model:singlequote}}) OR {prefix}model IN (${{model:singlequote}}))
  AND ('*' IN (${{kind:singlequote}}) OR {prefix}kind IN (${{kind:singlequote}}))
""".strip()


FILTERS = filters_for()

# An empty singlequote selection renders as nothing in Grafana. Wrapping the
# interpolation in a typed array keeps Run Detail SQL valid for empty URL values;
# nullIf turns the empty string into NULL so non-run events with an empty run_id
# cannot match an empty selection.
RUN_ID_FILTER = "run_id = nullIf(arrayElement(CAST([${run_id:singlequote}], 'Array(String)'), 1), '')"
TRACE_ID_FILTER = "TraceId = nullIf(arrayElement(CAST([${trace_id:singlequote}], 'Array(String)'), 1), '')"
LANGFUSE_URL_PLACEHOLDER = "__LANGFUSE_PUBLIC_URL__"


def stat_panel(pid, title, desc, sql, grid, unit="none", thresholds=None, color_mode="value", graph="area"):
    thresholds = thresholds or {"mode": "absolute", "steps": [{"color": "green", "value": None}]}
    return {
        "datasource": DS_CH,
        "description": desc,
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "mappings": [], "thresholds": thresholds, "unit": unit}, "overrides": []},
        "gridPos": grid,
        "id": pid,
        "options": {"colorMode": color_mode, "graphMode": graph, "justifyMode": "auto", "orientation": "auto", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}, "textMode": "auto", "wideLayout": True},
        "pluginVersion": "10.4.1",
        "targets": [ch_target("A", sql)],
        "title": title,
        "type": "stat",
    }


def timeseries_panel(pid, title, desc, targets, grid, unit="short", legend_mode="table", stack="none"):
    return {
        "datasource": DS_CH if targets and targets[0].get("datasource", {}).get("uid") == "clickhouse-factory" else DS_PROM,
        "description": desc,
        "fieldConfig": {"defaults": {"color": {"mode": "palette-classic"}, "custom": {"axisBorderShow": False, "axisCenteredZero": False, "axisColorMode": "text", "axisLabel": "", "axisPlacement": "auto", "barAlignment": 0, "drawStyle": "line", "fillOpacity": 10, "gradientMode": "none", "hideFrom": {"legend": False, "tooltip": False, "viz": False}, "insertNulls": False, "lineInterpolation": "linear", "lineWidth": 1, "pointSize": 4, "scaleDistribution": {"type": "linear"}, "showPoints": "never", "spanNulls": False, "stacking": {"group": "A", "mode": stack}, "thresholdsStyle": {"mode": "off"}}, "mappings": [], "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": None}]}, "unit": unit}, "overrides": []},
        "gridPos": grid,
        "id": pid,
        "options": {"legend": {"calcs": ["lastNotNull", "max"], "displayMode": legend_mode, "placement": "bottom", "showLegend": True}, "tooltip": {"mode": "multi", "sort": "desc"}},
        "targets": targets,
        "title": title,
        "type": "timeseries",
    }


def table_panel(pid, title, desc, sql, grid, overrides=None):
    return {
        "datasource": DS_CH,
        "description": desc,
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "custom": {"align": "auto", "cellOptions": {"type": "auto"}, "inspect": False}, "mappings": [], "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": None}]}}, "overrides": overrides or []},
        "gridPos": grid,
        "id": pid,
        "options": {"cellHeight": "sm", "footer": {"countRows": False, "fields": "", "reducer": ["sum"], "show": False}, "showHeader": True, "sortBy": []},
        "pluginVersion": "10.4.1",
        "targets": [ch_target("A", sql)],
        "title": title,
        "type": "table",
    }


def barchart_panel(pid, title, desc, sql, grid):
    return {
        "datasource": DS_CH,
        "description": desc,
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "custom": {"axisBorderShow": False, "axisCenteredZero": False, "axisColorMode": "text", "axisLabel": "", "axisPlacement": "auto", "fillOpacity": 80, "gradientMode": "none", "hideFrom": {"legend": False, "tooltip": False, "viz": False}, "lineWidth": 1, "scaleDistribution": {"type": "linear"}, "thresholdsStyle": {"mode": "off"}}, "mappings": [], "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": None}]}}, "overrides": []},
        "gridPos": grid,
        "id": pid,
        "options": {"barRadius": 0, "barWidth": 0.8, "fullHighlight": False, "groupWidth": 0.7, "legend": {"calcs": [], "displayMode": "list", "placement": "bottom", "showLegend": True}, "orientation": "auto", "showValue": "auto", "stacking": "none", "tooltip": {"mode": "single", "sort": "none"}, "xTickLabelRotation": 0, "xTickLabelSpacing": 0},
        "targets": [ch_target("A", sql)],
        "title": title,
        "type": "barchart",
    }


def prom_stat(pid, title, desc, expr, grid, unit="none", thresholds=None):
    thresholds = thresholds or {"mode": "absolute", "steps": [{"color": "green", "value": None}]}
    return {
        "datasource": DS_PROM,
        "description": desc,
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "mappings": [], "thresholds": thresholds, "unit": unit}, "overrides": []},
        "gridPos": grid,
        "id": pid,
        "options": {"colorMode": "value", "graphMode": "none", "justifyMode": "auto", "orientation": "auto", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}, "textMode": "auto", "wideLayout": True},
        "pluginVersion": "10.4.1",
        "targets": [prom_target("A", expr, instant=True)],
        "title": title,
        "type": "stat",
    }


def prom_timeseries(pid, title, desc, targets, grid, unit="short"):
    return {
        "datasource": DS_PROM,
        "description": desc,
        "fieldConfig": {"defaults": {"color": {"mode": "palette-classic"}, "custom": {"axisBorderShow": False, "axisCenteredZero": False, "axisColorMode": "text", "axisLabel": "", "axisPlacement": "auto", "drawStyle": "line", "fillOpacity": 10, "gradientMode": "none", "hideFrom": {"legend": False, "tooltip": False, "viz": False}, "insertNulls": False, "lineInterpolation": "linear", "lineWidth": 1, "pointSize": 4, "showPoints": "never", "spanNulls": False, "stacking": {"group": "A", "mode": "none"}, "thresholdsStyle": {"mode": "off"}}, "mappings": [], "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": None}]}, "unit": unit}, "overrides": []},
        "gridPos": grid,
        "id": pid,
        "options": {"legend": {"calcs": ["lastNotNull", "max"], "displayMode": "table", "placement": "bottom", "showLegend": True}, "tooltip": {"mode": "multi", "sort": "desc"}},
        "targets": targets,
        "title": title,
        "type": "timeseries",
    }


def dashboard_overview():
    panels = [
        stat_panel(1, "Issues processed (24h)", "Distinct issues with a run started in the selected window.", f"""
SELECT uniqExact(issue_id) AS value
FROM factory.runs
WHERE $__timeFilter(started_at) AND issue_id IS NOT NULL
  {FILTERS}
""", {"h":4,"w":4,"x":0,"y":0}),
        stat_panel(2, "Issues completed (24h)", "Issues with a merged PR in the selected window (EVENTS.md: merged factory PR).", f"""
SELECT uniqExact(issue_id) AS value
FROM factory.events FINAL
WHERE $__timeFilter(ts) AND event = 'pr.merged' AND issue_id IS NOT NULL
  AND ('*' IN (${{factory_id:singlequote}}) OR factory_id IN (${{factory_id:singlequote}}))
""", {"h":4,"w":4,"x":4,"y":0}),
        stat_panel(3, "Run success rate", "Completed runs / all terminal runs in window.", f"""
SELECT round(countIf(outcome='completed') * 100.0 / nullIf(countIf(outcome IN ('completed','failed')), 0), 1) AS value
FROM factory.runs
WHERE $__timeFilter(started_at)
  {FILTERS}
""", {"h":4,"w":4,"x":8,"y":0}, unit="percent", thresholds={"mode":"absolute","steps":[{"color":"red","value":None},{"color":"yellow","value":70},{"color":"green","value":90}]}),
        stat_panel(4, "Active agents", "Distinct agents with runs started in window.", f"""
SELECT uniqExact(agent_id) AS value
FROM factory.runs
WHERE $__timeFilter(started_at) AND agent_id != ''
  {FILTERS}
""", {"h":4,"w":4,"x":12,"y":0}),
        stat_panel(5, "Avg pickup to merge", "Average seconds from first run start for issue to pr.merged (EVENTS.md pickup-to-merge).", f"""
SELECT avg(dateDiff('second', r.first_run_at, p.merged_at)) AS value
FROM (
  SELECT issue_id, min(started_at) AS first_run_at
  FROM factory.runs
  WHERE $__timeFilter(started_at) AND issue_id IS NOT NULL {FILTERS}
  GROUP BY issue_id
) r
INNER JOIN (
  SELECT issue_id, max(ts) AS merged_at
  FROM factory.events FINAL
  WHERE event='pr.merged' AND issue_id IS NOT NULL
  GROUP BY issue_id
) p ON p.issue_id = r.issue_id
WHERE p.merged_at > r.first_run_at
""", {"h":4,"w":4,"x":16,"y":0}, unit="s"),
        stat_panel(6, "Total reported cost (USD)", "Sum of cost_usd reported by OpenCode; may be 0 for subscription models.", f"""
SELECT round(sum(coalesce(cost_usd, toDecimal64(0,6))), 4) AS value
FROM factory.runs
WHERE $__timeFilter(started_at)
  {FILTERS}
""", {"h":4,"w":4,"x":20,"y":0}, unit="currencyUSD"),
        stat_panel(7, "Total tokens", "Input+output+reasoning+cache tokens for terminal runs in window.", f"""
SELECT sum(coalesce(input_tokens,0)+coalesce(output_tokens,0)+coalesce(reasoning_tokens,0)+coalesce(cache_read_tokens,0)+coalesce(cache_write_tokens,0)) AS value
FROM factory.runs
WHERE $__timeFilter(started_at)
  {FILTERS}
""", {"h":4,"w":4,"x":0,"y":4}, unit="short"),
        prom_stat(8, "Last tick age", "Seconds since last successful factory tick (Prometheus textfile metric).", "time() - factory_tick_last_success_timestamp_seconds", {"h":4,"w":4,"x":4,"y":4}, unit="s", thresholds={"mode":"absolute","steps":[{"color":"green","value":None},{"color":"yellow","value":3600},{"color":"red","value":7200}]}),
        stat_panel(9, "Issues processed (7d)", "Distinct issues with runs started in the last 7 days (ignores dashboard range for this panel).", f"""
SELECT uniqExact(issue_id) AS value
FROM factory.runs
WHERE started_at >= now() - INTERVAL 7 DAY AND issue_id IS NOT NULL
  {FILTERS}
""", {"h":4,"w":4,"x":8,"y":4}),
        stat_panel(10, "Merged PRs (7d)", "Merged factory PRs in last 7 days.", f"""
SELECT uniqExact(pr_number) AS value
FROM factory.events FINAL
WHERE ts >= now() - INTERVAL 7 DAY AND event='pr.merged' AND pr_number IS NOT NULL
  AND ('*' IN (${{factory_id:singlequote}}) OR factory_id IN (${{factory_id:singlequote}}))
""", {"h":4,"w":4,"x":12,"y":4}),
        timeseries_panel(11, "Throughput over time", "Runs and merged PRs per day.", [
            ch_target("Runs", f"""
SELECT toStartOfInterval(started_at, INTERVAL 1 day) AS time, count() AS runs
FROM factory.runs
WHERE $__timeFilter(started_at) {FILTERS}
GROUP BY time ORDER BY time
""", "timeseries", 0),
            ch_target("Merged PRs", f"""
SELECT toStartOfInterval(ts, INTERVAL 1 day) AS time, uniqExact(pr_number) AS merged_prs
FROM factory.events FINAL
WHERE $__timeFilter(ts) AND event='pr.merged'
  AND ('*' IN (${{factory_id:singlequote}}) OR factory_id IN (${{factory_id:singlequote}}))
GROUP BY time ORDER BY time
""", "timeseries", 0),
        ], {"h":8,"w":12,"x":0,"y":8}),
        timeseries_panel(12, "Run outcomes over time", "Completed and failed runs per hour.", [
            ch_target("Completed", f"""
SELECT toStartOfInterval(started_at, INTERVAL 1 hour) AS time, countIf(outcome='completed') AS completed
FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}
GROUP BY time ORDER BY time
""", "timeseries", 0),
            ch_target("Failed", f"""
SELECT toStartOfInterval(started_at, INTERVAL 1 hour) AS time, countIf(outcome='failed') AS failed
FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}
GROUP BY time ORDER BY time
""", "timeseries", 0),
        ], {"h":8,"w":12,"x":12,"y":8}),
        table_panel(13, "Current queue", "Latest factory.queue snapshot by state.", """
SELECT factory_id, ts, infant, planned, approved_waiting, in_pr, blocked_pr, needs_info
FROM factory.queue_latest
ORDER BY factory_id
""", {"h":7,"w":12,"x":0,"y":16}),
        table_panel(14, "Recent completed issues / PRs", "Recent merged PRs with issue, lead time, and human intervention proxy. Filtered by Factory through matching factory.runs; pr_outcomes has no factory_id.", f"""
SELECT
  p.repo,
  p.issue_id,
  p.pr_number,
  p.merged_at,
  dateDiff('minute', r.first_run_at, p.merged_at) AS pickup_to_merge_min,
  p.human_commits,
  p.review_comments,
  format('https://github.com/{{}}/issues/{{}}', p.repo, toString(p.issue_id)) AS issue_url,
  format('https://github.com/{{}}/pull/{{}}', p.repo, toString(p.pr_number)) AS pr_url
FROM factory.pr_outcomes p
LEFT JOIN (SELECT repo, issue_id, min(started_at) AS first_run_at FROM factory.runs WHERE issue_id IS NOT NULL GROUP BY repo, issue_id) r ON r.issue_id = p.issue_id AND r.repo = p.repo
WHERE p.merged_at IS NOT NULL AND $__timeFilter(p.merged_at)
  AND (
    '*' IN (${{factory_id:singlequote}})
    OR EXISTS (
      SELECT 1 FROM factory.runs rf
      WHERE rf.repo = p.repo AND rf.issue_id = p.issue_id
        AND rf.factory_id IN (${{factory_id:singlequote}})
    )
  )
ORDER BY p.merged_at DESC
LIMIT 50
""", {"h":7,"w":12,"x":12,"y":16}, overrides=[
            {"matcher":{"id":"byName","options":"issue_url"},"properties":[{"id":"links","value":[{"title":"Open issue","url":"${__value.raw}"}]}]},
            {"matcher":{"id":"byName","options":"pr_url"},"properties":[{"id":"links","value":[{"title":"Open PR","url":"${__value.raw}"}]}]},
        ]),
    ]
    return base_dashboard("factory-overview", "Factory Overview", "Factory throughput, success rate, queue, and recent delivery outcomes.", panels, ["overview"])



def dashboard_agents():
    panels = [
        stat_panel(1, "Runs", "Total runs in window.", f"SELECT count() AS value FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}", {"h":4,"w":4,"x":0,"y":0}),
        stat_panel(2, "Success rate", "Completed / terminal runs.", f"SELECT round(countIf(outcome='completed')*100.0/nullIf(countIf(outcome IN ('completed','failed')),0),1) AS value FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}", {"h":4,"w":4,"x":4,"y":0}, unit="percent"),
        stat_panel(3, "Merged PRs", "Merged PRs in window (by pr.merged events).", f"SELECT uniqExact(pr_number) AS value FROM factory.events FINAL WHERE $__timeFilter(ts) AND event='pr.merged' AND pr_number IS NOT NULL AND ('*' IN (${{factory_id:singlequote}}) OR factory_id IN (${{factory_id:singlequote}}))", {"h":4,"w":4,"x":8,"y":0}),
        stat_panel(4, "Avg cost / successful issue", "Reported cost per completed build/fix issue; cost as reported by OpenCode.", f"""
SELECT round(sumIf(coalesce(cost_usd,toDecimal64(0,6)), outcome='completed') / nullIf(uniqExactIf(issue_id, outcome='completed' AND issue_id IS NOT NULL),0), 4) AS value
FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}
""", {"h":4,"w":4,"x":12,"y":0}, unit="currencyUSD"),
        table_panel(5, "Agent / version / model performance", "Per agent, agent_version, model: runs, success rate, avg duration, avg cost/successful issue, retry/fallback share, PR merge rate proxy.", f"""
SELECT
  agent_id,
  agent_version,
  model,
  count() AS runs,
  countIf(outcome='completed') AS successes,
  round(countIf(outcome='completed')*100.0/nullIf(count(),0),1) AS success_rate_pct,
  round(avgIf(duration_ms, outcome IN ('completed','failed'))/1000,1) AS avg_duration_s,
  round(sumIf(coalesce(cost_usd,toDecimal64(0,6)), outcome='completed')/nullIf(uniqExactIf(issue_id,outcome='completed' AND issue_id IS NOT NULL),0),4) AS avg_cost_per_success_issue_usd,
  round(countIf(fallback_level IN ('backup','free'))*100.0/nullIf(count(),0),1) AS backup_free_pct,
  uniqExactIf(pr_number, outcome='completed' AND pr_number IS NOT NULL) AS prs_touched
FROM factory.runs
WHERE $__timeFilter(started_at) {FILTERS}
GROUP BY agent_id, agent_version, model
ORDER BY successes DESC, runs DESC
LIMIT 100
""", {"h":8,"w":24,"x":0,"y":4}),
        table_panel(6, "Leaderboard (merged PRs per run hour)", "Agent efficiency: merged PRs / run hours (EVENTS.md). Uses issue merged PRs joined to runs in window.", f"""
SELECT
  r.agent_id,
  r.agent_version,
  r.model,
  uniqExactIf(p.pr_number, p.merged_at IS NOT NULL) AS merged_prs,
  round(sum(coalesce(r.duration_ms,0))/3600000,3) AS run_hours,
  round(uniqExactIf(p.pr_number, p.merged_at IS NOT NULL) / nullIf(sum(coalesce(r.duration_ms,0))/3600000,0),3) AS merged_prs_per_run_hour
FROM factory.runs r
LEFT JOIN factory.pr_outcomes p ON p.issue_id = r.issue_id AND p.repo = r.repo
WHERE $__timeFilter(r.started_at) {filters_for('r')}
GROUP BY r.agent_id, r.agent_version, r.model
ORDER BY merged_prs_per_run_hour DESC
LIMIT 50
""", {"h":8,"w":24,"x":0,"y":12}),
        timeseries_panel(7, "Success/failure by agent", "Runs by outcome and agent.", [
            ch_target("Completed", f"SELECT toStartOfInterval(started_at, INTERVAL 1 hour) AS time, agent_id, countIf(outcome='completed') AS value FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS} GROUP BY time, agent_id ORDER BY time", "timeseries", 0),
            ch_target("Failed", f"SELECT toStartOfInterval(started_at, INTERVAL 1 hour) AS time, agent_id, countIf(outcome='failed') AS value FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS} GROUP BY time, agent_id ORDER BY time", "timeseries", 0),
        ], {"h":8,"w":12,"x":0,"y":20}),
        table_panel(8, "Prompt version breakdown", "Performance by prompt_version (sha256 prefix).", f"""
SELECT prompt_version, model, agent_id, count() AS runs, countIf(outcome='completed') AS successes, round(countIf(outcome='completed')*100.0/nullIf(count(),0),1) AS success_pct, round(avgIf(duration_ms,outcome IN ('completed','failed'))/1000,1) AS avg_s
FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}
GROUP BY prompt_version, model, agent_id ORDER BY runs DESC LIMIT 100
""", {"h":8,"w":12,"x":12,"y":20}),
    ]
    return base_dashboard("factory-agents", "Agent Performance", "Agent, version, model and prompt performance. Leaderboard uses merged PRs per run hour (EVENTS.md agent efficiency).", panels, ["agents"])


def dashboard_execution():
    panels = [
        stat_panel(1, "Runs (window)", "Runs started in window.", f"SELECT count() AS value FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}", {"h":4,"w":4,"x":0,"y":0}),
        stat_panel(2, "Failures", "Failed runs in window.", f"SELECT countIf(outcome='failed') AS value FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}", {"h":4,"w":4,"x":4,"y":0}, thresholds={"mode":"absolute","steps":[{"color":"green","value":None},{"color":"red","value":1}]}),
        stat_panel(3, "Stuck runs", "Runs with no end after 3900s (factory.stuck_runs).", "SELECT count() AS value FROM factory.stuck_runs", {"h":4,"w":4,"x":8,"y":0}, thresholds={"mode":"absolute","steps":[{"color":"green","value":None},{"color":"red","value":1}]}),
        stat_panel(4, "Avg duration", "Average terminal run duration.", f"SELECT round(avgIf(duration_ms, outcome IN ('completed','failed'))/1000,1) AS value FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}", {"h":4,"w":4,"x":12,"y":0}, unit="s"),
        timeseries_panel(5, "Runs per hour", "Run starts per hour by kind.", [ch_target("Runs", f"SELECT toStartOfInterval(started_at, INTERVAL 1 hour) AS time, kind, count() AS runs FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS} GROUP BY time, kind ORDER BY time", "timeseries", 0)], {"h":8,"w":12,"x":0,"y":4}),
        timeseries_panel(6, "Run duration distribution (p50/p90)", "Run duration p50/p90 over time.", [
            ch_target("p50", f"SELECT toStartOfInterval(started_at, INTERVAL 1 hour) AS time, quantile(0.5)(duration_ms)/1000 AS p50_s FROM factory.runs WHERE $__timeFilter(started_at) AND outcome IN ('completed','failed') {FILTERS} GROUP BY time ORDER BY time", "timeseries", 0),
            ch_target("p90", f"SELECT toStartOfInterval(started_at, INTERVAL 1 hour) AS time, quantile(0.9)(duration_ms)/1000 AS p90_s FROM factory.runs WHERE $__timeFilter(started_at) AND outcome IN ('completed','failed') {FILTERS} GROUP BY time ORDER BY time", "timeseries", 0),
        ], {"h":8,"w":12,"x":12,"y":4}, unit="s"),
        table_panel(7, "Top tools", "Most used tools from agent.tool.called.", f"""
SELECT tool, count() AS calls, countIf(status='error' OR status='failed') AS errors, round(avg(duration_ms),1) AS avg_ms
FROM factory.tool_calls
WHERE $__timeFilter(ts) AND ('*' IN (${{factory_id:singlequote}}) OR factory_id IN (${{factory_id:singlequote}}))
  AND ('*' IN (${{agent_id:singlequote}}) OR agent_id IN (${{agent_id:singlequote}}))
  AND ('*' IN (${{model:singlequote}}) OR model IN (${{model:singlequote}}))
  AND ('*' IN (${{kind:singlequote}}) OR kind IN (${{kind:singlequote}}))
GROUP BY tool ORDER BY calls DESC LIMIT 30
""", {"h":8,"w":12,"x":0,"y":12}),
        table_panel(8, "Skills loaded", "Skill loads (tool=skill) and status.", f"""
SELECT skill_name, count() AS loads, countIf(status='error' OR status='failed') AS errors
FROM factory.tool_calls
WHERE $__timeFilter(ts) AND tool='skill' AND skill_name != ''
  AND ('*' IN (${{factory_id:singlequote}}) OR factory_id IN (${{factory_id:singlequote}}))
GROUP BY skill_name ORDER BY loads DESC LIMIT 30
""", {"h":8,"w":12,"x":12,"y":12}),
        table_panel(9, "Failure reasons / fingerprints", "Failures by reason and error fingerprint.", f"""
SELECT failure_reason, error_fingerprint, count() AS failures, max(ended_at) AS last_seen
FROM factory.runs
WHERE $__timeFilter(started_at) AND outcome='failed' {FILTERS}
GROUP BY failure_reason, error_fingerprint ORDER BY failures DESC LIMIT 50
""", {"h":8,"w":12,"x":0,"y":20}),
        table_panel(10, "Issues with most runs", "Issues consuming most runs in window.", f"""
SELECT issue_id, count() AS runs, countIf(kind='fix') AS fix_runs, countIf(outcome='failed') AS failures, max(started_at) AS last_run
FROM factory.runs
WHERE $__timeFilter(started_at) AND issue_id IS NOT NULL {FILTERS}
GROUP BY issue_id ORDER BY runs DESC LIMIT 30
""", {"h":8,"w":12,"x":12,"y":20}),
        table_panel(11, "Retries / fallback / operational events", "Key operational events in window.", f"""
SELECT event, count() AS count, max(ts) AS last_seen
FROM factory.events FINAL
WHERE $__timeFilter(ts)
  AND event IN ('backup_retry','free_retry','usage_filled','claim_conflict','lock_skipped','gh_op_failed','guardrail_drift','reconcile_failed','discovery_failed','git_fetch_failed','dirty_worktree_skipped_reset')
  AND ('*' IN (${{factory_id:singlequote}}) OR factory_id IN (${{factory_id:singlequote}}))
GROUP BY event ORDER BY count DESC
""", {"h":7,"w":12,"x":0,"y":28}),
        table_panel(12, "Stuck runs detail", "Runs started but not ended after 3900s.", """
SELECT run_id, factory_id, kind, agent_id, model, issue_id, pr_number, session_id, trace_id, started_at, age_seconds
FROM factory.stuck_runs
ORDER BY age_seconds DESC
LIMIT 50
""", {"h":7,"w":12,"x":12,"y":28}, overrides=[
            {"matcher":{"id":"byName","options":"trace_id"},"properties":[{"id":"links","value":[{"title":"Open run detail","url":"/d/factory-run-detail/factory-run-detail?orgId=1&var-run_id=${__data.fields.run_id}&var-trace_id=${__value.raw}&${__url_time_range}"}]}]},
            {"matcher":{"id":"byName","options":"run_id"},"properties":[{"id":"links","value":[{"title":"Open run detail","url":"/d/factory-run-detail/factory-run-detail?orgId=1&var-run_id=${__value.raw}&var-trace_id=${__data.fields.trace_id}&${__url_time_range}"}]}]},
        ]),
    ]
    return base_dashboard("factory-execution", "Execution Analytics", "Run timing, tools, retries, failures, and operational health.", panels, ["execution"])


def dashboard_cost():
    panels = [
        stat_panel(1, "Reported cost (USD)", "Sum cost_usd as reported by OpenCode. Subscription models may report 0.", f"SELECT round(sum(coalesce(cost_usd,toDecimal64(0,6))),4) AS value FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}", {"h":4,"w":4,"x":0,"y":0}, unit="currencyUSD"),
        stat_panel(2, "Total tokens", "All token types for terminal runs.", f"SELECT sum(coalesce(input_tokens,0)+coalesce(output_tokens,0)+coalesce(reasoning_tokens,0)+coalesce(cache_read_tokens,0)+coalesce(cache_write_tokens,0)) AS value FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}", {"h":4,"w":4,"x":4,"y":0}, unit="short"),
        stat_panel(3, "Cost / merged PR", "Reported cost divided by merged PRs in window (approx).", f"""
SELECT round(sum(coalesce(reported_cost_usd,toDecimal64(0,6))) / nullIf(uniqExactIf(pr_number, event='pr.merged' AND pr_number IS NOT NULL),0),4) AS value
FROM (
  SELECT ts, pr_number, event, factory_id, toDecimal64(0,6) AS reported_cost_usd FROM factory.events FINAL WHERE $__timeFilter(ts) AND event='pr.merged'
  UNION ALL
  SELECT started_at AS ts, pr_number, outcome AS event, factory_id, coalesce(cost_usd,toDecimal64(0,6)) AS reported_cost_usd FROM factory.runs WHERE $__timeFilter(started_at)
) t WHERE ('*' IN (${{factory_id:singlequote}}) OR factory_id IN (${{factory_id:singlequote}}))
""", {"h":4,"w":4,"x":8,"y":0}, unit="currencyUSD"),
        stat_panel(4, "Tokens / merged PR", "Tokens per merged PR in window (approx).", f"""
SELECT round(sum(tokens) / nullIf(sum(merged),0),0) AS value FROM (
  SELECT 0 AS merged, sum(coalesce(input_tokens,0)+coalesce(output_tokens,0)+coalesce(reasoning_tokens,0)+coalesce(cache_read_tokens,0)+coalesce(cache_write_tokens,0)) AS tokens
  FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}
  UNION ALL
  SELECT uniqExact(pr_number) AS merged, 0 AS tokens FROM factory.events FINAL WHERE $__timeFilter(ts) AND event='pr.merged' AND pr_number IS NOT NULL
    AND ('*' IN (${{factory_id:singlequote}}) OR factory_id IN (${{factory_id:singlequote}}))
)
""", {"h":4,"w":4,"x":12,"y":0}, unit="short"),
        timeseries_panel(5, "Cost over time (reported)", "Reported cost per day; may be 0 for subscription models.", [ch_target("Cost USD", f"SELECT toStartOfInterval(started_at, INTERVAL 1 day) AS time, sum(coalesce(cost_usd,toDecimal64(0,6))) AS reported_cost_usd FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS} GROUP BY time ORDER BY time", "timeseries", 0)], {"h":8,"w":12,"x":0,"y":4}, unit="currencyUSD"),
        timeseries_panel(6, "Tokens over time", "Token types per day.", [
            ch_target("Input", f"SELECT toStartOfInterval(started_at, INTERVAL 1 day) AS time, sum(coalesce(input_tokens,0)) AS input FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS} GROUP BY time ORDER BY time", "timeseries", 0),
            ch_target("Output", f"SELECT toStartOfInterval(started_at, INTERVAL 1 day) AS time, sum(coalesce(output_tokens,0)) AS output FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS} GROUP BY time ORDER BY time", "timeseries", 0),
            ch_target("Reasoning", f"SELECT toStartOfInterval(started_at, INTERVAL 1 day) AS time, sum(coalesce(reasoning_tokens,0)) AS reasoning FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS} GROUP BY time ORDER BY time", "timeseries", 0),
            ch_target("Cache read", f"SELECT toStartOfInterval(started_at, INTERVAL 1 day) AS time, sum(coalesce(cache_read_tokens,0)) AS cache_read FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS} GROUP BY time ORDER BY time", "timeseries", 0),
            ch_target("Cache write", f"SELECT toStartOfInterval(started_at, INTERVAL 1 day) AS time, sum(coalesce(cache_write_tokens,0)) AS cache_write FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS} GROUP BY time ORDER BY time", "timeseries", 0),
        ], {"h":8,"w":12,"x":12,"y":4}, unit="short"),
        table_panel(7, "Cost/tokens by model", "Model breakdown; cost as reported by OpenCode.", f"""
SELECT model, count() AS runs, countIf(outcome='completed') AS successes,
  round(sum(coalesce(cost_usd,toDecimal64(0,6))),4) AS reported_cost_usd,
  sum(coalesce(input_tokens,0)+coalesce(output_tokens,0)+coalesce(reasoning_tokens,0)+coalesce(cache_read_tokens,0)+coalesce(cache_write_tokens,0)) AS tokens,
  round(sum(coalesce(cost_usd,toDecimal64(0,6))) / nullIf(countIf(outcome='completed'),0),4) AS cost_per_success
FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}
GROUP BY model ORDER BY reported_cost_usd DESC LIMIT 50
""", {"h":8,"w":12,"x":0,"y":12}),
        table_panel(8, "Cost/tokens by agent/kind", "Agent and kind breakdown.", f"""
SELECT agent_id, kind, count() AS runs,
  round(sum(coalesce(cost_usd,toDecimal64(0,6))),4) AS reported_cost_usd,
  sum(coalesce(input_tokens,0)+coalesce(output_tokens,0)+coalesce(reasoning_tokens,0)+coalesce(cache_read_tokens,0)+coalesce(cache_write_tokens,0)) AS tokens
FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}
GROUP BY agent_id, kind ORDER BY reported_cost_usd DESC LIMIT 50
""", {"h":8,"w":12,"x":12,"y":12}),
        table_panel(9, "Usage-filled / backup / free share", "Quota pressure and fallback share.", f"""
SELECT
  countIf(fallback_level='backup') AS backup_runs,
  countIf(fallback_level='free') AS free_runs,
  round(countIf(fallback_level IN ('backup','free'))*100.0/nullIf(count(),0),2) AS fallback_pct,
  countIf(failure_reason='usage_filled') AS usage_filled_failures,
  countIf(failure_reason='usage_filled_skipped') AS usage_filled_skipped
FROM factory.runs WHERE $__timeFilter(started_at) {FILTERS}
""", {"h":5,"w":24,"x":0,"y":20}),
    ]
    return base_dashboard("factory-cost", "Cost and Efficiency", "Tokens and reported cost by model/agent/kind. Cost is as reported by OpenCode; subscription models may report 0.", panels, ["cost"])


def dashboard_quality():
    panels = [
        stat_panel(1, "PR acceptance rate", "pr.merged / (pr.merged + pr.closed) in window (EVENTS.md).", f"""
SELECT round(
  uniqExactIf(pr_number, event='pr.merged') * 100.0 /
  nullIf(uniqExactIf(pr_number, event='pr.merged') + uniqExactIf(pr_number, event='pr.closed'), 0), 1) AS value
FROM factory.events FINAL
WHERE $__timeFilter(ts) AND event IN ('pr.merged','pr.closed') AND pr_number IS NOT NULL
  AND ('*' IN (${{factory_id:singlequote}}) OR factory_id IN (${{factory_id:singlequote}}))
""", {"h":4,"w":4,"x":0,"y":0}, unit="percent"),
        stat_panel(2, "Merged PRs", "Merged PRs in window.", f"SELECT uniqExact(pr_number) AS value FROM factory.events FINAL WHERE $__timeFilter(ts) AND event='pr.merged' AND pr_number IS NOT NULL AND ('*' IN (${{factory_id:singlequote}}) OR factory_id IN (${{factory_id:singlequote}}))", {"h":4,"w":4,"x":4,"y":0}),
        stat_panel(3, "Human intervention rate", "Merged PRs with human_commits>0 or owner changes_requested / merged PRs (EVENTS.md proxy).", f"""
SELECT round(sumIf(1, human_commits > 0 OR changes_requested > 0) * 100.0 / nullIf(countIf(merged_at IS NOT NULL AND merged_at > toDateTime64('1970-01-01 00:00:00',3,'UTC')),0),1) AS value
FROM factory.pr_outcomes
WHERE merged_at IS NOT NULL AND $__timeFilter(merged_at)
""", {"h":4,"w":4,"x":8,"y":0}, unit="percent"),
        stat_panel(4, "Lead time p50 (h)", "Approved/first run to merge p50 hours (EVENTS.md lead time).", f"""
SELECT round(quantile(0.5)(dateDiff('second', coalesce(approved_at, first_run_at), merged_at)) / 3600, 2) AS value
FROM factory.issues
WHERE merged_at IS NOT NULL AND merged_at > toDateTime64('1970-01-01 00:00:00',3,'UTC') AND $__timeFilter(merged_at)
""", {"h":4,"w":4,"x":12,"y":0}, unit="h"),
        stat_panel(5, "First-pass success rate", "Issues merged with no fix runs / completed issues (EVENTS.md).", f"""
SELECT round(countIf(first_pass)*100.0/nullIf(countIf(state='completed'),0),1) AS value
FROM factory.issues
WHERE merged_at IS NOT NULL AND $__timeFilter(merged_at)
""", {"h":4,"w":4,"x":16,"y":0}, unit="percent"),
        stat_panel(6, "Reopened issues", "Issues reopened in window.", f"SELECT uniqExact(issue_id) AS value FROM factory.events FINAL WHERE $__timeFilter(ts) AND event='issue.reopened' AND issue_id IS NOT NULL", {"h":4,"w":4,"x":20,"y":0}),
        timeseries_panel(7, "PR outcomes over time", "Merged vs closed-unmerged PRs by day.", [
            ch_target("Merged", f"SELECT toStartOfInterval(ts, INTERVAL 1 day) AS time, uniqExact(pr_number) AS merged FROM factory.events FINAL WHERE $__timeFilter(ts) AND event='pr.merged' GROUP BY time ORDER BY time", "timeseries", 0),
            ch_target("Closed unmerged", f"SELECT toStartOfInterval(ts, INTERVAL 1 day) AS time, uniqExact(pr_number) AS closed FROM factory.events FINAL WHERE $__timeFilter(ts) AND event='pr.closed' GROUP BY time ORDER BY time", "timeseries", 0),
        ], {"h":8,"w":12,"x":0,"y":4}),
        timeseries_panel(8, "Lead time p50/p90 (hours)", "Pickup/approved to merge lead time.", [
            ch_target("p50", f"SELECT toStartOfInterval(merged_at, INTERVAL 1 day) AS time, quantile(0.5)(dateDiff('second', coalesce(approved_at, first_run_at), merged_at))/3600 AS p50_h FROM factory.issues WHERE merged_at IS NOT NULL AND $__timeFilter(merged_at) GROUP BY time ORDER BY time", "timeseries", 0),
            ch_target("p90", f"SELECT toStartOfInterval(merged_at, INTERVAL 1 day) AS time, quantile(0.9)(dateDiff('second', coalesce(approved_at, first_run_at), merged_at))/3600 AS p90_h FROM factory.issues WHERE merged_at IS NOT NULL AND $__timeFilter(merged_at) GROUP BY time ORDER BY time", "timeseries", 0),
        ], {"h":8,"w":12,"x":12,"y":4}, unit="h"),
        table_panel(9, "Rework / abandonment", "Issues with fix runs, abandoned issues, and first-pass outcomes.", f"""
SELECT
  countIf(state='completed') AS completed,
  countIf(state='abandoned') AS abandoned,
  countIf(state='completed' AND fix_runs > 0) AS completed_with_rework,
  round(countIf(state='completed' AND fix_runs > 0)*100.0/nullIf(countIf(state='completed'),0),1) AS rework_rate_pct,
  countIf(first_pass) AS first_pass
FROM factory.issues
WHERE $__timeFilter(coalesce(merged_at, closed_at, first_run_at, first_seen_at))
""", {"h":6,"w":12,"x":0,"y":12}),
        table_panel(10, "CI failures on factory PRs", "Latest pr.checks conclusions and failed checks (from pr.checks events).", f"""
SELECT pr_number, repo, last_checks_conclusion, last_failed_checks, merged_at, closed_at, review_comments
FROM factory.pr_outcomes
WHERE $__timeFilter(coalesce(merged_at, closed_at, created_at, toDateTime64(now(),3,'UTC')))
ORDER BY coalesce(merged_at, closed_at, created_at) DESC
LIMIT 50
""", {"h":6,"w":12,"x":12,"y":12}),
    ]
    return base_dashboard("factory-quality", "Quality and Outcomes", "PR outcomes, review/CI signals, lead time, rework and abandonment.", panels, ["quality"])


def dashboard_host():
    panels = [
        prom_stat(1, "CPU usage", "1 - avg idle CPU.", "100 * (1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])))", {"h":4,"w":4,"x":0,"y":0}, unit="percent", thresholds={"mode":"absolute","steps":[{"color":"green","value":None},{"color":"yellow","value":75},{"color":"red","value":90}]}),
        prom_stat(2, "Memory usage", "Host memory usage ratio.", "100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))", {"h":4,"w":4,"x":4,"y":0}, unit="percent", thresholds={"mode":"absolute","steps":[{"color":"green","value":None},{"color":"yellow","value":80},{"color":"red","value":90}]}),
        prom_stat(3, "Disk / usage", "Root filesystem usage.", "100 * (1 - (node_filesystem_avail_bytes{mountpoint=\"/\",fstype!~\"tmpfs|overlay\"} / node_filesystem_size_bytes{mountpoint=\"/\",fstype!~\"tmpfs|overlay\"}))", {"h":4,"w":4,"x":8,"y":0}, unit="percent", thresholds={"mode":"absolute","steps":[{"color":"green","value":None},{"color":"yellow","value":80},{"color":"red","value":90}]}),
        prom_stat(4, "Load (1m)", "1 minute load average.", "node_load1", {"h":4,"w":4,"x":12,"y":0}),
        prom_timeseries(5, "Host CPU %", "CPU usage over time.", [prom_target("A", "100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])))", "{{instance}}")], {"h":8,"w":12,"x":0,"y":4}, unit="percent"),
        prom_timeseries(6, "Host memory %", "Memory usage over time.", [prom_target("A", "100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))", "memory")], {"h":8,"w":12,"x":12,"y":4}, unit="percent"),
        prom_timeseries(7, "Disk usage %", "Filesystem usage by mountpoint.", [prom_target("A", "100 * (1 - (node_filesystem_avail_bytes{fstype!~\"tmpfs|overlay\"} / node_filesystem_size_bytes{fstype!~\"tmpfs|overlay\"}))", "{{mountpoint}}")], {"h":8,"w":12,"x":0,"y":12}, unit="percent"),
        prom_timeseries(8, "Collector records", "OTel collector accepted/refused/sent/failed log records (if exposed).", [
            prom_target("Accepted", "sum(rate(otelcol_receiver_accepted_log_records_total[5m])) or sum(rate(otelcol_receiver_accepted_log_records[5m])) or vector(0)", "accepted"),
            prom_target("Refused", "sum(rate(otelcol_receiver_refused_log_records_total[5m])) or sum(rate(otelcol_receiver_refused_log_records[5m])) or vector(0)", "refused"),
            prom_target("Sent", "sum(rate(otelcol_exporter_sent_log_records_total[5m])) or sum(rate(otelcol_exporter_sent_log_records[5m])) or vector(0)", "sent"),
            prom_target("Send failed", "sum(rate(otelcol_exporter_send_failed_log_records_total[5m])) or sum(rate(otelcol_exporter_send_failed_log_records[5m])) or vector(0)", "send_failed"),
        ], {"h":8,"w":12,"x":12,"y":12}, unit="ops"),
        prom_timeseries(9, "Per-container memory (if available)", "Container memory working set; empty if cAdvisor/container metrics profile is not enabled.", [prom_target("A", "container_memory_working_set_bytes{container!=\"\",container!=\"POD\"}", "{{container}}")], {"h":8,"w":12,"x":0,"y":20}, unit="bytes"),
        prom_timeseries(10, "Prometheus TSDB size", "Prometheus TSDB storage size.", [prom_target("A", "prometheus_tsdb_storage_blocks_bytes + prometheus_tsdb_wal_storage_size_bytes + prometheus_tsdb_head_chunks_storage_size_bytes", "tsdb")], {"h":8,"w":12,"x":12,"y":20}, unit="bytes"),
        table_panel(11, "ClickHouse disk use by table", "ClickHouse table sizes (best effort; requires grafana SELECT on system.parts).", """
SELECT database, table, formatReadableSize(sum(bytes_on_disk)) AS size, sum(rows) AS rows
FROM system.parts
WHERE active AND database IN ('factory', 'otel')
GROUP BY database, table
ORDER BY sum(bytes_on_disk) DESC
LIMIT 50
""", {"h":8,"w":24,"x":0,"y":28}),
    ]
    return base_dashboard("factory-host", "Factory Host", "Factory host, collector, ClickHouse and Prometheus health.", panels, ["host"])


def dashboard_run_detail():
    run_var = {
        "datasource": DS_CH,
        "definition": "SELECT run_id FROM factory.runs WHERE $__timeFilter(started_at) ORDER BY started_at DESC LIMIT 200",
        "description": "Defaults to the newest run in the selected time range. An empty selection returns no rows.",
        "hide": 0,
        "includeAll": False,
        "label": "Run ID",
        "multi": False,
        "name": "run_id",
        "options": [],
        "query": "SELECT run_id FROM factory.runs WHERE $__timeFilter(started_at) ORDER BY started_at DESC LIMIT 200",
        "refresh": 2,
        "regex": "",
        "skipUrlSync": False,
        "sort": 0,
        "type": "query",
    }
    trace_var = {
        "datasource": DS_CH,
        "definition": f"SELECT trace_id FROM factory.runs WHERE {RUN_ID_FILTER} AND trace_id != '' LIMIT 1",
        "hide": 2,
        "includeAll": False,
        "label": "Trace ID",
        "multi": False,
        "name": "trace_id",
        "options": [],
        "query": f"SELECT trace_id FROM factory.runs WHERE {RUN_ID_FILTER} AND trace_id != '' LIMIT 1",
        "refresh": 2,
        "regex": "",
        "skipUrlSync": False,
        "sort": 0,
        "type": "query",
    }
    langfuse_url_var = {
        "current": {"selected": True, "text": LANGFUSE_URL_PLACEHOLDER, "value": LANGFUSE_URL_PLACEHOLDER},
        "description": "Browser-reachable Langfuse base URL, rendered from LANGFUSE_PUBLIC_URL at stack startup with a loopback fallback.",
        "hide": 0,
        "label": "Langfuse URL",
        "name": "langfuse_url",
        "options": [{"selected": True, "text": LANGFUSE_URL_PLACEHOLDER, "value": LANGFUSE_URL_PLACEHOLDER}],
        "query": LANGFUSE_URL_PLACEHOLDER,
        "skipUrlSync": False,
        "type": "textbox",
    }
    langfuse_project_var = {
        "current": {"selected": True, "text": "factory-project", "value": "factory-project"},
        "hide": 0,
        "label": "Langfuse Project ID",
        "name": "langfuse_project_id",
        "options": [{"selected": True, "text": "factory-project", "value": "factory-project"}],
        "query": "factory-project",
        "skipUrlSync": False,
        "type": "textbox",
    }

    panels = [
        table_panel(1, "Run summary", "Newest run by default, or the selected run from factory.runs. Empty selections return no rows.", f"""
SELECT
  run_id, factory_id, tick_id, kind, agent_id, agent_version, prompt_version, model, tier_label,
  fallback_level, attempt, issue_id, pr_number, repo, session_id, trace_id,
  started_at, ended_at, outcome, failure_reason, duration_ms,
  input_tokens, output_tokens, reasoning_tokens, cache_read_tokens, cache_write_tokens,
  cost_usd, tool_calls, tool_errors, files_changed, exit_code, error_fingerprint
FROM factory.runs
WHERE {RUN_ID_FILTER}
LIMIT 1
""", {"h": 6, "w": 24, "x": 0, "y": 0}, overrides=[
            {"matcher": {"id": "byName", "options": "trace_id"}, "properties": [{"id": "links", "value": [
                {"title": "Open Langfuse trace", "url": "${langfuse_url}/project/${langfuse_project_id}/traces/${__value.raw}", "targetBlank": True}
            ]}]},
        ]),
        table_panel(2, "Run events", "Factory events for the selected run.", f"""
SELECT ts, event, status, kind, agent_id, model, session_id, trace_id, duration_ms, failure_reason, error_fingerprint, attrs
FROM factory.events FINAL
WHERE {RUN_ID_FILTER}
ORDER BY ts ASC
LIMIT 500
""", {"h": 8, "w": 24, "x": 0, "y": 6}),
        {
            "datasource": DS_CH,
            "description": "Trace waterfall from otel.otel_traces for the selected run trace_id. Requires Grafana ClickHouse datasource traces support.",
            "gridPos": {"h": 10, "w": 24, "x": 0, "y": 14},
            "id": 3,
            "options": {},
            "targets": [{
                "datasource": DS_CH,
                "editorType": "sql",
                "format": 3,
                "meta": {"builderOptions": {"columns": [], "database": "otel", "limit": 1000, "mode": "list", "queryType": "traces"}},
                "pluginVersion": "4.23.5",
                "queryType": "traces",
                "rawSql": f"""
SELECT
  TraceId AS traceID,
  SpanId AS spanID,
  ParentSpanId AS parentSpanID,
  ServiceName AS serviceName,
  SpanName AS operationName,
  Timestamp AS startTime,
  Duration / 1000000 AS duration,
  arrayMap(k -> map('key', k, 'value', SpanAttributes[k]), mapKeys(SpanAttributes)) AS tags,
  arrayMap(k -> map('key', k, 'value', ResourceAttributes[k]), mapKeys(ResourceAttributes)) AS serviceTags,
  if(StatusCode = 'STATUS_CODE_ERROR' OR StatusCode = 'Error' OR StatusCode = '2', 2, 0) AS statusCode
FROM otel.otel_traces
WHERE {TRACE_ID_FILTER}
ORDER BY Timestamp ASC
LIMIT 1000
""".strip(),
                "refId": "A",
            }],
            "title": "Trace (waterfall)",
            "type": "traces",
        },
        table_panel(4, "Tool calls", "Tool calls emitted by the run.", f"""
SELECT ts, tool, status, duration_ms, skill_name, run_id, attrs
FROM factory.tool_calls
WHERE {RUN_ID_FILTER}
ORDER BY ts ASC
LIMIT 500
""", {"h": 8, "w": 12, "x": 0, "y": 24}),
        table_panel(5, "Tokens per step", "LLM step spans from otel.otel_traces with GenAI token attributes.", f"""
SELECT
  Timestamp AS ts,
  SpanName AS span,
  SpanAttributes['gen_ai.request.model'] AS model,
  toInt64OrNull(SpanAttributes['gen_ai.usage.input_tokens']) AS input_tokens,
  toInt64OrNull(SpanAttributes['gen_ai.usage.output_tokens']) AS output_tokens,
  toInt64OrNull(SpanAttributes['gen_ai.usage.reasoning_tokens']) AS reasoning_tokens,
  toInt64OrNull(SpanAttributes['gen_ai.usage.cache_read_tokens']) AS cache_read_tokens,
  toInt64OrNull(SpanAttributes['gen_ai.usage.cache_write_tokens']) AS cache_write_tokens,
  toFloat64OrNull(SpanAttributes['gen_ai.usage.cost_usd']) AS cost_usd,
  Duration / 1000000 AS duration_ms
FROM otel.otel_traces
WHERE {TRACE_ID_FILTER}
  AND SpanName IN ('opencode.llm.step', 'factory.agent.run')
ORDER BY Timestamp ASC
LIMIT 200
""", {"h": 8, "w": 12, "x": 12, "y": 24}),
    ]
    return base_dashboard(
        "factory-run-detail",
        "Factory Run Detail",
        "Deep dive for one factory run: events, trace waterfall, tool calls, and token/cost per step.",
        panels,
        ["run-detail", "traces"],
        extra_vars=[run_var, trace_var, langfuse_url_var, langfuse_project_var],
        time_from="now-7d",
    )


DASHBOARDS = [
    dashboard_overview(),
    dashboard_agents(),
    dashboard_execution(),
    dashboard_cost(),
    dashboard_quality(),
    dashboard_host(),
    dashboard_run_detail(),
]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for d in DASHBOARDS:
        p = OUT / f"{d['uid']}.json"
        p.write_text(json.dumps(d, indent=2, sort_keys=True) + "\n")
        print(f"wrote {p}")
    readme = OUT / "README.md"
    readme.write_text("""# Factory Grafana dashboards

Dashboards in this directory are provisioned into the "Factory" folder by
Grafana on startup. They are generated from
`../scripts/generate_dashboards.py`.

Regenerate:

```sh
python3 dev-ops/factory/monitoring/scripts/generate_dashboards.py
```
""")
    print(f"wrote {readme}")


if __name__ == "__main__":
    main()
