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
    m, b = factory.model_for_labels(entries, ["light-build-task", "heavy-build-task"])
    # first in insertion order wins only if present; heavy first in dict order
    assert m == "heavy"
    m2, b2 = factory.model_for_labels(entries, ["light-build-task"])
    assert m2 == "light"
    m3, b3 = factory.model_for_labels(entries, [])
    assert m3 == "def"

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
    assert e["schema_version"] == 1
    assert e["event"] == "tick_start"
    assert e["foo"] == "bar"


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
         "statusCheckRollup": [], "createdAt": "2026-01-01", "number": 10},
        {"isDraft": True, "headRefName": "factory/issue-2", "headRefOid": "def",
         "reviewDecision": "", "mergeable": "", "statusCheckRollup": [], "createdAt": "x", "number": 11},
    ]
    rows = factory.fix_candidates_from_prs(prs)
    assert len(rows) == 1
    assert rows[0][1] == 10
    assert "changes-requested" in rows[0][4]

def test_prioritize_issues():
    issues = [{"number": 2, "createdAt": "b"}, {"number": 1, "createdAt": "a"}]
    prio = {1: ("2026", 1, 5.0)}
    out = factory.prioritize_issues(issues, prio)
    assert out == [1, 2]

def test_has_marker_comments():
    comments = [{"body": "x <!-- factory:plan --> y"}]
    assert factory.has_marker_comments(comments, "<!-- factory:plan -->")


def test_classify_git_and_permission():
    assert factory.classify_git_error("permission denied 403") == "permission"
    assert factory.classify_gh_error("rate limit exceeded") == "rate_limit"
    assert factory.classify_gh_error("connection timeout") == "transient"


def test_event_schema_and_fields():
    e = factory.make_event("tick_result", "t", False, "backup", "dev", "host", result="ok", fix_failures=0)
    assert e["schema_version"] == 1
    assert e["result"] == "ok"
    assert e["fix_failures"] == 0

def test_usage_filled_reason():
    filled, reason = factory.is_usage_filled("quota exceeded now")
    assert filled
    assert reason

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
