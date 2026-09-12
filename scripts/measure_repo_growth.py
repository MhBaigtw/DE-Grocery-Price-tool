#!/usr/bin/env python3
"""Measure how much each committed refresh grows the repository.

WHY THIS EXISTS. The automated refresh commits tool/data/ (about 5.8 MB of JSON) to main every
time upstream publishes. The owner's condition for doing that was a measurement, not a guess:
if a refresh costs materially more than a few hundred KB of history, committing the extract is
the wrong design. A clone carries every refresh ever committed, so the per-refresh growth
compounds.

WHAT IT MEASURES. Extracts built for successive snapshots are committed, in date order, into a
fresh standalone repository, so the rest of this repository's history does not blur the result.
After each commit it reports:
  - loose   : the zlib-compressed size of the objects the commit added. The upper bound: what
              one refresh costs before git packs it against earlier versions.
  - packed  : growth of the pack after `git gc --aggressive`. This is what a clone downloads,
              once git has delta-compressed each file against its previous version.
The first commit is the baseline, not a refresh; growth is reported from the second on. A real
refresh also adds a provenance record of about 1.5 KB, which is included when --provenance is
given.

  python scripts/measure_repo_growth.py DIR_A DIR_B [DIR_C ...]   # each DIR holds tool/data/*.json

Each DIR is an extract directory (meta.json, products.json, history.json), in date order.
"""
from __future__ import annotations
import argparse, json, pathlib, shutil, subprocess, sys, tempfile, zlib

FILES = ("meta.json", "products.json", "history.json")


def git(repo: pathlib.Path, *a: str) -> str:
    return subprocess.run(["git", *a], cwd=repo, capture_output=True, text=True, check=True).stdout


def pack_bytes(repo: pathlib.Path) -> int:
    git(repo, "gc", "--aggressive", "--prune=now", "--quiet")
    kv = dict(l.split(": ", 1) for l in git(repo, "count-objects", "-v").splitlines())
    return int(kv["size-pack"]) * 1024 + int(kv["size"]) * 1024


def loose_bytes(files: list[pathlib.Path]) -> int:
    total = 0
    for f in files:
        blob = f.read_bytes()
        total += len(zlib.compress(b"blob %d\0" % len(blob) + blob))
    return total


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dirs", nargs="+", help="extract directories, oldest first")
    ap.add_argument("--provenance", nargs="*", default=None,
                    help="provenance record files, one per directory, committed alongside")
    args = ap.parse_args()
    dirs = [pathlib.Path(d) for d in args.dirs]
    if len(dirs) < 2:
        print("need at least two extracts: a baseline and one refresh")
        return 1

    with tempfile.TemporaryDirectory() as td:
        repo = pathlib.Path(td) / "growth"
        repo.mkdir()
        git(repo, "init", "--quiet")
        git(repo, "config", "user.name", "measure")
        git(repo, "config", "user.email", "measure@localhost")
        git(repo, "config", "core.autocrlf", "false")
        (repo / "tool" / "data").mkdir(parents=True)
        (repo / "data" / "provenance").mkdir(parents=True)
        prev = None
        print(f"{'extract':<34} {'date':<11} {'raw KB':>8} {'loose KB':>9} {'pack KB':>9} {'growth KB':>10}")
        for i, d in enumerate(dirs):
            added = []
            for f in FILES:
                shutil.copyfile(d / f, repo / "tool" / "data" / f)
                added.append(repo / "tool" / "data" / f)
            if args.provenance:
                p = pathlib.Path(args.provenance[i])
                shutil.copyfile(p, repo / "data" / "provenance" / p.name)
                added.append(repo / "data" / "provenance" / p.name)
            git(repo, "add", "-A")
            git(repo, "commit", "--quiet", "-m", f"extract {i}")
            meta = json.loads((d / "meta.json").read_text(encoding="utf-8"))
            raw = sum(f.stat().st_size for f in added)
            loose = loose_bytes(added)
            pack = pack_bytes(repo)
            growth = "baseline" if prev is None else f"{(pack - prev) / 1024:10.1f}"
            print(f"{meta.get('snapshot_id', d.name):<34} {str(meta.get('extract_date')):<11} "
                  f"{raw / 1024:8.0f} {loose / 1024:9.0f} {pack / 1024:9.0f} {growth:>10}")
            prev = pack
    print("\nloose = one refresh before packing (upper bound); growth = pack growth after "
          "git gc --aggressive (what a clone carries per refresh).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
