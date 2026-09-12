#!/usr/bin/env python3
"""Load a Project Hammer snapshot into DuckDB for analysis.

Locked decision #2 (CLAUDE.md): the snapshot is never modified. This script only
reads from data/snapshots/<id>/ and writes a separate, gitignored DuckDB file.
Re-running rebuilds the DuckDB from scratch; the snapshot is untouched.

Source of truth is the SQLite distribution (hammer-3-compressed.zip). The CSV
distribution is downloaded too (the brief asks for both) but the SQLite file is what
we load: it carries declared column types and avoids the CSV BOM/quoting variance the
upstream notes warn about.

Usage:  python scripts/load_snapshot.py [snapshot_id] [--db hammer.duckdb]
"""
import argparse
import json
import pathlib
import re
import shutil
import sys
import zipfile

import duckdb

REPO = pathlib.Path(__file__).resolve().parent.parent
SNAPSHOTS = REPO / "data" / "snapshots"


def pick_snapshot(snapshot_id: str | None) -> pathlib.Path:
    if snapshot_id and (pathlib.Path(snapshot_id) / "manifest.json").exists():
        return pathlib.Path(snapshot_id)
    if snapshot_id:
        p = SNAPSHOTS / snapshot_id
        if not p.is_dir():
            sys.exit(f"no such snapshot: {p}")
        return p
    candidates = sorted(p for p in SNAPSHOTS.glob("*") if (p / "manifest.json").exists())
    if not candidates:
        sys.exit(f"no snapshots with a manifest under {SNAPSHOTS}; run fetch_snapshot.py")
    return candidates[-1]


def extract_sqlite(snap: pathlib.Path, workdir: pathlib.Path) -> pathlib.Path:
    """Extract the .sqlite member from the SQLite archive into a scratch dir."""
    archive = snap / "hammer-3-compressed.zip"
    with zipfile.ZipFile(archive) as zf:
        members = [n for n in zf.namelist() if n.lower().endswith((".sqlite", ".db", ".sqlite3"))]
        if not members:
            members = [n for n in zf.namelist() if not n.endswith("/")]
        if len(members) != 1:
            sys.exit(f"expected one db member in {archive.name}, found: {members}")
        name = members[0]
        print(f"extracting {name} from {archive.name} ...")
        with zf.open(name) as src, open(workdir / "hammer.sqlite", "wb") as dst:
            shutil.copyfileobj(src, dst, length=1 << 22)
    return workdir / "hammer.sqlite"


def load(snap: pathlib.Path, db: pathlib.Path, workdir: pathlib.Path,
         vendors: tuple[str, ...] | None = None, drop_sqlite: bool = False) -> dict:
    """Copy the snapshot's tables into a fresh DuckDB file.

    vendors=None is the full load every analysis figure is computed from. A vendor list is the
    LIGHT load (scripts/refresh_light.py): `product` keeps only those vendors' rows and `raw`
    keeps only price rows whose product is one of them. Every other source table is created
    with its columns and no rows, so the schema contract sees exactly the table set and types a
    full load would. The filter is proven, not assumed: scripts/check_light_parity.py requires
    the light extract to equal the full extract for the same snapshot.
    """
    manifest = json.loads((snap / "manifest.json").read_text(encoding="utf-8"))
    print(f"snapshot {manifest['snapshot_id']}  upstream last-updated "
          f"{manifest['upstream_lastupdated_raw']!r}")

    workdir.mkdir(parents=True, exist_ok=True)
    sqlite_path = extract_sqlite(snap, workdir)

    if db.exists():
        db.unlink()
    con = duckdb.connect(str(db))
    con.execute("INSTALL sqlite; LOAD sqlite;")
    con.execute(f"ATTACH '{sqlite_path.as_posix()}' AS src (TYPE sqlite, READ_ONLY);")

    tables = [r[0] for r in con.execute(
        "SELECT table_name FROM information_schema.tables WHERE table_catalog='src'"
    ).fetchall()]
    print("source tables:", tables)

    counts: dict = {}
    if vendors is None:
        for t in tables:
            print(f"  copying {t} ...", flush=True)
            con.execute(f'CREATE TABLE "{t}" AS SELECT * FROM src."{t}";')
            n = con.execute(f'SELECT count(*) FROM "{t}"').fetchone()[0]
            print(f"  {t}: {n:,} rows")
    else:
        for v in vendors:
            if not re.fullmatch(r"[A-Za-z]+", v):
                sys.exit(f"refusing vendor name {v!r}: letters only, it is spliced into SQL")
        if not {"product", "raw"} <= set(tables):
            sys.exit(f"light load needs source tables product and raw, found {tables}")
        in_list = ", ".join(f"'{v}'" for v in vendors)
        print(f"  light load: vendors {in_list} only", flush=True)
        con.execute(f"CREATE TABLE product AS SELECT * FROM src.product WHERE vendor IN ({in_list});")
        con.execute("CREATE TABLE raw AS SELECT r.* FROM src.raw r "
                    "WHERE r.product_id IN (SELECT id FROM product);")
        for t in tables:
            if t not in ("product", "raw"):
                con.execute(f'CREATE TABLE "{t}" AS SELECT * FROM src."{t}" LIMIT 0;')
        counts = {
            "load_filter": "vendors=" + ",".join(vendors),
            "product_rows_source": con.execute("SELECT count(*) FROM src.product").fetchone()[0],
            "product_rows_loaded": con.execute("SELECT count(*) FROM product").fetchone()[0],
            "raw_rows_source": con.execute("SELECT count(*) FROM src.raw").fetchone()[0],
            "raw_rows_loaded": con.execute("SELECT count(*) FROM raw").fetchone()[0],
        }
        print(f"  product: {counts['product_rows_loaded']:,} of {counts['product_rows_source']:,} rows")
        print(f"  raw: {counts['raw_rows_loaded']:,} of {counts['raw_rows_source']:,} rows "
              f"({100 * counts['raw_rows_loaded'] / max(1, counts['raw_rows_source']):.1f}%)")

    # Provenance travels with the analysis DB so no number is orphaned from its source.
    con.execute("CREATE TABLE _snapshot_provenance (k VARCHAR, v VARCHAR);")
    con.execute("INSERT INTO _snapshot_provenance VALUES (?,?),(?,?)",
                ["snapshot_id", manifest["snapshot_id"],
                 "upstream_lastupdated_raw", manifest["upstream_lastupdated_raw"]])
    for a in manifest["archives"]:
        con.execute("INSERT INTO _snapshot_provenance VALUES (?,?),(?,?)",
                    [f"{a['filename']}.sha256", a["sha256"],
                     f"{a['filename']}.downloaded_utc", a["download_finished_utc"]])
    for k, v in counts.items():
        con.execute("INSERT INTO _snapshot_provenance VALUES (?,?)", [k, str(v)])

    con.execute("DETACH src;")
    con.close()
    if drop_sqlite:
        sqlite_path.unlink()
        print(f"deleted the extracted {sqlite_path.name}")
    print(f"\nwrote {db}")
    return counts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("snapshot_id", nargs="?",
                    help="a snapshot id under data/snapshots/, or a snapshot directory")
    ap.add_argument("--db", default=str(REPO / "hammer.duckdb"))
    ap.add_argument("--workdir", default=None,
                    help="scratch dir for the extracted sqlite (default: alongside --db)")
    ap.add_argument("--vendors", default=None,
                    help="LIGHT load: comma-separated vendors to keep (the tool's chains). "
                         "Omit for the full load every analysis figure uses.")
    ap.add_argument("--drop-sqlite", action="store_true",
                    help="delete the extracted SQLite once loaded (the light path's disk budget)")
    args = ap.parse_args()

    snap = pick_snapshot(args.snapshot_id)
    workdir = pathlib.Path(args.workdir) if args.workdir else pathlib.Path(args.db).parent
    vendors = tuple(v.strip() for v in args.vendors.split(",")) if args.vendors else None
    load(snap, pathlib.Path(args.db), workdir, vendors, args.drop_sqlite)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
