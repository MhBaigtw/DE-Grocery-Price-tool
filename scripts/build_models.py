#!/usr/bin/env python3
"""Materialise the Phase 1 models into a snapshot's DuckDB.

REPRODUCIBILITY CONTRACT
------------------------
`stg_price` is a CACHE, not an artifact. Everything in it is a pure function of
  (a) the immutable snapshot archive under data/snapshots/<id>/, verified by sha256, and
  (b) the committed SQL in models/.
Nothing is hand-edited, nothing is appended incrementally, and no state accumulates
across builds -- the model is DROPped and recreated in full every run. Deleting the
2.1 GB table costs only the time to rebuild it:

    python scripts/load_snapshot.py <snapshot_id> --db hammer.duckdb
    python scripts/build_models.py --db hammer.duckdb --materialize table

That is why the materialisation is gitignored without hesitation and why it can be
rebuilt on any machine from the archive plus this repo. `scripts/verify_reproducible.py`
asserts it rather than leaving it as a claim.

Opens the database READ-WRITE, which is why this is a separate script from
run_query.py (that one is deliberately read-only so a query can never mutate state).
The target databases are derived and gitignored; the immutable snapshot archives under
data/snapshots/ are never touched.

Models are materialised as VIEWS by default. The parse is pure computation over columns
already in the table, so a view costs no disk and cannot drift from its source -- which
matters here because we hold two snapshots and a stale materialisation would silently
mix them. Pass --materialize table if a downstream step needs the speed.

Usage:
  python scripts/build_models.py [--db hammer.duckdb] [--materialize view|table]
"""
import argparse
import pathlib
import sys

import duckdb

REPO = pathlib.Path(__file__).resolve().parent.parent
MACROS = REPO / "models" / "price_parse_macros.sql"
MODELS = [("stg_price", REPO / "models" / "stg_price.sql")]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(REPO / "hammer.duckdb"))
    ap.add_argument("--materialize", choices=["view", "table"], default="view")
    args = ap.parse_args()

    db = pathlib.Path(args.db)
    if not db.exists():
        sys.exit(f"no such database: {db} (run scripts/load_snapshot.py first)")

    con = duckdb.connect(str(db))
    con.execute("PRAGMA disable_progress_bar;")

    # Macros are recreated every build so the database always matches the committed file.
    con.execute(MACROS.read_text(encoding="utf-8"))
    print(f"macros loaded from {MACROS.relative_to(REPO)}")

    for name, path in MODELS:
        body = path.read_text(encoding="utf-8")
        kind = "VIEW" if args.materialize == "view" else "TABLE"
        # DuckDB raises rather than no-opping when DROP VIEW IF EXISTS hits a table
        # (and vice versa), so the existing object's type decides which DROP to issue.
        # Getting this wrong silently leaves a STALE model in place while the build
        # reports success -- which is exactly what happened on the first attempt to
        # rebuild after the Walmart bare-integer fix.
        existing = con.execute(
            "SELECT table_type FROM information_schema.tables WHERE table_name = ?",
            [name]).fetchone()
        if existing:
            con.execute(f"DROP {'TABLE' if existing[0] == 'BASE TABLE' else 'VIEW'} {name};")
        con.execute(f"CREATE {kind} {name} AS {body}")
        n = con.execute(f"SELECT count(*) FROM {name}").fetchone()[0]
        src = con.execute("SELECT count(*) FROM raw").fetchone()[0]
        status = "OK" if n == src else "ROW COUNT MISMATCH"
        print(f"  {name}: {kind.lower()}, {n:,} rows (raw has {src:,}) -- {status}")
        if n != src:
            print("  refusing to continue: the model must be 1:1 with raw", file=sys.stderr)
            return 1

    con.close()
    print(f"\nbuilt into {db}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
