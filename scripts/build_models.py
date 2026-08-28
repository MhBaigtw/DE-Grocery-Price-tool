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
MACRO_FILES = [
    REPO / "models" / "product_key_macros.sql",
    REPO / "models" / "price_parse_macros.sql",
    REPO / "models" / "unit_parse_macros.sql",
    REPO / "models" / "brand_class_macros.sql",
]
# (model name, sql file, source table it must be 1:1 with)
MODELS = [
    ("stg_price",   REPO / "models" / "stg_price.sql",   "raw"),
    ("stg_product", REPO / "models" / "stg_product.sql", "product"),
]


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

    # Any failure below must STOP the build and be unmistakable in a log. The first
    # rebuild after the section 2.5 fix crashed on a DROP type mismatch, and the queries
    # that followed ran happily against the STALE table while the traceback sat several
    # screens further up. A build step that can leave old data in place while later steps
    # report success is worse than one that simply fails.
    def fail(msg: str) -> int:
        print("\n" + "=" * 70, file=sys.stderr)
        print("BUILD FAILED -- MODELS MAY BE STALE. DO NOT TRUST ANY QUERY RUN AFTER THIS.",
              file=sys.stderr)
        print(f"  {msg}", file=sys.stderr)
        print("=" * 70, file=sys.stderr)
        return 1

    # Macros are recreated every build so the database always matches the committed files.
    for mf in MACRO_FILES:
        con.execute(mf.read_text(encoding="utf-8"))
        print(f"macros loaded from {mf.relative_to(REPO)}")

    for name, path, src_table in MODELS:
      try:
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
        src = con.execute(f"SELECT count(*) FROM {src_table}").fetchone()[0]
        status = "OK" if n == src else "ROW COUNT MISMATCH"
        print(f"  {name}: {kind.lower()}, {n:,} rows ({src_table} has {src:,}) -- {status}")
        if n != src:
            return fail(f"{name} is {n:,} rows but {src_table} is {src:,} -- "
                        "the model must be 1:1 with its source")
      except Exception as exc:
        return fail(f"while building {name}: {type(exc).__name__}: {exc}")

    # Build stamp: what was built, from which macro sources, when. verify_reproducible.py
    # compares these digests against the committed files, so a model built from an older
    # version of the macros is detectable rather than merely suspected.
    import hashlib
    import datetime
    con.execute("DROP TABLE IF EXISTS _build_stamp;")
    con.execute("CREATE TABLE _build_stamp (k VARCHAR, v VARCHAR);")
    con.execute("INSERT INTO _build_stamp VALUES (?, ?)",
                ["built_utc", datetime.datetime.now(datetime.timezone.utc).isoformat()])
    con.execute("INSERT INTO _build_stamp VALUES (?, ?)", ["materialize", args.materialize])
    for f in MACRO_FILES + [m[1] for m in MODELS]:
        digest = hashlib.sha256(f.read_bytes()).hexdigest()
        con.execute("INSERT INTO _build_stamp VALUES (?, ?)",
                    [f"sha256:{f.relative_to(REPO).as_posix()}", digest])
    con.close()
    print(f"\nbuilt into {db}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
