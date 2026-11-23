#!/usr/bin/env python3
"""Compute factory.queue snapshot counts. Best-effort; extra gh calls only
when invoked (end of tick, not hot path)."""

from __future__ import annotations

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))


def gh_json(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "").strip())
    return json.loads(r.stdout or "null")


def compute_queue(repo: str | None = None) -> dict:
    # infant: open, no labels
    issues = gh_json("issue", "list", "--state", "open", "--limit", "200",
                     "--json", "number,labels,comments")
    if not isinstance(issues, list):
        issues = []
    infant = 0
    planned = 0
    approved_waiting = 0
    for it in issues:
        if not isinstance(it, dict):
            continue
        labels = [l.get("name") for l in (it.get("labels") or []) if isinstance(l, dict)]
        if len(labels) == 0:
            infant += 1
            continue
        has_approved = "owner approved" in labels
        has_plan = any("<!-- factory:plan -->" in (c.get("body") or "") for c in (it.get("comments") or []) if isinstance(c, dict))
        if has_plan and not has_approved:
            planned += 1
        if has_approved:
            # check open factory PR
            num = it.get("number")
            try:
                prs = gh_json("pr", "list", "--state", "open", "--head", f"factory/issue-{num}", "--json", "number")
                has_pr = isinstance(prs, list) and len(prs) > 0
            except Exception:
                has_pr = False
            if not has_pr:
                approved_waiting += 1

    # in_pr: open factory PRs
    try:
        open_prs = gh_json("pr", "list", "--state", "open", "--limit", "200", "--json", "number,headRefName,statusCheckRollup,reviewDecision,mergeable,isDraft,headRefOid")
    except Exception:
        open_prs = []
    in_pr = 0
    blocked_pr = 0
    if isinstance(open_prs, list):
        import re
        for pr in open_prs:
            if not isinstance(pr, dict):
                continue
            head = pr.get("headRefName") or ""
            if not re.match(r"^factory/issue-\d+$", head):
                continue
            in_pr += 1
            # blocked_pr: discovery would consider for fixing
            if pr.get("isDraft"):
                continue
            reasons = []
            rollup = pr.get("statusCheckRollup") or []
            if isinstance(rollup, list):
                for item in rollup:
                    if not isinstance(item, dict):
                        continue
                    st = (item.get("state") or item.get("conclusion") or item.get("status") or "").upper()
                    if item.get("__typename") == "CheckRun" and (item.get("status") or "").upper() not in ("COMPLETED", ""):
                        st = "PENDING"
                    if st in {"FAILURE","FAILED","ERROR","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE","STALE"}:
                        reasons.append("f")
                        break
            if (pr.get("reviewDecision") or "").upper() == "CHANGES_REQUESTED":
                reasons.append("r")
            if (pr.get("mergeable") or "").upper() == "CONFLICTING":
                reasons.append("c")
            if reasons:
                blocked_pr += 1

    out = {
        "infant": infant,
        "planned": planned,
        "approved_waiting": approved_waiting,
        "in_pr": in_pr,
        "blocked_pr": blocked_pr,
    }
    # needs_info only if label exists in taxonomy - check labels on repo
    try:
        labels = gh_json("label", "list", "--limit", "200", "--json", "name")
        names = {l.get("name") for l in labels if isinstance(l, dict)} if isinstance(labels, list) else set()
        if "needs info" in names or "needs-info" in names:
            target = "needs info" if "needs info" in names else "needs-info"
            needs = gh_json("issue", "list", "--state", "open", "--label", target, "--limit", "200", "--json", "number")
            out["needs_info"] = len(needs) if isinstance(needs, list) else 0
    except Exception:
        pass
    return out


def main():
    try:
        out = compute_queue()
        print(json.dumps(out))
        return 0
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
