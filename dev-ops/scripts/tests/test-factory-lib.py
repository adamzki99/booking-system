import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "factory", "lib"))
import factory

def test_normalize_beam_free():
    assert factory.normalize_model("opencode-go/beam-free") == "opencode-go/beam-free#high"
    assert factory.normalize_model("") == ""
    assert factory.normalize_model("opencode-go/x") == "opencode-go/x"

def test_validate_models_ok():
    cfg = {"labels": {"default": {"model": "m", "backup_model": "b"}}}
    assert factory.validate_models(cfg) is True

def test_validate_models_missing_default():
    try:
        factory.validate_models({"labels": {"a": {"model": "m"}}})
    except ValueError:
        return
    raise AssertionError("expected ValueError")

def test_model_for_labels_priority():
    entries = {
        "heavy-build-task": {"model": "heavy", "backup_model": "hb"},
        "light-build-task": {"model": "light", "backup_model": "lb"},
        "default": {"model": "def", "backup_model": "db"},
    }
    m, b, t = factory.model_for_labels(entries, ["light-build-task", "heavy-build-task"])
    # first in insertion order wins only if present; heavy first in dict order
    assert m == "heavy"
    assert t == "heavy-build-task"
    m2, b2, t2 = factory.model_for_labels(entries, ["light-build-task"])
    assert m2 == "light"
    assert t2 == "light-build-task"
    m3, b3, t3 = factory.model_for_labels(entries, [])
    assert m3 == "def"
    assert t3 == "default"

def test_classify_gh():
    assert factory.classify_gh_error("HTTP 401 Unauthorized") == "auth"
    assert factory.classify_gh_error("rate limit exceeded") == "rate_limit"
    assert factory.classify_gh_error("connection timeout") == "transient"
    assert factory.classify_gh_error("not found") == "not_found"

def test_usage_filled():
    filled, reason = factory.is_usage_filled("Error: usage limit reached")
    assert filled and reason
    filled2, _ = factory.is_usage_filled("all good")
    assert not filled2

def test_make_event_schema():
    e = factory.make_event("tick_start", "abc", False, "backup", "dev", "host", foo="bar")
    assert e["schema_version"] == 2
    assert e["event"] == "tick_start"
    assert e["event_id"]
    assert e["factory_id"] == "factory-1"
    assert e["deployment.environment"] == "dev"
    assert e["foo"] == "bar"


def test_make_event_typed_coercion():
    e = factory.make_event("tick_end", "abc", True, "backup", "prod", "host",
                           exit_code="1", duration_ms="42",
                           cost_usd="1.5", attempt="3", skills_loaded="a,b",
                           area_labels='["x","y"]')
    assert e["schema_version"] == 2
    assert e["exit_code"] == 1
    assert e["duration_ms"] == 42
    assert e["dry_run"] is True
    assert e["deployment.environment"] == "prod"
    assert e["cost_usd"] == 1.5
    assert e["attempt"] == 3
    assert e["skills_loaded"] == ["a", "b"]
    assert e["area_labels"] == ["x", "y"]


def test_emit_cli_reports_unwritable_log(tmp_path):
    logfile = tmp_path / "missing" / "tick.jsonl"
    argv = [
        "factory.py", "emit", "tick_start", str(logfile), "tick", "0",
        "backup", "dev", "host", "factory-1", "owner/repo",
    ]
    assert factory._emit_cli(argv) != 0


def test_validate_invalid_missing_model():
    try:
        factory.validate_models({"labels": {"default": {}}})
    except ValueError:
        return
    raise AssertionError("expected ValueError")

def test_usage_reason_output():
    filled, reason = factory.is_usage_filled("boom usage limit now")
    assert filled
    assert "usage" in reason or "limit" in reason


def test_fix_candidates_from_prs():
    prs = [
        {"isDraft": False, "headRefName": "factory/issue-1", "headRefOid": "abc",
         "reviewDecision": "CHANGES_REQUESTED", "mergeable": "MERGEABLE",
         "statusCheckRollup": [], "createdAt": "2026-01-01", "number": 10,
         "isCrossRepository": False, "author": {"login": "owner"},
         "headRepositoryOwner": {"login": "owner"}},
        {"isDraft": True, "headRefName": "factory/issue-2", "headRefOid": "def",
         "reviewDecision": "", "mergeable": "", "statusCheckRollup": [], "createdAt": "x", "number": 11,
         "isCrossRepository": False, "author": {"login": "owner"},
         "headRepositoryOwner": {"login": "owner"}},
    ]
    rows = factory.fix_candidates_from_prs(prs, {"owner"}, "owner")
    assert len(rows) == 1
    assert rows[0][1] == 10
    assert "changes-requested" in rows[0][4]


def test_fix_candidates_require_explicit_same_repo_trust():
    def candidate(number, **overrides):
        pr = {
            "isDraft": False,
            "headRefName": f"factory/issue-{number}",
            "headRefOid": f"sha-{number}",
            "reviewDecision": "CHANGES_REQUESTED",
            "mergeable": "MERGEABLE",
            "statusCheckRollup": [],
            "createdAt": f"2026-01-{number:02d}",
            "number": number,
            "isCrossRepository": False,
            "author": {"login": "owner"},
            "headRepositoryOwner": {"login": "owner"},
        }
        pr.update(overrides)
        return pr

    prs = [
        candidate(1),
        candidate(2, isCrossRepository=True),
        candidate(3, author={"login": "outsider"}),
        candidate(4, headRepositoryOwner={"login": "fork-owner"}),
        candidate(5, isCrossRepository=None),
        candidate(6, author=None),
        candidate(7, headRepositoryOwner=None),
    ]

    rows = factory.fix_candidates_from_prs(prs, {"OWNER"}, "OWNER")

    assert [row[1] for row in rows] == [1]


def test_filter_trusted_issues_fails_closed():
    issues = [
        {"number": 1, "author": {"login": "Owner"}},
        {"number": 2, "author": {"login": "outsider"}},
        {"number": 3, "author": None},
        None,
    ]

    assert factory.parse_trusted_logins(" Owner, factory-bot\n") == {"owner", "factory-bot"}
    assert factory.parse_trusted_logins("") == set()
    assert factory.trusted_logins_from_env({}) == set()
    assert factory.trusted_logins_from_env({
        "FACTORY_TRUSTED_LOGINS": "Owner, reviewer",
        "FACTORY_LOGIN": "Factory-Bot",
    }) == {"owner", "reviewer", "factory-bot"}
    assert [issue["number"] for issue in factory.filter_trusted_issues(issues, "owner")] == [1]
    assert factory.filter_trusted_issues(issues, "") == []
    assert not factory.is_trusted_login(None, "none")


def test_filter_trusted_issues_accepts_rest_user_field():
    issues = [
        {"number": 1, "user": {"login": "Owner"}},
        {"number": 2, "user": {"login": "outsider"}},
        {"number": 3, "user": None},
        {"number": 4, "author": {"login": "outsider"}, "user": {"login": "Owner"}},
    ]

    assert [issue["number"] for issue in factory.filter_trusted_issues(issues, "owner")] == [1]
    assert factory.filter_trusted_issues(issues, "") == []


def test_build_prompt_context_only_trusted_comments():
    comments = [
        {"author": {"login": "OWNER"}, "createdAt": "2026-01-01", "body": "owner guidance"},
        {"author": {"login": "outsider"}, "createdAt": "2026-01-02", "body": "outsider injection"},
        {"author": None, "body": "deleted author text"},
    ]

    context = factory.build_prompt_context("issue body", comments, "owner,factory-bot")

    assert "issue body" in context
    assert "owner guidance" in context
    assert "--- Comment by OWNER at 2026-01-01 ---" in context
    assert "outsider injection" not in context
    assert "deleted author text" not in context
    assert factory.build_prompt_context("issue body", comments, "") == "issue body"


def test_prioritize_issues():
    issues = [{"number": 2, "createdAt": "b"}, {"number": 1, "createdAt": "a"}]
    prio = {1: ("2026", 1, 5.0)}
    out = factory.prioritize_issues(issues, prio)
    assert out == [1, 2]

def test_has_marker_comments():
    comments = [{"body": "x <!-- factory:plan --> y"}]
    assert factory.has_marker_comments(comments, "<!-- factory:plan -->")


def test_has_marker_comments_filters_author():
    marker = "<!-- factory:plan -->"
    comments = [
        {"author": {"login": "owner"}, "body": marker},
        {"author": {"login": "factory-bot"}, "body": "no marker"},
        {"author": {"login": "factory-bot"}, "body": marker},
    ]
    assert factory.has_marker_comments(comments, marker, "factory-bot")
    assert not factory.has_marker_comments(comments, marker, "another-bot")
    assert not factory.has_marker_comments(comments, marker, "")


def test_classify_git_and_permission():
    assert factory.classify_git_error("permission denied 403") == "permission"
    assert factory.classify_gh_error("rate limit exceeded") == "rate_limit"
    assert factory.classify_gh_error("connection timeout") == "transient"


def test_event_schema_and_fields():
    e = factory.make_event("tick_result", "t", False, "backup", "dev", "host", result="ok", fix_failures=0)
    assert e["schema_version"] == 2
    assert e["event_id"]
    assert e["result"] == "ok"
    assert e["fix_failures"] == 0


def test_validate_event_v2_and_rejects_v3():
    e = factory.make_event("x", "tick1", True, "skip", "prod", "h", attempt=2)
    assert factory.validate_event(e) is True
    assert e["schema_version"] == factory.SCHEMA_VERSION
    assert e["dry_run"] is True
    assert e["attempt"] == 2
    try:
        factory.validate_event({"event": "x"})
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError for missing fields")
    # v3 must be rejected
    try:
        factory.validate_event(dict(e, schema_version=3))
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError for schema_version 3")
    # non-int schema_version rejected
    try:
        factory.validate_event(dict(e, schema_version="2"))
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError for string schema_version")

def test_usage_filled_reason():
    filled, reason = factory.is_usage_filled("quota exceeded now")
    assert filled
    assert reason


def test_usage_filled_from_structured_error():
    samples = [
        '{"type":"error","error":{"type":"provider.error","message":"request failed","status":429}}',
        '{"type":"error","error":{"type":"provider.go-limit","status":429}}',
        '{"type":"error","error":{"type":"provider.error","message":"payment required","status":402}}',
    ]
    for text in samples:
        filled, reason = factory.is_usage_filled(text)
        assert filled and reason, text
    filled, _ = factory.is_usage_filled(
        '{"type":"error","error":{"type":"provider.error","message":"request failed","status":500}}'
    )
    assert not filled

def test_classify_matrix():
    assert factory.classify_gh_error("HTTP 404 not found") == "not_found"
    assert factory.classify_gh_error("") == "empty"
    assert factory.classify_gh_error("permission denied 403") == "permission"


def test_changed_files_zero_is_empty_and_never_merge_ready():
    # A PR with changedFiles: 0 is empty. There is deliberately no merge-ready
    # verdict, so an empty PR can never be classified as mergeable.
    verdict = factory.classify_pr_changes(0)
    assert verdict == "empty"
    assert verdict != "changes"
    assert "merge" not in verdict


def test_classify_pr_changes_matrix():
    assert factory.classify_pr_changes(3) == "changes"
    assert factory.classify_pr_changes(-1) == "unknown"
    assert factory.classify_pr_changes(None) == "unknown"
    assert factory.classify_pr_changes("") == "unknown"
    assert factory.classify_pr_changes("abc") == "unknown"
    assert factory.classify_pr_changes(True) == "unknown"


def test_classify_pr_changes_cli():
    import subprocess
    script = os.path.join(os.path.dirname(__file__), "..", "..", "factory", "lib", "factory.py")
    out = subprocess.check_output([sys.executable, script, "classify-pr-changes", "0"], text=True).strip()
    assert out == "empty"
    out = subprocess.check_output([sys.executable, script, "classify-pr-changes", "abc"], text=True).strip()
    assert out == "unknown"


def test_classify_extended_and_retry_decisions():
    assert factory.classify_gh_error("Bad credentials") == "auth"
    assert factory.classify_gh_error("abuse detection mechanism") == "rate_limit"
    assert factory.classify_gh_error("502 Bad Gateway") == "transient"
    assert factory.classify_gh_error("repository not found") == "not_found"
    assert factory.classify_git_error("Authentication failed for https://...") == "auth"
    assert factory.classify_git_error("Could not resolve host: github.com") == "transient"
    assert factory.should_retry_category("transient") is True
    assert factory.should_retry_category("rate_limit") is True
    assert factory.should_retry_category("auth") is False
    assert factory.should_retry_category("other") is False


def test_validate_event_fields_and_make_event():
    e = factory.make_event("x", "tick1", True, "skip", "prod", "h", attempt=2)
    assert factory.validate_event(e) is True
    assert e["schema_version"] == factory.SCHEMA_VERSION
    assert e["dry_run"] is True
    assert e["attempt"] == 2
    try:
        factory.validate_event({"event": "x"})
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError for missing fields")


def test_validate_models_rejects_unknown_and_empty_backup():
    cfg = {"labels": {"default": {"model": "m", "backup_model": "b"}}}
    assert factory.validate_models(cfg) is True
    try:
        factory.validate_models({"labels": {"default": {"model": "m"}}, "extra": 1})
    except ValueError:
        pass
    else:
        raise AssertionError("expected unknown top-level key rejection")
    try:
        factory.validate_models({"labels": {"default": {"model": "m", "backup_model": ""}}})
    except ValueError:
        pass
    else:
        raise AssertionError("expected empty backup_model rejection")


def test_claim_acquire_release_and_ttl():
    import tempfile, time, os
    with tempfile.TemporaryDirectory() as d:
        claim = os.path.join(d, "c.claim")
        now = int(time.time())
        ok, state, _ = factory.acquire_claim(claim, 7200, now, "123", pid_alive_fn=lambda p: True)
        assert ok and state == "acquired"
        ok2, state2, detail = factory.acquire_claim(claim, 7200, now + 1, "124", pid_alive_fn=lambda p: str(p) == "123")
        assert (not ok2) and state2 == "active"
        assert detail == "123"
        # stale by ttl
        stale_claim = os.path.join(d, "s.claim")
        os.mkdir(stale_claim)
        with open(os.path.join(stale_claim, "pid"), "w") as f:
            f.write("999")
        old = now - 10000
        os.utime(stale_claim, (old, old))
        ok3, state3, _ = factory.acquire_claim(stale_claim, 60, now, "125", pid_alive_fn=lambda p: False)
        assert ok3 and state3 == "acquired"
        assert factory.release_claim(stale_claim) is True
        assert factory.release_claim(stale_claim) is True  # idempotent


def test_claim_dead_pid_treated_stale_within_ttl():
    import tempfile, time, os
    with tempfile.TemporaryDirectory() as d:
        claim = os.path.join(d, "d.claim")
        os.mkdir(claim)
        with open(os.path.join(claim, "pid"), "w") as f:
            f.write("777")
        now = int(time.time())
        ok, state, _ = factory.acquire_claim(claim, 7200, now, "888", pid_alive_fn=lambda p: False)
        assert ok and state == "acquired"


# ---------------------------------------------------------------------------
# session-id parsing (F-01)
# ---------------------------------------------------------------------------

FIXTURE_DIR = os.path.join(os.path.dirname(__file__), "fixtures")


def _fixture(name):
    return os.path.join(FIXTURE_DIR, name)


def test_session_id_from_fixture():
    path = _fixture("opencode-stream-v2.3.2.jsonl")
    assert os.path.isfile(path), f"fixture not found: {path}"
    with open(path, "r", encoding="utf-8") as f:
        sid = factory.session_id_from_stream(f.read())
    assert sid == "ses_sanitized-example"


def test_session_id_from_stream_malformed_tolerant():
    bad = 'not json at all\n{"type":"step_start","sessionID":"ses_abc"}\n{broken\n'
    assert factory.session_id_from_stream(bad) == "ses_abc"
    assert factory.session_id_from_stream("garbage only") is None
    assert factory.session_id_from_stream("") is None


def test_session_id_cli(tmp_path):
    p = tmp_path / "stream.jsonl"
    p.write_text('{"type":"step_start","sessionID":"ses_cli-1"}\n', encoding="utf-8")
    import subprocess, sys
    script = os.path.join(os.path.dirname(__file__), "..", "..", "factory", "lib", "factory.py")
    out = subprocess.check_output([sys.executable, script, "session-id", str(p)], text=True).strip()
    assert out == "ses_cli-1"


# ---------------------------------------------------------------------------
# usage / tool parsing (fixture plus malformed stream)
# ---------------------------------------------------------------------------

def test_parse_opencode_stream_from_fixture():
    path = _fixture("opencode-stream-v2.3.2.jsonl")
    with open(path, "r", encoding="utf-8") as f:
        d = factory.parse_opencode_stream(f.read())
    assert d["session_id"] == "ses_sanitized-example"
    assert d["steps"] == 2
    assert d["tool_calls"] == 1
    assert d["input_tokens"] == 2937  # 25 + 2912
    assert d["output_tokens"] == 44   # 25 + 19
    assert d["reasoning_tokens"] == 48  # 27 + 21
    assert d["cache_read_tokens"] == 6656  # 4736 + 1920
    assert d.get("cost_usd", 0.0) == 0.0


def test_parse_opencode_stream_malformed_never_crashes():
    assert factory.parse_opencode_stream("garbage\n{not json\n") == {}
    assert factory.parse_opencode_stream("") == {}
    assert factory.parse_opencode_stream(None) == {}


def test_parse_opencode_stream_tool_error_and_skills():
    text = (
        '{"type":"tool_use","part":{"type":"tool","state":{"status":"error"},"error":"boom"}}\n'
        '{"type":"text","text":"loading the implement skill now"}\n'
        '{"type":"step_finish","part":{"tokens":{"input":1,"output":2,"reasoning":3,"cache":{"read":4,"write":5}},"cost":0.5}}\n'
    )
    d = factory.parse_opencode_stream(text)
    assert d["tool_calls"] == 1
    assert d["tool_errors"] == 1
    assert d["skills_loaded"] == ["implement"]
    assert d["steps"] == 1
    assert d["input_tokens"] == 1
    assert d["cost_usd"] == 0.5


def test_parse_opencode_stream_reports_provider_error_without_raw_message():
    text = (
        '{"type":"step_start","sessionID":"ses_limit","part":{"id":"prt_1"}}\n'
        '{"type":"error","sessionID":"ses_limit","error":{"type":"provider.go-limit","message":"monthly usage limit reached","status":429}}\n'
    )
    d = factory.parse_opencode_stream(text)
    assert d["session_id"] == "ses_limit"
    assert d["error_type"] == "provider.go-limit"
    assert d["error_status"] == 429
    assert "monthly usage limit reached" not in d.values()


# ---------------------------------------------------------------------------
# failure_reason classification (F-08)
# ---------------------------------------------------------------------------

def test_classify_failure_matrix():
    assert factory.classify_failure("timed out after 3600s", 124) == "timeout"
    assert factory.classify_failure("usage limit reached", 1) == "usage_filled"
    assert factory.classify_failure("some error", 1) == "exit_nonzero"
    assert factory.classify_failure("interrupted by user", 130) == "interrupted"
    assert factory.classify_failure("opencode panic: boom", 1) == "opencode_error"
    assert factory.classify_failure("opencode error: failed", 255) == "opencode_error"


def test_error_fingerprint_deterministic_and_short():
    fp = factory.error_fingerprint("Error: something went wrong here\n")
    assert fp is not None
    assert len(fp) == 12
    assert factory.error_fingerprint("Error: something went wrong here\n") == fp
    assert factory.error_fingerprint("") is None
    assert factory.error_fingerprint(None) is None


# ---------------------------------------------------------------------------
# deterministic agent_version hashing
# ---------------------------------------------------------------------------

def test_agent_version_deterministic(tmp_path, monkeypatch):
    import os as _os
    agents = tmp_path / ".opencode" / "agents"
    agents.mkdir(parents=True)
    (agents / "planner.md").write_text("prompt v1 content", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    v1 = factory.agent_version_for("planner")
    assert v1 is not None and len(v1) == 12
    assert factory.agent_version_for("planner") == v1
    # different content -> different version
    (agents / "planner.md").write_text("prompt v2 content", encoding="utf-8")
    assert factory.agent_version_for("planner") != v1
    assert factory.agent_version_for("missing-agent") is None


# ---------------------------------------------------------------------------
# tool call parsing and trace id (event model v2)
# ---------------------------------------------------------------------------

def test_parse_tool_calls_from_fixture():
    path = _fixture("opencode-stream-v2.3.2.jsonl")
    with open(path, "r", encoding="utf-8") as f:
        calls = factory.parse_tool_calls(f.read())
    assert len(calls) == 1
    assert calls[0]["tool"] == "glob"
    assert calls[0]["status"] == "completed"
    assert calls[0]["duration_ms"] == 138


def test_parse_tool_calls_malformed_and_skill():
    text = (
        'garbage\n'
        '{"type":"tool_use","part":{"tool":"skill","state":{"status":"completed","input":{"name":"tdd"}},"time":{"start":1,"end":2}}}\n'
        '{"type":"tool_use","part":{"tool":"bash","state":{"status":"error"},"error":"boom"}}\n'
    )
    calls = factory.parse_tool_calls(text)
    assert len(calls) == 2
    assert calls[0]["tool"] == "skill"
    assert calls[0]["skill_name"] == "tdd"
    assert calls[1]["tool"] == "bash"
    assert calls[1]["status"] == "error"


def test_new_trace_id_format():
    tid = factory.new_trace_id()
    assert isinstance(tid, str)
    assert len(tid) == 32
    int(tid, 16)  # hex
    assert factory.new_trace_id() != tid


# ---------------------------------------------------------------------------
# trace export (prompt 05, option c)
# ---------------------------------------------------------------------------

def test_build_run_spans_from_fixture():
    import factory_trace
    path = _fixture("opencode-stream-v2.3.2.jsonl")
    with open(path, "r", encoding="utf-8") as f:
        stream = f.read()
    spans = factory_trace.build_run_spans(
        trace_id="0123456789abcdef0123456789abcdef",
        run_id="run-1",
        session_id="ses_sanitized-example",
        kind="build",
        agent_id="builder",
        model="test/model",
        repo="owner/repo",
        issue_id=42,
        pr_number=7,
        attempt=1,
        fallback_level="primary",
        outcome="completed",
        stream_text=stream,
        include_content=False,
    )
    assert spans, "expected spans"
    root = spans[0]
    assert root["name"] == "factory.agent.run"
    assert root["traceId"] == "0123456789abcdef0123456789abcdef"
    attrs = {a["key"]: a["value"] for a in root["attributes"]}
    assert attrs["factory.run_id"]["stringValue"] == "run-1"
    assert attrs["factory.kind"]["stringValue"] == "build"
    assert attrs["factory.outcome"]["stringValue"] == "completed"
    # child spans include LLM steps and tool call
    names = [s["name"] for s in spans]
    assert "opencode.llm.step" in names
    assert any(n.startswith("execute_tool ") for n in names)
    # all spans share the same trace id
    assert {s["traceId"] for s in spans} == {"0123456789abcdef0123456789abcdef"}
    # tool span has tool name but no content by default
    tool_spans = [s for s in spans if s["name"].startswith("execute_tool ")]
    assert tool_spans
    tool_attrs = {a["key"]: a["value"] for a in tool_spans[0]["attributes"]}
    assert tool_attrs["gen_ai.tool.name"]["stringValue"] == "glob"
    assert "tool.input" not in tool_attrs
    assert "tool.output" not in tool_attrs


def test_build_run_spans_no_content_by_default(monkeypatch):
    import factory_trace
    monkeypatch.delenv("FACTORY_TRACE_CONTENT", raising=False)
    stream = '{"type":"tool_use","timestamp":1,"sessionID":"s","part":{"tool":"bash","state":{"status":"completed","input":{"command":"echo secret-token"},"output":"secret-token","time":{"start":1,"end":2}}}}\n{"type":"step_finish","timestamp":2,"sessionID":"s","part":{"type":"step-finish","reason":"stop","tokens":{"input":1,"output":1},"cost":0}}\n'
    spans = factory_trace.build_run_spans(
        trace_id="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        run_id="r1",
        outcome="completed",
        stream_text=stream,
    )
    tool_spans = [s for s in spans if s["name"].startswith("execute_tool ")]
    tool_attrs = {a["key"]: a["value"] for a in tool_spans[0]["attributes"]}
    assert "tool.input" not in tool_attrs
    assert "tool.output" not in tool_attrs


def test_build_run_spans_includes_content_when_opted_in(monkeypatch):
    import factory_trace
    monkeypatch.setenv("FACTORY_TRACE_CONTENT", "1")
    stream = '{"type":"text","timestamp":1,"sessionID":"s","part":{"text":"hello","messageID":"m","type":"text"}}\n{"type":"step_finish","timestamp":2,"sessionID":"s","part":{"type":"step-finish","reason":"stop","tokens":{"input":1,"output":1},"cost":0}}\n'
    spans = factory_trace.build_run_spans(
        trace_id="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        run_id="r2",
        outcome="completed",
        stream_text=stream,
    )
    llm = [s for s in spans if s["name"] == "opencode.llm.step"][0]
    attrs = {a["key"]: a["value"] for a in llm["attributes"]}
    assert attrs["output.value"]["stringValue"] == "hello"
