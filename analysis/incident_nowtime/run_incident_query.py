#!/usr/bin/env python3
"""Run one of the N*.sql incident queries against upstream's SQLite files directly.

WHY THIS IS NOT scripts/run_query.py. Every other query in analysis/ runs against a loaded
analysis DuckDB. These cannot: they compare upstream's archive in its OLD form with the same
archive in its NEW form, column type and all, and the loader would refuse one of them at the
schema gate before a single row was read. So they read the two SQLite files as upstream
shipped them, attached read-only:

    n   the new-form archive (raw.nowtime INTEGER) -- upstream's 2026-11-14 publication,
        hammer-3-compressed.zip sha256 3b0fed4c547788ef37d4067bac934b71387fa266be6a40b4f6c7ac00a122d32b
    o   the old-form archive (raw.nowtime TEXT) -- data/snapshots/20260911T200435Z

Extract hammer-2-processed.sqlite from each zip into its own directory first (about 4.4 GB
each). Nothing is written to either file.

    python analysis/incident_nowtime/run_incident_query.py N4_overlap_date_proof.sql \
        --new <dir>/new/hammer-2-processed.sqlite --old <dir>/old/hammer-2-processed.sqlite

N6 also needs the extract committed by the last good refresh:

    git show 97a2886:tool/data/products.json > <dir>/products.json
    ... N6_extract_of_20261105.sql --new ... --old ... --extract <dir>/products.json

Every statement that returns rows is printed, in file order. Memory is capped at 2 GB: these
were written on an 8 GB laptop and each query streams.
"""
import argparse
import pathlib
import sys

import duckdb

HERE = pathlib.Path(__file__).resolve().parent


def statements(sql: str):
    """Split on ';' at end of line. The query files keep ';' out of strings and comments."""
    buf = []
    for line in sql.splitlines():
        buf.append(line)
        if line.rstrip().endswith(";"):
            yield "\n".join(buf)
            buf = []
    if "\n".join(buf).strip():
        yield "\n".join(buf)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("query", help="an N*.sql file in this directory, or a path")
    ap.add_argument("--new", required=True, help="the new-form hammer-2-processed.sqlite")
    ap.add_argument("--old", required=True, help="the old-form hammer-2-processed.sqlite")
    ap.add_argument("--extract", default=None, help="products.json of commit 97a2886 (N6 only)")
    ap.add_argument("--max-rows", type=int, default=60)
    args = ap.parse_args()

    q = pathlib.Path(args.query)
    if not q.exists():
        q = HERE / args.query
    for label, p in (("--new", args.new), ("--old", args.old)):
        if not pathlib.Path(p).is_file():
            sys.exit(f"{label}: no such file: {p}")

    con = duckdb.connect()
    con.execute("SET memory_limit='2GB'; SET threads=4; PRAGMA disable_progress_bar;")
    con.execute("INSTALL sqlite; LOAD sqlite;")
    con.execute(f"ATTACH '{pathlib.Path(args.new).as_posix()}' AS n (TYPE sqlite, READ_ONLY);")
    con.execute(f"ATTACH '{pathlib.Path(args.old).as_posix()}' AS o (TYPE sqlite, READ_ONLY);")
    if args.extract:
        con.execute("SET VARIABLE extract_json = ?", [pathlib.Path(args.extract).as_posix()])

    print(f"query : {q.name}\nnew   : {args.new}\nold   : {args.old}\n")
    for stmt in statements(q.read_text(encoding="utf-8")):
        body = "\n".join(l for l in stmt.splitlines() if not l.strip().startswith("--")).strip()
        if not body:
            continue
        res = con.execute(stmt)
        if res.description is None:
            continue
        rows = res.fetchall()
        if len(res.description) == 1 and res.description[0][0] in ("Count", "Success"):
            continue                                    # CREATE TABLE AS and friends
        print(" | ".join(d[0] for d in res.description))
        for r in rows[:args.max_rows]:
            print("   " + " | ".join("NULL" if v is None else str(v) for v in r))
        if len(rows) > args.max_rows:
            print(f"   ... {len(rows) - args.max_rows} more row(s)")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
