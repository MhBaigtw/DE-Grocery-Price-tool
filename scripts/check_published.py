#!/usr/bin/env python3
"""Assert the live site is serving the extract the repository holds.

WHY THIS EXISTS. Between 2026-09-13 and 2026-09-27 the refresh ran daily, committed a fresh
extract every time, and the site served none of it: Netlify refused every deploy with "credit
usage exceeded". The pipeline was healthy, the data in git was current, and the public site sat
16 days stale for two weeks. Nothing noticed, because every check in this project runs against
the working tree or the freshly built extract, and the one check that runs against the live URL
(verify_deploy.py) was never wired into the refresh.

WHAT IT CHECKS, AND WHY IT IS NOT verify_deploy.py. verify_deploy asks whether the live site is
internally sound. This asks a different question: whether the live site is CURRENT -- does the
extract date it serves match the one committed here? A publish step that silently stops is
invisible to every other check in the repository, and this is the only thing that sees it.

It retries, because a deploy takes a few minutes and a CDN may hold a cached copy briefly (the
data files are served with a 300-second max-age). A mismatch after the whole window is a
failure, not a warning: the site is serving prices older than the ones that passed the gates.

  python scripts/check_published.py                      # expect what tool/data holds
  python scripts/check_published.py --expect 2026-09-26   # expect a specific extract date
  python scripts/check_published.py --wait-minutes 0      # one look, no waiting

Exit 0 = the live site serves the expected extract. Exit 1 = it does not, or could not be read.
"""
from __future__ import annotations
import argparse, json, pathlib, sys, time, urllib.error, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
URL = "https://de-grocery-price-tool.vercel.app/"
UA = ("Mozilla/5.0 (Project Hammer downstream analysis; "
      "+https://github.com/MhBaigtw/DE-Grocery-Price-tool)")


def live_meta(base: str) -> dict:
    # A cache-busting query and a no-cache header: the question is what the origin holds now,
    # not what an edge cached a minute ago.
    url = f"{base}data/meta.json?t={int(time.time())}"
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, timeout=45) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default=URL)
    ap.add_argument("--expect", default=None,
                    help="extract date the site must serve (default: the one in tool/data/meta.json)")
    ap.add_argument("--expect-snapshot", default=None,
                    help="snapshot id the site must serve (default: the one in tool/data/meta.json)")
    ap.add_argument("--wait-minutes", type=float, default=15,
                    help="how long to keep looking while a deploy completes (default 15)")
    ap.add_argument("--interval", type=float, default=30)
    args = ap.parse_args()
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:                                      # noqa: BLE001
            pass

    base = args.url if args.url.endswith("/") else args.url + "/"
    want_date, want_snap = args.expect, args.expect_snapshot
    if not want_date or not want_snap:
        local = json.loads((ROOT / "tool" / "data" / "meta.json").read_text(encoding="utf-8"))
        want_date = want_date or str(local["extract_date"])[:10]
        want_snap = want_snap or local["snapshot_id"]

    print(f"site      : {base}")
    print(f"expecting : extract {want_date}, snapshot {want_snap}")
    deadline = time.time() + args.wait_minutes * 60
    seen, last_err = None, None
    while True:
        try:
            meta = live_meta(base)
            seen = (str(meta.get("extract_date"))[:10], meta.get("snapshot_id"))
            if seen == (want_date, want_snap):
                print(f"live      : extract {seen[0]}, snapshot {seen[1]}")
                print("\nOK - the live site is serving the extract this repository holds.")
                return 0
        except (urllib.error.URLError, OSError, ValueError) as e:
            last_err = e
        if time.time() >= deadline:
            break
        time.sleep(args.interval)

    print(f"live      : {('extract %s, snapshot %s' % seen) if seen else 'could not be read'}")
    if last_err and not seen:
        print(f"error     : {last_err}")
    print(f"\nFAIL - after {args.wait_minutes:g} minutes the live site is NOT serving what this "
          f"repository holds.\nThe refresh and its gates passed, so the publish step is the thing "
          f"that failed: the site is\nserving an older extract than the one that was committed. "
          f"Visitors see prices from {seen[0] if seen else 'an unknown date'},\nnot {want_date}. "
          "Check the host's deploy log; nothing here can fix it.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
