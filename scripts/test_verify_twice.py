#!/usr/bin/env python3
"""Prove `verify_twice.py` fails when it should.

The case that matters is the third one: TWO RUNS THAT BOTH FAIL THE SAME WAY. A plain
`diff` reports those as agreement, which is the hole this script exists to close. The
probe forces a deterministic failure (a memory limit far too small for the query) so both
runs truncate identically, and asserts the checker still refuses.

Probes are written into the scratch directory, not into `analysis/`, so a leftover file
cannot be mistaken for a committed query. A control case asserts a healthy query passes.

Exit codes: 0 all cases behaved as expected, 1 a case did not, 2 usage/environment error.
"""
import pathlib
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
CHECK = REPO / "scripts" / "verify_twice.py"

HEALTHY = """
SELECT 1 AS a, 'x' AS b;
SELECT 2 AS a UNION ALL SELECT 3 ORDER BY a;
"""

# Deterministic: `range` is unbounded enough that a tiny memory limit reliably fails.
BOTH_FAIL = """
SELECT count(*) AS n FROM (SELECT * FROM range(200000000)) t
  JOIN (SELECT * FROM range(200000000)) u ON t.range = u.range;
"""

# 200 rows, not 3: with three values a random order repeats often enough to make the
# probe itself flaky, which would be an embarrassing bug in a test for flakiness.
NONDETERMINISTIC = """
SELECT 1 AS a;
SELECT i AS v FROM range(200) t(i) ORDER BY random();
"""


def run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(CHECK), *args],
                          capture_output=True, text=True, cwd=str(REPO))


def main() -> int:
    workdir = pathlib.Path(tempfile.mkdtemp(prefix="verify_twice_probe_"))
    results = []
    try:
        cases = [
            ("control_healthy_query_passes", HEALTHY,
             ["--memory-limit", "1GB"], 0, "both runs completed successfully"),
            ("expected_statement_count_enforced", HEALTHY,
             ["--memory-limit", "1GB", "--expect-statements", "5"], 1,
             "expected 5 result sets"),
            ("min_rows_catches_empty_result", "SELECT 1 AS a WHERE false;",
             ["--memory-limit", "1GB", "--min-rows", "1"], 1, "below --min-rows"),
            # THE ONE THAT MATTERS: both runs fail identically, so diff would pass.
            ("both_runs_failing_identically_is_NOT_agreement", BOTH_FAIL,
             ["--memory-limit", "20MB"], 1, "failure marker"),
            ("nondeterministic_order_is_caught", NONDETERMINISTIC,
             ["--memory-limit", "1GB"], 1, "not byte-identical"),
        ]
        for name, sql, extra, want_exit, want_text in cases:
            probe = workdir / f"{name}.sql"
            probe.write_text(sql, encoding="utf-8")
            proc = run([str(probe), *extra])
            blob = proc.stdout + proc.stderr
            ok = proc.returncode == want_exit and want_text in blob
            results.append((name, ok, f"exit {proc.returncode}, expected {want_exit}"))
            if not ok:
                print(f"\n--- {name} ---\n{blob[-2500:]}", file=sys.stderr)
    finally:
        import shutil
        shutil.rmtree(workdir, ignore_errors=True)

    width = max(len(r[0]) for r in results)
    print()
    for name, ok, note in results:
        print(f"{'PASS' if ok else 'FAIL'}  {name:<{width}}  ({note})")
    bad = sum(1 for _, ok, _ in results if not ok)
    print(f"\n{len(results) - bad} of {len(results)} cases behaved as expected.")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
