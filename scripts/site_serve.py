"""Local check of site/t/: serves site/ plus a fake Supabase REST API on one
port, so the orchard page can be rendered headless with no real project.

  python scripts/site_serve.py 8765
  msedge --headless --dump-dom "http://127.0.0.1:8765/t/?h=gtest00001"

The fake data includes a title carrying markup, to prove the page renders it
as text. Lives outside site/ so the Pages workflow never publishes it.
"""
import http.server
import json
import os
import sys
import urllib.parse

SITE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "site")
OWNER = "11111111-2222-3333-4444-555555555555"
DATA = {
    "profiles": [{"id": OWNER, "display_name": "Ada", "handle": "gtest00001"}],
    "published_trees": [{"owner_id": OWNER, "level": 3}],
    "published_games": [
        {"owner_id": OWNER, "title": "Hades", "cover_url": None, "status": "finished",
         "rating": 5, "branch_name": "Cozy"},
        {"owner_id": OWNER, "title": "Celeste", "cover_url": "javascript:alert(1)",
         "status": "playing", "rating": None, "branch_name": "Cozy"},
        {"owner_id": OWNER, "title": "<img src=x onerror=alert(1)>", "cover_url": None,
         "status": "untouched", "rating": None, "branch_name": "Someday"},
    ],
}


class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=SITE, **k)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == "/config.js":
            port = self.server.server_address[1]
            body = (f'window.LUDECK={{supabaseUrl:"http://127.0.0.1:{port}",'
                    f'publishableKey:"sb_publishable_test",playPackage:"com.ludeck.android"}};')
            return self._send(body.encode(), "application/javascript")
        if u.path.startswith("/rest/v1/"):
            if self.headers.get("apikey") != "sb_publishable_test":
                return self._send(b"[]", "application/json", 401)
            table = u.path.rsplit("/", 1)[1]
            q = urllib.parse.parse_qs(u.query)
            rows = DATA.get(table, [])
            for k, v in q.items():
                if k in ("select", "order"):
                    continue
                want = v[0].removeprefix("eq.")
                rows = [r for r in rows if str(r.get(k)) == want]
            return self._send(json.dumps(rows).encode(), "application/json")
        return super().do_GET()

    def _send(self, body, ctype, code=200):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
