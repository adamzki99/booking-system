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
        prs = gh_json("pr", "list", "--state", "open", "--limit", "100", "--json", "number,headRefName,headRefOid,mergeable,reviewDecision,statusCheckRollup,isDraft,createdAt,isCrossRepository,author,headRepositoryOwner")
    except Exception as e:
        sys.stderr.write(f"[factory-tick] fix-pr discovery unavailable: {e}\n")
        raise SystemExit(1)
    trusted_raw = os.environ.get("FACTORY_TRUSTED_LOGINS", "")
    if os.environ.get("FACTORY_LOGIN"):
        trusted_raw = (trusted_raw + "," + os.environ["FACTORY_LOGIN"]).strip(",")
    trusted = factory.parse_trusted_logins(trusted_raw)
    if not trusted:
        sys.stderr.write("[factory-tick] FACTORY_TRUSTED_LOGINS empty; no fix candidates\n")
        raise SystemExit(0)
    try:
        repo = gh_json("repo", "view", "--json", "owner")
        repo_owner = (repo.get("owner") or {}).get("login")
    except Exception:
        repo_owner = None
    for _created, prnum, issue, sha, rkey, marker in factory.fix_candidates_from_prs(prs, trusted, repo_owner):
        print(f"{prnum}\t{issue}\t{sha}\t{rkey}\t{marker}")

if __name__ == "__main__":
    raise SystemExit(main())
