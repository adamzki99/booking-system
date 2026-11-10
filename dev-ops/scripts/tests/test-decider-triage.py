#!/usr/bin/env python3
import json, subprocess, os, sys, http.server, socketserver, threading

SCRIPT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "decider-triage.py"))

def run(env):
    return subprocess.run([sys.executable, SCRIPT, "1"], capture_output=True, text=True, env={**os.environ, **env}, timeout=15)

# unreachable
r = run({"DECIDER_URL": "http://127.0.0.1:9"})
assert r.returncode == 0, r
obj = json.loads(r.stdout)
assert obj.get("fallback") is True

# reachable
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n=int(self.headers.get('Content-Length',0)); self.rfile.read(n)
        data=json.dumps({"labels":["backend"],"confidence":0.9,"model":"m"}).encode()
        self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self,*a): pass
httpd = socketserver.TCPServer(("127.0.0.1", 8125), H)
t = threading.Thread(target=httpd.serve_forever, daemon=True); t.start()
r = run({"DECIDER_URL": "http://127.0.0.1:8125"})
httpd.shutdown()
assert r.returncode == 0, r
obj = json.loads(r.stdout)
assert obj["labels"] == ["backend"]
print("OK")
