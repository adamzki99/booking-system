#!/usr/bin/env python3
"""Reconcile GitHub factory outcomes into deterministic v2 factory events.

Pure functions take recorded gh JSON fixtures; thin gh wrappers fetch live
data. Runs at end of non-dry-run tick (best-effort) and standalone for
backfill.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import subprocess
import sys
from typing import Any

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))
import factory  # noqa: E402

FACTORY_LOGIN = os.environ.get("FACTORY_LOGIN", "")
REPO = os.environ.get("FACTORY_REPO", "")
FACTORY_LOG_FILE = os.environ.get(
    "FACTORY_LOG_FILE",
    os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "factory", "tick.jsonl"),
)
RECONCILE_STATE_FILE = os.environ.get(
    "FACTORY_RECONCILE_STATE_FILE",
    os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "factory", "reconcile.state"),
)
FACTORY_ID = os.environ.get("FACTORY_ID", "factory-1")
FACTORY_ENV = os.environ.get("FACTORY_ENV", "dev")
HOSTNAME_VAL = os.environ.get("HOSTNAME", "unknown")


def now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def deterministic_event_id(event: str, repo: str, node_id: str, state_field: str) -> str:
    raw = f"{event}|{repo}|{node_id}|{state_field}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32]


def _iso(ts: Any) -> str | None:
    if not isinstance(ts, str) or not ts.strip():
        return None
    # GitHub gives RFC3339; normalize to Z form if possible
    t = ts.strip()
    if t.endswith("+00:00"):
        t = t[:-6] + "Z"
    return t


def _int_or_none(v: Any) -> int | None:
    if isinstance(v, bool):
        return None
    if isinstance(v, int):
        return v
    if isinstance(v, str) and v.strip().isdigit():
        return int(v.strip())
    return None


def _safe_label_name(v: Any) -> str | None:
    if isinstance(v, str) and v.strip():
        # label names only - no free text, but labels are repo-controlled; keep as-is trimmed
        return v.strip()
    return None


def issue_id_from_head(head: Any) -> int | None:
    if not isinstance(head, str):
        return None
    import re
    m = re.match(r"^factory/issue-(\d+)$", head.strip())
    if not m:
        return None
    try:
        return int(m.group(1))
    except ValueError:
        return None


def is_factory_pr(pr: dict[str, Any]) -> bool:
    head = ((pr.get("headRefName") or pr.get("head_branch") or "") if isinstance(pr, dict) else "")
    return issue_id_from_head(head) is not None


def make_outcome_event(event: str, repo: str, node_id: str, state_field: str,
                       ts: str, observed_at: str, **fields: Any) -> dict[str, Any]:
    eid = deterministic_event_id(event, repo, str(node_id), str(state_field))
    obj = factory.make_event(
        event,
        tick_id="reconcile",
        dry_run=False,
        on_usage_filled="backup",
        env=FACTORY_ENV,
        host=HOSTNAME_VAL,
        factory_id=FACTORY_ID,
        repo=repo,
        event_id=eid,
        ts=ts,
        observed_at=observed_at,
        **fields,
    )
    return obj


def events_for_pr(pr: dict[str, Any], repo: str, factory_login: str, observed_at: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if not isinstance(pr, dict):
        return out
    head = pr.get("headRefName") or pr.get("head_branch") or ""
    issue_id = issue_id_from_head(head)
    if issue_id is None:
        return out
    pr_number = _int_or_none(pr.get("number") or pr.get("pr_number"))
    if pr_number is None:
        return out
    node_id = pr.get("id") or pr.get("node_id") or str(pr_number)
    created_at = _iso(pr.get("createdAt") or pr.get("created_at"))
    if created_at:
        out.append(make_outcome_event(
            "pr.created", repo, node_id, created_at, created_at, observed_at,
            pr_number=pr_number, issue_id=issue_id, created_at=created_at,
            head_branch=str(head), draft=bool(pr.get("isDraft") or pr.get("draft") or False),
        ))

    # reviews
    reviews = pr.get("reviews") or []
    if isinstance(reviews, dict):
        reviews = reviews.get("nodes") or []
    for rv in reviews if isinstance(reviews, list) else []:
        if not isinstance(rv, dict):
            continue
        review_id = rv.get("id") or rv.get("databaseId") or rv.get("review_id")
        if review_id is None:
            continue
        submitted_at = _iso(rv.get("submittedAt") or rv.get("submitted_at"))
        state = (rv.get("state") or "").upper()
        state_map = {
            "APPROVED": "approved",
            "CHANGES_REQUESTED": "changes_requested",
            "COMMENTED": "commented",
        }
        mapped = state_map.get(state)
        if not mapped or not submitted_at:
            continue
        author = rv.get("author") or {}
        login = ""
        if isinstance(author, dict):
            login = author.get("login") or ""
        elif isinstance(author, str):
            login = author
        reviewer_is_owner = bool(factory_login) and login == factory_login
        # Deterministic: event|repo|review_id|state
        out.append(make_outcome_event(
            "pr.review", repo, str(review_id), mapped, submitted_at, observed_at,
            pr_number=pr_number, review_id=str(review_id), state=mapped,
            reviewer_is_owner=reviewer_is_owner, submitted_at=submitted_at,
        ))

    # checks - when head changes / observed. We emit for current head state.
    head_sha = (pr.get("headRefOid") or pr.get("head_sha") or "").strip()
    rollup = pr.get("statusCheckRollup")
    if head_sha and rollup is not None:
        conclusion, failed_checks = summarize_checks(rollup)
        if conclusion:
            out.append(make_outcome_event(
                "pr.checks", repo, str(pr_number), f"{head_sha}:{conclusion}", observed_at, observed_at,
                pr_number=pr_number, head_sha=head_sha, conclusion=conclusion,
                failed_checks=failed_checks,
            ))

    merged_at = _iso(pr.get("mergedAt") or pr.get("merged_at"))
    if merged_at:
        commits_raw = pr.get("commitsCount") if pr.get("commitsCount") is not None else pr.get("commits")
        commits = _int_or_none(commits_raw)
        if commits is None and isinstance(pr.get("commits"), dict):
            cdict = pr["commits"]
            commits = _int_or_none(cdict.get("totalCount"))
            if commits is None and isinstance(cdict.get("nodes"), list):
                commits = len(cdict["nodes"])
        additions = _int_or_none(pr.get("additions"))
        deletions = _int_or_none(pr.get("deletions"))
        changed_files = _int_or_none(pr.get("changedFiles") or pr.get("changed_files"))
        review_comments = _int_or_none(pr.get("reviewsTotal") or pr.get("review_comments") or (len(reviews) if isinstance(reviews, list) else None))
        human_commits = count_human_commits(pr, factory_login)
        fields = {
            "pr_number": pr_number,
            "issue_id": issue_id,
            "merged_at": merged_at,
        }
        if commits is not None:
            fields["commits"] = commits
        if additions is not None:
            fields["additions"] = additions
        if deletions is not None:
            fields["deletions"] = deletions
        if changed_files is not None:
            fields["changed_files"] = changed_files
        if review_comments is not None:
            fields["review_comments"] = review_comments
        if human_commits is not None:
            fields["human_commits"] = human_commits
        out.append(make_outcome_event(
            "pr.merged", repo, node_id, merged_at, merged_at, observed_at, **fields,
        ))

    closed_at = _iso(pr.get("closedAt") or pr.get("closed_at"))
    state = (pr.get("state") or "").upper()
    if closed_at and state == "CLOSED" and not merged_at:
        out.append(make_outcome_event(
            "pr.closed", repo, node_id, closed_at, closed_at, observed_at,
            pr_number=pr_number, issue_id=issue_id, closed_at=closed_at,
        ))
    return out


def summarize_checks(rollup: Any) -> tuple[str | None, list[str]]:
    """Return (overall_conclusion, failed_check_names)."""
    nodes: list[Any] = []
    if isinstance(rollup, list):
        # gh --json statusCheckRollup returns list sometimes? in list form it's contexts
        nodes = rollup
    elif isinstance(rollup, dict):
        nodes = rollup.get("nodes") or rollup.get("contexts") or []
        if isinstance(nodes, dict):
            nodes = nodes.get("nodes") or []
    if not isinstance(nodes, list):
        return None, []
    failed: list[str] = []
    states: list[str] = []
    for n in nodes:
        if not isinstance(n, dict):
            continue
        typename = n.get("__typename") or ""
        name = n.get("name") or n.get("context") or ""
        # CheckRun: status, conclusion. StatusContext: state
        conclusion = (n.get("conclusion") or "").upper()
        status = (n.get("status") or "").upper()
        state = (n.get("state") or "").upper()
        if typename == "CheckRun":
            if status and status != "COMPLETED":
                states.append("PENDING")
                continue
            c = conclusion or "UNKNOWN"
        elif typename == "StatusContext":
            c = state or "UNKNOWN"
        else:
            c = conclusion or state or status or "UNKNOWN"
        states.append(c)
        if c in factory.FAIL_STATES:
            if isinstance(name, str) and name:
                failed.append(name)
    if not states:
        return None, []
    if any(s in factory.FAIL_STATES for s in states):
        overall = "failure"
    elif any(s == "PENDING" for s in states):
        overall = "pending"
    elif all(s in ("SUCCESS", "NEUTRAL", "SKIPPED") for s in states):
        overall = "success"
    else:
        overall = "mixed"
    # dedupe, keep stable order
    seen = set()
    uniq_failed = []
    for f in failed:
        if f not in seen:
            seen.add(f)
            uniq_failed.append(f)
    return overall, uniq_failed


def count_human_commits(pr: dict[str, Any], factory_login: str) -> int | None:
    commits = pr.get("commits")
    nodes = None
    if isinstance(commits, dict):
        nodes = commits.get("nodes")
    elif isinstance(commits, list):
        nodes = commits
    if not isinstance(nodes, list):
        return None
    if not factory_login:
        # cannot distinguish; best not invent
        return None
    human = 0
    saw = False
    for c in nodes:
        if not isinstance(c, dict):
            continue
        commit = c.get("commit") if isinstance(c.get("commit"), dict) else c
        if not isinstance(commit, dict):
            continue
        saw = True
        authors = []
        for key in ("author", "committer"):
            a = commit.get(key)
            if isinstance(a, dict):
                user = a.get("user")
                if isinstance(user, dict) and user.get("login"):
                    authors.append(user["login"])
                elif a.get("name"):
                    authors.append(a.get("name"))
        # also GitHub API shape: commit.authors.nodes or commit.author.login
        login = ""
        a = commit.get("author")
        if isinstance(a, dict):
            u = a.get("user")
            if isinstance(u, dict):
                login = u.get("login") or ""
        if login:
            is_human = login != factory_login
        else:
            # if we can't attribute, do not count as human
            is_human = False
        if is_human:
            human += 1
    return human if saw else None


def events_for_issue(issue: dict[str, Any], timeline: list[dict[str, Any]] | None,
                     repo: str, observed_at: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if not isinstance(issue, dict):
        return out
    issue_id = _int_or_none(issue.get("number") or issue.get("issue_id"))
    if issue_id is None:
        return out
    node_id = issue.get("id") or issue.get("node_id") or str(issue_id)

    # approved - owner approved label added
    for ev in (timeline or []):
        if not isinstance(ev, dict):
            continue
        ev_type = (ev.get("event") or "").lower()
        if ev_type in ("labeled",):
            label = ev.get("label") or {}
            lname = label.get("name") if isinstance(label, dict) else None
            if _safe_label_name(lname) == "owner approved":
                created_at = _iso(ev.get("created_at") or ev.get("createdAt"))
                ev_id = ev.get("id") or ev.get("node_id") or f"{issue_id}:owner-approved:{created_at}"
                if created_at:
                    out.append(make_outcome_event(
                        "issue.approved", repo, str(ev_id), created_at, created_at, observed_at,
                        issue_id=issue_id, approved_at=created_at,
                    ))
        if ev_type == "closed":
            closed_at = _iso(ev.get("created_at") or ev.get("createdAt"))
            ev_id = ev.get("id") or ev.get("node_id") or f"{issue_id}:closed:{closed_at}"
            if closed_at:
                state_reason = ev.get("state_reason") or ev.get("stateReason") or ""
                if isinstance(state_reason, str):
                    state_reason = state_reason.strip().lower()
                else:
                    state_reason = ""
                fields = {"issue_id": issue_id, "closed_at": closed_at}
                if state_reason:
                    fields["state_reason"] = state_reason
                out.append(make_outcome_event(
                    "issue.closed", repo, str(ev_id), closed_at, closed_at, observed_at, **fields,
                ))
        if ev_type == "reopened":
            reopened_at = _iso(ev.get("created_at") or ev.get("createdAt"))
            ev_id = ev.get("id") or ev.get("node_id") or f"{issue_id}:reopened:{reopened_at}"
            if reopened_at:
                out.append(make_outcome_event(
                    "issue.reopened", repo, str(ev_id), reopened_at, reopened_at, observed_at,
                    issue_id=issue_id, reopened_at=reopened_at,
                ))

    # Fallback if timeline missing: use issue state for closed
    if not timeline:
        state = (issue.get("state") or "").upper()
        closed_at = _iso(issue.get("closedAt") or issue.get("closed_at"))
        if state == "CLOSED" and closed_at:
            fields = {"issue_id": issue_id, "closed_at": closed_at}
            sr = issue.get("stateReason") or issue.get("state_reason")
            if isinstance(sr, str) and sr.strip():
                fields["state_reason"] = sr.strip().lower()
            out.append(make_outcome_event(
                "issue.closed", repo, node_id, closed_at, closed_at, observed_at, **fields,
            ))
    return out


def load_watermark(path: str) -> str | None:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            ts = data.get("last_successful_reconcile")
            if isinstance(ts, str) and ts.strip():
                return ts.strip()
    except FileNotFoundError:
        return None
    except Exception:
        return None
    return None


def save_watermark(path: str, ts: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"last_successful_reconcile": ts}, f)
        f.write("\n")
    os.replace(tmp, path)


def gh_json(*args: str) -> Any:
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "").strip())
    return json.loads(r.stdout or "null")


def gh_text(*args: str) -> str:
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "").strip())
    return r.stdout


def fetch_factory_prs(repo: str, since: str | None = None) -> list[dict[str, Any]]:
    # Fetch all PRs; filter to factory/issue-* heads. Include fields needed for events.
    fields = ",".join([
        "number", "id", "headRefName", "headRefOid", "createdAt", "closedAt", "mergedAt", "updatedAt",
        "state", "isDraft", "additions", "deletions", "changedFiles",
        "reviews", "statusCheckRollup", "commits", "author",
    ])
    prs = gh_json("pr", "list", "--state", "all", "--limit", "200", "--json", fields)
    if not isinstance(prs, list):
        return []
    out = []
    for pr in prs:
        if not isinstance(pr, dict):
            continue
        if not is_factory_pr(pr):
            continue
        if since:
            timestamps = [
                _iso(pr.get("updatedAt")),
                _iso(pr.get("mergedAt")),
                _iso(pr.get("closedAt")),
                _iso(pr.get("createdAt")),
            ]
            # include if any known timestamp is >= since or if we can't tell
            known = [t for t in timestamps if t]
            if known and max(known) < since:
                continue
        out.append(pr)
    return out


def fetch_issue(repo: str, number: int) -> dict[str, Any]:
    data = gh_json("issue", "view", str(number), "--json", "number,id,state,closedAt,stateReason,labels")
    return data if isinstance(data, dict) else {"number": number}


def fetch_issue_timeline(repo: str, number: int) -> list[dict[str, Any]]:
    # gh api returns timeline events; paginate
    try:
        out = gh_text("api", f"repos/{repo}/issues/{number}/timeline", "--paginate",
                      "-H", "Accept: application/vnd.github+json")
    except Exception:
        return []
    # gh api --paginate may concatenate JSON arrays or objects; handle both
    events: list[dict[str, Any]] = []
    decoder = json.JSONDecoder()
    idx = 0
    s = out.strip()
    while idx < len(s):
        while idx < len(s) and s[idx].isspace():
            idx += 1
        if idx >= len(s):
            break
        try:
            obj, end = decoder.raw_decode(s, idx)
        except Exception:
            break
        idx = end
        if isinstance(obj, list):
            for e in obj:
                if isinstance(e, dict):
                    events.append(e)
        elif isinstance(obj, dict):
            events.append(obj)
    return events


def collect_reconcile_events(prs: list[dict[str, Any]], repo: str, factory_login: str,
                             observed_at: str,
                             issue_provider=None) -> list[dict[str, Any]]:
    """Pure-ish collection: issue_provider(issue_number)->(issue_dict, timeline_list)."""
    events: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    issue_numbers: set[int] = set()
    for pr in prs or []:
        for ev in events_for_pr(pr, repo, factory_login, observed_at):
            eid = ev.get("event_id")
            if isinstance(eid, str) and eid in seen_ids:
                continue
            if isinstance(eid, str):
                seen_ids.add(eid)
            events.append(ev)
        iid = issue_id_from_head((pr or {}).get("headRefName") or (pr or {}).get("head_branch") or "")
        if iid is not None:
            issue_numbers.add(iid)

    if issue_provider is not None:
        for iid in sorted(issue_numbers):
            try:
                issue, timeline = issue_provider(iid)
            except Exception:
                continue
            for ev in events_for_issue(issue or {"number": iid}, timeline, repo, observed_at):
                eid = ev.get("event_id")
                if isinstance(eid, str) and eid in seen_ids:
                    continue
                if isinstance(eid, str):
                    seen_ids.add(eid)
                events.append(ev)
    return events


def emit_events(events: list[dict[str, Any]], log_file: str) -> int:
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    written = 0
    with open(log_file, "a", encoding="utf-8") as f:
        for ev in events:
            line = json.dumps(ev, ensure_ascii=False, separators=(",", ":"))
            f.write(line + "\n")
            written += 1
    return written


def default_issue_provider(repo: str):
    def provider(number: int):
        issue = fetch_issue(repo, number)
        timeline = fetch_issue_timeline(repo, number)
        return issue, timeline
    return provider


def run_reconcile(repo: str, factory_login: str, log_file: str, state_file: str,
                  since: str | None = None, observed_at: str | None = None,
                  prs: list[dict[str, Any]] | None = None,
                  issue_provider=None) -> dict[str, Any]:
    observed_at = observed_at or now_iso()
    watermark = since or load_watermark(state_file)
    if prs is None:
        prs = fetch_factory_prs(repo, since=watermark)
    if issue_provider is None:
        issue_provider = default_issue_provider(repo)
    events = collect_reconcile_events(prs, repo, factory_login, observed_at, issue_provider=issue_provider)
    written = emit_events(events, log_file) if events else 0
    save_watermark(state_file, observed_at)
    return {"written": written, "events": len(events), "watermark": observed_at}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Reconcile factory GitHub outcomes into v2 events")
    ap.add_argument("--since", default=None, help="ISO timestamp; overrides watermark")
    ap.add_argument("--repo", default=REPO, help="owner/name")
    ap.add_argument("--factory-login", default=FACTORY_LOGIN)
    ap.add_argument("--log-file", default=FACTORY_LOG_FILE)
    ap.add_argument("--state-file", default=RECONCILE_STATE_FILE)
    ap.add_argument("--dry-run", action="store_true", help="Collect and print count, do not write")
    args = ap.parse_args(argv)

    repo = args.repo
    if not repo or repo == "unknown":
        try:
            repo = gh_json("repo", "view", "--json", "nameWithOwner").get("nameWithOwner", "")
        except Exception:
            repo = repo or ""
    if not repo:
        print("reconcile: repo unknown", file=sys.stderr)
        return 2

    observed_at = now_iso()
    try:
        watermark = args.since or load_watermark(args.state_file)
        prs = fetch_factory_prs(repo, since=watermark)
        events = collect_reconcile_events(prs, repo, args.factory_login, observed_at,
                                          issue_provider=default_issue_provider(repo))
        if args.dry_run:
            print(json.dumps({"events": len(events), "watermark": watermark, "observed_at": observed_at}))
            return 0
        written = emit_events(events, args.log_file) if events else 0
        save_watermark(args.state_file, observed_at)
        print(json.dumps({"written": written, "events": len(events), "watermark": observed_at}))
        return 0
    except Exception as e:
        print(f"reconcile: failed: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
