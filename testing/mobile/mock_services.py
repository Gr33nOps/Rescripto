"""Local protocol smoke server for phone QA (adb reverse tcp:18765 tcp:18765).

It keeps one WebDAV file in memory and returns a fixed rewrite over the
OpenAI-compatible streaming API. No request body or credential is logged.
Run only for a test session; it is not a production service.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from email.utils import format_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    stored: bytes | None = None
    revision = 0
    modified = datetime.now(timezone.utc)

    def log_message(self, format: str, *args: object) -> None:
        print("%s %s" % (self.command, self.path), flush=True)

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path == "/v1/models":
            body = json.dumps({"data": [{"id": "qa-rewrite", "object": "model"}]}).encode()
            self._send(200, body, "application/json")
        elif self.path.endswith("/rescripto-sync.rescriptobackup"):
            if type(self).stored is None:
                self._send(404, b"", "application/octet-stream")
            else:
                self._send(200, type(self).stored, "application/octet-stream")
        else:
            self._send(404, b"", "text/plain")

    def do_POST(self) -> None:
        if self.path != "/v1/chat/completions":
            self._send(404, b"", "text/plain")
            return
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        chunk = {"choices": [{"index": 0, "delta": {"content": "Hello, I can send the report tomorrow."}}]}
        body = ("data: " + json.dumps(chunk) + "\n\ndata: [DONE]\n\n").encode()
        self._send(200, body, "text/event-stream")

    def do_PROPFIND(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        if type(self).stored is None:
            self._send(404, b"", "application/xml")
            return
        modified = format_datetime(type(self).modified, usegmt=True)
        body = (
            '<d:multistatus xmlns:d="DAV:"><d:response><d:propstat><d:prop>'
            f"<d:getlastmodified>{modified}</d:getlastmodified>"
            f'<d:getetag>"qa-{type(self).revision}"</d:getetag>'
            '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
            '</d:response></d:multistatus>'
        ).encode()
        self._send(207, body, "application/xml")

    def do_PUT(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        type(self).stored = self.rfile.read(length)
        type(self).revision += 1
        type(self).modified = datetime.now(timezone.utc)
        self._send(201, b"", "text/plain")


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 18765), Handler).serve_forever()
