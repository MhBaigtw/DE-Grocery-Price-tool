#!/usr/bin/env python3
"""A full rebuild's extract must be byte-identical to the light extract for the same snapshot.

WHY THIS EXISTS. The light refresh (refresh_light.py) loads only the chains the tool reads.
That filter is the one thing the light path does that the full path does not. A filter that
drops rows the extract needs does not crash. It ships a quietly different extract that passes
every floor, every structural check and the render test. The only proof that it does not is
to build both extracts from the same archive and compare the bytes, so that is what this does.
It runs at the end of every full rebuild (scripts/refresh.py), and a mismatch fails that
rebuild loudly.

WHAT "IDENTICAL" MEANS. products.json and history.json byte for byte. meta.json field for field,
except built_utc, which records when each build ran and so must differ. Extracts from different
snapshots are refused rather than compared: a difference between them would prove nothing.

  python scripts/check_light_parity.py 20260911T200435Z          # build the light extract, compare with tool/data
  python scripts/check_light_parity.py --light-dir DIR           # compare with an extract already built

Exit 0 = identical. Exit 1 = they differ, or parity could not be established.
"""
from __future__ import annotations
import argparse, hashlib, json, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PY = sys.executable
BYTE_FILES = ("products.json", "history.json")
META_IGNORED = {"built_utc"}


def _short_sha(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()[:12]


def _keys(path: pathlib.Path) -> set:
    rows = json.loads(path.read_text(encoding="utf-8"))
    return {(r.get("gtin14"), r.get("chain"), r.get("basis")) for r in rows}


def compare_extracts(full: pathlib.Path, light: pathlib.Path) -> list[str]:
    problems: list[str] = []
    for f in ("meta.json",) + BYTE_FILES:
        for side, d in (("full", full), ("light", light)):
            if not (d / f).exists():
                problems.append(f"{f} is missing from the {side} extract ({d})")
    if problems:
        return problems

    mf = json.loads((full / "meta.json").read_text(encoding="utf-8"))
    ml = json.loads((light / "meta.json").read_text(encoding="utf-8"))
    if mf.get("snapshot_id") != ml.get("snapshot_id"):
        return [f"the extracts come from different snapshots (full {mf.get('snapshot_id')}, "
                f"light {ml.get('snapshot_id')}); parity can only be judged on one snapshot"]
    for k in sorted((set(mf) | set(ml)) - META_IGNORED):
        if mf.get(k) != ml.get(k):
            problems.append(f"meta.json field {k!r} differs: full "
                            f"{json.dumps(mf.get(k))[:100]} / light {json.dumps(ml.get(k))[:100]}")

    for f in BYTE_FILES:
        a, b = full / f, light / f
        if a.read_bytes() == b.read_bytes():
            continue
        detail = ""
        try:
            ka, kb = _keys(a), _keys(b)
            detail = f"; {len(ka - kb)} record(s) only in full, {len(kb - ka)} only in light"
        except Exception:                                      # noqa: BLE001
            detail = "; one side is not valid JSON"
        problems.append(f"{f} differs: full {a.stat().st_size:,} B ({_short_sha(a)}), "
                        f"light {b.stat().st_size:,} B ({_short_sha(b)}){detail}")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("snapshot", nargs="?",
                    help="snapshot id under data/snapshots/, or a snapshot directory")
    ap.add_argument("--full-dir", default=str(ROOT / "tool" / "data"),
                    help="the full rebuild's extract (default: tool/data)")
    ap.add_argument("--light-dir", default=None,
                    help="an already-built light extract; skips the build")
    ap.add_argument("--workdir", default=None,
                    help="scratch directory for the light build (default: a temporary directory)")
    args = ap.parse_args()
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:                                      # noqa: BLE001
            pass

    full = pathlib.Path(args.full_dir)
    if args.light_dir:
        light = pathlib.Path(args.light_dir)
    else:
        if not args.snapshot:
            print("FAIL - name a snapshot, or pass --light-dir")
            return 1
        snap = pathlib.Path(args.snapshot)
        if not (snap / "manifest.json").exists():
            snap = ROOT / "data" / "snapshots" / args.snapshot
        if not (snap / "manifest.json").exists():
            print(f"FAIL - no snapshot with a manifest at {args.snapshot}")
            return 1
        sid = json.loads((snap / "manifest.json").read_text(encoding="utf-8"))["snapshot_id"]
        full_sid = json.loads((full / "meta.json").read_text(encoding="utf-8")).get("snapshot_id")
        if sid != full_sid:
            print(f"FAIL - {full} was built from {full_sid}, not {sid}. Parity is judged on one "
                  "snapshot; run this straight after the full rebuild of that snapshot.")
            return 1
        work = pathlib.Path(args.workdir) if args.workdir else pathlib.Path(
            tempfile.mkdtemp(prefix="parity_"))
        print(f"building the light extract for {sid} under {work} ...", flush=True)
        p = subprocess.run([PY, "scripts/refresh_light.py", "--snapshot", str(snap),
                            "--out", str(work / "out"), "--workdir", str(work / "work"),
                            "--vintage", "warn"], cwd=ROOT)
        if p.returncode != 0:
            print("FAIL - the light build itself refused, so parity could not be established.")
            return 1
        light = work / "out" / "tool" / "data"

    problems = compare_extracts(full, light)
    print(f"\nfull extract  : {full}")
    print(f"light extract : {light}")
    if problems:
        for pr in problems:
            print(f"FAIL  {pr}")
        print("\nPARITY FAILED - the light refresh does not reproduce the full extract. Its filter "
              "is dropping or changing rows the extract needs, so every automated refresh since "
              "the last passing parity check is suspect. Stop the automated refresh and find the "
              "cause before it ships again.")
        return 1
    print("\nOK - the light extract is byte-identical to the full extract for the same snapshot "
          "(meta.json differs only in built_utc).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
