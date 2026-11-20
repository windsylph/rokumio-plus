# Rokumio+ desktop simulator host (npm run sim).
#
# Serves tools/simulator/web with the COOP/COEP headers brs-engine needs
# (SharedArrayBuffer), a same-origin proxy at /proxy/<url> so add-on and image
# requests pass COEP, an optional local test add-on at /addon/manifest.json
# (streams web/test.mp4, see make-test-video.sh), and /save/<name>.png for
# display captures.
import http.server, http.client, socketserver, sys, urllib.request, urllib.error, urllib.parse, os, threading, time, webbrowser, collections
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web")

# --- upstream connections ---------------------------------------------------
# A shared pool of kept-alive connections per host: every poster used to pay a
# fresh TCP + TLS handshake, which is most of what made the simulator feel
# slow. A connection is borrowed for one request and returned afterwards.
_idle = collections.defaultdict(list)
_idle_lock = threading.Lock()

def _borrow(scheme, host, port):
    with _idle_lock:
        if _idle[(scheme, host, port)]:
            return _idle[(scheme, host, port)].pop()
    cls = http.client.HTTPSConnection if scheme == "https" else http.client.HTTPConnection
    return cls(host, port, timeout=60)

def _give_back(scheme, host, port, c):
    with _idle_lock:
        if len(_idle[(scheme, host, port)]) < 8:
            _idle[(scheme, host, port)].append(c); return
    try: c.close()
    except Exception: pass

def upstream(method, url, headers, body=None, redirects=5):
    """(status, content-type, bytes) for url, following redirects, reusing connections."""
    for _ in range(redirects + 1):
        u = urllib.parse.urlsplit(url)
        scheme = u.scheme or "https"
        port = u.port or (443 if scheme == "https" else 80)
        path = (u.path or "/") + ("?" + u.query if u.query else "")
        for attempt in (1, 2):
            c = _borrow(scheme, u.hostname, port)
            try:
                c.request(method, path, body=body, headers=dict(headers, Host=u.netloc))
                r = c.getresponse()
                data = r.read()
                _give_back(scheme, u.hostname, port, c)
                break
            except (http.client.HTTPException, OSError):
                # A kept-alive socket the server closed: retry once on a fresh one.
                try: c.close()
                except Exception: pass
                if attempt == 2: raise
        if r.status in (301, 302, 303, 307, 308) and r.getheader("Location"):
            url = urllib.parse.urljoin(url, r.getheader("Location"))
            if r.status == 303: method, body = "GET", None
            continue
        return r.status, r.getheader("Content-Type", "application/octet-stream"), data
    return 508, "text/plain", b"too many redirects"

# --- response cache ---------------------------------------------------------
# GETs of artwork and add-on catalogs/metas are reused while the simulator runs
# (a TV caches images too). The Stremio account API and link codes are never
# cached: they carry your session and must always be live.
_cache = collections.OrderedDict()
_cache_bytes = 0
_cache_lock = threading.Lock()
CACHE_LIMIT = 300 * 1024 * 1024
NO_CACHE_HOSTS = ("api.strem.io", "link.stremio.com", "localhost", "127.0.0.1")

def cache_ttl(url, ctype):
    host = urllib.parse.urlsplit(url).hostname or ""
    if any(host == h or host.endswith("." + h) for h in NO_CACHE_HOSTS): return 0
    if ctype.startswith("image/"): return 3600
    if "json" in ctype: return 300
    return 0

def cache_get(url):
    with _cache_lock:
        hit = _cache.get(url)
        if hit is None: return None
        if hit[0] < time.time():
            _cache_pop(url); return None
        _cache.move_to_end(url)
        return hit[1]

def _cache_pop(url):
    global _cache_bytes
    old = _cache.pop(url, None)
    if old is not None: _cache_bytes -= len(old[1][2])

def cache_put(url, entry, ttl):
    global _cache_bytes
    with _cache_lock:
        _cache_pop(url)
        _cache[url] = (time.time() + ttl, entry)
        _cache_bytes += len(entry[2])
        while _cache_bytes > CACHE_LIMIT and _cache:
            _cache_pop(next(iter(_cache)))

class H(http.server.SimpleHTTPRequestHandler):
    # Keep the browser's connection open between requests as well.
    protocol_version = "HTTP/1.1"
    def __init__(self, *a, **k): super().__init__(*a, directory=ROOT, **k)
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        self.send_header("Access-Control-Allow-Origin", "*")
        # The engine and its font/sound bundle never change while you test, so
        # the browser may keep them; the app package and API calls never cache.
        path = self.path.split("?")[0]
        if path.startswith("/lib/") or path.startswith("/assets/"):
            self.send_header("Cache-Control", "max-age=3600")
        else:
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
            self.send_response(404); self.send_header("Content-Length", "0"); self.end_headers(); return
        data = _j.dumps(body).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def video(self):
        f = os.path.join(ROOT, "test.mp4")
        if not os.path.exists(f):
            self.send_response(404); self.send_header("Content-Length", "0"); self.end_headers(); return
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
        cacheable = method == "GET" and "Range" not in headers
        hit = cache_get(url) if cacheable else None
        if hit is not None:
            status, ctype, data = hit
        else:
            try:
                status, ctype, data = upstream(method, url, headers, body)
                ttl = cache_ttl(url, ctype) if cacheable and status == 200 else 0
                if ttl > 0: cache_put(url, (status, ctype, data), ttl)
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
        self.send_response(404); self.send_header("Content-Length", "0"); self.end_headers()
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
