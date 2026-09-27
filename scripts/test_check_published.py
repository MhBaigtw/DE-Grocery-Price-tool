#!/usr/bin/env python3
"""Proves check_published.py fails when the live site is behind the repository.

This is the check that would have caught the 2026-09-13 to 2026-09-27 outage on day one, so it
has to refuse the exact shape of that failure: a site serving a real, valid, internally sound
extract that is simply older than the one just committed. Each case serves a meta.json from a
local HTTP server and asserts the verdict.

Run: python scripts/test_check_published.py
"""
from __future__ import annotations
import json, pathlib, subprocess, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHECK = ROOT / "scripts" / "check_published.py"
CURRENT = {"extract_date": "2026-09-26", "snapshot_id": "20260927T102334Z"}
STALE = {"extract_date": "2026-09-11", "snapshot_id": "20260913T003455Z"}


class Handler(BaseHTTPRequestHandler):
    payload: dict | None = CURRENT

    def log_message(self, *a):
        pass

    def do_GET(self):
        if not self.path.startswith("/data/meta.json") or Handler.payload is None:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = json.dumps(Handler.payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def verdict(base: str, expect: dict):
    p = subprocess.run([sys.executable, str(CHECK), "--url", base, "--wait-minutes", "0",
                        "--expect", expect["extract_date"],
                        "--expect-snapshot", expect["snapshot_id"]],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return p.returncode, p.stdout + p.stderr


def main() -> int:
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:                                      # noqa: BLE001
            pass
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{srv.server_address[1]}/"

    cases = []

    def case(name, payload, expect, want_rc, needle):
        Handler.payload = payload
        rc, out = verdict(base, expect)
        ok = rc == want_rc and needle.lower() in out.lower()
        cases.append(ok)
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
        if not ok:
            print(f"        wanted exit {want_rc} naming {needle!r}, got exit {rc}")
            print("\n".join("        " + l for l in out.strip().splitlines()[-4:]))

    print("check_published.py -- cases\n")
    case("the live site serving the committed extract passes",
         CURRENT, CURRENT, 0, "serving the extract this repository holds")
    case("a site left on an older extract is refused (the 2026-09-13 outage)",
         STALE, CURRENT, 1, "NOT serving what this repository holds")
    case("the refusal names what visitors actually see",
         STALE, CURRENT, 1, "visitors see prices from 2026-09-11")
    case("a matching date under a different snapshot is refused",
         {"extract_date": "2026-09-26", "snapshot_id": "20260926T000000Z"}, CURRENT, 1,
         "NOT serving")
    case("a site that cannot be read is refused, never passed",
         None, CURRENT, 1, "could not be read")

    srv.shutdown()
    print(f"\n{sum(cases)} of {len(cases)} cases behaved correctly.")
    if not all(cases):
        print("FAIL - a stale published site could pass unnoticed.")
        return 1
    print("OK - a site behind the repository is refused, and the refusal says what is served.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
