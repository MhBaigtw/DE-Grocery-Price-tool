#!/usr/bin/env python3
"""Prove `check_determinism.py` fails when it should.

Same standard as `test_check_schema.py` and `test_dbt_contracts.py`: a check that has
never failed has not been tested. The cases below are the ones that matter, and the
third is the one worth reading twice -- an annotation must NOT be able to silence a
ranking function with no ORDER BY, because there is no fact about the data that could
make that construct deterministic.

The probe file is written into `analysis/phase1/` because that is a directory the linter
scans, and is removed afterwards whether or not the run succeeds. A control case asserts
the repo is clean both before and after, so a probe left behind cannot pass unnoticed.

Exit codes: 0 all cases behaved as expected, 1 a case did not, 2 usage/environment error.
"""
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
PROBE = REPO / "analysis" / "phase1" / "ZZ_determinism_probe.sql"
CHECK = REPO / "scripts" / "check_determinism.py"

CASES = [
    ("control_repo_is_clean", None, 0, "OK - every non-deterministic construct is justified"),
    ("unannotated_any_value",
     "SELECT k, any_value(v) AS v FROM t GROUP BY 1;\n",
     1, "picks an arbitrary row"),
    ("row_number_without_order_by_cannot_be_annotated_away",
     "-- determinism-ok: I promise this is fine, honestly, it is definitely fine\n"
     "SELECT row_number() OVER (PARTITION BY k) AS rn FROM t;\n",
     1, "never correct"),
    ("thin_justification_rejected",
     "-- determinism-ok: fine\n"
     "SELECT k, any_value(v) AS v FROM t GROUP BY 1;\n",
     1, "justification too thin"),
    ("limit_without_order_by",
     "SELECT * FROM t LIMIT 10;\n",
     1, "arbitrary sample"),
    ("string_agg_without_order_by",
     "SELECT k, string_agg(v, ',') AS vs FROM t GROUP BY 1;\n",
     1, "concatenation order varies"),
    ("good_annotation_accepted",
     "-- determinism-ok: k is the primary key of t, so v is constant within every group\n"
     "SELECT k, any_value(v) AS v FROM t GROUP BY 1;\n",
     0, "OK - every non-deterministic construct is justified"),
    ("control_repo_is_clean_again", None, 0, "OK - every non-deterministic construct is justified"),
]


def run() -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(CHECK)], capture_output=True, text=True,
                          cwd=str(REPO))


def main() -> int:
    if PROBE.exists():
        print(f"refusing to run: {PROBE} already exists", file=sys.stderr)
        return 2
    results = []
    try:
        for name, body, want_exit, want_text in CASES:
            if body is None:
                PROBE.unlink(missing_ok=True)
            else:
                PROBE.write_text(body, encoding="utf-8")
            proc = run()
            blob = proc.stdout + proc.stderr
            ok = proc.returncode == want_exit and want_text in blob
            results.append((name, ok, f"exit {proc.returncode}, expected {want_exit}"))
            if not ok:
                print(f"\n--- {name} ---\n{blob[-2000:]}", file=sys.stderr)
    finally:
        PROBE.unlink(missing_ok=True)

    width = max(len(r[0]) for r in results)
    print()
    for name, ok, note in results:
        print(f"{'PASS' if ok else 'FAIL'}  {name:<{width}}  ({note})")
    bad = sum(1 for _, ok, _ in results if not ok)
    print(f"\n{len(results) - bad} of {len(results)} cases behaved as expected.")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
