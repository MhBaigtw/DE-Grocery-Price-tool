#!/usr/bin/env python3
"""Assert that stg_price is a cache, not an artifact.

The claim: every value in the materialised table is a pure function of the immutable
snapshot plus the committed SQL. If that is true, rebuilding the model from scratch must
produce byte-identical content -- so a materialisation can be deleted without losing
anything, and a stale one cannot silently diverge from its source.

This checks it rather than asserting it: it recomputes the model definition as a view
over `raw` and compares, column by column, against the materialised table.

Exit 0 if the cache matches its definition, 1 if it has drifted, 2 on a usage error.

Usage:  python scripts/verify_reproducible.py [--db hammer.duckdb]
"""
import argparse
import pathlib
import sys

import duckdb

REPO = pathlib.Path(__file__).resolve().parent.parent


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(REPO / "hammer.duckdb"))
    args = ap.parse_args()

    # An in-memory connection with the database ATTACHed read-only. Macros are CREATEd,
    # which a read-only connection refuses, but the snapshot database itself must stay
    # read-only -- a verifier that can modify what it verifies is not a verifier.
    con = duckdb.connect(":memory:")
    con.execute("PRAGMA disable_progress_bar;")
    con.execute("SET threads=4;")
    con.execute(f"ATTACH '{pathlib.Path(args.db).as_posix()}' AS snap (READ_ONLY);")
    # Macros are created in the in-memory catalog (the default), NOT in snap -- a
    # read-only attachment refuses CREATE, which is the point: the verifier must not be
    # able to modify what it verifies.
    for mf in ("product_key_macros.sql", "price_parse_macros.sql",
               "unit_parse_macros.sql", "brand_class_macros.sql"):
        con.execute((REPO / "models" / mf).read_text(encoding="utf-8"))

    kind = con.execute(
        "SELECT table_type FROM information_schema.tables "
        "WHERE table_name='stg_price' AND table_catalog='snap'"
    ).fetchone()
    if not kind:
        print("stg_price does not exist; nothing to verify", file=sys.stderr)
        return 2
    if kind[0] != "BASE TABLE":
        print(f"stg_price is a {kind[0]}, not a materialised table -- "
              "it is its definition by construction. Nothing to drift.")
        return 0

    # Build stamp first: a model built from older macro sources is stale even if its
    # content happens to match today's recomputation on the columns we check.
    import hashlib
    try:
        stamp = dict(con.execute("SELECT k, v FROM snap._build_stamp").fetchall())
    except Exception:
        stamp = {}
    if stamp:
        drifted = []
        for key, recorded in stamp.items():
            if not key.startswith("sha256:"):
                continue
            f = REPO / key[len("sha256:"):]
            if not f.exists() or hashlib.sha256(f.read_bytes()).hexdigest() != recorded:
                drifted.append(key[len("sha256:"):])
        if drifted:
            print("\nFAIL - built from source files that have since changed: "
                  + ", ".join(drifted), file=sys.stderr)
            print("       rebuild before trusting any query.", file=sys.stderr)
            return 1
        n_src = len([k for k in stamp if k.startswith("sha256:")])
        print(f"build stamp   : OK, {n_src} source files match")
    else:
        print("build stamp   : absent (built before stamping was added)")

    # Build stamp first: a model built from older macro sources is stale even if its
    # content happens to match today's recomputation on the columns we check.
    import hashlib
    try:
        stamp = dict(con.execute("SELECT k, v FROM snap._build_stamp").fetchall())
    except Exception:
        stamp = {}
    if stamp:
        drifted = []
        for key, recorded in stamp.items():
            if not key.startswith("sha256:"):
                continue
            f = REPO / key[len("sha256:"):]
            if not f.exists() or hashlib.sha256(f.read_bytes()).hexdigest() != recorded:
                drifted.append(key[len("sha256:"):])
        if drifted:
            print("FAIL - built from source files that have since changed: "
                  + ", ".join(drifted), file=sys.stderr)
            print("       rebuild before trusting any query.", file=sys.stderr)
            return 1
        n_src = len([k for k in stamp if k.startswith("sha256:")])
        print(f"build stamp   : OK, {n_src} source files match")
    else:
        print("build stamp   : absent (built before stamping was added)")

    body = (REPO / "models" / "stg_price.sql").read_text(encoding="utf-8")
    body = body.replace("FROM raw r", "FROM snap.raw r").replace(
    "JOIN product pr", "JOIN snap.product pr")
    con.execute(f"CREATE OR REPLACE TEMP VIEW stg_price_recomputed AS {body}")

    n_cached = con.execute("SELECT count(*) FROM snap.stg_price").fetchone()[0]
    n_fresh = con.execute("SELECT count(*) FROM stg_price_recomputed").fetchone()[0]
    print(f"cached rows     : {n_cached:,}")
    print(f"recomputed rows : {n_fresh:,}")
    if n_cached != n_fresh:
        print("\nFAIL - row counts differ; the cache is stale.", file=sys.stderr)
        return 1

    # Full-content comparison via an order-independent checksum per column.
    cols = [r[0] for r in con.execute(
        "SELECT column_name FROM information_schema.columns "
        "WHERE table_name='stg_price' AND table_catalog='snap' "
        "ORDER BY ordinal_position").fetchall()]
    drift = []
    for c in cols:
        a, b = con.execute(
            f'SELECT (SELECT sum(hash(coalesce(CAST("{c}" AS VARCHAR),chr(1))))::HUGEINT FROM snap.stg_price),'
            f'       (SELECT sum(hash(coalesce(CAST("{c}" AS VARCHAR),chr(1))))::HUGEINT FROM stg_price_recomputed)'
        ).fetchone()
        mark = "ok  " if a == b else "DRIFT"
        if a != b:
            drift.append(c)
        print(f"  {mark} {c}")

    if drift:
        print(f"\nFAIL - {len(drift)} column(s) drifted from the committed definition: "
              f"{', '.join(drift)}", file=sys.stderr)
        return 1
    print(f"\nOK - stg_price matches its definition across {len(cols)} columns. "
          "The materialisation is a cache and can be deleted safely.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
