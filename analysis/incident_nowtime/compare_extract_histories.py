#!/usr/bin/env python3
"""Compare two tool extracts' price histories over the days both of them cover.

WHY THIS EXISTS. The incident's date proof (N4) is about the archive. This is the same
question asked of what the tool actually ships: build the extract from the new integer-date
archive with the fixed decode, and compare its history.json with the one the last good
refresh committed from the old string-date archive (commit 97a2886, extract date
2026-11-04). If the decode moved dates, every series would disagree, on interior days, by
one day. If it did not, the two agree wherever they overlap.

A history spell is a run of consecutive OBSERVED days at one price, so a spell's dates are
the days the product was seen. Each series is expanded to day -> (price, on_sale) and the
two sides are compared day by day inside the window both extracts cover.

    git show 97a2886:tool/data/history.json > old_history.json
    python analysis/incident_nowtime/compare_extract_histories.py old_history.json \
        <new extract>/tool/data/history.json --from 2026-10-04 --to 2026-11-04

--from is the first day of the NEWER extract's history window and --to is the OLDER
extract's extract date. Outside that range one side has no data by construction.

Reads two JSON files, writes nothing. Standard library only.
"""
import argparse
import collections
import datetime as dt
import json


def key(r):
    return (r["gtin14"], r["chain"], r["basis"])


def days(r, lo, hi):
    out = {}
    for s in r["spells"]:
        d, last = dt.date.fromisoformat(s["from_date"]), dt.date.fromisoformat(s["to_date"])
        while d <= last:
            if lo <= d <= hi:
                out[d] = (s["price"], s["on_sale"])
            d += dt.timedelta(days=1)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("--from", dest="lo", required=True)
    ap.add_argument("--to", dest="hi", required=True)
    args = ap.parse_args()
    lo, hi = dt.date.fromisoformat(args.lo), dt.date.fromisoformat(args.hi)

    old = {key(r): r for r in json.load(open(args.old, encoding="utf-8"))}
    new = {key(r): r for r in json.load(open(args.new, encoding="utf-8"))}
    both = sorted(set(old) & set(new))

    identical = 0
    kinds, chains = collections.Counter(), collections.Counter()
    only_new, only_old, changed = (collections.Counter() for _ in range(3))
    for k in both:
        a, b = days(old[k], lo, hi), days(new[k], lo, hi)
        if a == b:
            identical += 1
            continue
        chains[k[1]] += 1
        gained, lost = set(b) - set(a), set(a) - set(b)
        moved = {d for d in set(a) & set(b) if a[d] != b[d]}
        for d in gained:
            only_new[d] += 1
        for d in lost:
            only_old[d] += 1
        for d in moved:
            changed[d] += 1
        kinds[" + ".join(n for n, s in (("gained days", gained), ("lost days", lost),
                                        ("price or sale flag changed", moved)) if s)] += 1

    def show(c):
        return ", ".join(f"{d} x{n}" for d, n in sorted(c.items())) or "none"

    print(f"window                       : {lo} to {hi}")
    print(f"series old / new / in both   : {len(old)} / {len(new)} / {len(both)}")
    print(f"only in old / only in new    : {len(set(old) - set(new))} / {len(set(new) - set(old))}")
    print(f"identical over the window    : {identical} of {len(both)}")
    print(f"differ                       : {len(both) - identical}")
    print(f"  by chain                   : {dict(sorted(chains.items()))}")
    print(f"  by kind                    : {dict(sorted(kinds.items()))}")
    print(f"  days present only in new   : {show(only_new)}")
    print(f"  days present only in old   : {show(only_old)}")
    print(f"  days with a different price or sale flag: {show(changed)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
