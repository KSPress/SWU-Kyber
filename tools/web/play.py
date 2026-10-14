#!/usr/bin/env python3
"""Plays the SWU Kyber web build in your browser.

Godot web builds can't be opened straight from disk (file://); they need a
tiny local web server. This serves the folder this script sits in on
http://localhost:8060 (only reachable from this computer) and opens it.
Stdlib only. Close the window / press Ctrl+C to stop.
"""
import http.server
import os
import socketserver
import sys
import threading
import webbrowser

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
PORT = int(ARGS[0]) if ARGS else 8060
OPEN = "--no-open" not in sys.argv
# --lan: also reachable from phones/tablets on the same Wi-Fi (not the internet)
LAN = "--lan" in sys.argv


def lan_ip() -> str:
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.168.0.1", 9))   # no packet is sent; just picks the LAN interface
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()
ROOT = os.path.dirname(os.path.abspath(__file__))


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".pck": "application/octet-stream", ".js": "text/javascript"}

    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def end_headers(self):
        # cross-origin isolation (lets the browser use SharedArrayBuffer if a threaded build is used)
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, *a):
        pass


socketserver.ThreadingTCPServer.allow_reuse_address = True
socketserver.ThreadingTCPServer.daemon_threads = True
with socketserver.ThreadingTCPServer(("0.0.0.0" if LAN else "127.0.0.1", PORT), Handler) as httpd:
    url = f"http://localhost:{PORT}/index.html"
    print(f"SWU Kyber is running at {url}  (Ctrl+C to stop)")
    if LAN:
        print(f"On your phone (same Wi-Fi): http://{lan_ip()}:{PORT}/index.html")
    if OPEN:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
