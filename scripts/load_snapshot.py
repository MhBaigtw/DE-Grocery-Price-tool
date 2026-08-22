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
import shutil
import sys
import zipfile

import duckdb

REPO = pathlib.Path(__file__).resolve().parent.parent
SNAPSHOTS = REPO / "data" / "snapshots"


def pick_snapshot(snapshot_id: str | None) -> pathlib.Path:
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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("snapshot_id", nargs="?")
    ap.add_argument("--db", default=str(REPO / "hammer.duckdb"))
    ap.add_argument("--workdir", default=None,
                    help="scratch dir for the extracted sqlite (default: alongside --db)")
    args = ap.parse_args()

    snap = pick_snapshot(args.snapshot_id)
    manifest = json.loads((snap / "manifest.json").read_text(encoding="utf-8"))
    print(f"snapshot {manifest['snapshot_id']}  upstream last-updated "
          f"{manifest['upstream_lastupdated_raw']!r}")

    workdir = pathlib.Path(args.workdir) if args.workdir else pathlib.Path(args.db).parent
    workdir.mkdir(parents=True, exist_ok=True)
    sqlite_path = extract_sqlite(snap, workdir)

    db = pathlib.Path(args.db)
    if db.exists():
        db.unlink()
    con = duckdb.connect(str(db))
    con.execute("INSTALL sqlite; LOAD sqlite;")
    con.execute(f"ATTACH '{sqlite_path.as_posix()}' AS src (TYPE sqlite, READ_ONLY);")

    tables = [r[0] for r in con.execute(
        "SELECT table_name FROM information_schema.tables WHERE table_catalog='src'"
    ).fetchall()]
    print("source tables:", tables)

    for t in tables:
        print(f"  copying {t} ...", flush=True)
        con.execute(f'CREATE TABLE "{t}" AS SELECT * FROM src."{t}";')
        n = con.execute(f'SELECT count(*) FROM "{t}"').fetchone()[0]
        print(f"  {t}: {n:,} rows")

    # Provenance travels with the analysis DB so no number is orphaned from its source.
    con.execute("CREATE TABLE _snapshot_provenance (k VARCHAR, v VARCHAR);")
    con.execute("INSERT INTO _snapshot_provenance VALUES (?,?),(?,?)",
                ["snapshot_id", manifest["snapshot_id"],
                 "upstream_lastupdated_raw", manifest["upstream_lastupdated_raw"]])
    for a in manifest["archives"]:
        con.execute("INSERT INTO _snapshot_provenance VALUES (?,?),(?,?)",
                    [f"{a['filename']}.sha256", a["sha256"],
                     f"{a['filename']}.downloaded_utc", a["download_finished_utc"]])

    con.execute("DETACH src;")
    con.close()
    print(f"\nwrote {db}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
