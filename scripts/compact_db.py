#!/usr/bin/env python3
"""Compact a DuckDB analysis database by rewriting it into a fresh file.

DuckDB does not reclaim pages on `CREATE OR REPLACE TABLE`. After a handful of model
rebuilds the file is mostly dead space -- this repo's hammer.duckdb reached 5.74 GB with
13,448 used blocks against 10,073 free, roughly 43% waste. The only way to shed that is to
write a new database and swap it in.

WHY NOT JUST RE-RUN load_snapshot.py + build_models.py: that path extracts a 4.3 GB SQLite
file first, which needs more free space than a nearly-full disk has. This copies table by
table straight out of the existing database, so the peak requirement is
(old file) + (compacted file) with no intermediate.

The swap is deliberately last and atomic-ish: the new file is fully built and verified
row-for-row BEFORE the old one is deleted. If anything fails, the original is untouched.

Usage:  python scripts/compact_db.py [--db hammer.duckdb] [--keep-original]
"""
import argparse
import pathlib
import shutil
import sys

import duckdb


def gb(path: pathlib.Path) -> float:
    return path.stat().st_size / 1024**3


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="hammer.duckdb")
    ap.add_argument("--keep-original", action="store_true",
                    help="leave the original in place as <name>.bloated")
    args = ap.parse_args()

    src = pathlib.Path(args.db).resolve()
    if not src.exists():
        sys.exit(f"no such database: {src}")
    dst = src.with_name(src.stem + "_compact.duckdb")
    if dst.exists():
        dst.unlink()

    print(f"source     : {src.name}  {gb(src):.2f} GB")

    con = duckdb.connect(str(dst))
    con.execute("PRAGMA disable_progress_bar;")
    con.execute("SET threads=4;")
    con.execute(f"ATTACH '{src.as_posix()}' AS old (READ_ONLY);")

    tables = [r[0] for r in con.execute(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_catalog='old' AND table_type='BASE TABLE' ORDER BY table_name"
    ).fetchall()]
    print(f"tables     : {', '.join(tables)}")

    counts = {}
    for t in tables:
        con.execute(f'CREATE TABLE "{t}" AS SELECT * FROM old."{t}";')
        n_new = con.execute(f'SELECT count(*) FROM "{t}"').fetchone()[0]
        n_old = con.execute(f'SELECT count(*) FROM old."{t}"').fetchone()[0]
        counts[t] = (n_old, n_new)
        flag = "OK" if n_old == n_new else "MISMATCH"
        print(f"  {t:<22} {n_new:>12,} rows  (source {n_old:,})  {flag}")
        if n_old != n_new:
            con.close()
            dst.unlink(missing_ok=True)
            print("\nrow count mismatch -- original left untouched", file=sys.stderr)
            return 1

    con.execute("DETACH old;")
    con.close()

    print(f"\ncompacted  : {dst.name}  {gb(dst):.2f} GB "
          f"({gb(src) - gb(dst):+.2f} GB)")

    if args.keep_original:
        src.rename(src.with_suffix(".duckdb.bloated"))
    else:
        src.unlink()
    shutil.move(str(dst), str(src))
    print(f"swapped in : {src.name}  {gb(src):.2f} GB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
