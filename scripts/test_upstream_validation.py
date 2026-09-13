#!/usr/bin/env python3
"""Proves the upstream validation and retry refuse a challenge page, and stop when they should.

On 2026-09-13 one GitHub runner was answered with a bot-verification challenge page instead of
the files. The probe treated the page as a new publication, and the fetch saved it under the
archive's name. This test serves the same kind of page from a local HTTP server, alongside
genuine answers, and asserts:
  - the probe refuses anything that is not a date stamp;
  - the fetch refuses anything not served as a zip AND starting with a zip header, before any
    file exists and before any manifest or provenance record is written;
  - a refusal is retried at most three times, then the run stops;
  - a longer retry schedule is itself refused;
  - a transient refusal that clears on a later attempt succeeds.
The challenge body is an excerpt of the page recorded in workflow run 34727228990.

Run: python scripts/test_upstream_validation.py
"""
from __future__ import annotations
import hashlib, io, json, os, pathlib, sys, tempfile, threading, time, zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import fetch_snapshot   # noqa: E402
import refresh_light    # noqa: E402

CHALLENGE = (b'<!DOCTYPE html>\n<html lang="en">\n<head>\n  <title>One moment, please...</title>\n'
             b'</head>\n<body>\n  <div id="text">\n        Please wait while your request is being '
             b'verified...\n      </div>\n</body>\n</html>\n')
STAMP = b"2026-09-11 22:14:30.98 (Eastern Time)\n"
buf = io.BytesIO()
with zipfile.ZipFile(buf, "w") as z:
    z.writestr("hammer-2-processed.sqlite", b"not really sqlite, but a real zip member" * 100)
ZIP = buf.getvalue()

HITS: dict[str, int] = {}
FLAKY_LEFT = {"n": 2}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, ctype, body, length=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(length if length is not None else len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = self.path
        HITS[p] = HITS.get(p, 0) + 1
        if p == "/stamp":
            self.send(200, "text/plain", STAMP)
        elif p == "/challenge":
            self.send(200, "text/html", CHALLENGE)
        elif p == "/challenge-as-text":
            self.send(200, "text/plain", CHALLENGE)
        elif p == "/challenge-as-zip":
            self.send(200, "application/zip", CHALLENGE)
        elif p == "/zip":
            self.send(200, "application/zip", ZIP)
        elif p == "/zip-as-html":
            self.send(200, "text/html", ZIP)
        elif p == "/zip-truncated":
            self.send(200, "application/zip", ZIP[: len(ZIP) // 2], length=len(ZIP))
            self.close_connection = True
        elif p == "/flaky-stamp":
            if FLAKY_LEFT["n"] > 0:
                FLAKY_LEFT["n"] -= 1
                self.send(200, "text/html", CHALLENGE)
            else:
                self.send(200, "text/plain", STAMP)
        else:
            self.send(404, "text/plain", b"no")


def main() -> int:
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:                                      # noqa: BLE001
            pass
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{srv.server_address[1]}"
    results = []

    def check(name, fn):
        try:
            ok, detail = fn()
        except Exception as e:                                 # noqa: BLE001
            ok, detail = False, f"raised {type(e).__name__}: {e}"
        results.append(ok)
        print(f"  {'PASS' if ok else 'FAIL'}  {name}" + ("" if ok else f"\n        {detail}"))

    def refused(fn, needle):
        try:
            fn()
        except fetch_snapshot.UpstreamRefused as e:
            return needle in str(e), str(e)
        return False, "was not refused"

    print("upstream validation -- cases\n")
    check("the probe accepts a genuine stamp",
          lambda: (fetch_snapshot.fetch_stamp(base + "/stamp") == STAMP.decode().strip(), "wrong value"))
    check("the probe refuses a challenge page",
          lambda: refused(lambda: fetch_snapshot.fetch_stamp(base + "/challenge"),
                          "bot-verification challenge page"))
    check("the probe refuses a challenge page served as text/plain",
          lambda: refused(lambda: fetch_snapshot.fetch_stamp(base + "/challenge-as-text"),
                          "did not return a last-updated stamp"))

    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)

        def good_zip():
            rec = fetch_snapshot.fetch_archive(base + "/zip", td / "good.zip")
            return rec["sha256"] == hashlib.sha256(ZIP).hexdigest() and (td / "good.zip").exists(), rec
        check("the fetch accepts a genuine zip", good_zip)

        for path, name, needle in (
                ("/challenge", "a challenge page", "bot-verification challenge page"),
                ("/challenge-as-zip", "a challenge page served as application/zip", "did not return a zip"),
                ("/zip-as-html", "zip bytes served as text/html", "did not return a zip"),
                ("/zip-truncated", "a truncated archive", "")):
            dest = td / ("x" + path.strip("/").replace("-", "_") + ".zip")

            def case(path=path, dest=dest, needle=needle):
                ok, detail = refused(lambda: fetch_snapshot.fetch_archive(base + path, dest), needle)
                return ok and not dest.exists(), detail + ("" if not dest.exists() else "; a file was left behind")
            check(f"the fetch refuses {name}, and leaves no file", case)

    # Retry: at most three attempts, then Stop. Offsets shortened to seconds for the test.
    at = refresh_light.retry_schedule("0,1,2")

    def retries_then_stops():
        HITS.pop("/challenge", None)
        t = time.monotonic()
        try:
            refresh_light.with_retries("probe", lambda: fetch_snapshot.fetch_stamp(base + "/challenge"), at)
        except refresh_light.Stop:
            took = time.monotonic() - t
            return HITS.get("/challenge") == 3 and took >= 2, f"{HITS.get('/challenge')} attempts in {took:.1f}s"
        return False, "did not stop"
    check("a refused request is attempted exactly three times, then the run stops", retries_then_stops)

    def transient_clears():
        FLAKY_LEFT["n"] = 2
        HITS.pop("/flaky-stamp", None)
        v = refresh_light.with_retries("probe", lambda: fetch_snapshot.fetch_stamp(base + "/flaky-stamp"), at)
        return v == STAMP.decode().strip() and HITS["/flaky-stamp"] == 3, f"{HITS.get('/flaky-stamp')} attempts"
    check("a challenge that clears on the third attempt succeeds", transient_clears)

    def schedule_caps():
        ok = refresh_light.retry_schedule(refresh_light.DEFAULT_RETRY_AT) == (0, 900, 2700)
        for bad in ("0,900,2700,3000", "0,4000", "60,900", "0,2700,900"):
            try:
                refresh_light.retry_schedule(bad)
                return False, f"{bad!r} was accepted"
            except refresh_light.Stop:
                pass
        return ok, "default schedule is not 0, +15, +45 minutes"
    check("a schedule of more than 3 attempts, or beyond an hour, is refused", schedule_caps)

    # End to end: --probe-only against a challenge exits 1, emits no decision, records nothing.
    def probe_only_refuses():
        old_url, old_argv = fetch_snapshot.LASTUPDATED_URL, sys.argv
        records = sorted(refresh_light.PROVENANCE.glob("*.json"))
        with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".txt") as gh:
            gh_path = gh.name
        os.environ["GITHUB_OUTPUT"] = gh_path
        try:
            fetch_snapshot.LASTUPDATED_URL = base + "/challenge"
            sys.argv = ["refresh_light.py", "--probe-only", "--retry-at", "0,1,2"]
            rc = refresh_light.main()
        finally:
            fetch_snapshot.LASTUPDATED_URL, sys.argv = old_url, old_argv
            os.environ.pop("GITHUB_OUTPUT", None)
        emitted = pathlib.Path(gh_path).read_text(encoding="utf-8")
        os.unlink(gh_path)
        ok = rc == 1 and "changed=" not in emitted and sorted(refresh_light.PROVENANCE.glob("*.json")) == records
        return ok, f"exit {rc}, emitted {emitted!r}"
    check("--probe-only on a challenge exits 1, decides nothing, records nothing", probe_only_refuses)

    # Refresh mode: a challenge in place of the archive leaves no archive and no manifest.
    def fetch_refuses():
        old_url, old_arch = fetch_snapshot.LASTUPDATED_URL, dict(fetch_snapshot.ARCHIVES)
        HITS.pop("/challenge", None)
        try:
            fetch_snapshot.LASTUPDATED_URL = base + "/stamp"
            fetch_snapshot.ARCHIVES[refresh_light.SQLITE_ARCHIVE] = base + "/challenge"
            with tempfile.TemporaryDirectory() as wd:
                try:
                    refresh_light.fetch(pathlib.Path(wd), at)
                except refresh_light.Stop:
                    left = [p.name for p in pathlib.Path(wd).rglob("*") if p.is_file()]
                    return not left and HITS.get("/challenge") == 3, f"left {left}, {HITS.get('/challenge')} attempts"
                return False, "fetch did not stop"
        finally:
            fetch_snapshot.LASTUPDATED_URL = old_url
            fetch_snapshot.ARCHIVES.clear()
            fetch_snapshot.ARCHIVES.update(old_arch)
    check("a refresh answered with a challenge instead of the archive writes no archive and no manifest",
          fetch_refuses)

    srv.shutdown()
    print(f"\n{sum(results)} of {len(results)} cases behaved correctly.")
    if not all(results):
        print("FAIL - a non-answer from upstream could be used, recorded, or retried without limit.")
        return 1
    print("OK - challenge pages are refused before use or record, and retries stop at three.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
