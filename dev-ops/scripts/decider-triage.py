#!/usr/bin/env python3
"""Advisory issue-triage helper for Strands Decider (Pilot 1).

Usage: decider-triage.py <issue-number>

Calls the decider service and prints a JSON proposal:
  {"labels": [...], "confidence": <float>, "model": <str|null>}

On service failure, timeout, or low confidence, prints a documented fallback
object and exits 0 (fail-open).
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

FALLBACK = {
    "labels": [],
    "confidence": 0.0,
    "model": None,
    "fallback": True,
    "reason": "service_unavailable_or_low_confidence",
}

THRESHOLD = float(os.environ.get("DECIDER_CONFIDENCE_THRESHOLD", "0.5"))
BASE_URL = os.environ.get("DECIDER_URL", "http://localhost:8090").rstrip("/")


def fetch_issue(number):
    try:
        out = subprocess.check_output(
            ["gh", "issue", "view", str(number), "--json", "title,body"],
            text=True, stderr=subprocess.DEVNULL, timeout=10,
        )
        data = json.loads(out)
        return f"{data.get('title','')}\n\n{data.get('body','')}"
    except Exception:
        return f"Issue {number}"


def main():
    if len(sys.argv) < 2:
        print(json.dumps(FALLBACK))
        return 0
    number = sys.argv[1]
    state = fetch_issue(number)
    payload = json.dumps({
        "question_type": "choice",
        "options": ["backend", "frontend", "dev-ops", "size/S", "size/M", "size/L",
                    "trivial", "light", "standard", "heavy", "ready-for-build", "needs-info"],
        "state": state[:4000],
    }).encode()

    url = f"{BASE_URL}/v1/systemone"
    try:
        req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
        data = json.loads(raw)
    except Exception:
        print(json.dumps(FALLBACK))
        return 0

    # Normalize response into proposal.
    proposal = None
    if isinstance(data, dict):
        if "labels" in data:
            proposal = {
                "labels": data.get("labels") or [],
                "confidence": float(data.get("confidence", 0.0) or 0.0),
                "model": data.get("model"),
            }
        elif "proposal" in data and isinstance(data["proposal"], dict):
            p = data["proposal"]
            proposal = {
                "labels": p.get("labels") or [],
                "confidence": float(p.get("confidence", 0.0) or 0.0),
                "model": p.get("model", data.get("model")),
            }
        else:
            # decider-style: choice + confidence
            choice = data.get("choice") or data.get("answer")
            conf = data.get("confidence", data.get("score", 0.0))
            try:
                conf = float(conf)
            except (TypeError, ValueError):
                conf = 0.0
            labels = [choice] if choice else []
            proposal = {"labels": labels, "confidence": conf, "model": data.get("model")}

    if proposal is None:
        print(json.dumps(FALLBACK))
        return 0

    if proposal["confidence"] < THRESHOLD:
        print(json.dumps(FALLBACK))
        return 0

    print(json.dumps(proposal))
    return 0


if __name__ == "__main__":
    sys.exit(main())