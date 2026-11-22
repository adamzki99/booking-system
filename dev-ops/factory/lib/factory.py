"""Factory orchestration helpers (testable, no network)."""

import json
import math
import os
import re
import shutil
import sys

SCHEMA_VERSION = 1


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
    """Return (model, backup) for a set of labels."""
    have = set(have or [])
    model = ""
    backup = ""
    # preserve insertion order (YAML order) for priority
    for name, cfg in (entries or {}).items():
        if name != "default" and name in have and isinstance(cfg, dict):
            model = cfg.get("model") or ""
            backup = cfg.get("backup_model") or cfg.get("backup") or ""
            if model:
                break
    if not model:
        default = (entries or {}).get("default") or {}
        model = default.get("model") or ""
        backup = backup or default.get("backup_model") or default.get("backup") or ""
    if not backup:
        default = (entries or {}).get("default") or {}
        backup = default.get("backup_model") or default.get("backup") or ""
    return model, backup


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
    "ts",
    "service.name",
    "deployment.environment",
    "host.name",
    "tick_id",
    "dry_run",
    "on_usage_filled",
    "event",
]


def validate_event(obj):
    if not isinstance(obj, dict):
        raise ValueError("event must be an object")
    for key in REQUIRED_EVENT_FIELDS:
        if key not in obj:
            raise ValueError(f"event missing required field: {key}")
    if obj.get("schema_version") != SCHEMA_VERSION:
        raise ValueError(f"unsupported schema_version: {obj.get('schema_version')}")
    if not isinstance(obj.get("event"), str) or not obj["event"]:
        raise ValueError("event name must be a non-empty string")
    if not isinstance(obj.get("tick_id"), str):
        raise ValueError("tick_id must be a string")
    if not isinstance(obj.get("dry_run"), bool):
        raise ValueError("dry_run must be boolean")
    return True


def make_event(event, tick_id, dry_run, on_usage_filled, env, host, **fields):
    import datetime
    obj = {}
    obj["schema_version"] = SCHEMA_VERSION
    obj["ts"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    obj["service.name"] = "factory-tick"
    obj["deployment.environment"] = env or "dev"
    obj["host.name"] = host or "unknown"
    obj["tick_id"] = tick_id
    obj["dry_run"] = bool(dry_run)
    obj["on_usage_filled"] = on_usage_filled
    obj["event"] = event
    for k, v in fields.items():
        obj[k] = v
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


def has_marker_comments(comments, marker):
    return any(marker in (c.get("body") or "") for c in (comments or []))


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


def main(argv):
    # CLI subcommands for shell integration
    if len(argv) < 2:
        print(
            "usage: factory.py <validate-models|validate-event|normalize-model|classify-gh|classify-git|classify-pr-changes|should-retry|is-usage-filled|model-for-labels|claim-acquire|claim-release> ...",
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
    if cmd == "classify-pr-changes":
        arg = argv[2] if len(argv) > 2 else "-"
        raw = sys.stdin.read() if arg == "-" else arg
        try:
            value = int(raw)
        except (TypeError, ValueError):
            value = raw
        print(classify_pr_changes(value))
        return 0
    if cmd == "should-retry":
        arg = argv[2] if len(argv) > 2 else "-"
        cat = sys.stdin.read().strip() if arg == "-" else arg.strip()
        print("true" if should_retry_category(cat) else "false")
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
        model, backup = model_for_labels(entries, argv[3:])
        print(f"{model}\t{backup}")
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
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))


def parse_trusted_logins(raw):
    """Parse a comma/whitespace separated login list into a lowercase set.

    An empty/None value yields an empty set (fail closed).
    """
    if raw is None:
        return set()
    if isinstance(raw, (list, tuple, set, frozenset)):
        out = set()
        for item in raw:
            if isinstance(item, dict):
                val = item.get("login") or item.get("name") or ""
            else:
                val = item
            val = str(val).strip().lower()
            if val:
                out.add(val)
        return out
    text = str(raw)
    out = set()
    for part in re.split(r"[,\s]+", text):
        part = part.strip().lower()
        if part:
            out.add(part)
    return out


def _login_of(candidate):
    if isinstance(candidate, dict):
        for key in ("login", "name", "user"):
            if key in candidate and candidate.get(key) is not None:
                return candidate.get(key)
        return ""
    return candidate


def is_trusted_login(candidate, trusted):
    """Return True if candidate (login or {login:...}) is in trusted set."""
    trusted_set = parse_trusted_logins(trusted) if not isinstance(trusted, (set, frozenset)) else trusted
    # normalize trusted set to lowercase strings even if passed as set
    trusted_set = {str(x).strip().lower() for x in trusted_set if str(x).strip()}
    login = _login_of(candidate)
    return str(login).strip().lower() in trusted_set


def filter_trusted_issues(issues, trusted):
    """Keep only issues whose author.login is trusted. Empty trusted keeps nothing."""
    trusted_set = parse_trusted_logins(trusted) if not isinstance(trusted, (set, frozenset)) else trusted
    trusted_set = {str(x).strip().lower() for x in trusted_set if str(x).strip()}
    out = []
    for issue in issues or []:
        if not isinstance(issue, dict):
            continue
        author = issue.get("author")
        if is_trusted_login(author, trusted_set):
            out.append(issue)
    return out


def build_prompt_context(body, comments, trusted):
    """Return body plus only trusted-author comments, with author/timestamp headers."""
    trusted_set = parse_trusted_logins(trusted) if not isinstance(trusted, (set, frozenset)) else trusted
    trusted_set = {str(x).strip().lower() for x in trusted_set if str(x).strip()}
    parts = []
    if body is not None and str(body).strip():
        parts.append(str(body).rstrip())
    for c in comments or []:
        if not isinstance(c, dict):
            continue
        author = c.get("author")
        if not is_trusted_login(author, trusted_set):
            continue
        login = _login_of(author)
        created = c.get("createdAt") or c.get("created_at") or c.get("timestamp") or ""
        header = f"--- Comment by {login}" + (f" at {created}" if created else "") + " ---"
        parts.append(header + "\n" + (c.get("body") or ""))
    return "\n\n".join(parts).strip()


def pr_is_trusted(pr, trusted, repo_owner=None):
    if not isinstance(pr, dict):
        return False
    if pr.get("isCrossRepository") is True:
        return False
    if not is_trusted_login(pr.get("author"), trusted):
        return False
    if repo_owner is not None:
        hro = pr.get("headRepositoryOwner")
        hro_login = _login_of(hro)
        if hro_login and str(hro_login).strip().lower() != str(repo_owner).strip().lower():
            return False
    return True


# Wrap fix_candidates_from_prs to accept trusted/repo_owner while keeping
# backward compatibility with the no-arg form.
_orig_fix_candidates_from_prs = fix_candidates_from_prs

def fix_candidates_from_prs(prs, trusted=None, repo_owner=None):
    rows = []
    for pr in prs or []:
        if not isinstance(pr, dict):
            continue
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
        if pr.get("isCrossRepository") is True:
            continue
        if trusted is not None and not is_trusted_login(pr.get("author"), trusted):
            continue
        if trusted is None:
            # fail closed when no trusted set provided? keep legacy behavior:
            pass
        if repo_owner is not None:
            hro = pr.get("headRepositoryOwner")
            hro_login = _login_of(hro)
            if hro_login and str(hro_login).strip().lower() != str(repo_owner).strip().lower():
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
