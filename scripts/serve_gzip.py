#!/usr/bin/env python3
"""A static server that gzips, so local verification matches what a real host does.

WHY THIS EXISTS. `python -m http.server` sends everything uncompressed. Measuring the tool
against it made `products.json` a 7.6 MB transfer and put time-to-interactive at 40 seconds
on a phone profile -- a number no visitor would ever see, because GitHub Pages (and every
other static host) serves these files gzipped at about 344 KB. Verifying against a server
that behaves differently from the deployment is not verification, and in this case it
overstated the cost by more than 20x.

Usage:  python scripts/serve_gzip.py [--port 8902] [--dir .]
"""
from __future__ import annotations
import argparse
import functools
import gzip
import http.server
import io
import pathlib
import socketserver

COMPRESSIBLE = (".html", ".json", ".js", ".css", ".svg", ".txt", ".md", ".xml")
MIN_BYTES = 512          # below this, the header costs more than the saving


class GzipHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Static hosts set long-lived caching on assets; the measurement disables the cache
        # explicitly, so this only affects casual local browsing.
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def send_head(self):
        path = pathlib.Path(self.translate_path(self.path))
        if path.is_dir():
            for index in ("index.html",):
                if (path / index).is_file():
                    path = path / index
                    break
            else:
                return super().send_head()

        if not path.is_file():
            return super().send_head()

        accepts_gzip = "gzip" in self.headers.get("Accept-Encoding", "")
        if not (accepts_gzip and path.suffix.lower() in COMPRESSIBLE):
            return super().send_head()

        raw = path.read_bytes()
        if len(raw) < MIN_BYTES:
            return super().send_head()

        body = gzip.compress(raw, 6)     # 6 is what nginx and friends default to
        ctype = self.guess_type(str(path))
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Encoding", "gzip")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Vary", "Accept-Encoding")
        self.end_headers()
        return io.BytesIO(body)

    def log_message(self, fmt, *args):       # keep the measurement output readable
        pass


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8902)
    ap.add_argument("--dir", default=".")
    args = ap.parse_args()

    handler = functools.partial(GzipHandler, directory=args.dir)
    with Server(("127.0.0.1", args.port), handler) as httpd:
        print(f"serving {pathlib.Path(args.dir).resolve()} with gzip "
              f"on http://127.0.0.1:{args.port}/", flush=True)
        httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
