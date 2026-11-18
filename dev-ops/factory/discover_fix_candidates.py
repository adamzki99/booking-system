#!/usr/bin/env python3
import json, re, subprocess, sys
sys.path.insert(0, "/".join(__file__.split("/")[:-1]) + "/lib")
import factory

def gh_json(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "").strip())
    return json.loads(r.stdout or "null")

def main():
    try:
        prs = gh_json("pr", "list", "--state", "open", "--limit", "100", "--json", "number,headRefName,headRefOid,mergeable,reviewDecision,statusCheckRollup,isDraft,createdAt")
    except Exception as e:
        sys.stderr.write(f"[factory-tick] fix-pr discovery unavailable: {e}\n")
        raise SystemExit(1)
    for _created, prnum, issue, sha, rkey, marker in factory.fix_candidates_from_prs(prs):
        print(f"{prnum}\t{issue}\t{sha}\t{rkey}\t{marker}")

if __name__ == "__main__":
    raise SystemExit(main())
