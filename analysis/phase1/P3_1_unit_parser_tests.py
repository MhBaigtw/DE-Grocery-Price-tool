"""Unit-parser test cases with the answer written down in advance.

A parser nobody checked is a parser that quietly invents numbers. Each case here exists
because it was wrong at some point: '60gx6' failed entirely (a \\b anchor cannot match a
unit token followed by 'x'), and '24ea' put the count in the wrong column until the P3.4
pack-count cross-check caught it.

Run:  python analysis/phase1/P3_1_unit_parser_tests.py
Exit 0 if all pass, 1 otherwise.
"""
import duckdb, pathlib

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
c = duckdb.connect(":memory:")
c.execute((REPO / "models" / "unit_parse_macros.sql").read_text(encoding="utf-8"))

# raw, expected per-item qty, uom, pack_count, total_qty, confidence
T = [
    ("2 x 500 mL",     500.0,   "ml",    2.0, 1000.0,  "derived"),
    ("12x355.0ml",     355.0,   "ml",   12.0, 4260.0,  "derived"),
    ("60gx6",           60.0,   "g",     6.0,  360.0,  "derived"),
    ("4x100g",         100.0,   "g",     4.0,  400.0,  "derived"),
    ("500g",           500.0,   "g",     1.0,  500.0,  "exact"),
    ("1.36kg",        1360.0,   "g",     1.0, 1360.0,  "exact"),
    ("2 l",           2000.0,   "ml",    1.0, 2000.0,  "exact"),
    ("250 millilitre", 250.0,   "ml",    1.0,  250.0,  "exact"),
    ("15LB",          6803.88,  "g",     1.0, 6803.88, "exact"),
    ("1ea",              1.0,   "count", 1.0,    1.0,  "exact"),
    ("24ea",             1.0,   "count",24.0,   24.0,  "exact"),
    ("6 each",           1.0,   "count", 6.0,    6.0,  "exact"),
    ("4 per pack",       1.0,   "count", 4.0,    4.0,  "inferred"),
    ("error",           None,   None,   None,   None,  "none"),
    ("",                None,   None,   None,   None,  "none"),
    ("perfect every time",None, None,    1.0,   None,  "none"),
]

def close(a, b):
    if a is None and b is None:
        return True
    if a is None or b is None:
        return False
    return abs(a - b) < 0.05

bad = 0
for raw, q, u, p, t, cf in T:
    g = c.execute(
        "SELECT round(u_qty(?),2), u_uom(?), u_pack_count(?), round(u_total_qty(?),2), u_confidence(?)",
        [raw] * 5).fetchone()
    ok = close(g[0], q) and g[1] == u and close(g[2], p) and close(g[3], t) and g[4] == cf
    bad += 0 if ok else 1
    tag = "ok  " if ok else "FAIL"
    print(f"{tag} {raw!r:22s} qty={str(g[0]):9s} uom={str(g[1]):6s} pack={str(g[2]):5s} "
          f"total={str(g[3]):9s} conf={g[4]}")
    if not ok:
        print(f"      wanted qty={q} uom={u} pack={p} total={t} conf={cf}")

print(f"\nunit parser tests: {len(T)-bad} of {len(T)} pass")
raise SystemExit(1 if bad else 0)
