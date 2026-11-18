"""Factory orchestration helpers (testable, no network)."""

import json
import math
import re
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
    labels = config.get("labels")
    if not isinstance(labels, dict) or not labels:
        raise ValueError("models config must contain non-empty 'labels' mapping")
    if "default" not in labels:
        raise ValueError("models config must define a 'default' entry")
    for name, cfg in labels.items():
        if not isinstance(cfg, dict):
            raise ValueError(f"label entry '{name}' must be a mapping")
        model = cfg.get("model")
        if not isinstance(model, str) or not model.strip():
            raise ValueError(f"label entry '{name}' missing/invalid 'model'")
        backup = cfg.get("backup_model", cfg.get("backup"))
        if backup is not None and (not isinstance(backup, str)):
            raise ValueError(f"label entry '{name}' invalid backup_model")
    # primary vs backup distinctness is encouraged but not required
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
    if "auth" in t or "401" in t or "not logged" in t or "gh auth" in t:
        return "auth"
    if "rate limit" in t or "429" in t or "secondary rate" in t:
        return "rate_limit"
    if any(x in t for x in ("timeout", "timed out", "connection", "network", "502", "503", "504", "econnreset", "tls")):
        return "transient"
    if "not found" in t or "404" in t:
        return "not_found"
    if t.strip() == "":
        return "empty"
    return "other"


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

def main(argv):
    # CLI subcommands for shell integration
    if len(argv) < 2:
        print("usage: factory.py <validate-models|normalize-model|classify-gh|is-usage-filled> ...", file=sys.stderr)
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
    if cmd == "normalize-model":
        print(normalize_model(argv[2] if len(argv) > 2 else ""), end="")
        return 0
    if cmd == "classify-gh":
        # read text from stdin or arg
        text = argv[2] if len(argv) > 2 else sys.stdin.read()
        print(classify_gh_error(text))
        return 0
    if cmd == "is-usage-filled":
        arg = argv[2] if len(argv) > 2 else "-"
        text = sys.stdin.read() if arg == "-" else arg
        filled, reason = is_usage_filled(text)
        print(("true" if filled else "false") + "\\t" + reason)
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
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
