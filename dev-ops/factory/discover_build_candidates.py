#!/usr/bin/env python3
import json, math, subprocess, sys
sys.path.insert(0, "/".join(__file__.split("/")[:-1]) + "/lib")
import factory

APPROVED_LABEL = sys.argv[1] if len(sys.argv) > 1 else "owner approved"


def gh_json(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "").strip())
    return json.loads(r.stdout or "null")


def main():
    try:
        issues = gh_json("issue", "list", "--state", "open", "--label", APPROVED_LABEL, "--limit", "200", "--json", "number,createdAt")
    except Exception as e:
        sys.stderr.write(f"[factory-tick] build discovery unavailable: {e}\n")
        raise SystemExit(1)
    if not issues:
        raise SystemExit(0)

    try:
        repo = gh_json("repo", "view", "--json", "owner,nameWithOwner")
        owner = repo["owner"]["login"]
        full = repo["nameWithOwner"]
        projects = []
        for q in (
            "query($login:String!){ user(login:$login){ projectsV2(first:50){ nodes{ number id createdAt closed } } } }",
            "query($login:String!){ organization(login:$login){ projectsV2(first:50){ nodes{ number id createdAt closed } } } }",
        ):
            try:
                pdata = gh_json("api", "graphql", "-f", f"query={q}", "-F", f"login={owner}")["data"]
                for key in ("user", "organization"):
                    nodes = ((pdata.get(key) or {}).get("projectsV2") or {}).get("nodes") or []
                    projects.extend([n for n in nodes if n])
            except Exception:
                pass
        seen_p = set()
        uniq_projects = []
        for p in projects:
            n = p.get("number")
            if n not in seen_p:
                seen_p.add(n)
                uniq_projects.append(p)

        items_q = (
            "query($id:ID!, $after:String){ node(id:$id){ ... on ProjectV2{"
            " items(first:100, after:$after){ nodes{ content{ __typename"
            " ... on Issue{ number repository{ nameWithOwner } }"
            " ... on PullRequest{ number repository{ nameWithOwner } } }"
            " fieldValueByName(name:\"Build order\"){ __typename"
            " ... on ProjectV2ItemFieldNumberValue{ number }"
            " ... on ProjectV2ItemFieldTextValue{ text } } }"
            " pageInfo{ hasNextPage endCursor } } } } }"
        )

        prio = {}
        for p in uniq_projects:
            if p.get("closed") or not p.get("id"):
                continue
            pnum = p.get("number")
            pcreated = p.get("createdAt") or "9999"
            after = None
            while True:
                try:
                    args = ["api", "graphql", "-f", f"query={items_q}", "-f", f"id={p['id']}"]
                    if after:
                        args += ["-f", f"after={after}"]
                    conn = ((gh_json(*args).get("data") or {}).get("node") or {}).get("items") or {}
                except Exception:
                    break
                for it in conn.get("nodes") or []:
                    content = it.get("content") or {}
                    if (content.get("__typename") or "").lower() != "issue":
                        continue
                    repo_name = ((content.get("repository") or {}).get("nameWithOwner") or "").strip()
                    if repo_name != full:
                        continue
                    num = content.get("number")
                    if not isinstance(num, int):
                        continue
                    fv = it.get("fieldValueByName") or {}
                    bo = fv.get("number")
                    if bo is None:
                        bo = fv.get("text")
                    try:
                        bof = float(bo)
                    except Exception:
                        bof = math.inf
                    cand = (pcreated, pnum or math.inf, bof)
                    if num not in prio or cand < prio[num]:
                        prio[num] = cand
                page = conn.get("pageInfo") or {}
                if not page.get("hasNextPage"):
                    break
                after = page.get("endCursor")
                if not after:
                    break
        for n in factory.prioritize_issues(issues, prio):
            print(n)
    except Exception as e:
        sys.stderr.write(f"[factory-tick] project priority unavailable, using issue age: {e}\n")
        for n in factory.prioritize_issues(issues, {}):
            print(n)


if __name__ == "__main__":
    raise SystemExit(main())
