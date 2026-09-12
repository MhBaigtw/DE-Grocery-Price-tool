#!/usr/bin/env python3
"""Proves netlify_changes.sh skips only what it should and relaxes the age limit only when it
should.

Two ways it can be wrong, and both are tested against real commits in this repository:
  - too eager: skipping a build that changes the site, or relaxing the age limit on a deploy
    that changes the data. That ships a stale extract, which is the thing the limit exists for.
  - too strict: building on a documentation-only commit and enforcing the limit on it. That
    is the defect this script was written to fix.
And every "cannot tell" case must fail safe: build, and treat the data as changed.

Run: python scripts/test_netlify_changes.py
"""
from __future__ import annotations
import os, pathlib, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = "scripts/netlify_changes.sh"
SHIPS = ("tool/", "netlify.toml", "scripts/netlify_build.sh", "scripts/netlify_changes.sh",
         "scripts/check_extract.py", "scripts/test_tool_render.js")


def bash() -> str:
    # On Windows, a bare `bash` can resolve to WSL rather than Git's bash; prefer Git's.
    for p in (r"C:\Program Files\Git\bin\bash.exe", r"C:\Program Files\Git\usr\bin\bash.exe"):
        if os.path.exists(p):
            return p
    return shutil.which("bash") or "bash"


def git(*a: str) -> str:
    return subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True, check=True).stdout


def answer(mode: str, cached: str | None, commit: str | None) -> int:
    env = {k: v for k, v in os.environ.items() if k not in ("CACHED_COMMIT_REF", "COMMIT_REF")}
    if cached is not None:
        env["CACHED_COMMIT_REF"] = cached
    if commit is not None:
        env["COMMIT_REF"] = commit
    return subprocess.run([bash(), SCRIPT, mode], cwd=ROOT, env=env,
                          capture_output=True, text=True).returncode


def changed(c: str) -> list[str]:
    return [l for l in git("diff", "--name-only", f"{c}^", c).splitlines() if l]


def find(pred) -> str:
    for c in git("rev-list", "--no-merges", "HEAD").split():
        try:
            files = changed(c)
        except subprocess.CalledProcessError:
            continue                                         # the root commit has no parent
        if files and pred(files):
            return c
    raise AssertionError("no commit in history matches this fixture")


def main() -> int:
    ships = lambda f: any(x == s or x.startswith(s) for x in f for s in SHIPS)
    docs_only = find(lambda f: not ships(f))
    data = find(lambda f: any(x.startswith("tool/data/") for x in f))
    ui_only = find(lambda f: ships(f) and not any(x.startswith("tool/data/") for x in f))

    head = git("rev-parse", "HEAD").strip()
    cases = [
        # name, mode, cached, commit, expected exit
        ("documentation-only commit: build skipped", "ignore", f"{docs_only}^", docs_only, 0),
        ("documentation-only commit: data unchanged", "data-changed", f"{docs_only}^", docs_only, 1),
        ("data commit: builds", "ignore", f"{data}^", data, 1),
        ("data commit: age limit enforced", "data-changed", f"{data}^", data, 0),
        ("interface-only commit: builds", "ignore", f"{ui_only}^", ui_only, 1),
        ("interface-only commit: age limit reported, not enforced", "data-changed", f"{ui_only}^", ui_only, 1),
        ("no CACHED_COMMIT_REF: builds", "ignore", None, head, 1),
        ("no CACHED_COMMIT_REF: data treated as changed", "data-changed", None, head, 0),
        ("same commit rebuilt: builds", "ignore", head, head, 1),
        ("same commit rebuilt: data treated as changed", "data-changed", head, head, 0),
        ("cached commit not in the clone: builds", "ignore", "0" * 40, head, 1),
        ("cached commit not in the clone: data treated as changed", "data-changed", "0" * 40, head, 0),
    ]
    print("netlify_changes.sh -- cases (fixtures from this repository's history)")
    print(f"  docs-only {docs_only[:7]}, data {data[:7]}, interface-only {ui_only[:7]}\n")
    ok = []
    for name, mode, cached, commit, want in cases:
        cached = git("rev-parse", cached).strip() if cached and cached.endswith("^") else cached
        got = answer(mode, cached, commit)
        ok.append(got == want)
        print(f"  {'PASS' if got == want else 'FAIL'}  {name}" + ("" if got == want else f"  (exit {got}, wanted {want})"))
    print(f"\n{sum(ok)} of {len(ok)} cases behaved correctly.")
    if not all(ok):
        print("FAIL - the build would skip, or the age limit relax, where it must not (or the reverse).")
        return 1
    print("OK - documentation skips, data enforces, and every unknown fails safe.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
