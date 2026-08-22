#!/usr/bin/env python3
"""Prove scripts/check_schema.py actually fails when the schema differs.

Phase 0 brief, G2: "Test it by deliberately corrupting a copy of the schema file and
confirming the check fails. A check that has never failed has not been tested."

Method: copy config/expected_schema.json, mutate the copy, and run check_schema.py
against the mutated copy. Mutating the EXPECTED file is equivalent to the database
having changed in the opposite direction, and it means the test never has to build a
corrupted 880MB DuckDB file. The real database is opened read-only and never touched.

The headline case is `product_id_becomes_number`: the maintainer has stated
raw.product_id will change from string to number, and this asserts we would catch it.

Exit codes: 0 all cases behaved as expected, 1 one or more did not, 2 environment error.
No third-party dependencies. Run: python scripts/test_check_schema.py
"""
import json
import pathlib
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
SCHEMA = REPO / "config" / "expected_schema.json"
CHECKER = REPO / "scripts" / "check_schema.py"
DB = REPO / "hammer.duckdb"


def mut_product_id_to_number(d):
    for c in d["tables"]["raw"]["columns"]:
        if c["name"] == "product_id":
            c["type"] = "BIGINT"


def mut_drop_expected_column(d):
    d["tables"]["product"]["columns"] = [
        c for c in d["tables"]["product"]["columns"] if c["name"] != "upc"
    ]


def mut_add_expected_column(d):
    d["tables"]["raw"]["columns"].append(
        {"name": "promo_id", "type": "VARCHAR", "position": 7}
    )


def mut_swap_positions(d):
    cols = d["tables"]["raw"]["columns"]
    cols[0]["position"], cols[1]["position"] = 2, 1


def mut_expect_missing_table(d):
    d["tables"]["inventory"] = {"columns": [{"name": "qty", "type": "BIGINT", "position": 1}]}


# (name, mutation, extra CLI args, expected substring in output)
CASES = [
    ("product_id_becomes_number", mut_product_id_to_number, [], "TYPE MISMATCH"),
    ("expected_column_dropped",   mut_drop_expected_column, [], "UNEXPECTED"),
    ("expected_column_added",     mut_add_expected_column,  [], "MISSING"),
    ("column_position_moved",     mut_swap_positions, ["--strict-position"], "POSITION DRIFT"),
    ("expected_table_absent",     mut_expect_missing_table, [], "TABLE MISSING"),
]


def run_checker(schema_path: pathlib.Path, extra: list[str]):
    return subprocess.run(
        [sys.executable, str(CHECKER), "--db", str(DB), "--schema", str(schema_path), *extra],
        capture_output=True, text=True,
    )


def main() -> int:
    if not SCHEMA.exists():
        print(f"error: {SCHEMA} not found", file=sys.stderr)
        return 2
    if not DB.exists():
        print(f"error: {DB} not found - run scripts/load_snapshot.py first", file=sys.stderr)
        return 2

    base = json.loads(SCHEMA.read_text(encoding="utf-8"))
    results = []

    # Control: the committed schema must PASS. If this fails, every other
    # result below is meaningless.
    r = run_checker(SCHEMA, [])
    ok = r.returncode == 0
    results.append(("control_unmodified_schema_passes", ok, f"exit {r.returncode}"))

    with tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        for name, mutate, extra, expect in CASES:
            doc = json.loads(json.dumps(base))
            mutate(doc)
            p = tmp / f"{name}.json"
            p.write_text(json.dumps(doc, indent=2), encoding="utf-8")
            r = run_checker(p, extra)
            out = r.stdout + r.stderr
            ok = r.returncode == 1 and expect in out
            detail = f"exit {r.returncode}, expected substring {expect!r} {'found' if expect in out else 'NOT FOUND'}"
            results.append((name, ok, detail))

    width = max(len(n) for n, _, _ in results)
    passed = 0
    for name, ok, detail in results:
        print(f"{'PASS' if ok else 'FAIL'}  {name:<{width}}  ({detail})")
        passed += ok

    total = len(results)
    print(f"\n{passed} of {total} cases behaved as expected.")
    return 0 if passed == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
