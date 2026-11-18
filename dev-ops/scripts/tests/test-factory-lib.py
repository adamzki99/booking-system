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
