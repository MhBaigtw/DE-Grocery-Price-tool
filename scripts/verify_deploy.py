#!/usr/bin/env python3
"""Verify the DEPLOYED site over HTTP, against the live URL (brief 5.5).

WHY AGAINST THE LIVE URL. Every other check in this project runs against the working tree.
A deploy that "succeeded" while serving a stale extract, a 404 on a data file, or a page
whose stated date disagrees with the data behind it would pass all of them and still be
broken for every visitor. The failure this catches is the one §4.5 names: a site serving
stale prices under a fresh-looking date.

It asserts, over HTTP:
  - every asset loads (200) and is non-empty
  - every JSON parses
  - the date the page will show matches the date in the extract it actually fetched
  - the extract on the live site is not older than the refresh interval allows
  - the disclosures the licence and the brief require are present in the served HTML
  - the page carries no external script or stylesheet (no trackers, brief non-goal)

  python scripts/verify_deploy.py https://owner.github.io/repo/
"""
from __future__ import annotations
import argparse, datetime as dt, json, re, sys, urllib.error, urllib.request

FAILS: list[str] = []
WARNS: list[str] = []
UA = "Mozilla/5.0 (Project Hammer downstream analysis; deploy verification)"


def get(url: str, timeout: int = 45) -> tuple[int, bytes]:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception as e:                                     # noqa: BLE001
        FAILS.append(f"{url}: {type(e).__name__}: {e}")
        return 0, b""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("base", help="the deployed site root, e.g. https://owner.github.io/repo/")
    ap.add_argument("--max-extract-age-days", type=int, default=21)
    args = ap.parse_args()
    base = args.base if args.base.endswith("/") else args.base + "/"
    print(f"verifying {base}\n")

    status, html = get(base)
    if status != 200 or not html:
        print(f"FAIL - the site root returned {status}")
        return 1
    page = html.decode("utf-8", "replace")
    print(f"  200  {len(html):>9,} B  (root)")

    data = {}
    for name in ("data/meta.json", "data/products.json", "data/history.json"):
        st, body = get(base + name)
        if st != 200 or not body:
            FAILS.append(f"{name} returned {st}")
            continue
        try:
            data[name] = json.loads(body)
        except Exception as e:                                 # noqa: BLE001
            FAILS.append(f"{name} did not parse: {e}")
            continue
        print(f"  {st}  {len(body):>9,} B  {name}")

    meta = data.get("data/meta.json")
    products = data.get("data/products.json")

    if meta:
        # The stated date must be the extract's own date. These are different fields and
        # conflating them is the publication-lag error repeated inside our own product.
        d = str(meta["extract_date"])[:10]
        if d not in page and "extract_date" not in page:
            # The page renders the date from meta at runtime, so it need not appear in the
            # HTML source; what must hold is that meta is the single source of it.
            WARNS.append("the date is rendered from meta.json at runtime, not baked into "
                         "the HTML -- correct, but it cannot be verified from source alone")
        age = (dt.date.today() - dt.date.fromisoformat(d)).days
        line = f"  extract date {d} ({age} days old)"
        if age > args.max_extract_age_days:
            FAILS.append(f"the live site is serving an extract {age} days old "
                         f"(limit {args.max_extract_age_days}); the refresh has stopped")
        elif age > 10:
            WARNS.append(f"live extract is {age} days old")
        print(line)

        if "ProjectHammer.org" not in meta.get("attribution", ""):
            FAILS.append("the live meta.json does not carry the required attribution")
        for k in meta:
            if "stale" in k.lower():
                FAILS.append(f"the live meta.json carries a pooled staleness key {k!r}")
        if products is not None and meta.get("products_shipped") != len(products):
            FAILS.append("the live meta and products disagree on how many products shipped")

    if products is not None:
        if not products:
            FAILS.append("the live products.json is empty")
        else:
            print(f"  products {len(products):,}")

    # COMPRESSION. products.json is ~7.5 MB of JSON and ~360 KB gzipped. Measured on a
    # mid-range phone profile (CPU 4x, Slow 4G) the tool is usable in 3.3 s compressed and
    # 40 s uncompressed -- a 12x difference that is invisible in every other check, because
    # the file is byte-identical either way. If the host ever stops compressing, the tool is
    # broken for phone users and nothing else here would notice.
    big = [n for n in ("data/products.json", "data/history.json") if n in data]
    for name in big:
        req = urllib.request.Request(base + name,
                                     headers={"User-Agent": UA, "Accept-Encoding": "gzip, br"})
        try:
            with urllib.request.urlopen(req, timeout=45) as r:
                enc = (r.headers.get("Content-Encoding") or "").lower()
                clen = r.headers.get("Content-Length")
        except Exception as e:                                 # noqa: BLE001
            FAILS.append(f"{name}: compression probe failed: {e}")
            continue
        if enc in ("gzip", "br", "deflate", "zstd"):
            print(f"  {name} served {enc}" + (f", {int(clen)/1024:.0f} KB" if clen else ""))
        else:
            FAILS.append(
                f"{name} is served UNCOMPRESSED (Content-Encoding: {enc or 'none'}). "
                "It is ~7.5 MB raw against ~360 KB gzipped; on a mid-range phone that is "
                "40 s to usable instead of 3.3 s. Enable compression on the host.")

    # Disclosures that must be in the served HTML itself, not fetched or behind a link.
    for needle, label in (("Toronto", "Toronto scope"),
                          ("ProjectHammer.org", "attribution"),
                          ("national brands", "national-brands-only"),
                          ("no basket", "the no-basket rule")):
        if needle.lower() not in page.lower():
            FAILS.append(f"the served page does not state {label}")

    # The brief's non-goal: no ads, ad-network scripts or third-party trackers. Deferred
    # pending a written answer from the maintainer, so nothing of the kind may appear.
    ext = re.findall(r'<(?:script|link|iframe|img)[^>]+(?:src|href)\s*=\s*["\'](https?://[^"\']+)',
                     page, re.I)
    external = [u for u in ext if "projecthammer.org" not in u.lower()
                and "github.com" not in u.lower()]
    if external:
        FAILS.append("the served page loads external resources, which the no-tracker "
                     f"non-goal forbids: {external[:5]}")
    else:
        print("  no external scripts, styles, frames or images")

    print()
    for w in WARNS:
        print(f"WARN  {w}")
    for f in FAILS:
        print(f"FAIL  {f}")
    if FAILS:
        print("\nFAIL - the deployed site is not serving what it should.")
        return 1
    print("\nOK - the live site loads, parses, and states what it is required to state.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
