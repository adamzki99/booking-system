#!/usr/bin/env python3
"""Allowlisting HTTP/CONNECT proxy for disposable factory agent sandboxes.

The proxy accepts only destinations whose host appears in an explicit
allowlist. Every other destination is answered with HTTP 403. It is intended
to run on the factory host on loopback while the agent session runs in a
bwrap sandbox that shares the host network namespace; the sandbox receives
the proxy address through the standard proxy environment variables.

Secrets are never logged. Request URLs, headers and bodies are never written
to stdout or stderr. Diagnostics are limited to the bound address and a
startup failure message.
"""
import argparse
import os
import select
import signal
import socket
import socketserver
import sys

# Destinations needed by factory sessions by default:
#   GitHub (git/gh), the Go module proxy and checksum db, the npm registry,
#   and common model provider endpoints used by OpenCode. Extra hosts can be
#   added with --extra-hosts (for example a self-hosted OpenCode endpoint).
DEFAULT_ALLOWLIST = (
    "github.com",
    "api.github.com",
    "www.github.com",
    "raw.githubusercontent.com",
    "objects.githubusercontent.com",
    "codeload.github.com",
    "proxy.golang.org",
    "sum.golang.org",
    "registry.npmjs.org",
    "api.opencode.ai",
    "opencode.ai",
    "api.anthropic.com",
    "api.openai.com",
    "openrouter.ai",
    "api.openrouter.ai",
)
MAX_LINE = 8192
RELAY_TIMEOUT = 30


def normalise_host(host):
    """Lowercase a hostname and drop a trailing dot without resolving it."""
    return str(host or "").strip().lower().rstrip(".")


def parse_allowlist(raw, extra=""):
    """Return a set of (host, port) entries; port None means any port.

    Entries may be bare hostnames or host:port pairs. Ports are restricted to
    decimal integers; malformed entries are ignored so a typo cannot widen
    the allowlist by accident.
    """
    entries = set()
    for item in list(raw or []) + list(extra or []):
        part = str(item).strip()
        if not part:
            continue
        if ":" in part:
            host, _, port = part.rpartition(":")
            if not port.isdigit():
                continue
            entries.add((normalise_host(host), int(port)))
        else:
            entries.add((normalise_host(part), None))
    entries.discard(("", None))
    return entries


def is_allowed(host, port, allowlist):
    """True when host:port matches an allowlist entry."""
    host = normalise_host(host)
    if not host:
        return False
    try:
        port = int(port)
    except (TypeError, ValueError):
        return False
    return (host, None) in allowlist or (host, port) in allowlist


def _relay(left, right):
    while True:
        try:
            readable, _, _ = select.select([left, right], [], [], RELAY_TIMEOUT)
        except (OSError, ValueError):
            return
        if not readable:
            return
        for source in readable:
            target = right if source is left else left
            try:
                data = source.recv(65536)
            except OSError:
                return
            if not data:
                return
            try:
                target.sendall(data)
            except OSError:
                return


def _deny(client):
    body = b"403 Forbidden\n"
    client.sendall(
        b"HTTP/1.1 403 Forbidden\r\n"
        b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n"
        b"Connection: close\r\n\r\n" + body
    )


def _destination(line):
    """Return (host, port) for a CONNECT authority or an absolute HTTP URL."""
    target = line.split(" ", 2)[1] if len(line.split(" ", 2)) > 1 else ""
    if not target:
        return "", 0
    if target.startswith("http://"):
        target = target[len("http://"):]
        target = target.split("/", 1)[0]
    if ":" in target:
        host, _, port = target.rpartition(":")
        if port.isdigit():
            return host, int(port)
        target = host
    return target, 80


class ProxyHandler(socketserver.BaseRequestHandler):
    def handle(self):
        client = self.request
        client.settimeout(RELAY_TIMEOUT)
        try:
            stream = client.makefile("rb")
            line = stream.readline(MAX_LINE)
            if not line:
                return
            method = line.split(b" ", 1)[0].upper()
            try:
                text = line.decode("ascii", "replace").strip()
            except Exception:
                _deny(client)
                return
            host, port = _destination(text)
            if not is_allowed(host, port, self.server.allowlist):
                _deny(client)
                return
            # Read request headers exactly once. Reading them twice would
            # swallow the body and forward a malformed request upstream.
            headers = []
            length = 0
            for _ in range(64):
                header = stream.readline(MAX_LINE)
                if not header or header in (b"\r\n", b"\n"):
                    break
                headers.append(header)
                if header.lower().startswith(b"content-length:"):
                    try:
                        length = int(header.split(b":", 1)[1].strip())
                    except ValueError:
                        length = 0
            try:
                upstream = socket.create_connection((host, port), timeout=RELAY_TIMEOUT)
            except OSError:
                _deny(client)
                return
            with upstream:
                upstream.settimeout(RELAY_TIMEOUT)
                if method == b"CONNECT":
                    client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                else:
                    # Force close so the bidirectional relay terminates.
                    forwarded = line + b"".join(headers) + b"Connection: close\r\n\r\n"
                    # Guard against unbounded bodies from a compromised client.
                    if 0 < length <= 4 * 1024 * 1024:
                        forwarded += stream.read(length)
                    upstream.sendall(forwarded)
                _relay(client, upstream)
        except (OSError, socket.timeout):
            return


class ProxyServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, address, allowlist):
        self.allowlist = allowlist
        super().__init__(address, ProxyHandler)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=0, help="0 selects an ephemeral port")
    ap.add_argument("--port-file", help="write the bound port to this file once listening")
    ap.add_argument("--allowlist", default=",".join(DEFAULT_ALLOWLIST),
                    help="comma-separated host[:port] allowlist (default: built-in)")
    ap.add_argument("--extra-hosts", default=os.environ.get("FACTORY_OPENCODE_ENDPOINT_HOSTS", ""),
                    help="additional comma-separated hosts for the OpenCode endpoint")
    args = ap.parse_args(argv)

    allowlist = parse_allowlist(args.allowlist.split(","), args.extra_hosts.split(","))
    if not allowlist:
        print("egress proxy: empty allowlist", file=sys.stderr)
        return 2
    server = ProxyServer((args.host, args.port), allowlist)
    if args.port_file:
        try:
            with open(args.port_file, "w", encoding="ascii") as handle:
                handle.write(str(server.server_address[1]))
        except OSError as exc:
            print(f"egress proxy: cannot write port file: {exc}", file=sys.stderr)
            server.server_close()
            return 1

    def stop(_signum, _frame):
        # serve_forever is interrupted from another thread in main().
        pass

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
