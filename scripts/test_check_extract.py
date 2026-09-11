#!/usr/bin/env python3
"""Proves check_extract.py fails when it should.

A check that has never failed has not been tested. Each case below takes the real extract,
breaks one promise in it, and asserts the gate refuses to deploy — and that the refusal
names the thing that broke, so a failure at 05:00 on a Friday is actionable rather than
merely red.

Run: python scripts/test_check_extract.py
"""
from __future__ import annotations
import copy, json, pathlib, shutil, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "tool" / "data"
GATE = ROOT / "scripts" / "check_extract.py"


def run(d: pathlib.Path, *extra: str):
    p = subprocess.run([sys.executable, str(GATE), "--dir", str(d), *extra],
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def case(name: str, mutate, expect_substr: str, *extra: str) -> bool:
    with tempfile.TemporaryDirectory() as td:
        d = pathlib.Path(td) / "data"
        shutil.copytree(SRC, d)
        meta = json.loads((d / "meta.json").read_text(encoding="utf-8"))
        prods = json.loads((d / "products.json").read_text(encoding="utf-8"))
        meta, prods = mutate(copy.deepcopy(meta), copy.deepcopy(prods))
        (d / "meta.json").write_text(json.dumps(meta), encoding="utf-8")
        (d / "products.json").write_text(json.dumps(prods), encoding="utf-8")
        rc, out = run(d, *extra)
        ok = rc != 0 and expect_substr.lower() in out.lower()
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
        if not ok:
            print(f"        expected a refusal naming {expect_substr!r}")
            print("        got rc=%d\n%s" % (rc, "\n".join("        " + l
                                                           for l in out.splitlines()[-8:])))
        return ok


def pooled(meta, prods):
    meta["staleness_pct_overall"] = 27.52          # the exact thing constraint 1 forbids
    return meta, prods


def unmeasured_figure(meta, prods):
    for p in prods:
        for o in p["offers"]:
            if o["staleness_exceeds_measured"]:
                o["staleness_pct"] = 38.33          # the §2 defect, reintroduced
                return meta, prods
    raise AssertionError("no offer beyond the measured horizon to break")


def verdict_without_comparison(meta, prods):
    for p in prods:
        if p["comparison"]["n_compared"] == 1:
            p["comparison"]["cheapest"] = p["comparison"]["compared"][0]
            return meta, prods
    raise AssertionError("no one-chain product to break")


def dropped_chain(meta, prods):
    for p in prods:
        if p["comparison"]["unavailable"]:
            p["comparison"]["unavailable"] = []     # silently drop the absent chain
            return meta, prods
    raise AssertionError("no product with an unavailable chain")


def raw_code_in_claim(meta, prods):
    for p in prods:
        if p["comparison"]["n_compared"] >= 2:
            p["comparison"]["claim"] = "Cheapest of the 2 chains: SaveOnFoods and Walmart."
            return meta, prods
    raise AssertionError("no comparable product")


def staleness_falls_with_age(meta, prods):
    # A curve that improves as data ages is the shape of the withdrawn R1 defect.
    meta["chains"][0]["staleness"][-1]["pct_wrong"] = 0.01
    return meta, prods


def thin_extract(meta, prods):
    keep = prods[:200]
    meta["products_shipped"] = len(keep)
    return meta, keep


def mostly_incomparable(meta, prods):
    keep = [p for p in prods if p["comparison"]["n_compared"] < 2]
    meta["products_shipped"] = len(keep)
    return meta, keep


def attribution_gone(meta, prods):
    meta["attribution"] = "Data from somewhere."
    return meta, prods


def scope_gone(meta, prods):
    meta["scope"] = {"note": "prices"}
    return meta, prods


def excluded_without_reason(meta, prods):
    for p in prods:
        if p["comparison"]["unavailable"]:
            p["comparison"]["unavailable"][0]["reason"] = ""
            return meta, prods
    raise AssertionError("no excluded chain")


def promo_brand(meta, prods):
    prods[0]["brand"] = "You save$0.53"      # the defect the phone-width check found
    return meta, prods


def real_brand_containing_save(meta, prods):
    prods[0]["brand"] = "LIFESAVERS"         # a real brand; must NOT be refused
    return meta, prods


def fuzzy_tier_chain(meta, prods):
    # The guarantee the relaxed basket rests on: only reliable-tier chains in the extract.
    prods[0]["offers"][0]["chain"] = "Loblaws"
    prods[0]["offers"][0]["chain_label"] = "Loblaws"
    return meta, prods


CASES = [
    ("a pooled staleness figure is refused",            pooled,                  "pooled"),
    ("an unmeasured age carrying a figure is refused",  unmeasured_figure,       "carries a staleness figure"),
    ("a cheapest verdict with one chain is refused",    verdict_without_comparison, "only 1 comparable"),
    ("silently dropping an absent chain is refused",    dropped_chain,           "disagree about which chains"),
    ("a raw vendor code in the claim is refused",       raw_code_in_claim,       "raw vendor code"),
    ("staleness falling as data ages is refused",       staleness_falls_with_age, "falls as data ages"),
    ("a near-empty extract is refused",                 thin_extract,            "floor"),
    ("an extract with little comparable is refused",    mostly_incomparable,     "too thin to publish"),
    ("a missing attribution is refused",                attribution_gone,        "projecthammer"),
    ("missing scope statements are refused",            scope_gone,              "scope does not state"),
    ("an excluded chain with no reason is refused",     excluded_without_reason, "no reason given"),
    ("promotional text in the brand field is refused",  promo_brand,             "promotional text"),
    ("a fuzzy-tier chain in the extract is refused",    fuzzy_tier_chain,        "reliable-tier"),
]


def main() -> int:
    print("check_extract.py -- failure cases\n")
    ok = [case(n, m, e) for n, m, e in CASES]

    # And one case that must NOT fail: the real extract, unmodified.
    rc, out = run(SRC)
    passes = rc == 0
    print(f"  {'PASS' if passes else 'FAIL'}  the real extract is accepted")
    if not passes:
        print("\n".join("        " + l for l in out.splitlines()[-10:]))
    ok.append(passes)

    # A real brand that merely contains "save" must be accepted, or the check is too blunt
    # to keep switched on.
    with tempfile.TemporaryDirectory() as td:
        d = pathlib.Path(td) / "data"
        shutil.copytree(SRC, d)
        prods = json.loads((d / "products.json").read_text(encoding="utf-8"))
        _, prods = real_brand_containing_save(None, prods)
        (d / "products.json").write_text(json.dumps(prods), encoding="utf-8")
        rc, out = run(d)
        fp_ok = rc == 0 or "promotional text" not in out
    print(f"  {'PASS' if fp_ok else 'FAIL'}  a real brand containing 'save' is not refused")
    ok.append(fp_ok)

    # A stale extract is refused even though nothing about it is malformed.
    rc, out = run(SRC, "--max-extract-age-days", "0")
    stale_ok = rc != 0 and "refresh has stopped" in out
    print(f"  {'PASS' if stale_ok else 'FAIL'}  a stale extract is refused on vintage alone")
    ok.append(stale_ok)

    print(f"\n{sum(ok)} of {len(ok)} cases behaved correctly.")
    if not all(ok):
        print("FAIL - the deploy gate does not refuse something it must refuse.")
        return 1
    print("OK - the gate refuses every violation and accepts the real extract.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
