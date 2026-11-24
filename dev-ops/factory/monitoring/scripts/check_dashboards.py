#!/usr/bin/env python3
"""Validate factory dashboard variables and render ClickHouse SQL for smoke tests."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DASHBOARDS = ROOT / "grafana" / "dashboards"
SQL_LITERAL = re.compile(r"^'(?:[^'\\]|\\.|'')*'$", re.DOTALL)
VARIABLE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_.]*)(?::([^}]+))?\}")
IN_STAR = re.compile(r"\bIN\s*\(\s*\*\s*\)", re.IGNORECASE)
LANGFUSE_PLACEHOLDER = "__LANGFUSE_PUBLIC_URL__"
INCOMPLETE_VALUE = re.compile(
    r"(?:=|\bIN)\s*(?=$|\)|\bAND\b|\bOR\b|\bORDER\b|\bLIMIT\b)",
    re.IGNORECASE | re.MULTILINE,
)


def fail(message: str) -> None:
    raise ValueError(message)


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def sql_quote(value: str, formatter: str) -> str:
    if formatter == "sqlstring":
        return "'" + value.replace("'", "''") + "'"
    escaped = value.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{escaped}'"


def default_values(variables: dict[str, dict]) -> dict[str, list[str]]:
    values: dict[str, list[str]] = {}
    for name, var in variables.items():
        current = var.get("current") or {}
        value = current.get("value")
        if var.get("includeAll") and value == "$__all":
            values[name] = ["$__all"]
        elif isinstance(value, list):
            values[name] = [str(v) for v in value]
        elif value not in (None, ""):
            values[name] = [str(value)]
        elif var.get("options"):
            values[name] = [str(var["options"][0].get("value", ""))]
        else:
            # Grafana preselects the first query result when no current value is
            # stored. The concrete value is unavailable during static checks.
            values[name] = [f"__{name}_first__"]
    return values


def format_values(var: dict, values: list[str], formatter: str | None) -> str:
    if var.get("includeAll") and values == ["$__all"]:
        all_value = var.get("allValue")
        if all_value is None:
            # No custom all value: use a harmless sample to check SQL shape.
            return sql_quote("__all_option__", "singlequote")
        return str(all_value)
    if not values or (len(values) == 1 and values[0] == ""):
        # Grafana's singlequote formatter emits nothing for an empty selection.
        return ""
    if formatter in ("singlequote", "sqlstring"):
        return ",".join(sql_quote(value, formatter) for value in values)
    return ",".join(values)


def replace_time_filter(sql: str) -> str:
    marker = "$__timeFilter("
    output: list[str] = []
    cursor = 0
    while True:
        start = sql.find(marker, cursor)
        if start < 0:
            output.append(sql[cursor:])
            break
        output.append(sql[cursor:start])
        index = start + len(marker)
        depth = 1
        expression_start = index
        while index < len(sql) and depth:
            if sql[index] == "(":
                depth += 1
            elif sql[index] == ")":
                depth -= 1
            index += 1
        if depth:
            fail("unbalanced $__timeFilter macro")
        expression = sql[expression_start : index - 1].strip()
        output.append(
            f"({expression} >= toDateTime64('2000-01-01 00:00:00', 3, 'UTC') "
            f"AND {expression} <= toDateTime64('2100-01-01 00:00:00', 3, 'UTC'))"
        )
        cursor = index
    rendered = "".join(output)
    rendered = rendered.replace("$__interval", "INTERVAL 1 HOUR")
    if "$__" in rendered:
        fail(f"unsupported Grafana macro in rendered SQL: {rendered}")
    return rendered


def render_sql(sql: str, variables: dict[str, dict], overrides: dict[str, list[str]]) -> str:
    values = default_values(variables)
    values.update(overrides)

    def replace(match: re.Match) -> str:
        name, formatter = match.groups()
        if name not in variables:
            fail(f"unknown dashboard variable {name}")
        return format_values(variables[name], values[name], formatter)

    rendered = VARIABLE.sub(replace, sql)
    rendered = replace_time_filter(rendered)
    if "${" in rendered:
        fail(f"unresolved variable syntax in rendered SQL: {rendered}")
    if "{RUN_ID_FILTER}" in rendered or "{TRACE_ID_FILTER}" in rendered:
        fail(f"unresolved generator filter in SQL: {rendered}")
    if IN_STAR.search(rendered):
        fail(f"rendered SQL contains IN (*): {rendered}")
    if INCOMPLETE_VALUE.search(rendered):
        fail(f"empty variable left an incomplete SQL expression: {rendered}")
    return rendered


def dashboard_queries(dashboard: dict) -> list[tuple[str, str]]:
    queries: list[tuple[str, str]] = []
    for item in walk(dashboard):
        raw_sql = item.get("rawSql")
        if isinstance(raw_sql, str) and raw_sql.strip():
            queries.append(("panel SQL", raw_sql))
    for var in dashboard.get("templating", {}).get("list", []):
        if var.get("type") != "query":
            continue
        for key in ("definition", "query"):
            query = var.get(key)
            if isinstance(query, str) and query.strip():
                queries.append((f"variable {var.get('name')}", query))
    return queries


def validate_dashboards(directory: Path) -> tuple[list[dict], dict[str, tuple[str, str]]]:
    dashboards = sorted(directory.glob("*.json"))
    if not dashboards:
        fail(f"no dashboard JSON files in {directory}")
    records: list[dict] = []
    query_index: dict[str, tuple[str, str]] = {}
    for path in dashboards:
        dashboard = json.loads(path.read_text())
        variables = {
            var["name"]: var
            for var in dashboard.get("templating", {}).get("list", [])
            if var.get("name")
        }
        for name, var in variables.items():
            if not var.get("includeAll"):
                continue
            all_value = var.get("allValue")
            if all_value is not None and not SQL_LITERAL.fullmatch(str(all_value)):
                fail(
                    f"{path.name}: variable {name} has non-SQL allValue {all_value!r}; "
                    "use a quoted SQL string literal"
                )
        if dashboard.get("uid") == "factory-run-detail":
            run_var = variables.get("run_id")
            trace_var = variables.get("trace_id")
            if not run_var or not trace_var:
                fail(f"{path.name}: run_id and trace_id variables are required")
            if run_var.get("current") not in (None, {}):
                fail(f"{path.name}: run_id must omit current so Grafana selects the newest first result")
            if "ORDER BY STARTED_AT DESC" not in str(run_var.get("query", "")).upper():
                fail(f"{path.name}: run_id query must order newest first")
            if trace_var.get("current") not in (None, {}):
                fail(f"{path.name}: trace_id must omit current so Grafana selects the first result")
            langfuse_var = variables.get("langfuse_url")
            if not langfuse_var or (langfuse_var.get("current") or {}).get("value") != LANGFUSE_PLACEHOLDER:
                fail(f"{path.name}: langfuse_url must use the deploy-time rendering placeholder")
        queries = dashboard_queries(dashboard)
        if not queries:
            fail(f"{path.name}: no SQL queries found")
        cases = {
            "defaults": {},
            "multi": {
                name: [f"{name}-a", f"{name}-b"]
                for name, var in variables.items()
                if var.get("includeAll")
            },
        }
        if dashboard.get("uid") == "factory-run-detail":
            cases["empty-run"] = {"run_id": [""], "trace_id": [""]}
        for case, overrides in cases.items():
            for location, sql in queries:
                rendered = render_sql(sql, variables, overrides)
                key = f"{path.name}\t{case}\t{location}"
                query_index[rendered] = (key, sql)
                records.append({"dashboard": path.name, "case": case, "location": location, "sql": rendered})
    return records, query_index


def clickhouse_query(container: str, sql: str) -> str:
    result = subprocess.run(
        ["docker", "exec", "-i", container, "clickhouse-client", "--query", sql],
        text=True,
        capture_output=True,
        timeout=30,
    )
    if result.returncode:
        fail(f"ClickHouse query failed: {result.stderr.strip()}\nSQL:\n{sql}")
    return result.stdout.strip()


def explain_queries(container: str, query_index: dict[str, tuple[str, str]]) -> None:
    for rendered, (label, _) in query_index.items():
        try:
            clickhouse_query(container, f"EXPLAIN SYNTAX {rendered}")
            clickhouse_query(container, f"SELECT count() FROM ({rendered})")
        except ValueError as exc:
            fail(f"{label}: {exc}")
    print(f"ClickHouse parsed and executed {len(query_index)} distinct rendered queries")


def execute_run_detail(container: str, directory: Path) -> tuple[str, str]:
    dashboard = json.loads((directory / "factory-run-detail.json").read_text())
    variables = {var["name"]: var for var in dashboard["templating"]["list"]}
    newest_run = clickhouse_query(
        container,
        "SELECT run_id FROM factory.runs ORDER BY started_at DESC LIMIT 1",
    )
    if not newest_run:
        fail("Run Detail smoke requires at least one factory run")
    trace_id = clickhouse_query(
        container,
        "SELECT trace_id FROM factory.runs WHERE run_id = "
        + sql_quote(newest_run, "sqlstring")
        + " LIMIT 1",
    )
    summary = next(panel for panel in dashboard["panels"] if panel.get("id") == 1)
    rendered = render_sql(
        summary["targets"][0]["rawSql"],
        variables,
        {"run_id": [newest_run], "trace_id": [trace_id]},
    )
    actual = clickhouse_query(container, f"SELECT run_id FROM ({rendered})")
    if actual != newest_run:
        fail(f"Run Detail default query returned {actual!r}, expected newest run {newest_run!r}")
    print(f"Run Detail default query returned newest run {newest_run}")
    return newest_run, trace_id


def execute_empty_selections(container: str, directory: Path, run_id: str, trace_id: str) -> None:
    dashboard = json.loads((directory / "factory-run-detail.json").read_text())
    variables = {var["name"]: var for var in dashboard["templating"]["list"]}
    cases = (
        ("run_id", {"run_id": [""], "trace_id": [trace_id]}, "${run_id:singlequote}"),
        ("trace_id", {"run_id": [run_id], "trace_id": [""]}, "${trace_id:singlequote}"),
    )
    for name, overrides, marker in cases:
        checked = 0
        for _location, sql in dashboard_queries(dashboard):
            if marker not in sql:
                continue
            rendered = render_sql(sql, variables, overrides)
            count = clickhouse_query(container, f"SELECT count() FROM ({rendered})")
            if count != "0":
                fail(f"empty {name} query returned {count} rows, expected 0")
            checked += 1
        if not checked:
            fail(f"no Run Detail queries found for empty {name} check")
        print(f"Empty {name} selection returned zero rows for {checked} queries")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dashboards-dir", type=Path, default=DEFAULT_DASHBOARDS)
    parser.add_argument("--clickhouse-container")
    parser.add_argument("--execute-run-detail", action="store_true")
    args = parser.parse_args()
    try:
        records, query_index = validate_dashboards(args.dashboards_dir)
        if args.clickhouse_container:
            explain_queries(args.clickhouse_container, query_index)
        if args.execute_run_detail:
            if not args.clickhouse_container:
                fail("--execute-run-detail requires --clickhouse-container")
            newest_run, trace_id = execute_run_detail(args.clickhouse_container, args.dashboards_dir)
            execute_empty_selections(args.clickhouse_container, args.dashboards_dir, newest_run, trace_id)
    except (ValueError, OSError, json.JSONDecodeError, subprocess.SubprocessError, StopIteration) as exc:
        print(f"[dashboard-check] FAIL: {exc}", file=sys.stderr)
        return 1
    print(f"[dashboard-check] OK: {len(records)} rendered queries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
