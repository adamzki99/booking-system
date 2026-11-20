#!/usr/bin/env python3
"""Mint a short-lived GitHub App installation token.

Reads an app private key, mints a JWT, resolves the installation for a
repository (or uses a provided installation id), and exchanges it for an
installation access token. Prints only the token to stdout; diagnostics go
to stderr. Secrets are never logged.
"""
import argparse
import datetime
import json
import os
import re
import sys
import urllib.request
import urllib.error


def _read_key(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def _jwt(app_id, key_pem):
    import jwt as pyjwt

    now = datetime.datetime.now(datetime.timezone.utc)
    payload = {
        "iat": int((now - datetime.timedelta(seconds=60)).timestamp()),
        "exp": int((now + datetime.timedelta(minutes=9)).timestamp()),
        "iss": str(app_id),
    }
    return pyjwt.encode(payload, key_pem, algorithm="RS256")


def _request(method, url, token, data=None):
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = None
    if data is not None:
        body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = {"message": raw}
        return e.code, parsed


def _repo_from_git(repo_root):
    import subprocess

    try:
        url = subprocess.check_output(
            ["git", "-C", repo_root, "config", "--get", "remote.origin.url"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except Exception:
        return None
    m = re.search(r"github\.com[:/](?P<owner>[^/]+)/(?P<repo>[^/]+?)(?:\.git)?$", url)
    if not m:
        return None
    return f"{m.group('owner')}/{m.group('repo')}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app-id", required=True)
    ap.add_argument("--key-file")
    ap.add_argument("--key", help="private key PEM (avoid; prefer --key-file)")
    ap.add_argument("--installation-id")
    ap.add_argument("--repo", help="owner/name")
    ap.add_argument("--repo-root", default=".")
    args = ap.parse_args()

    if args.key_file:
        key_pem = _read_key(args.key_file)
    elif args.key:
        key_pem = args.key
    else:
        # allow env
        env_key = os.environ.get("FACTORY_GITHUB_APP_PRIVATE_KEY")
        env_file = os.environ.get("FACTORY_GITHUB_APP_PRIVATE_KEY_FILE")
        if env_file:
            key_pem = _read_key(env_file)
        elif env_key:
            key_pem = env_key
        else:
            print("missing private key", file=sys.stderr)
            return 2

    try:
        token_jwt = _jwt(args.app_id, key_pem)
    except Exception as e:
        print(f"jwt error: {e}", file=sys.stderr)
        return 2

    repo = args.repo or _repo_from_git(args.repo_root)
    install_id = args.installation_id or os.environ.get("FACTORY_GITHUB_INSTALLATION_ID")

    if not install_id:
        if not repo:
            print("cannot resolve repository; pass --repo or --repo-root", file=sys.stderr)
            return 2
        owner, name = repo.split("/", 1)
        status, data = _request("GET", f"https://api.github.com/repos/{owner}/{name}/installation", token_jwt)
        if status != 200:
            print(f"installation lookup failed: {status} {data}", file=sys.stderr)
            return 1
        install_id = data.get("id")
        if not install_id:
            print("no installation id returned", file=sys.stderr)
            return 1

    status, data = _request(
        "POST",
        f"https://api.github.com/app/installations/{install_id}/access_tokens",
        token_jwt,
        {},
    )
    if status != 201:
        print(f"token mint failed: {status} {data}", file=sys.stderr)
        return 1
    access_token = data.get("token")
    if not access_token:
        print("no token returned", file=sys.stderr)
        return 1
    # print only token
    sys.stdout.write(access_token)
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
