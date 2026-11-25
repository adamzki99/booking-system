"""Tests for the factory sandbox egress allowlist proxy."""
import http.server
import os
import socket
import sys
import threading

import pytest

LIB = os.path.join(os.path.dirname(__file__), "..", "..", "factory", "lib")
sys.path.insert(0, os.path.abspath(LIB))

import egress_proxy  # noqa: E402


def test_default_allowlist_covers_factory_destinations():
    allow = egress_proxy.parse_allowlist(egress_proxy.DEFAULT_ALLOWLIST)
    for host in ("github.com", "proxy.golang.org", "registry.npmjs.org", "api.opencode.ai"):
        assert egress_proxy.is_allowed(host, 443, allow)
    assert not egress_proxy.is_allowed("example.com", 443, allow)


def test_parse_allowlist_ignores_malformed_entries():
    allow = egress_proxy.parse_allowlist(
        ["github.com", "api.github.com:443", "bad:port", "", "  "],
        ["extra.example:8443"],
    )
    assert egress_proxy.is_allowed("github.com", 22, allow)
    assert egress_proxy.is_allowed("api.github.com", 443, allow)
    assert not egress_proxy.is_allowed("api.github.com", 22, allow)
    assert egress_proxy.is_allowed("extra.example", 8443, allow)
    assert not egress_proxy.is_allowed("bad", 80, allow)


def test_is_allowed_normalises_host_case_and_trailing_dot():
    allow = egress_proxy.parse_allowlist(["GitHub.Com."])
    assert egress_proxy.is_allowed("github.com", 443, allow)
    assert egress_proxy.is_allowed("api.github.com", 443, allow) is False


def test_plain_http_request_is_forwarded_to_allowed_host():
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = self.path.encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):
            pass

    target = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    target_thread = threading.Thread(target=target.serve_forever, daemon=True)
    target_thread.start()
    server = egress_proxy.ProxyServer(
        ("127.0.0.1", 0),
        egress_proxy.parse_allowlist([f"127.0.0.1:{target.server_address[1]}"]),
    )
    proxy_thread = threading.Thread(target=server.serve_forever, daemon=True)
    proxy_thread.start()
    try:
        with socket.create_connection(server.server_address, timeout=2) as client:
            request = (
                f"GET http://127.0.0.1:{target.server_address[1]}/hello HTTP/1.1\r\n"
                "Host: 127.0.0.1\r\n\r\n"
            ).encode()
            client.sendall(request)
            client.settimeout(3)
            response = b""
            while b"/hello" not in response:
                chunk = client.recv(4096)
                if not chunk:
                    break
                response += chunk
        assert b"200 OK" in response and b"/hello" in response
    finally:
        server.shutdown()
        server.server_close()
        target.shutdown()
        target.server_close()
        proxy_thread.join(timeout=2)
        target_thread.join(timeout=2)


def test_connect_is_denied_for_unlisted_destination():
    server = egress_proxy.ProxyServer(
        ("127.0.0.1", 0),
        egress_proxy.parse_allowlist(["localhost"]),
    )
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with socket.create_connection(server.server_address, timeout=2) as client:
            client.sendall(b"CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n")
            status = client.recv(64)
        assert status.startswith(b"HTTP/1.1 403")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
