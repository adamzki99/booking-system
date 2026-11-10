#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
TRIAGE="$SCRIPT_DIR/../../decider/triage.sh"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }
pass() { PASS=$((PASS+1)); }

# unreachable service -> fallback, exit 0
set +e
out="$(DECIDER_URL="http://127.0.0.1:9" "$TRIAGE" 1 2>/dev/null)"
rc=$?
set -e
if [ "$rc" -eq 0 ] && echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d.get("fallback") is True'; then
  pass
else
  fail "unreachable case (rc=$rc out=$out)"
fi

# reachable service -> proposal, exit 0
port=18127
python3 - "$port" <<'PY' &
import http.server, socketserver, sys, json
port=int(sys.argv[1])
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n=int(self.headers.get('Content-Length',0)); self.rfile.read(n)
        data=json.dumps({"labels":["backend"],"confidence":0.9,"model":"m"}).encode()
        self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self,*a): pass
httpd=socketserver.TCPServer(("127.0.0.1",port),H)
httpd.serve_forever()
PY
srv_pid=$!
# wait for server
for i in $(seq 1 20); do
  python3 -c "import socket; s=socket.create_connection(('127.0.0.1',$port),1); s.close()" 2>/dev/null && break
  sleep 0.1
done
set +e
out="$(DECIDER_URL="http://127.0.0.1:$port" "$TRIAGE" 1 2>/dev/null)"
rc=$?
set -e
kill "$srv_pid" 2>/dev/null || true
wait "$srv_pid" 2>/dev/null || true
if [ "$rc" -eq 0 ] && echo "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d["labels"]==["backend"]'; then
  pass
else
  fail "reachable case (rc=$rc out=$out)"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
