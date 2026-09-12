#!/usr/bin/env python3
"""Proves check_claims.py fails when it should.

A check that has never failed has not been tested. Each case copies the published documents,
the claims manifest and the committed sources into a scratch directory, breaks one thing, and
asserts the check refuses and names what broke.

Run: python scripts/test_check_claims.py
"""
from __future__ import annotations
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHECK = ROOT / "scripts" / "check_claims.py"
DOCS = ["docs/writeup.md", "README.md", "docs/method-note.md", "docs/CLAIMS.md"]


def run(root: pathlib.Path | None = None):
    cmd = [sys.executable, str(CHECK)] + (["--root", str(root)] if root else [])
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return p.returncode, p.stdout + p.stderr


def scratch(td: str) -> pathlib.Path:
    r = pathlib.Path(td) / "repo"
    for d in DOCS:
        (r / d).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / d, r / d)
    shutil.copytree(ROOT / "analysis", r / "analysis")
    shutil.copytree(ROOT / "scripts", r / "scripts",
                    ignore=shutil.ignore_patterns("__pycache__"))
    return r


def edit(path: pathlib.Path, old: str, new: str) -> None:
    s = path.read_text(encoding="utf-8")
    assert old in s, f"test fixture drifted: {old[:60]!r} not found in {path.name}"
    path.write_text(s.replace(old, new, 1), encoding="utf-8")


def case(name: str, mutate, expect: str) -> bool:
    with tempfile.TemporaryDirectory() as td:
        r = scratch(td)
        mutate(r)
        rc, out = run(r)
        ok = rc != 0 and expect.lower() in out.lower()
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
        if not ok:
            print(f"        expected a refusal naming {expect!r}; got rc={rc}")
            print("\n".join("        " + l for l in out.splitlines()[-6:]))
        return ok


def unsourced_figure(r):
    # A new claim appears in the writeup and nobody records where it came from.
    edit(r / "docs/writeup.md", "## Almost every price change happens on a Thursday",
         "Walmart was 41.3% cheaper on 1,234 dates.\n\n## Almost every price change happens on a Thursday")


def changed_figure(r):
    # A number is edited in the document but not in the manifest.
    edit(r / "docs/writeup.md", "56,176,157", "56,176,158")


def missing_source(r):
    edit(r / "docs/CLAIMS.md", "analysis/phase4/R6_save_on_foods_store_ids.sql",
         "analysis/phase4/R99_does_not_exist.sql")


def lost_without_note(r):
    p = r / "docs/CLAIMS.md"
    p.write_text(p.read_text(encoding="utf-8")
                 + "| 105,540 | 105,540 | provenance-lost |  |\n", encoding="utf-8")


def anchor_without_figure(r):
    edit(r / "docs/CLAIMS.md", "| 97% | 97% |", "| 97% | In this dataset |")


def source_deleted(r):
    # The source file named by an entry is removed from the repository.
    (r / "analysis/phase2/Q2e_flag_rank_correlation.sql").unlink()


CASES = [
    ("a figure with no manifest entry is refused",          unsourced_figure,      "no traceable source"),
    ("a figure edited without updating the manifest",       changed_figure,        "stale entry"),
    ("an entry naming a file that is not committed",        missing_source,        "not a committed file"),
    ("a deleted source is refused",                         source_deleted,        "not a committed file"),
    ("provenance-lost with no note is refused",             lost_without_note,     "no note"),
    ("an anchor that does not contain its figure",          anchor_without_figure, "anchor does not contain"),
]


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:                                      # noqa: BLE001
            pass
    print("check_claims.py -- failure cases\n")
    ok = [case(n, m, e) for n, m, e in CASES]

    rc, out = run()
    real = rc == 0
    print(f"  {'PASS' if real else 'FAIL'}  the real repository is accepted")
    if not real:
        print("\n".join("        " + l for l in out.splitlines()[-12:]))
    ok.append(real)

    print(f"\n{sum(ok)} of {len(ok)} cases behaved correctly.")
    if not all(ok):
        print("FAIL - the claims check does not refuse something it must refuse.")
        return 1
    print("OK - the check refuses every unsourced figure and accepts the real documents.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
