#!/usr/bin/env python3
"""Command relay for the Samsung TV agent loop.

The TV polls GET /cmd (one command at a time), executes it as root, and POSTs
the output to /out. Nothing ever connects *into* the TV.
"""
import hmac
import json
import os
import secrets
import socketserver
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

STATE = os.environ.get("TV_AGENT_STATE", "/var/lib/tv-agent")
TOKEN_FILE = os.environ.get("TV_AGENT_TOKEN_FILE", "/etc/tv-agent.token")
# 0.0.0.0 so a stock host works without editing anything; the token gates access.
BIND = os.environ.get("TV_AGENT_BIND", "0.0.0.0")
PORT = int(os.environ.get("TV_AGENT_PORT", "8899"))
MAX_OUT = 400_000
LOCK = threading.Lock()
LAST_POLL = {"ts": 0.0}


def token():
    """Read once; the relay cannot authenticate anything without it."""
    global _TOKEN
    if _TOKEN is None:
        try:
            with open(TOKEN_FILE) as f:
                _TOKEN = f.read().strip()
        except OSError:
            raise SystemExit("tv-agent-server: %s missing - generate a token first "
                             "(openssl rand -hex 24 > %s; chmod 600)" % (TOKEN_FILE, TOKEN_FILE))
        if not _TOKEN:
            raise SystemExit("tv-agent-server: %s is empty" % TOKEN_FILE)
    return _TOKEN


_TOKEN = None


def path(name):
    return os.path.join(STATE, name)


def read_json(name, default):
    try:
        with open(path(name)) as f:
            return json.load(f)
    except Exception:
        return default


def write_json(name, obj):
    tmp = path(name + ".tmp")
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path(name))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _auth(self, q):
        return hmac.compare_digest(q.get("t", [""])[0], token())

    def _send(self, code, body=b"", ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if not self._auth(q):
            return self._send(403, b"forbidden")
        if u.path == "/cmd":
            LAST_POLL["ts"] = time.time()
            with LOCK:
                queue = read_json("queue.json", [])
                if not queue:
                    return self._send(204)
                cid, cmd = queue.pop(0)
                write_json("queue.json", queue)
                write_json("inflight.json", {"id": cid, "cmd": cmd, "ts": time.time()})
            return self._send(200, (cid + "\n" + cmd).encode())
        if u.path == "/result":
            cid = q.get("id", [""])[0]
            r = read_json("result.json", {})
            if r.get("id") == cid and r.get("done"):
                return self._send(200, json.dumps({"rc": r["rc"], "out": r["out"]}).encode(), "application/json")
            return self._send(204)
        if u.path == "/status":
            inflight = read_json("inflight.json", {})
            queue = read_json("queue.json", [])
            age = round(time.time() - LAST_POLL["ts"], 1) if LAST_POLL["ts"] else -1
            body = json.dumps({
                "last_poll_age_s": age,
                "alive": age >= 0 and age < 4,
                "queued": len(queue),
                "inflight": inflight.get("id"),
            }).encode()
            return self._send(200, body, "application/json")
        if u.path == "/ping":
            return self._send(200, b"ok")
        return self._send(404, b"not found")

    def do_POST(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if not self._auth(q):
            return self._send(403, b"forbidden")
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        if u.path == "/enqueue":
            if not body.strip():
                return self._send(400, b"empty command")
            with LOCK:
                queue = read_json("queue.json", [])
                cid = "%d-%s" % (int(time.time() * 1000), secrets.token_hex(3))
                queue.append([cid, body])
                write_json("queue.json", queue)
            return self._send(200, cid.encode())
        if u.path == "/reset":
            with LOCK:
                write_json("queue.json", [])
                write_json("inflight.json", {})
                write_json("result.json", {})
            return self._send(200, b"reset")
        if u.path == "/out":
            rc = int(q.get("rc", ["1"])[0])
            with LOCK:
                fl = read_json("inflight.json", {})
                cid = fl.get("id") or q.get("id", [""])[0]
                write_json("result.json", {"id": cid, "rc": rc, "out": body[:MAX_OUT], "done": True, "ts": time.time()})
                write_json("inflight.json", {})
            return self._send(200, b"ok")
        return self._send(404, b"not found")


class Server(ThreadingHTTPServer):
    """Skip HTTPServer's reverse-DNS call, which blocks ~16 s on this host."""

    daemon_threads = True
    allow_reuse_address = True

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name = BIND
        self.server_port = PORT


def main():
    os.makedirs(STATE, exist_ok=True)
    for f in ("queue.json", "inflight.json", "result.json"):
        if not os.path.exists(path(f)):
            write_json(f, [] if f == "queue.json" else {})
    srv = Server((BIND, PORT), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()
