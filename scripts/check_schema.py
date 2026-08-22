#!/usr/bin/env python3
"""Validate a loaded snapshot's schema against config/expected_schema.json.

CLAUDE.md ("Upstream volatility"): on every load, check column presence and type
against a committed expected-schema file. On mismatch, STOP THE RUN AND REPORT --
never silently cast, coerce, or infer.

The maintainer has stated `raw.product_id` will change from a string to a number.
This check is the thing that should catch it, loudly, at ingest.

Reports, per table:
  * missing columns        (expected, not present)
  * unexpected columns     (present, not expected)
  * type mismatches        (present, wrong type)  <- the product_id change lands here
  * position drift         (present, right type, different ordinal)

Exit codes: 0 schema matches, 1 mismatch, 2 usage/environment error.
No third-party dependencies beyond duckdb (already required to load a snapshot).

Usage:
  python scripts/check_schema.py [--db hammer.duckdb] [--schema config/expected_schema.json]
                                 [--strict-position]
"""
import argparse
import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent


def load_expected(path: pathlib.Path) -> dict:
    if not path.exists():
        print(f"error: expected-schema file not found: {path}", file=sys.stderr)
        raise SystemExit(2)
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"error: {path} is not valid JSON: {exc}", file=sys.stderr)
        raise SystemExit(2)
    if "tables" not in doc:
        print(f"error: {path} has no 'tables' key", file=sys.stderr)
        raise SystemExit(2)
    return doc


def actual_schema(db: pathlib.Path, tables: list[str]) -> dict:
    try:
        import duckdb
    except ImportError:
        print("error: duckdb is not installed", file=sys.stderr)
        raise SystemExit(2)
    if not db.exists():
        print(f"error: database not found: {db} (run scripts/load_snapshot.py first)",
              file=sys.stderr)
        raise SystemExit(2)
    con = duckdb.connect(str(db), read_only=True)
    out = {}
    for t in tables:
        rows = con.execute(
            "SELECT column_name, data_type, ordinal_position "
            "FROM information_schema.columns WHERE table_name = ? "
            "ORDER BY ordinal_position",
            [t],
        ).fetchall()
        out[t] = [{"name": r[0], "type": r[1], "position": r[2]} for r in rows]
    con.close()
    return out


def compare_table(name: str, expected: list[dict], actual: list[dict],
                  strict_position: bool) -> list[str]:
    problems = []
    exp_by = {c["name"]: c for c in expected}
    act_by = {c["name"]: c for c in actual}

    if not actual:
        return [f"[{name}] TABLE MISSING from the database entirely"]

    for col in expected:
        n = col["name"]
        if n not in act_by:
            problems.append(f"[{name}.{n}] MISSING - expected {col['type']}, column not present")
            continue
        got = act_by[n]
        if got["type"].upper() != col["type"].upper():
            problems.append(
                f"[{name}.{n}] TYPE MISMATCH - expected {col['type']}, found {got['type']}"
            )
        elif strict_position and got["position"] != col.get("position", got["position"]):
            problems.append(
                f"[{name}.{n}] POSITION DRIFT - expected #{col['position']}, found #{got['position']}"
            )

    for col in actual:
        if col["name"] not in exp_by:
            problems.append(
                f"[{name}.{col['name']}] UNEXPECTED - {col['type']} present but not in expected schema"
            )
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(REPO / "hammer.duckdb"))
    ap.add_argument("--schema", default=str(REPO / "config" / "expected_schema.json"))
    ap.add_argument("--strict-position", action="store_true",
                    help="also fail when a column's ordinal position moves")
    args = ap.parse_args()

    expected_doc = load_expected(pathlib.Path(args.schema))
    expected = expected_doc["tables"]
    actual = actual_schema(pathlib.Path(args.db), list(expected.keys()))

    print(f"schema file : {args.schema} (version {expected_doc.get('schema_version', '?')})")
    print(f"database    : {args.db}")

    problems = []
    for tname, tdef in expected.items():
        problems += compare_table(tname, tdef["columns"], actual.get(tname, []),
                                  args.strict_position)

    if not problems:
        n = sum(len(t["columns"]) for t in expected.values())
        print(f"\nOK - schema matches: {len(expected)} tables, {n} columns.")
        return 0

    print(f"\nSCHEMA MISMATCH - {len(problems)} problem(s):\n", file=sys.stderr)
    for p in problems:
        print(f"  {p}", file=sys.stderr)
    print(
        "\nIngest must STOP. Do not cast, coerce, or infer around this.\n"
        "If upstream changed deliberately (e.g. the announced raw.product_id\n"
        "string -> number change), update config/expected_schema.json in its own\n"
        "commit, with a note, and re-run.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
