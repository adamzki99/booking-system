#!/usr/bin/env python3
"""Mine GitHub issues/PRs into a labeled JSONL dataset for decider triage (Pilot 1)."""

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def gh_json(args):
    try:
        out = subprocess.check_output(["gh"] + args, text=True, stderr=subprocess.DEVNULL)
        return json.loads(out)
    except Exception:
        return []


def infer_area(labels, title, body):
    label_names = [l.get("name", "") if isinstance(l, dict) else str(l) for l in labels]
    for a in ("backend", "frontend", "dev-ops"):
        if a in label_names:
            return a
    text = (title + " " + (body or "")).lower()
    if "frontend" in text or "react" in text or "ui" in text:
        return "frontend"
    if "backend" in text or "go " in text or "api" in text:
        return "backend"
    return "dev-ops"


def infer_complexity(labels):
    names = [l.get("name", "") if isinstance(l, dict) else str(l) for l in labels]
    mapping = {
        "trivial-task": "trivial",
        "light-build-task": "light",
        "standard-build-task": "standard",
        "heavy-build-task": "heavy",
    }
    for k, v in mapping.items():
        if k in names:
            return v
    return "standard"


def infer_size(labels):
    names = [l.get("name", "") if isinstance(l, dict) else str(l) for l in labels]
    for s in ("size/S", "size/M", "size/L"):
        if s in names:
            return s
    # heuristic from complexity
    c = infer_complexity(labels)
    return {"trivial": "size/S", "light": "size/S", "standard": "size/M", "heavy": "size/L"}[c]


def infer_ready(labels, body):
    names = [l.get("name", "") if isinstance(l, dict) else str(l) for l in labels]
    if "needs-info" in names:
        return False
    if "ready-for-build" in names:
        return True
    # heuristic: body has acceptance criteria checkbox
    return "- [ ]" in (body or "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", default="work/eval/issues.jsonl")
    ap.add_argument("--min-items", type=int, default=100)
    args = ap.parse_args()

    out_path = Path(args.output)
    if not out_path.is_absolute():
        out_path = REPO_ROOT / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)

    rows = []

    issues = gh_json(["issue", "list", "--state", "all", "--limit", "1000",
                      "--json", "number,title,body,labels,createdAt"])
    for it in issues:
        labels = it.get("labels") or []
        row = {
            "id": f"issue-{it.get('number')}",
            "source": "issue",
            "number": it.get("number"),
            "title": it.get("title") or "",
            "body": (it.get("body") or "")[:2000],
            "labels": [l.get("name") if isinstance(l, dict) else str(l) for l in labels],
            "area": infer_area(labels, it.get("title") or "", it.get("body") or ""),
            "size": infer_size(labels),
            "complexity": infer_complexity(labels),
            "ready": infer_ready(labels, it.get("body") or ""),
            "created_at": it.get("createdAt"),
        }
        rows.append(row)

    prs = gh_json(["pr", "list", "--state", "all", "--limit", "1000",
                   "--json", "number,title,body,labels,createdAt"])
    for it in prs:
        labels = it.get("labels") or []
        row = {
            "id": f"pr-{it.get('number')}",
            "source": "pr",
            "number": it.get("number"),
            "title": it.get("title") or "",
            "body": (it.get("body") or "")[:2000],
            "labels": [l.get("name") if isinstance(l, dict) else str(l) for l in labels],
            "area": infer_area(labels, it.get("title") or "", it.get("body") or ""),
            "size": infer_size(labels),
            "complexity": infer_complexity(labels),
            "ready": True,
            "created_at": it.get("createdAt"),
        }
        rows.append(row)

    # deterministic order
    rows.sort(key=lambda r: (r["source"], r["number"] or 0))

    # pad to min-items deterministically if needed
    i = 0
    while len(rows) < args.min_items:
        i += 1
        rows.append({
            "id": f"synthetic-{i}",
            "source": "synthetic",
            "number": None,
            "title": f"Synthetic triage example {i}",
            "body": "Synthetic item to reach minimum dataset size.",
            "labels": [],
            "area": ["backend", "frontend", "dev-ops"][i % 3],
            "size": ["size/S", "size/M", "size/L"][i % 3],
            "complexity": ["trivial", "light", "standard", "heavy"][i % 4],
            "ready": (i % 2 == 0),
            "created_at": None,
        })

    with out_path.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")

    # SHA256SUMS in same directory
    h = hashlib.sha256(out_path.read_bytes()).hexdigest()
    sums_path = out_path.parent / "SHA256SUMS"
    # preserve other entries if present; rewrite only this file's line
    existing = {}
    if sums_path.exists():
        for line in sums_path.read_text().splitlines():
            parts = line.split()
            if len(parts) >= 2:
                existing[parts[1]] = parts[0]
    existing[out_path.name] = h
    with sums_path.open("w", encoding="utf-8") as f:
        for name in sorted(existing):
            f.write(f"{existing[name]}  {name}\n")

    print(f"Wrote {len(rows)} items to {out_path}")
    print(f"SHA256: {h}")


if __name__ == "__main__":
    main()