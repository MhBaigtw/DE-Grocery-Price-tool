#!/usr/bin/env python3
"""Run the dbt test suite against both snapshots and report the results as COUNTS.

Two jobs, both of them small and both of them things that went wrong once already.

1. ABSOLUTE DATABASE PATHS. dbt resolves a `path:` in profiles.yml against the current
   working directory, not against the profile. The first version of the profile said
   `../hammer.duckdb`, and run from the repo root that points one level ABOVE the repo --
   where DuckDB cheerfully created an empty database and dbt then reported a missing-macro
   catalog error. The visible symptom was nothing like the cause, and the invisible half
   was worse: a green suite would have meant nothing. This sets the paths explicitly.

2. COUNTS, NEVER A PHASE PASS RATE. Brief 5.4 and CLAUDE.md honesty rule 8 ("report a pass rate only for tests that exist"): the output is
   "N of M tests passed", scoped to the tests that exist. It is not a percentage, and it
   is not a statement about Phase 1 as a whole.

`scripts/build_models.py` must have run against a database before it can be tested; dbt's
on-run-start hook says so if the parsing macros are absent. Note that `dbt run` is NOT the
build path -- see docs/FILES.md on dbt/.

Usage:  python scripts/run_dbt_tests.py [--target dev|snapshot2|all]
Exit codes: 0 every test passed on every target, 1 a test failed, 2 environment error.
"""
import argparse
import os
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
DBT = REPO / "dbt"

TARGETS = {
    "dev":       ("HAMMER_DB",  REPO / "hammer.duckdb",  "snapshot 1"),
    "snapshot2": ("HAMMER2_DB", REPO / "hammer2.duckdb", "snapshot 2"),
}

DONE = re.compile(r"PASS=(\d+)\s+WARN=(\d+)\s+ERROR=(\d+)\s+SKIP=(\d+)")

# dbt's `Done. PASS=N` counts NODES, and the on-run-start hook is a node. Reporting that
# number as a test count inflates it by one: this project has 40 data tests and 1 hook, so
# PASS=41 would be published as "41 tests". The hook is a real assertion -- it fails the
# run if the DuckDB parsing macros are missing -- but it is not a test, and honesty rule 8
# is specifically about not reporting a test count that is larger than the tests that
# exist. So the data-test count is taken from the line that states it.
FINISHED = re.compile(r"Finished running(?:\s+\d+\s+project hooks?,)?\s+(\d+)\s+data tests?")

# dbt colourises its output; the counts have to be read out of the plain text.
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def run(target: str) -> tuple[int, int, int, str]:
    env_var, db, label = TARGETS[target]
    if not db.exists():
        print(f"SKIP  {target} ({label}): {db.name} does not exist. Build it with:\n"
              f"      python scripts/load_snapshot.py <id> --db {db.name}\n"
              f"      python scripts/build_models.py --db {db.name} --materialize table",
              file=sys.stderr)
        return (0, 0, 1, label)

    env = dict(os.environ)
    # Both are set every run: dbt renders the whole profile, so an unset variable for a
    # target we are NOT using still has to resolve.
    for var, path, _ in TARGETS.values():
        env[var] = str(path)
    env["DBT_PROFILES_DIR"] = str(DBT)

    proc = subprocess.run(
        [sys.executable, "-m", "dbt.cli.main", "test",
         "--target", target, "--project-dir", str(DBT)],
        capture_output=True, text=True, env=env, cwd=str(REPO))

    clean = ANSI.sub("", proc.stdout)
    m, f = DONE.search(clean), FINISHED.search(clean)
    if not m or not f:
        print(clean[-4000:], file=sys.stderr)
        return (0, 0, 1, label)
    npass, _warn, nerror, _skip = (int(x) for x in m.groups())
    n_data_tests = int(f.group(1))
    # PASS counts nodes (data tests + the on-run-start hook); subtract the hook so the
    # reported figure is a count of tests and nothing else.
    npass -= (npass + nerror) - n_data_tests

    if nerror:
        print(f"\n--- failing tests on {target} ({label}) ---", file=sys.stderr)
        for line in clean.splitlines():
            if "[ERROR" in line or "Failure in test" in line or "Got " in line:
                print("  " + line.strip(), file=sys.stderr)
    return (npass, n_data_tests, nerror, label)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", default="all", choices=["dev", "snapshot2", "all"])
    args = ap.parse_args()

    targets = list(TARGETS) if args.target == "all" else [args.target]
    rows, bad = [], 0
    for t in targets:
        npass, total, nerror, label = run(t)
        rows.append((t, label, npass, total, nerror))
        bad += nerror

    print()
    for t, label, npass, total, nerror in rows:
        verdict = "all passed" if total and not nerror else f"{nerror} failed"
        print(f"{t:10s} ({label}):  {npass} of {total} tests passed   [{verdict}]")
    print("\nCounts only. This is not a pass rate for Phase 1 -- it is the number of "
          "tests that\nexist and the number that passed (CLAUDE.md honesty rule 8).")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
