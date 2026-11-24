import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

FACTORY_DIR = Path(__file__).resolve().parents[2] / "factory"


def run_discovery(tmp_path, name, fixture, trusted="owner", factory_login="factory-bot"):
    tmp = tmp_path / name
    bin_dir = tmp / "bin"
    bin_dir.mkdir(parents=True)
    gh_log = tmp / "gh.log"
    fixture_path = tmp / "fixture.json"
    fixture_path.write_text(json.dumps(fixture), encoding="utf-8")
    gh = bin_dir / "gh"
    gh.write_text(
        """#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["GH_LOG"], "a", encoding="utf-8") as log:
    log.write(" ".join(args) + "\\n")
with open(os.environ["GH_FIXTURE"], encoding="utf-8") as source:
    fixture = json.load(source)


def option(name):
    try:
        return args[args.index(name) + 1]
    except (ValueError, IndexError):
        return ""


if args[:2] == ["repo", "view"]:
    print(json.dumps({"owner": {"login": "owner"}, "nameWithOwner": "owner/repo"}))
elif args[:2] == ["issue", "list"]:
    print(json.dumps(fixture.get("issues", [])))
elif args[:2] == ["pr", "list"]:
    print(json.dumps(fixture.get("prs", [])))
elif args[:2] == ["api", "graphql"]:
    print(json.dumps({"data": {"user": {"projectsV2": {"nodes": []}}, "organization": {"projectsV2": {"nodes": []}}}}))
else:
    print("[]")
""",
        encoding="utf-8",
    )
    gh.chmod(0o755)
    env = os.environ.copy()
    env.update(
        PATH=f"{bin_dir}{os.pathsep}{env['PATH']}",
        GH_FIXTURE=str(fixture_path),
        GH_LOG=str(gh_log),
        FACTORY_TRUSTED_LOGINS=trusted,
        FACTORY_LOGIN=factory_login,
        PYTHONDONTWRITEBYTECODE="1",
    )
    result = subprocess.run(
        [sys.executable, str(FACTORY_DIR / name)],
        cwd=FACTORY_DIR.parents[1],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    return result, gh_log.read_text(encoding="utf-8") if gh_log.exists() else ""


@pytest.mark.parametrize(
    "script",
    ["discover_build_candidates.py", "discover_fix_candidates.py"],
)
def test_discovery_without_trusted_logins_queries_nothing(tmp_path, script):
    result, gh_log = run_discovery(
        tmp_path,
        script,
        {"issues": [{"number": 1, "author": {"login": "owner"}}], "prs": []},
        trusted="",
        factory_login="",
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout == ""
    assert gh_log == ""


def test_build_discovery_keeps_only_trusted_authors(tmp_path):
    data = {
        "issues": [
            {"number": 1, "createdAt": "2026-01-01", "author": {"login": "outsider"}},
            {"number": 2, "createdAt": "2026-01-02", "author": {"login": "OWNER"}},
            {"number": 3, "createdAt": "2026-01-03", "author": {"login": "factory-bot"}},
        ]
    }

    result, gh_log = run_discovery(tmp_path, "discover_build_candidates.py", data)

    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == ["2", "3"]
    assert "number,createdAt,author" in gh_log


def test_fix_discovery_keeps_only_trusted_same_repo_prs(tmp_path):
    def pr(number, **overrides):
        value = {
            "number": number,
            "headRefName": f"factory/issue-{number}",
            "headRefOid": f"sha-{number}",
            "mergeable": "CONFLICTING",
            "reviewDecision": "",
            "statusCheckRollup": [],
            "isDraft": False,
            "createdAt": f"2026-01-{number:02d}",
            "isCrossRepository": False,
            "author": {"login": "owner"},
            "headRepositoryOwner": {"login": "owner"},
        }
        value.update(overrides)
        return value

    data = {
        "prs": [
            pr(1),
            pr(2, isCrossRepository=True),
            pr(3, author={"login": "outsider"}),
            pr(4, headRepositoryOwner={"login": "fork-owner"}),
        ]
    }

    result, gh_log = run_discovery(tmp_path, "discover_fix_candidates.py", data)

    assert result.returncode == 0, result.stderr
    assert [line.split("\t")[:2] for line in result.stdout.splitlines()] == [["1", "1"]]
    assert "isCrossRepository,author,headRepositoryOwner" in gh_log
