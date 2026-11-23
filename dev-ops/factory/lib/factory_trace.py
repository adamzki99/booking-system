"""OTLP trace export for factory agent runs (stdlib only).

Converts an opencode JSON stream into OTLP/HTTP JSON spans and posts them to
the configured collector. Option (c) from monitoring prompt 05: the factory owns
the trace shape and trace_id correlation, independent of OpenCode internals.

Privacy: no prompt/completion/tool input/output content is exported unless
FACTORY_TRACE_CONTENT=1. Redaction is applied as defence in depth.
"""

from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.request
import uuid
from typing import Any

SENSITIVE_KEY_RE = re.compile(
    r"(?i)(token|password|secret|authorization|api.?key|passwd|credential|private.?key|email|ical)"
)
SENSITIVE_VALUE_RE = re.compile(
    r"(?i)(bearer\s+[a-z0-9._\-]+|sk-[a-z0-9]+|ghp_[a-z0-9]+|github_pat_[a-z0-9_]+)"
)


def _now_ns() -> int:
    return time.time_ns()


def _hex_id(nbytes: int) -> str:
    return os.urandom(nbytes).hex()


def _as_int(value: Any) -> int | None:
    try:
        if value is None or isinstance(value, bool):
            return None
        return int(value)
    except (TypeError, ValueError):
        return None


def _ms_to_ns(ms: Any) -> int | None:
    v = _as_int(ms)
    if v is None:
        return None
    # opencode stream timestamps are milliseconds since epoch
    if v < 10_000_000_000:  # seconds-ish guard
        return v * 1_000_000_000
    if v < 10_000_000_000_000:  # milliseconds
        return v * 1_000_000
    return v  # already ns-ish


def _attr(key: str, value: Any) -> dict[str, Any] | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return {"key": key, "value": {"boolValue": value}}
    if isinstance(value, int) and not isinstance(value, bool):
        return {"key": key, "value": {"intValue": str(value)}}
    if isinstance(value, float):
        return {"key": key, "value": {"doubleValue": value}}
    if isinstance(value, (list, tuple)):
        vals = []
        for v in value:
            a = _attr("v", v)
            if a:
                vals.append(a["value"])
        return {"key": key, "value": {"arrayValue": {"values": vals}}}
    text = str(value)
    return {"key": key, "value": {"stringValue": text}}


def _attrs(d: dict[str, Any]) -> list[dict[str, Any]]:
    out = []
    for k, v in d.items():
        a = _attr(k, v)
        if a is not None:
            out.append(a)
    return out


def _redact_text(text: str) -> str:
    if not text:
        return text
    redacted = SENSITIVE_VALUE_RE.sub("[REDACTED]", text)
    # redact e-mail-like tokens and long opaque tokens
    redacted = re.sub(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "[REDACTED_EMAIL]", redacted)
    return redacted


def _sanitize_attr_value(key: str, value: Any, include_content: bool) -> Any:
    if SENSITIVE_KEY_RE.search(key or ""):
        return "[REDACTED]"
    if isinstance(value, str):
        value = _redact_text(value)
        if not include_content and len(value) > 512:
            return value[:512] + "...[TRUNCATED]"
        return value
    if isinstance(value, dict):
        return {k: _sanitize_attr_value(k, v, include_content) for k, v in value.items()}
    if isinstance(value, list):
        return [_sanitize_attr_value(key, v, include_content) for v in value]
    return value


def _content_allowed() -> bool:
    return os.environ.get("FACTORY_TRACE_CONTENT", "").strip() == "1"


def parse_stream_events(text: str) -> list[dict[str, Any]]:
    events = []
    for line in (text or "").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if isinstance(obj, dict):
            events.append(obj)
    return events


def _span(
    *,
    trace_id: str,
    span_id: str,
    parent_span_id: str | None,
    name: str,
    start_ns: int,
    end_ns: int,
    kind: int = 1,
    attributes: dict[str, Any] | None = None,
    status_code: int = 1,
    status_message: str = "",
) -> dict[str, Any]:
    if end_ns < start_ns:
        end_ns = start_ns
    span: dict[str, Any] = {
        "traceId": trace_id,
        "spanId": span_id,
        "name": name,
        "kind": kind,
        "startTimeUnixNano": str(start_ns),
        "endTimeUnixNano": str(end_ns),
        "attributes": _attrs(attributes or {}),
        "status": {"code": status_code},
    }
    if parent_span_id:
        span["parentSpanId"] = parent_span_id
    if status_message:
        span["status"]["message"] = status_message
    return span


def build_run_spans(
    *,
    trace_id: str,
    run_id: str,
    session_id: str = "",
    kind: str = "",
    agent_id: str = "",
    model: str = "",
    repo: str = "",
    issue_id: str | int | None = None,
    pr_number: str | int | None = None,
    attempt: str | int | None = None,
    fallback_level: str = "",
    outcome: str = "",
    failure_reason: str = "",
    stream_text: str = "",
    run_start_ns: int | None = None,
    run_end_ns: int | None = None,
    include_content: bool | None = None,
) -> list[dict[str, Any]]:
    """Build OTLP span dicts for one factory agent run."""
    if include_content is None:
        include_content = _content_allowed()

    events = parse_stream_events(stream_text)
    now = _now_ns()
    root_start = run_start_ns or now
    root_end = run_end_ns or now
    if events:
        ts_vals = [_ms_to_ns(e.get("timestamp")) for e in events]
        ts_vals = [t for t in ts_vals if t is not None]
        if ts_vals:
            root_start = min([root_start] + ts_vals) if run_start_ns else min(ts_vals)
            root_end = max([root_end] + ts_vals) if run_end_ns else max(ts_vals)
    if root_end < root_start:
        root_end = root_start

    root_id = _hex_id(8)
    spans: list[dict[str, Any]] = []

    # Group by message/step. We treat each step_finish as an LLM span boundary.
    # step_start gives start; step_finish gives end+tokens. Tool events between
    # are child spans.
    steps: list[dict[str, Any]] = []
    current_step: dict[str, Any] | None = None

    for ev in events:
        etype = ev.get("type")
        part = ev.get("part") or {}
        ts = _ms_to_ns(ev.get("timestamp"))
        if etype == "step_start":
            if current_step is not None:
                steps.append(current_step)
            current_step = {
                "start_ns": ts,
                "end_ns": ts,
                "message_id": part.get("messageID") or part.get("messageId") or "",
                "tools": [],
                "texts": [],
                "finish": None,
            }
        elif etype in ("tool_use", "tool"):
            tool = {
                "tool": part.get("tool") or ev.get("tool") or "unknown",
                "call_id": part.get("id") or part.get("callID") or part.get("toolCallID") or "",
                "status": "",
                "start_ns": ts,
                "end_ns": ts,
                "input": None,
                "output": None,
                "error": None,
            }
            state = part.get("state") or {}
            if isinstance(state, dict):
                tool["status"] = str(state.get("status") or "")
                t = state.get("time") or {}
                if isinstance(t, dict):
                    tool["start_ns"] = _ms_to_ns(t.get("start")) or ts
                    tool["end_ns"] = _ms_to_ns(t.get("end")) or ts
                if include_content:
                    tool["input"] = _sanitize_attr_value("input", state.get("input"), True)
                    tool["output"] = _sanitize_attr_value("output", state.get("output"), True)
            err = part.get("error") or (state.get("error") if isinstance(state, dict) else None)
            if err and include_content:
                tool["error"] = _sanitize_attr_value("error", err, True)
            elif err:
                tool["error"] = "[REDACTED]"
            if current_step is None:
                current_step = {"start_ns": ts, "end_ns": ts, "message_id": part.get("messageID") or "", "tools": [], "texts": [], "finish": None}
            current_step["tools"].append(tool)
            if ts and (current_step["end_ns"] is None or ts > current_step["end_ns"]):
                current_step["end_ns"] = ts
        elif etype == "text":
            if current_step is None:
                current_step = {"start_ns": ts, "end_ns": ts, "message_id": part.get("messageID") or "", "tools": [], "texts": [], "finish": None}
            if include_content:
                text_val = part.get("text")
                if isinstance(text_val, str):
                    current_step["texts"].append(_redact_text(text_val))
            if ts and (current_step["end_ns"] is None or ts > current_step["end_ns"]):
                current_step["end_ns"] = ts
        elif etype == "step_finish":
            if current_step is None:
                current_step = {"start_ns": ts, "end_ns": ts, "message_id": part.get("messageID") or "", "tools": [], "texts": [], "finish": None}
            current_step["finish"] = part
            if ts:
                current_step["end_ns"] = ts
            steps.append(current_step)
            current_step = None
        else:
            # keep unknown events from extending root timing only through ts_vals above
            pass

    if current_step is not None:
        steps.append(current_step)

    total_input = total_output = total_reasoning = total_cache_read = total_cache_write = 0
    total_cost = 0.0
    tool_count = 0
    tool_errors = 0

    for i, step in enumerate(steps):
        step_start = step.get("start_ns") or root_start
        step_end = step.get("end_ns") or step_start
        finish = step.get("finish") or {}
        tokens = finish.get("tokens") or {}
        cache = tokens.get("cache") or {} if isinstance(tokens, dict) else {}
        inp = _as_int(tokens.get("input")) if isinstance(tokens, dict) else None
        outp = _as_int(tokens.get("output")) if isinstance(tokens, dict) else None
        reasoning = _as_int(tokens.get("reasoning")) if isinstance(tokens, dict) else None
        cache_read = _as_int(cache.get("read")) if isinstance(cache, dict) else None
        cache_write = _as_int(cache.get("write")) if isinstance(cache, dict) else None
        cost = finish.get("cost")
        try:
            cost_f = float(cost) if cost is not None else None
        except Exception:
            cost_f = None
        if inp: total_input += inp
        if outp: total_output += outp
        if reasoning: total_reasoning += reasoning
        if cache_read: total_cache_read += cache_read
        if cache_write: total_cache_write += cache_write
        if cost_f: total_cost += cost_f

        llm_span_id = _hex_id(8)
        llm_attrs: dict[str, Any] = {
            "factory.run_id": run_id,
            "factory.kind": kind,
            "factory.step_index": i,
            "gen_ai.operation.name": "chat",
            "gen_ai.provider.name": "opencode",
        }
        if model:
            llm_attrs["gen_ai.request.model"] = model
            llm_attrs["gen_ai.response.model"] = model
        if session_id:
            llm_attrs["session.id"] = session_id
        if inp is not None:
            llm_attrs["gen_ai.usage.input_tokens"] = inp
        if outp is not None:
            llm_attrs["gen_ai.usage.output_tokens"] = outp
        if reasoning is not None:
            llm_attrs["gen_ai.usage.reasoning_tokens"] = reasoning
        if cache_read is not None:
            llm_attrs["gen_ai.usage.cache_read_tokens"] = cache_read
        if cache_write is not None:
            llm_attrs["gen_ai.usage.cache_write_tokens"] = cache_write
        if cost_f is not None:
            llm_attrs["gen_ai.usage.cost_usd"] = cost_f
        if finish.get("reason"):
            llm_attrs["gen_ai.response.finish_reasons"] = [str(finish.get("reason"))]
        if include_content and step.get("texts"):
            llm_attrs["output.value"] = "\n".join(step["texts"])[:4000]

        spans.append(_span(
            trace_id=trace_id,
            span_id=llm_span_id,
            parent_span_id=root_id,
            name="opencode.llm.step",
            start_ns=step_start,
            end_ns=step_end,
            kind=3,  # CLIENT
            attributes=llm_attrs,
        ))

        for tool in step.get("tools", []):
            tool_count += 1
            status = str(tool.get("status") or "unknown")
            is_err = status == "error" or bool(tool.get("error"))
            if is_err:
                tool_errors += 1
            t_attrs: dict[str, Any] = {
                "factory.run_id": run_id,
                "factory.kind": kind,
                "gen_ai.operation.name": "execute_tool",
                "gen_ai.tool.name": str(tool.get("tool") or "unknown"),
                "tool.status": status,
            }
            call_id = tool.get("call_id")
            if call_id:
                t_attrs["gen_ai.tool.call.id"] = str(call_id)
            if include_content and tool.get("input") is not None:
                t_attrs["tool.input"] = json.dumps(tool["input"], ensure_ascii=False)[:4000]
            if include_content and tool.get("output") is not None:
                outv = tool["output"]
                t_attrs["tool.output"] = outv if isinstance(outv, str) else json.dumps(outv, ensure_ascii=False)
                t_attrs["tool.output"] = str(t_attrs["tool.output"])[:4000]
            if tool.get("error"):
                t_attrs["error.message"] = str(tool["error"])[:1000]
            spans.append(_span(
                trace_id=trace_id,
                span_id=_hex_id(8),
                parent_span_id=llm_span_id,
                name=f"execute_tool {t_attrs['gen_ai.tool.name']}",
                start_ns=tool.get("start_ns") or step_start,
                end_ns=tool.get("end_ns") or step_end,
                kind=1,  # INTERNAL
                attributes=t_attrs,
                status_code=2 if is_err else 1,
                status_message=str(tool.get("error") or "")[:500] if is_err else "",
            ))

    root_attrs: dict[str, Any] = {
        "factory.run_id": run_id,
        "factory.kind": kind,
        "factory.outcome": outcome,
        "service.name": "factory-tick",
    }
    if session_id:
        root_attrs["session.id"] = session_id
    if agent_id:
        root_attrs["factory.agent_id"] = agent_id
    if model:
        root_attrs["gen_ai.request.model"] = model
    if repo:
        root_attrs["factory.repo"] = repo
    if issue_id not in (None, ""):
        root_attrs["factory.issue_id"] = str(issue_id)
    if pr_number not in (None, ""):
        root_attrs["factory.pr_number"] = str(pr_number)
    if attempt not in (None, ""):
        try:
            root_attrs["factory.attempt"] = int(attempt)  # type: ignore[arg-type]
        except Exception:
            root_attrs["factory.attempt"] = str(attempt)
    if fallback_level:
        root_attrs["factory.fallback_level"] = fallback_level
    if failure_reason:
        root_attrs["factory.failure_reason"] = failure_reason
    if total_input:
        root_attrs["gen_ai.usage.input_tokens"] = total_input
    if total_output:
        root_attrs["gen_ai.usage.output_tokens"] = total_output
    if total_reasoning:
        root_attrs["gen_ai.usage.reasoning_tokens"] = total_reasoning
    if total_cache_read:
        root_attrs["gen_ai.usage.cache_read_tokens"] = total_cache_read
    if total_cache_write:
        root_attrs["gen_ai.usage.cache_write_tokens"] = total_cache_write
    if total_cost:
        root_attrs["gen_ai.usage.cost_usd"] = total_cost
    if tool_count:
        root_attrs["factory.tool_calls"] = tool_count
    if tool_errors:
        root_attrs["factory.tool_errors"] = tool_errors
    root_attrs["factory.step_count"] = len(steps)

    root_status = 2 if outcome == "failed" else 1
    spans.insert(0, _span(
        trace_id=trace_id,
        span_id=root_id,
        parent_span_id=None,
        name="factory.agent.run",
        start_ns=root_start,
        end_ns=root_end,
        kind=1,
        attributes=root_attrs,
        status_code=root_status,
        status_message=failure_reason if outcome == "failed" else "",
    ))
    return spans


def build_otlp_payload(
    spans: list[dict[str, Any]],
    *,
    service_name: str = "factory-tick",
    resource_attributes: dict[str, Any] | None = None,
) -> dict[str, Any]:
    res_attrs = {"service.name": service_name}
    if resource_attributes:
        res_attrs.update(resource_attributes)
    return {
        "resourceSpans": [
            {
                "resource": {"attributes": _attrs(res_attrs)},
                "scopeSpans": [
                    {
                        "scope": {"name": "booking-system.factory", "version": "prompt-05"},
                        "spans": spans,
                    }
                ],
            }
        ]
    }


def export_otlp_http(
    payload: dict[str, Any],
    *,
    endpoint: str,
    timeout_s: float = 10.0,
    headers: dict[str, str] | None = None,
) -> tuple[bool, str]:
    url = endpoint.rstrip("/")
    if not url.endswith("/v1/traces"):
        url = url + "/v1/traces"
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return 200 <= resp.status < 300, f"http {resp.status}: {body[:200]}"
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace") if hasattr(e, "read") else str(e)
        return False, f"http {e.code}: {body[:200]}"
    except Exception as e:
        return False, str(e)


def export_run_trace(
    *,
    trace_id: str,
    run_id: str,
    endpoint: str,
    stream_text: str = "",
    metadata: dict[str, Any] | None = None,
    timeout_s: float = 10.0,
    headers: dict[str, str] | None = None,
) -> tuple[bool, str]:
    md = metadata or {}
    spans = build_run_spans(
        trace_id=trace_id,
        run_id=run_id,
        session_id=str(md.get("session_id") or ""),
        kind=str(md.get("kind") or ""),
        agent_id=str(md.get("agent_id") or ""),
        model=str(md.get("model") or ""),
        repo=str(md.get("repo") or ""),
        issue_id=md.get("issue_id"),
        pr_number=md.get("pr_number"),
        attempt=md.get("attempt"),
        fallback_level=str(md.get("fallback_level") or ""),
        outcome=str(md.get("outcome") or ""),
        failure_reason=str(md.get("failure_reason") or ""),
        stream_text=stream_text,
        run_start_ns=_as_int(md.get("start_ns")),
        run_end_ns=_as_int(md.get("end_ns")),
        include_content=_content_allowed() if md.get("include_content") is None else bool(md.get("include_content")),
    )
    resource_attrs = {}
    for k in ("deployment.environment", "host.name", "factory_id"):
        v = md.get(k)
        if v:
            resource_attrs[k] = str(v)
    payload = build_otlp_payload(spans, service_name="factory-tick", resource_attributes=resource_attrs)
    return export_otlp_http(payload, endpoint=endpoint, timeout_s=timeout_s, headers=headers)
