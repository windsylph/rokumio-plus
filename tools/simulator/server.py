# Rokumio+ desktop simulator host (npm run sim).
#
# Serves tools/simulator/web with the COOP/COEP headers brs-engine needs
# (SharedArrayBuffer), a same-origin proxy at /proxy/<url> so add-on and image
# requests pass COEP, an optional local test add-on at /addon/manifest.json
# (streams web/test.mp4, see make-test-video.sh), and /save/<name>.png for
# display captures.
import http.server, socketserver, sys, urllib.request, urllib.error, urllib.parse, os, threading, webbrowser
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web")
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=ROOT, **k)
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
    def addon(self):
        # A tiny local Stremio add-on for simulator screenshots: every movie and
        # episode gets two direct streams of the local test clip.
        import json as _j
        path = self.path.split("?")[0]
        if path.endswith("/manifest.json"):
            body = {"id": "local.test.streams", "version": "1.0.0", "name": "Local Test",
                    "description": "Simulator test streams", "resources": ["stream"],
                    "types": ["movie", "series"], "idPrefixes": ["tt"], "catalogs": []}
        elif "/stream/" in path:
            host = "http://" + self.headers.get("Host", "localhost:6502")
            body = {"streams": [
                {"name": "Local Test\n1080p", "title": "Test clip 1080p", "url": host + "/test.mp4",
                 "behaviorHints": {"bingeGroup": "local-1080p", "filename": "test.1080p.mp4"}},
                {"name": "Local Test\n720p", "title": "Test clip 720p", "url": host + "/test.mp4",
                 "behaviorHints": {"bingeGroup": "local-720p", "filename": "test.720p.mp4"}}]}
        else:
            self.send_response(404); self.end_headers(); return
        data = _j.dumps(body).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def video(self):
        f = os.path.join(ROOT, "test.mp4")
        if not os.path.exists(f):
            self.send_response(404); self.end_headers(); return
        size = os.path.getsize(f)
        rng = self.headers.get("Range")
        start, end = 0, size - 1
        if rng and rng.startswith("bytes="):
            a, b = rng[6:].split("-")
            start = int(a) if a else 0
            end = int(b) if b else min(size - 1, start + 8 * 1024 * 1024)
            self.send_response(206); self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        else:
            end = size - 1; self.send_response(200)
        self.send_header("Content-Type", "video/mp4"); self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1)); self.end_headers()
        with open(f, "rb") as fh:
            fh.seek(start); left = end - start + 1
            while left > 0:
                chunk = fh.read(min(left, 1 << 20))
                if not chunk: break
                try: self.wfile.write(chunk)
                except Exception: return
                left -= len(chunk)
    def do_HEAD(self):
        if self.path.split("?")[0] == "/test.mp4" and os.path.exists(os.path.join(ROOT, "test.mp4")):
            size = os.path.getsize(os.path.join(ROOT, "test.mp4"))
            self.send_response(200); self.send_header("Content-Type", "video/mp4"); self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(size)); self.end_headers(); return
        return super().do_HEAD()
    def do_GET(self):
        if self.path.startswith("/addon/"): return self.addon()
        if self.path.split("?")[0] == "/test.mp4": return self.video()
        if self.path.startswith("/proxy/"): return self.forward("GET")
        return super().do_GET()
    def forward(self, method):
        # Same-origin proxy for the app's network calls. Forwards the method,
        # body and content headers, and passes the upstream status and body
        # through untouched: the Stremio account API (addonCollectionGet,
        # datastoreGet, ...) is POST, and the app reads real 4xx/5xx answers.
        url = self.path[len("/proxy/"):]
        if not url.startswith("http"): url = urllib.parse.unquote(url)
        body = None
        if method == "POST":
            n = int(self.headers.get("Content-Length", "0") or "0")
            body = self.rfile.read(n) if n > 0 else b""
        headers = {"User-Agent": "Roku/DVP-15.3"}
        for h in ("Content-Type", "Accept", "Authorization", "Range"):
            if self.headers.get(h): headers[h] = self.headers.get(h)
        status, ctype, data = 502, "text/plain", b""
        try:
            req = urllib.request.Request(url, data=body, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=60) as r:
                status, ctype, data = r.status, r.headers.get("Content-Type", "application/octet-stream"), r.read()
        except urllib.error.HTTPError as e:
            status, ctype, data = e.code, e.headers.get("Content-Type", "text/plain"), e.read()
        except Exception as e:
            data = str(e).encode()
        self.send_response(status); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_POST(self):
        if self.path.startswith("/proxy/"): return self.forward("POST")
        # /save/<name>.png — the page posts a capture of the display buffer.
        if self.path.startswith("/save/"):
            name = os.path.basename(self.path[len("/save/"):])
            n = int(self.headers.get("Content-Length", "0"))
            data = self.rfile.read(n)
            out = os.path.join(ROOT, "shots"); os.makedirs(out, exist_ok=True)
            with open(os.path.join(out, name), "wb") as f: f.write(data)
            self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"ok")
            return
        self.send_response(404); self.end_headers()
    def log_message(self, *a): pass
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 6502
HELP = f"""
Rokumio+ simulator running at http://localhost:{PORT}  (Ctrl+C to stop)

  Remote            Keyboard
  ----------------  ------------------------------
  D-pad             Arrow keys
  OK                Enter
  Back              Esc  (or Delete)
  Play/Pause        End
  Rewind / FF       PageUp / PageDown  (Cmd+Left / Cmd+Right)
  Replay            Backspace
  * (options)       Insert  (or Ctrl+8)
  Home              Home  (closes the app; reload the page to restart)
  Text entry        type letters/digits in keyboard dialogs

Hold an arrow key in the player to try progressive scrubbing.
Test add-on for playback: install  http://localhost:{PORT}/addon/manifest.json
  in Add-ons > Add add-on (needs web/test.mp4: npm run sim:video).
"""
socketserver.ThreadingTCPServer.allow_reuse_address = True
try:
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", PORT), H)
except OSError as e:
    if getattr(e, "errno", None) == 48 or "in use" in str(e):
        print(f"""
Port {PORT} is already in use — another simulator is probably still running
(in another terminal tab). Stop it with Ctrl+C in that tab, or run:

    npm run sim:stop

then start again with:  npm run sim
""", flush=True)
        sys.exit(1)
    raise
with srv:
    print(HELP, flush=True)
    if "--no-open" not in sys.argv:
        threading.Timer(1.0, lambda: webbrowser.open(f"http://localhost:{PORT}/")).start()
    srv.serve_forever()
