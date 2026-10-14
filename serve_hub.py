"""Local start page for the macOS SEB demonstration profile."""

import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import subprocess
import threading
import time

HOST = "127.0.0.1"
PORT = 18765
PAGE = (Path(__file__).parent / "hub" / "index.html").read_bytes()
SCRIPT = (Path(__file__).parent / "hub" / "app.js").read_bytes()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            body = PAGE
            content_type = "text/html; charset=utf-8"
        elif self.path == "/app.js":
            body = SCRIPT
            content_type = "application/javascript; charset=utf-8"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; script-src 'self'; base-uri 'none'; form-action 'none'")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)


def stop_when_seb_exits(server):
    deadline = time.monotonic() + 45
    seb_seen = False
    while True:
        running = subprocess.run(
            ["/usr/bin/pgrep", "-x", "Safe Exam Browser"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode == 0
        if running:
            seb_seen = True
        elif seb_seen or time.monotonic() >= deadline:
            server.shutdown()
            return
        time.sleep(2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--stop-when-seb-exits", action="store_true")
    args = parser.parse_args()
    server = HTTPServer((HOST, PORT), Handler)
    if args.stop_when_seb_exits:
        threading.Thread(target=stop_when_seb_exits, args=(server,), daemon=True).start()
    try:
        server.serve_forever()
    finally:
        server.server_close()
