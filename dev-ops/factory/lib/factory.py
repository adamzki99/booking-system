"""Factory orchestration helpers (testable, no network)."""

import datetime
import hashlib
import json
import math
import os
import re
import shutil
import sys
import uuid

SCHEMA_VERSION = 2

# JSON type coercion for well-known event fields. tick.sh passes every field
# as a k=v string, so the library coerces the typed ones here so the emitted
# JSONL carries real JSON types (ints, bools, floats, arrays).
_INT_FIELDS = {
    "schema_version",
    "exit_code",
    "duration_ms",
    "attempt",
    "pr_number",
    "issue_id",
    "tool_calls",
    "tool_errors",
    "files_changed",
    "input_tokens",
    "output_tokens",
    "reasoning_tokens",
    "cache_read_tokens",
    "cache_write_tokens",
    "steps",
    "telemetry_errors",
    "fix_failures",
    # reconcile/queue/deploy outcome fields
    "commits",
    "additions",
    "deletions",
    "changed_files",
    "review_comments",
    "human_commits",
    "infant",
    "planned",
    "approved_waiting",
    "in_pr",
    "blocked_pr",
    "needs_info",
}
_FLOAT_FIELDS = {"cost_usd"}
_BOOL_FIELDS = {"dry_run", "draft", "reviewer_is_owner"}
_ARRAY_FIELDS = {"skills_loaded", "area_labels", "failed_checks"}


def normalize_model(model):
    if not model:
        return model
    base = model.split("#", 1)[0]
    if base == "opencode-go/beam-free":
        return "opencode-go/beam-free#high"
    return model


def validate_models(config):
    """Validate models.yaml structure. Raises ValueError on invalid config."""
    if not isinstance(config, dict):
        raise ValueError("models config must be a mapping")
    allowed_top = {"labels"}
    unknown_top = set(config.keys()) - allowed_top
    if unknown_top:
        raise ValueError(f"unknown top-level keys: {sorted(unknown_top)}")
    labels = config.get("labels")
    if not isinstance(labels, dict) or not labels:
        raise ValueError("models config must contain non-empty 'labels' mapping")
    if "default" not in labels:
        raise ValueError("models config must define a 'default' entry")
    allowed_entry = {"model", "backup_model", "backup"}
    for name, cfg in labels.items():
        if not isinstance(name, str) or not name.strip():
            raise ValueError("label names must be non-empty strings")
        if not isinstance(cfg, dict):
            raise ValueError(f"label entry '{name}' must be a mapping")
        unknown = set(cfg.keys()) - allowed_entry
        if unknown:
            raise ValueError(f"label entry '{name}' has unknown keys: {sorted(unknown)}")
        model = cfg.get("model")
        if not isinstance(model, str) or not model.strip():
            raise ValueError(f"label entry '{name}' missing/invalid 'model'")
        backup = cfg.get("backup_model", cfg.get("backup"))
        if backup is not None and (not isinstance(backup, str) or not backup.strip()):
            raise ValueError(f"label entry '{name}' invalid backup_model")
        if "backup_model" in cfg and "backup" in cfg and cfg.get("backup_model") != cfg.get("backup"):
            raise ValueError(f"label entry '{name}' has conflicting backup_model/backup")
    return True


def model_for_labels(entries, have):
    """Return (model, backup, tier_label) for a set of labels."""
    have = set(have or [])
    model = ""
    backup = ""
    tier_label = "default"
    # preserve insertion order (YAML order) for priority
    for name, cfg in (entries or {}).items():
        if name != "default" and name in have and isinstance(cfg, dict):
            model = cfg.get("model") or ""
            backup = cfg.get("backup_model") or cfg.get("backup") or ""
            if model:
                tier_label = name
                break
    if not model:
        default = (entries or {}).get("default") or {}
        model = default.get("model") or ""
        backup = backup or default.get("backup_model") or default.get("backup") or ""
        tier_label = "default"
    if not backup:
        default = (entries or {}).get("default") or {}
        backup = default.get("backup_model") or default.get("backup") or ""
    return model, backup, tier_label


def classify_gh_error(text):
    t = (text or "").lower()
    if "rate limit" in t or "429" in t or "secondary rate" in t or "abuse detection" in t:
        return "rate_limit"
    if "bad credentials" in t or "token" in t and ("invalid" in t or "expired" in t or "revoked" in t):
        return "auth"
    if "auth" in t or "401" in t or "not logged" in t or "gh auth" in t or "authentication" in t:
        return "auth"
    if "forbidden" in t or "permission" in t or "saml" in t or "403" in t:
        return "permission"
    if any(x in t for x in (
        "timeout", "timed out", "connection", "network", "502", "503", "504",
        "econnreset", "econnrefused", "tls", "dns", "ssl", "temporary failure",
        "temporarily unavailable", "service unavailable", "try again", "reset by peer",
        "broken pipe", "unexpected eof", "could not resolve host",
        "failed to connect", "unable to connect", "name or service not known",
        "no address associated", "connection refused", "connection reset",
    )):
        return "transient"
    if "not found" in t or "404" in t or "could not resolve to" in t:
        return "not_found"
    if "conflict" in t or "409" in t or "merge conflict" in t:
        return "conflict"
    if t.strip() == "":
        return "empty"
    return "other"


def classify_git_error(text):
    t = (text or "").lower()
    if "authentication failed" in t or "could not read username" in t or "terminal prompts disabled" in t:
        return "auth"
    if "permission denied" in t and "publickey" in t:
        return "auth"
    if "permission denied" in t or "403" in t:
        return "permission"
    if "repository not found" in t or "does not appear to be a git repository" in t:
        return "not_found"
    return classify_gh_error(text)


def should_retry_category(category):
    return category in ("transient", "rate_limit")


def classify_pr_changes(changed_files):
    """Classify a PR's changedFiles value as empty, changes, or unknown.

    There is deliberately no merge-ready verdict: a PR with no changed files
    can never be classified as mergeable by this function. Missing,
    non-integer, and negative values are unknown so callers fail safe instead
    of acting on data they cannot trust.
    """
    if isinstance(changed_files, bool):
        return "unknown"
    if isinstance(changed_files, int) and changed_files >= 0:
        return "empty" if changed_files == 0 else "changes"
    return "unknown"


QUOTA_PATTERNS = [
    "usage limit", "limit exceeded", "rate limit", "quota",
]


def is_usage_filled(text):
    out = (text or "").lower()
    if "usage limit" in out:
        return True, "usage limit"
    if "limit exceeded" in out:
        return True, "limit exceeded"
    if "rate limit" in out:
        return True, "rate limit"
    if "quota" in out and "exceed" in out:
        return True, "quota exceeded"
    if "usage" in out and "exceed" in out:
        return True, "usage exceeded"
    return False, ""


REQUIRED_EVENT_FIELDS = [
    "schema_version",
    "event_id",
    "event",
    "ts",
    "service.name",
    "factory_id",
    "deployment.environment",
    "host.name",
    "tick_id",
    "dry_run",
    "on_usage_filled",
]


def validate_event(obj):
    if not isinstance(obj, dict):
        raise ValueError("event must be an object")
    for key in REQUIRED_EVENT_FIELDS:
        if key not in obj:
            raise ValueError(f"event missing required field: {key}")
    version = obj.get("schema_version")
    if not isinstance(version, int) or version != SCHEMA_VERSION:
        raise ValueError(f"unsupported schema_version: {version!r}")
    if not isinstance(obj.get("event_id"), str) or not obj["event_id"]:
        raise ValueError("event_id must be a non-empty string")
    if not isinstance(obj.get("event"), str) or not obj["event"]:
        raise ValueError("event name must be a non-empty string")
    if not isinstance(obj.get("tick_id"), str):
        raise ValueError("tick_id must be a string")
    if not isinstance(obj.get("dry_run"), bool):
        raise ValueError("dry_run must be boolean")
    return True


def _coerce_value(key, value):
    if key in _INT_FIELDS:
        try:
            return int(value)
        except (TypeError, ValueError):
            return value
    if key in _FLOAT_FIELDS:
        try:
            return float(value)
        except (TypeError, ValueError):
            return value
    if key in _BOOL_FIELDS:
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            return value.strip().lower() in ("1", "true", "yes", "on")
        return bool(value)
    if key in _ARRAY_FIELDS:
        if isinstance(value, list):
            return value
        if isinstance(value, str):
            try:
                loaded = json.loads(value)
                if isinstance(loaded, list):
                    return loaded
            except (TypeError, ValueError):
                pass
            return [v.strip() for v in value.split(",") if v.strip()]
        return value
    return value


def make_event(event, tick_id, dry_run, on_usage_filled, env, host,
               factory_id="factory-1", repo="", **fields):
    obj = {}
    obj["schema_version"] = SCHEMA_VERSION
    obj["event_id"] = fields.pop("event_id", None) or str(uuid.uuid4())
    obj["ts"] = fields.pop("ts", None) or datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    obj["service.name"] = "factory-tick"
    obj["factory_id"] = factory_id or "factory-1"
    obj["deployment.environment"] = env or "dev"
    obj["host.name"] = host or "unknown"
    obj["tick_id"] = tick_id
    obj["dry_run"] = bool(dry_run)
    obj["on_usage_filled"] = on_usage_filled
    obj["event"] = event
    if repo:
        obj["repo"] = repo
    for k, v in fields.items():
        if isinstance(v, str) and v == "" and k in (_INT_FIELDS | _FLOAT_FIELDS):
            continue
        obj[k] = _coerce_value(k, v)
    validate_event(obj)
    return obj


FAIL_STATES = {"FAILURE", "FAILED", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"}


def check_state(item):
    if not isinstance(item, dict):
        return ""
    st = (item.get("state") or item.get("conclusion") or item.get("status") or "").upper()
    if item.get("__typename") == "CheckRun" and (item.get("status") or "").upper() not in ("COMPLETED", ""):
        return "PENDING"
    return st


def fix_candidates_from_prs(prs):
    rows = []
    for pr in prs or []:
        if pr.get("isDraft"):
            continue
        head = pr.get("headRefName") or ""
        m = re.match(r"^factory/issue-(\d+)$", head)
        if not m:
            continue
        issue = int(m.group(1))
        sha = (pr.get("headRefOid") or "").strip()
        if not sha:
            continue
        reasons = []
        rollup = pr.get("statusCheckRollup") or []
        if isinstance(rollup, list):
            for item in rollup:
                st = check_state(item)
                if st in FAIL_STATES:
                    reasons.append("failing-checks")
                    break
        rd = (pr.get("reviewDecision") or "").upper()
        if rd == "CHANGES_REQUESTED":
            reasons.append("changes-requested")
        mergeable = (pr.get("mergeable") or "").upper()
        if mergeable == "CONFLICTING":
            reasons.append("conflicts")
        if not reasons:
            continue
        reasons = sorted(set(reasons))
        rkey = ",".join(reasons)
        marker = f"<!-- factory:fix-pr:{sha}:{rkey} -->"
        rows.append((pr.get("createdAt") or "9999", pr.get("number"), issue, sha, rkey, marker))
    rows.sort()
    return rows


def prioritize_issues(issues, prio):
    import math
    def key(it):
        n = it["number"]
        created = it.get("createdAt") or "9999"
        if n in (prio or {}):
            pc, pn, bo = prio[n]
            return (0, pc, pn, bo, created, n)
        return (1, "9999", math.inf, math.inf, created, n)
    return [it["number"] for it in sorted(issues or [], key=key)]


def has_marker_comments(comments, marker, author=None):
    if author is not None and not author:
        return False
    return any(
        marker in (c.get("body") or "")
        and (author is None or (c.get("author") or {}).get("login") == author)
        for c in (comments or [])
    )


def claim_status(claim_dir, ttl, now_ts, pid_alive_fn=None):
    """Return (state, detail).

    state: free|active|stale
    pid_alive_fn takes pid string/int and returns bool.
    """
    if pid_alive_fn is None:
        pid_alive_fn = lambda p: False
    if not os.path.isdir(claim_dir):
        return "free", ""
    try:
        mtime = int(os.stat(claim_dir).st_mtime)
    except Exception:
        mtime = 0
    age = max(0, int(now_ts) - mtime)
    if age > int(ttl):
        return "stale", str(age)
    pid = ""
    try:
        with open(os.path.join(claim_dir, "pid"), "r", encoding="utf-8") as f:
            pid = f.read().strip()
    except Exception:
        pid = ""
    if pid and pid_alive_fn(pid):
        return "active", pid
    # no live pid evidence but not expired: treat as active-within-ttl to be safe
    if pid == "":
        return "active", "unknown-pid"
    return "stale", f"dead-pid:{pid}"


def acquire_claim(claim_dir, ttl, now_ts, pid, pid_alive_fn=None):
    state, detail = claim_status(claim_dir, ttl, now_ts, pid_alive_fn=pid_alive_fn)
    if state == "stale":
        release_claim(claim_dir)
        state = "free"
    if state == "active":
        return False, "active", detail
    try:
        os.mkdir(claim_dir)
    except FileExistsError:
        return False, "conflict", "mkdir-race"
    except Exception as e:
        return False, "error", str(e)
    try:
        with open(os.path.join(claim_dir, "pid"), "w", encoding="utf-8") as f:
            f.write(str(pid))
    except Exception:
        pass
    return True, "acquired", ""


def release_claim(claim_dir):
    try:
        shutil.rmtree(claim_dir)
        return True
    except FileNotFoundError:
        return True
    except Exception:
        return False


def _pid_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Session id parsing (F-01)
# ---------------------------------------------------------------------------

SESSION_ID_RE = re.compile(r'"sessionID"\s*:\s*"([^"]+)"')


def session_id_from_stream(text):
    """Return the first sessionID found in an opencode JSON stream, or None.

    Tolerates malformed lines: each line is parsed independently and a line
    that fails to parse is skipped (never a crash).
    """
    if not text:
        return None
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        m = SESSION_ID_RE.search(line)
        if m:
            return m.group(1)
        try:
            obj = json.loads(line)
        except (ValueError, TypeError):
            continue
        if isinstance(obj, dict):
            sid = obj.get("sessionID") or obj.get("session_id")
            if isinstance(sid, str) and sid:
                return sid
    return None


# ---------------------------------------------------------------------------
# Opencode stream parsing (Part B usage/cost)
# ---------------------------------------------------------------------------

SKILL_LOAD_RE = re.compile(r"(?:loading|load|using|loaded)\s+(?:the\s+)?(?:skill\s+)?['\"]?([A-Za-z0-9_.\-]+)['\"]?", re.IGNORECASE)


def parse_opencode_stream(text):
    """Parse an opencode run --format json stream into a typed summary dict.

    Missing fields are simply absent from the result; a malformed stream never
    raises. Returns keys: session_id, steps, input_tokens, output_tokens,
    reasoning_tokens, cache_read_tokens, cache_write_tokens, cost_usd,
    tool_calls, tool_errors, skills_loaded.
    """
    result = {}
    if not text:
        return result
    session_id = None
    steps = 0
    input_tokens = 0
    output_tokens = 0
    reasoning_tokens = 0
    cache_read_tokens = 0
    cache_write_tokens = 0
    cost_usd = 0.0
    tool_calls = 0
    tool_errors = 0
    skills_loaded = []
    seen_skills = set()

    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except (ValueError, TypeError):
            # try regex fallback for session id on raw line
            if session_id is None:
                m = SESSION_ID_RE.search(line)
                if m:
                    session_id = m.group(1)
            continue
        if not isinstance(obj, dict):
            continue
        if session_id is None:
            sid = obj.get("sessionID") or obj.get("session_id")
            if isinstance(sid, str) and sid:
                session_id = sid
        otype = obj.get("type")
        part = obj.get("part") or {}
        if otype == "step_finish":
            steps += 1
            tokens = part.get("tokens") or {}
            if isinstance(tokens, dict):
                input_tokens += int(tokens.get("input") or 0)
                output_tokens += int(tokens.get("output") or 0)
                reasoning_tokens += int(tokens.get("reasoning") or 0)
                cache = tokens.get("cache") or {}
                if isinstance(cache, dict):
                    cache_read_tokens += int(cache.get("read") or 0)
                    cache_write_tokens += int(cache.get("write") or 0)
            c = part.get("cost")
            if isinstance(c, (int, float)):
                cost_usd += float(c)
        if otype in ("tool_use", "tool"):
            tool_calls += 1
            state = part.get("state") or {}
            status = (state.get("status") or "") if isinstance(state, dict) else ""
            err = part.get("error") or state.get("error") if isinstance(state, dict) else None
            if status == "error" or err:
                tool_errors += 1
        text_blob = obj.get("text") or ""
        if isinstance(text_blob, str):
            for m in SKILL_LOAD_RE.finditer(text_blob):
                name = m.group(1)
                if name not in seen_skills:
                    seen_skills.add(name)
                    skills_loaded.append(name)

    if session_id:
        result["session_id"] = session_id
    if steps:
        result["steps"] = steps
    if input_tokens:
        result["input_tokens"] = input_tokens
    if output_tokens:
        result["output_tokens"] = output_tokens
    if reasoning_tokens:
        result["reasoning_tokens"] = reasoning_tokens
    if cache_read_tokens:
        result["cache_read_tokens"] = cache_read_tokens
    if cache_write_tokens:
        result["cache_write_tokens"] = cache_write_tokens
    if cost_usd:
        result["cost_usd"] = cost_usd
    if tool_calls:
        result["tool_calls"] = tool_calls
    if tool_errors:
        result["tool_errors"] = tool_errors
    if skills_loaded:
        result["skills_loaded"] = skills_loaded
    return result


def parse_tool_calls(text):
    """Return a list of tool-call dicts from an opencode JSON stream.

    Each dict has: tool, status, and optionally duration_ms, skill_name.
    Skill loads are represented as tool="skill" with skill_name when a skill
    name can be determined. Malformed lines are skipped; never raises.
    """
    calls = []
    if not text:
        return calls
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(obj, dict):
            continue
        otype = obj.get("type")
        if otype not in ("tool_use", "tool"):
            continue
        part = obj.get("part") or {}
        tool = part.get("tool") or obj.get("tool") or "unknown"
        state = part.get("state") or {}
        status = ""
        duration_ms = None
        if isinstance(state, dict):
            status = state.get("status") or ""
            t = state.get("time") or {}
            if isinstance(t, dict):
                start = t.get("start")
                end = t.get("end")
                try:
                    if start is not None and end is not None:
                        duration_ms = int(end) - int(start)
                except (TypeError, ValueError):
                    duration_ms = None
        err = part.get("error")
        if err and not status:
            status = "error"
        rec = {"tool": str(tool), "status": str(status or "unknown")}
        if duration_ms is not None and duration_ms >= 0:
            rec["duration_ms"] = duration_ms
        # Skill loads: tool name "skill" or input contains skill/name.
        inp = {}
        if isinstance(state, dict):
            inp = state.get("input") or {}
        if not isinstance(inp, dict):
            inp = {}
        skill_name = inp.get("name") or inp.get("skill") or inp.get("skill_name")
        if str(tool).lower() in ("skill", "opencode_skill", "load_skill"):
            rec["tool"] = "skill"
            if skill_name:
                rec["skill_name"] = str(skill_name)
        elif skill_name and str(tool).lower().endswith("skill"):
            rec["tool"] = "skill"
            rec["skill_name"] = str(skill_name)
        calls.append(rec)
    return calls


def new_trace_id():
    """Return a 32-hex-char W3C trace id."""
    return uuid.uuid4().hex



# ---------------------------------------------------------------------------
# Failure classification (F-08)
# ---------------------------------------------------------------------------

def classify_failure(text, exit_code):
    """Classify a failed session into a short failure_reason string.

    Returns one of: timeout, usage_filled, exit_nonzero, opencode_error,
    interrupted.
    """
    try:
        code = int(exit_code)
    except (TypeError, ValueError):
        code = 1
    if code in (124, 137, 143) or "timed out" in (text or "").lower():
        return "timeout"
    if is_usage_filled(text)[0]:
        return "usage_filled"
    low = (text or "").lower()
    if "opencode" in low and ("error" in low or "failed" in low or "panic" in low):
        return "opencode_error"
    if code in (130, 143) or "interrupt" in low or "signal" in low:
        return "interrupted"
    return "exit_nonzero"


def error_fingerprint(text):
    """sha256 of the normalised last error line, first 12 hex chars.

    Returns None when there is no usable error line.
    """
    if not text:
        return None
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if not lines:
        return None
    last = lines[-1]
    # normalise: drop leading "Error:"/"error:" prefixes and surrounding punctuation
    norm = re.sub(r"^(error|error:)\s*", "", last, flags=re.IGNORECASE).strip()
    norm = re.sub(r"\s+", " ", norm).strip(" .,:;!\"'")
    if not norm:
        return None
    return hashlib.sha256(norm.encode("utf-8")).hexdigest()[:12]


# ---------------------------------------------------------------------------
# Agent version hashing (Part B run-scoped fields)
# ---------------------------------------------------------------------------

def agent_version_for(agent_id, agents_dir=None):
    """First 12 hex chars of sha256 of .opencode/agents/<agent>.md.

    Returns None when the file cannot be read. Deterministic per file content.
    """
    if not agent_id:
        return None
    base = agents_dir or os.path.join(os.getcwd(), ".opencode", "agents")
    path = os.path.join(base, f"{agent_id}.md")
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = f.read()
    except (OSError, IOError):
        return None
    return hashlib.sha256(data.encode("utf-8")).hexdigest()[:12]


# ---------------------------------------------------------------------------
# CLI subcommands
# ---------------------------------------------------------------------------

def _emit_cli(argv):
    # factory.py emit <event> <logfile> <tick_id> <dry_run> <on_usage_filled>
    #   <env> <host> <factory_id> <repo> [k=v ...]
    if len(argv) < 10:
        print("usage: factory.py emit <event> <logfile> <tick_id> <dry_run> "
              "<on_usage_filled> <env> <host> <factory_id> <repo> [k=v ...]",
              file=sys.stderr)
        return 2
    event = argv[2]
    logfile = argv[3]
    tick_id = argv[4]
    dry_run = argv[5] == "1"
    on_usage_filled = argv[6]
    env = argv[7]
    host = argv[8]
    factory_id = argv[9]
    repo = argv[10] if len(argv) > 10 else ""
    fields = {}
    for a in argv[11:]:
        if "=" in a:
            k, v = a.split("=", 1)
            fields[k] = v
    obj = make_event(event, tick_id, dry_run, on_usage_filled, env, host,
                     factory_id, repo, **fields)
    line = json.dumps(obj, ensure_ascii=False)
    try:
        with open(logfile, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        # emission must never be fatal
        return 0
    return 0


def _session_id_cli(argv):
    # factory.py session-id <file|->
    if len(argv) < 3:
        print("usage: factory.py session-id <file|->", file=sys.stderr)
        return 2
    path = argv[2]
    if path == "-":
        text = sys.stdin.read()
    else:
        try:
            with open(path, "r", encoding="utf-8") as f:
                text = f.read()
        except OSError:
            return 1
    sid = session_id_from_stream(text)
    if sid is None:
        return 1
    print(sid)
    return 0


def main(argv):
    # CLI subcommands for shell integration
    if len(argv) < 2:
        print(
            "usage: factory.py <validate-models|validate-event|normalize-model|"
            "classify-gh|classify-git|should-retry|is-usage-filled|"
            "model-for-labels|claim-acquire|claim-release|emit|session-id|"
            "classify-failure|error-fingerprint|trace-id|parse-tool-calls|export-trace> ...",
            file=sys.stderr,
        )
        return 2
    cmd = argv[1]
    if cmd == "validate-models":
        path = argv[2] if len(argv) > 2 else "-"
        import yaml
        with (open(path) if path != "-" else sys.stdin) as f:
            cfg = yaml.safe_load(f)
        validate_models(cfg)
        print("OK: models.yaml valid")
        return 0
    if cmd == "validate-event":
        path = argv[2] if len(argv) > 2 else "-"
        with (open(path) if path != "-" else sys.stdin) as f:
            obj = json.load(f)
        validate_event(obj)
        print("OK: event valid")
        return 0
    if cmd == "normalize-model":
        print(normalize_model(argv[2] if len(argv) > 2 else ""), end="")
        return 0
    if cmd == "classify-gh":
        arg = argv[2] if len(argv) > 2 else "-"
        text = sys.stdin.read() if arg == "-" else arg
        print(classify_gh_error(text))
        return 0
    if cmd == "classify-git":
        arg = argv[2] if len(argv) > 2 else "-"
        text = sys.stdin.read() if arg == "-" else arg
        print(classify_git_error(text))
        return 0
    if cmd == "should-retry":
        arg = argv[2] if len(argv) > 2 else "-"
        cat = sys.stdin.read().strip() if arg == "-" else arg.strip()
        print("true" if should_retry_category(cat) else "false")
        return 0
    if cmd == "classify-pr-changes":
        value = argv[2] if len(argv) > 2 else ""
        # parse int when possible
        try:
            parsed = int(value)
        except (TypeError, ValueError):
            parsed = value
        print(classify_pr_changes(parsed))
        return 0
    if cmd == "is-usage-filled":
        arg = argv[2] if len(argv) > 2 else "-"
        text = sys.stdin.read() if arg == "-" else arg
        filled, reason = is_usage_filled(text)
        print(("true" if filled else "false") + "\t" + reason)
        return 0
    if cmd == "model-for-labels":
        # argv[2]=config path, rest labels
        import yaml
        with open(argv[2]) as f:
            cfg = yaml.safe_load(f)
        entries = (cfg or {}).get("labels") or {}
        model, backup, tier_label = model_for_labels(entries, argv[3:])
        print(f"{model}\t{backup}\t{tier_label}")
        return 0
    if cmd == "claim-acquire":
        # claim-acquire <claim_dir> <ttl> <now_ts> <pid>
        claim_dir = argv[2]
        ttl = int(argv[3])
        now_ts = int(argv[4])
        pid = argv[5]
        ok, state, detail = acquire_claim(claim_dir, ttl, now_ts, pid, pid_alive_fn=_pid_alive)
        print(("acquired" if ok else state) + "\t" + (detail or ""))
        return 0 if ok else 1
    if cmd == "claim-release":
        ok = release_claim(argv[2])
        print("released" if ok else "missing")
        return 0
    if cmd == "emit":
        return _emit_cli(argv)
    if cmd == "session-id":
        return _session_id_cli(argv)
    if cmd == "classify-failure":
        # classify-failure <exit_code> [text|-]; text from stdin when "-" or omitted
        if len(argv) < 3:
            print("usage: factory.py classify-failure <exit_code> [text|-]", file=sys.stderr)
            return 2
        exit_code = argv[2]
        arg = argv[3] if len(argv) > 3 else "-"
        text = sys.stdin.read() if arg == "-" else arg
        print(classify_failure(text, exit_code))
        return 0
    if cmd == "error-fingerprint":
        arg = argv[2] if len(argv) > 2 else "-"
        text = sys.stdin.read() if arg == "-" else arg
        fp = error_fingerprint(text)
        if fp:
            print(fp)
        return 0
    if cmd == "trace-id":
        print(new_trace_id())
        return 0
    if cmd == "parse-tool-calls":
        # parse-tool-calls <file|->  -> JSON array of tool call dicts
        path = argv[2] if len(argv) > 2 else "-"
        if path == "-":
            text = sys.stdin.read()
        else:
            try:
                with open(path, "r", encoding="utf-8") as f:
                    text = f.read()
            except OSError:
                print("[]")
                return 1
        print(json.dumps(parse_tool_calls(text), ensure_ascii=False))
        return 0
    if cmd == "export-trace":
        # export-trace <trace_id> <run_id> <endpoint|-> [k=v ...]
        # Reads opencode JSON stream from stdin. Metadata as k=v. endpoint "-"
        # or empty uses FACTORY_OTLP_TRACES_ENDPOINT/OTEL_EXPORTER_OTLP_ENDPOINT.
        if len(argv) < 4:
            print(
                "usage: factory.py export-trace <trace_id> <run_id> <endpoint|-> [k=v ...]",
                file=sys.stderr,
            )
            return 2
        trace_id = argv[2]
        run_id = argv[3]
        endpoint = argv[4] if len(argv) > 4 else "-"
        if endpoint == "-":
            endpoint = os.environ.get("FACTORY_OTLP_TRACES_ENDPOINT", "") or os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "")
        metadata = {}
        for a in argv[5:]:
            if "=" in a:
                k, v = a.split("=", 1)
                metadata[k] = v
        stream_text = sys.stdin.read()
        try:
            from factory_trace import export_run_trace
        except Exception:
            # allow running from repo root with lib on path
            lib_dir = os.path.dirname(os.path.abspath(__file__))
            if lib_dir not in sys.path:
                sys.path.insert(0, lib_dir)
            from factory_trace import export_run_trace
        ok, msg = export_run_trace(
            trace_id=trace_id,
            run_id=run_id,
            endpoint=endpoint,
            stream_text=stream_text,
            metadata=metadata,
        )
        if ok:
            print(f"OK: {msg}")
            return 0
        print(f"ERR: {msg}", file=sys.stderr)
        return 1
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
