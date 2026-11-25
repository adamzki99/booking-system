from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[3]
RULES_PATH = ROOT / "dev-ops/factory/monitoring/grafana/provisioning/alerting/rules.yaml"


def load_rules():
    data = yaml.safe_load(RULES_PATH.read_text())
    return {
        rule["uid"]: rule
        for group in data["groups"]
        for rule in group["rules"]
    }


def raw_sql(rule):
    return "\n".join(
        query["model"].get("rawSql", "")
        for query in rule["data"]
        if query.get("model", {}).get("datasource", {}).get("type")
        == "grafana-clickhouse-datasource"
    )


def expressions(rule):
    return "\n".join(
        query["model"].get("expression", "")
        for query in rule["data"]
        if query.get("model", {}).get("datasource", {}).get("type") == "__expr__"
    )


def prometheus_expressions(rule):
    return "\n".join(
        query["model"].get("expr", "")
        for query in rule["data"]
        if query.get("model", {}).get("datasource", {}).get("type") == "prometheus"
    )


def test_quota_alert_uses_current_run_events():
    sql = raw_sql(load_rules()["factory-quota-pressure"])
    assert "countIf(event='agent.run.failed' AND failure_reason IN ('usage_filled','usage_filled_skipped')) > 0" in sql
    assert "countIf(event='agent.run.started' AND fallback_level = 'free') > 2" in sql
    assert " OR " in sql
    assert "attrs['failure_reason']" not in sql
    assert "attrs['fallback_level']" not in sql


def test_new_alert_queries_have_valid_relative_time_ranges():
    rules = load_rules()
    for uid in (
        "factory-tick-failed",
        "factory-telemetry-broken",
        "factory-event-ingestion-stale",
    ):
        for query in rules[uid]["data"]:
            if query.get("datasourceUid") == "__expr__":
                continue
            time_range = query["relativeTimeRange"]
            assert time_range["from"] > time_range["to"], (uid, query["refId"])


def test_factory_validation_paths_trigger_monitoring_ci():
    workflow = (ROOT / ".github/workflows/ci.yml").read_text()
    for path in (
        "dev-ops/factory/tick.sh",
        "dev-ops/factory/lib/**",
        "dev-ops/factory/validate.sh",
        "dev-ops/scripts/tests/**",
    ):
        assert f"'{path}'" in workflow


def test_tick_failure_alert_uses_exit_code_metric():
    rule = load_rules()["factory-tick-failed"]
    assert "factory_tick_last_exit_code" in prometheus_expressions(rule)
    assert "!= bool 0" in prometheus_expressions(rule)
    assert "or vector(0)" in prometheus_expressions(rule)
    assert rule["labels"]["severity"] == "critical"
    assert rule["noDataState"] == "OK"


def test_telemetry_alert_uses_prometheus_error_metric():
    rule = load_rules()["factory-telemetry-broken"]
    datasources = {
        query.get("datasourceUid")
        for query in rule["data"]
        if query.get("datasourceUid") not in {None, "__expr__"}
    }
    assert "prometheus-factory" in datasources
    assert "factory_telemetry_errors_last" in prometheus_expressions(rule)
    assert "> bool 0" in prometheus_expressions(rule)
    assert "or vector(0)" in prometheus_expressions(rule)
    assert rule["noDataState"] == "OK"


def test_event_ingestion_alert_compares_tick_heartbeat_to_clickhouse():
    rule = load_rules()["factory-event-ingestion-stale"]
    datasources = {
        query.get("datasourceUid")
        for query in rule["data"]
        if query.get("datasourceUid") not in {None, "__expr__"}
    }
    assert datasources == {"prometheus-factory", "clickhouse-factory"}
    sql = raw_sql(rule)
    assert "tick_end" in sql
    assert "2 HOUR" in sql
    assert "factory_tick_last_run_timestamp_seconds" in prometheus_expressions(rule)
    assert "< bool 7200" in prometheus_expressions(rule)
    assert "or vector(0)" in prometheus_expressions(rule)
    assert "*" in expressions(rule)
    assert rule["noDataState"] == "OK"
