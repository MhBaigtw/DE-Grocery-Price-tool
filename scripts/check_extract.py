#!/usr/bin/env python3
"""Gate the built extract before anything deploys it.

WHY THIS EXISTS. Phase 4 §2 enforces the honesty rules inside the SQL that builds the
extract, and §3's render test enforces them on the page's output. Neither of those runs at
deploy time. This does. It is the last thing between a rebuilt extract and a live site, and
it fails the deploy rather than warning about it (brief §4.3).

It checks STRUCTURE AND FLOORS, not remembered values. A refresh legitimately changes every
count in the extract, so asserting "3,190 barcodes" here would fail every week for the wrong
reason. What must not change is the shape of the promises: per-chain staleness and never a
pooled figure, a comparison verdict that names its chains, a warning wherever a price is
older than anything measured, and enough coverage to be worth publishing at all.

Exit 0 = safe to deploy. Exit 1 = do not deploy; the previous extract stays live.
"""
from __future__ import annotations
import argparse, datetime as dt, json, pathlib, re, sys

VENDOR_CODES = ("SaveOnFoods",)          # keys that must never reach a reader
# A brand field carrying a price or a promotion. Anchored on a currency amount or the promo
# phrases, so a real brand that merely contains "save" (LIFESAVERS) is not refused.
PROMO_BRAND = re.compile("[$][0-9]|you save|current price")

# The three chains the tool reads, all reliable tier. This is the guarantee the relaxed
# basket rests on: Phase 4 dropped `is_reliable_only` because a fuzzy-tier vendor's price
# can never reach the extract, and that is only true while the extract contains these three
# and nothing else. E1 asserts it in SQL at build time; this asserts it on what shipped.
ALLOWED_CHAINS = {"Metro", "SaveOnFoods", "Walmart"}
FAILS: list[str] = []
WARNS: list[str] = []


def bad(msg: str) -> None:
    FAILS.append(msg)


def warn(msg: str) -> None:
    WARNS.append(msg)


def check_meta(meta: dict, args) -> None:
    for k in ("built_utc", "extract_date", "snapshot_id", "basket_barcodes",
              "products_shipped", "omitted", "chains", "exclusions", "scope", "attribution"):
        if k not in meta:
            bad(f"meta.json is missing {k!r}")
    if FAILS:
        return

    # 1. No pooled staleness may exist. The whole point of the constraint is that there is
    #    nothing for a page to reach for, so absence is the thing being checked.
    for k in meta:
        if "stale" in k.lower():
            bad(f"meta.json carries a top-level staleness key {k!r}: a pooled staleness "
                "figure must not exist. Pooling understates the chain a user is most "
                "likely to be wrong about. Staleness is per chain or it does not exist.")

    # 2. Every chain carries its own curve, and the curve is ordered and plausible.
    if not meta["chains"]:
        bad("meta.json lists no chains")
    for c in meta["chains"]:
        for k in ("chain", "chain_label", "last_observed", "days_behind", "products", "staleness"):
            if k not in c:
                bad(f"chain {c.get('chain')!r} is missing {k!r}")
                return
        if not c["staleness"]:
            bad(f"chain {c['chain']!r} carries no staleness curve")
            continue
        days = [s["days"] for s in c["staleness"]]
        if days != sorted(days):
            bad(f"chain {c['chain']!r} staleness curve is not in ascending order: {days}")
        pcts = [s["pct_wrong"] for s in c["staleness"]]
        if any(p is None for p in pcts):
            bad(f"chain {c['chain']!r} has a null in its staleness curve")
        elif pcts != sorted(pcts):
            # Staleness cannot fall as data gets older. If it does, the measure is wrong --
            # this is exactly the shape of the defect withdrawn from R1 in §1.3c.
            bad(f"chain {c['chain']!r} staleness falls as data ages: {pcts}")
        if c["chain"] in VENDOR_CODES and c["chain_label"] == c["chain"]:
            bad(f"chain {c['chain']!r} has no display label")
        if c["chain"] not in ALLOWED_CHAINS:
            bad(f"meta.json lists chain {c['chain']!r}, which is not one of the three "
                f"reliable-tier chains {sorted(ALLOWED_CHAINS)}. The relaxed basket is only "
                "safe while the extract reads these and nothing else.")

    # 3. The attribution the licence requires.
    if "ProjectHammer.org" not in meta["attribution"]:
        bad("meta.json attribution does not name ProjectHammer.org")

    # 4. Scope statements a reader must be given.
    scope = " ".join(str(v) for v in meta["scope"].values()).lower()
    for need, label in ((("toronto",), "Toronto"),
                        (("national brand",), "national brands"),
                        (("store brand",), "store brands"),
                        (("no basket", "no total"), "the no-basket rule")):
        if not any(n in scope for n in need):
            bad(f"meta.json scope does not state {label}")

    # 5. Vintage. An extract far older than the refresh interval means the pipeline stopped
    #    and nobody noticed -- the failure mode §1.4 called out by name.
    d = dt.date.fromisoformat(str(meta["extract_date"])[:10])
    age = (dt.date.today() - d).days
    if age > args.max_extract_age_days:
        bad(f"extract is {age} days old (limit {args.max_extract_age_days}); "
            "refresh has stopped or is failing silently")
    elif age > args.warn_extract_age_days:
        warn(f"extract is {age} days old")


def check_products(products: list, meta: dict, args) -> None:
    if len(products) < args.min_products:
        bad(f"only {len(products)} products (floor {args.min_products}); "
            "a near-empty extract must not deploy under a fresh date")
    if meta.get("products_shipped") != len(products):
        bad(f"meta says {meta.get('products_shipped')} products, products.json has {len(products)}")

    n_cmp = {0: 0, 1: 0, 2: 0, 3: 0}
    for p in products:
        g = p.get("gtin14", "?")
        for k in ("gtin14", "name", "basis", "offers", "comparison"):
            if k not in p:
                bad(f"{g}: missing {k!r}")
                return
        c, offers = p["comparison"], p["offers"]
        n = c["n_compared"]
        n_cmp[min(3, n)] = n_cmp.get(min(3, n), 0) + 1

        if not offers:
            bad(f"{g}: shipped with no offers at all")

        # A verdict may exist only where two or more chains were actually compared.
        if n < 2 and c.get("cheapest") is not None:
            bad(f"{g}: names a cheapest chain with only {n} comparable")
        if n >= 2 and c.get("cheapest") is None:
            bad(f"{g}: {n} chains comparable but no cheapest named")
        if len(c.get("compared", [])) != n:
            bad(f"{g}: n_compared={n} but compared lists {len(c.get('compared', []))}")

        claim = c.get("claim", "")
        if not claim:
            bad(f"{g}: no claim sentence")
        if any(v in claim for v in VENDOR_CODES):
            bad(f"{g}: claim prints a raw vendor code: {claim}")
        if " and " in claim and claim.count(" and ") > 1:
            bad(f"{g}: claim joins names with repeated 'and': {claim}")
        if n < 2 and "cheapest" in claim.lower() and "nothing" not in claim.lower():
            bad(f"{g}: claim says cheapest with {n} comparable: {claim}")

        brand = p.get("brand") or ""
        if PROMO_BRAND.search(brand.lower()):
            bad(f"{g}: brand field carries price or promotional text: {brand!r}")

        # Every chain in the extract is accounted for: compared, or listed as unavailable
        # with a reason. Brief §3.2 -- never silently dropped.
        listed = set(c.get("compared", [])) | {u["chain"] for u in c.get("unavailable", [])}
        if listed != {o["chain"] for o in offers}:
            bad(f"{g}: offers and comparison disagree about which chains exist")
        for u in c.get("unavailable", []):
            if not u.get("reason"):
                bad(f"{g}: {u['chain']} is excluded with no reason given")
            if not u.get("last_observed"):
                bad(f"{g}: {u['chain']} is excluded with no last-observed date")

        for o in offers:
            for k in ("chain", "chain_label", "price", "basis", "observed_date",
                      "days_behind", "is_recent", "comparable", "staleness_exceeds_measured"):
                if k not in o:
                    bad(f"{g}/{o.get('chain')}: offer missing {k!r}")
                    return
            if o["price"] is None or o["price"] <= 0:
                bad(f"{g}/{o['chain']}: non-positive price {o['price']}")
            if o["chain"] in VENDOR_CODES and o["chain_label"] == o["chain"]:
                bad(f"{g}/{o['chain']}: offer has no display label")
            if o["chain"] not in ALLOWED_CHAINS:
                bad(f"{g}: offer from {o['chain']!r}, outside the three reliable-tier "
                    "chains. A fuzzy-tier price may have reached the extract; do not deploy.")
            # The §2 defect: an unmeasured age must never carry a measured figure.
            if o["staleness_exceeds_measured"] and o["staleness_pct"] is not None:
                bad(f"{g}/{o['chain']}: {o['days_behind']}d old but carries a staleness figure")
            if not o["staleness_exceeds_measured"] and o["staleness_pct"] is None:
                bad(f"{g}/{o['chain']}: within the measured range but carries no figure")
            if o["comparable"] and o["basis"] != p["basis"]:
                bad(f"{g}/{o['chain']}: comparable on a different basis to the product")
            if not o["comparable"] and not o.get("not_comparable_reason"):
                bad(f"{g}/{o['chain']}: not comparable with no reason")

    comparable = n_cmp[2] + n_cmp[3]
    share = 100.0 * comparable / max(1, len(products))
    if share < args.min_comparable_pct:
        bad(f"only {share:.1f}% of products have two or more chains with a recent price "
            f"(floor {args.min_comparable_pct}%); the extract is too thin to publish")
    return share, n_cmp


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default="tool/data", help="directory holding the extract")
    ap.add_argument("--min-products", type=int, default=1500,
                    help="floor on products shipped; below this the extract is too thin "
                         "to deploy under a fresh date (default 1500, against 2,921 today)")
    ap.add_argument("--min-comparable-pct", type=float, default=40.0,
                    help="floor on the share of products with 2+ recent chains "
                         "(default 40, against 60.9%% today)")
    ap.add_argument("--max-extract-age-days", type=int, default=21,
                    help="hard limit on extract vintage (default 21 = three missed weeks)")
    ap.add_argument("--warn-extract-age-days", type=int, default=10)
    args = ap.parse_args()

    d = pathlib.Path(args.dir)
    try:
        meta = json.loads((d / "meta.json").read_text(encoding="utf-8"))
        products = json.loads((d / "products.json").read_text(encoding="utf-8"))
        history = json.loads((d / "history.json").read_text(encoding="utf-8"))
    except Exception as e:                                    # noqa: BLE001
        print(f"FAIL - could not read the extract from {d}: {e}")
        return 1

    check_meta(meta, args)
    res = check_products(products, meta, args) if not FAILS else None
    if not history:
        warn("history.json is empty; the 6-week chart will render nothing")

    print(f"extract dir       : {d}")
    print(f"extract date      : {meta.get('extract_date')}")
    print(f"products          : {len(products)}")
    if res:
        share, n = res
        print(f"comparable (2-3)  : {n[2] + n[3]} ({share:.2f}%)")
        print(f"one chain only    : {n[1]}")
        print(f"nothing recent    : {n[0]}")
    print(f"history rows      : {len(history)}")
    for w in WARNS:
        print(f"WARN  {w}")
    for f in FAILS[:20]:
        print(f"FAIL  {f}")
    if len(FAILS) > 20:
        print(f"      ... and {len(FAILS) - 20} more")

    if FAILS:
        print("\nFAIL - extract must not deploy. The previous deploy stays live.")
        return 1
    print("\nOK - extract is safe to deploy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
