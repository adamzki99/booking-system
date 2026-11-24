#!/usr/bin/env python3
"""Check shared Grafana/Prometheus hardening for a monitoring stack."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def volume_targets(service: dict) -> set[str]:
    targets = set()
    for volume in service.get("volumes", []):
        if isinstance(volume, str):
            parts = volume.split(":")
            if len(parts) >= 2:
                targets.add(parts[1])
        elif isinstance(volume, dict) and volume.get("target"):
            targets.add(str(volume["target"]))
    return targets


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compose", type=Path, required=True)
    parser.add_argument("--prometheus", type=Path, required=True)
    parser.add_argument("--env-example", type=Path, required=True)
    args = parser.parse_args()
    try:
        compose = yaml.safe_load(args.compose.read_text())
        services = compose["services"]
        grafana = services["grafana"]
        environment = grafana.get("environment", {})
        expected = {
            "GF_METRICS_BASIC_AUTH_USERNAME": "prometheus",
            "GF_METRICS_BASIC_AUTH_PASSWORD": "${GRAFANA_METRICS_PASSWORD:?set GRAFANA_METRICS_PASSWORD in .env}",
            "GF_SNAPSHOTS_EXTERNAL_ENABLED": "false",
            "GF_PUBLIC_DASHBOARDS_ENABLED": "false",
            "GF_PLUGINS_PLUGIN_ADMIN_ENABLED": "false",
        }
        for key, value in expected.items():
            require(environment.get(key) == value, f"grafana {key} must be {value!r}")
        require(
            str(environment.get("GF_SERVER_ROOT_URL", "")).startswith("${GRAFANA_ROOT_URL:-"),
            "grafana GF_SERVER_ROOT_URL must come from GRAFANA_ROOT_URL",
        )

        ports = [str(port) for port in grafana.get("ports", [])]
        require(
            any("${GRAFANA_BIND_ADDR:-127.0.0.1}:" in port for port in ports),
            "grafana port must default to GRAFANA_BIND_ADDR=127.0.0.1",
        )
        otel_ports = [str(port) for port in services["otel-collector"].get("ports", [])]
        require(
            sum("${OTLP_BIND_ADDR:-127.0.0.1}:" in port for port in otel_ports) >= 2,
            "OTLP ports must default to OTLP_BIND_ADDR=127.0.0.1",
        )
        if "langfuse-web" in services:
            langfuse_ports = [str(port) for port in services["langfuse-web"].get("ports", [])]
            require(
                any("${LANGFUSE_BIND_ADDR:-127.0.0.1}:" in port for port in langfuse_ports),
                "Langfuse port must default to LANGFUSE_BIND_ADDR=127.0.0.1",
            )

        check_env = services["check-env"]
        command = "\n".join(check_env.get("command", []))
        require("GRAFANA_METRICS_PASSWORD" in command, "check-env must require GRAFANA_METRICS_PASSWORD")
        require(
            "/etc/prometheus/secrets/grafana-metrics-password" in command,
            "check-env must generate the Prometheus password file",
        )
        require(
            "GRAFANA_METRICS_PASSWORD" in check_env.get("environment", {}),
            "check-env must receive GRAFANA_METRICS_PASSWORD",
        )
        for service_name in ("check-env", "prometheus"):
            require(
                "/etc/prometheus/secrets" in volume_targets(services[service_name]),
                f"{service_name} must mount the metrics auth volume",
            )

        if "langfuse-web" in services:
            require(
                check_env.get("environment", {}).get("LANGFUSE_PUBLIC_URL")
                == "${LANGFUSE_PUBLIC_URL:-http://127.0.0.1:3001}",
                "check-env must receive LANGFUSE_PUBLIC_URL with a loopback fallback",
            )
            require(
                "__LANGFUSE_PUBLIC_URL__" in command,
                "check-env must render the Langfuse URL placeholder",
            )
            check_env_targets = volume_targets(check_env)
            require(
                "/dashboards" in check_env_targets and "/var/lib/grafana/dashboards" in check_env_targets,
                "check-env must mount dashboard source and rendered volumes",
            )
            require(
                "/var/lib/grafana/dashboards" in volume_targets(grafana),
                "grafana must mount the rendered dashboard volume",
            )
            require(
                "LANGFUSE_PUBLIC_URL=" in args.env_example.read_text(),
                f"{args.env_example} must document LANGFUSE_PUBLIC_URL",
            )

        prometheus = yaml.safe_load(args.prometheus.read_text())
        jobs = [job for job in prometheus.get("scrape_configs", []) if job.get("job_name") == "grafana"]
        require(len(jobs) == 1, "prometheus must have exactly one grafana scrape job")
        basic_auth = jobs[0].get("basic_auth", {})
        require(basic_auth.get("username") == "prometheus", "grafana scrape username must be prometheus")
        require(
            basic_auth.get("password_file") == "/etc/prometheus/secrets/grafana-metrics-password",
            "grafana scrape must use the generated password_file",
        )
        require("password" not in basic_auth, "grafana scrape must not contain an inline password")

        env_example = args.env_example.read_text()
        for name in (
            "GRAFANA_METRICS_PASSWORD",
            "GRAFANA_BIND_ADDR",
            "OTLP_BIND_ADDR",
            "GRAFANA_ROOT_URL",
        ):
            require(f"{name}=" in env_example, f"{args.env_example} must document {name}")
        require(
            "reset-admin-password" in env_example,
            f"{args.env_example} must document admin password rotation",
        )
    except (OSError, ValueError, KeyError, TypeError, yaml.YAMLError) as exc:
        print(f"[monitoring-hardening] FAIL: {exc}", file=sys.stderr)
        return 1
    print(f"[monitoring-hardening] OK: {args.compose}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
