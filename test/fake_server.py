"""Minimal HTTP server standing in for obiguard-gateway-service's /v1/coverage
route during CI tests of this action — just enough to check the request shape
and return the 200 the real endpoint would return on success.
"""

import http.server
import json
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
REQUIRED_FIELDS = ["repoFullName", "branch", "commitSha", "lcov"]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Used by the test workflow as a readiness probe.
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        if self.path != "/v1/coverage":
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"not found")
            return

        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            data = json.loads(body)
        except Exception:
            data = {}

        missing = [f for f in REQUIRED_FIELDS if f not in data]
        if missing:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(f"missing fields: {missing}".encode())
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"nid":"test-nid"}')

    def log_message(self, format, *args):
        pass  # keep CI logs quiet


if __name__ == "__main__":
    http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
