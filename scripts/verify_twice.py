#!/usr/bin/env python3
"""Run a query file twice and verify the two runs AGREE AND SUCCEEDED.

WHY BYTE-IDENTITY IS NOT ENOUGH. Honesty rule 4 says a published number must be
reproducible twice, and the check for that has been `diff run1 run2`. That check has a
hole big enough to have already bitten:

    Two runs that both fail the same way compare as agreement.

During Phase 2 §1 several paired runs came back different purely because one had hit an
out-of-memory error under contention. That was caught because the two runs differed. The
dangerous case is the other one -- both runs OOM at the same statement, both produce the
same truncated output, and `diff` reports success. A crashed run and a clean run are
indistinguishable to a byte-comparison, and so are two crashed runs.

So this asserts, in order:

  1. Both runs exited 0.
  2. Neither run's output contains a failure marker (`!! statement N failed`,
     `Out of Memory`, `Error:`).
  3. Both runs produced the SAME NUMBER of result sets. A run that dies halfway emits
     fewer, which is the truncation signature.
  4. Every result set has the same row count in both runs.
  5. No result set is unexpectedly empty -- `--min-rows` guards the case where a query
     "succeeds" but returns nothing because an upstream temp table was silently empty.
  6. Only then, byte-identity.

`--expect-statements N` pins the number of result sets, so a query that quietly loses a
statement (an edit that comments one out, a parse error swallowed upstream) fails here
rather than being reported as reproducible.

Usage:
  python scripts/verify_twice.py analysis/phase2/Q2a_presale_inflation.sql \\
      --memory-limit 5GB --expect-statements 21 --min-rows 1

Exit codes: 0 verified, 1 verification failed, 2 usage/environment error.
"""
import argparse
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
RUNNER = REPO / "scripts" / "run_query.py"

STATEMENT = re.compile(r"^-- statement (\d+)\s+\(([\d,]+) rows\)\s*$", re.M)
FAILURE_MARKERS = (
    "!! statement",
    "Out of Memory",
    "Binder Error",
    "Parser Error",
    "Catalog Error",
    "Conversion Error",
    "Segmentation fault",
    "Traceback (most recent call last)",
)


def run_once(sql: str, db: str, memory_limit: str, temp_dir: str,
             max_rows: int) -> tuple[int, str]:
    cmd = [sys.executable, str(RUNNER), sql, "--all",
           "--memory-limit", memory_limit, "--max-rows", str(max_rows)]
    if db:
        cmd += ["--db", db]
    if temp_dir:
        cmd += ["--temp-dir", temp_dir]
    proc = subprocess.run(cmd, capture_output=True, text=True, cwd=str(REPO))
    # The progress bar writes carriage-return spam; strip it so the comparison is on
    # content rather than on terminal animation.
    out = "\n".join(l for l in (proc.stdout + proc.stderr).splitlines()
                    if "▕" not in l and "elapsed)" not in l)
    return proc.returncode, out


def statements(out: str) -> list[tuple[int, int]]:
    return [(int(n), int(r.replace(",", ""))) for n, r in STATEMENT.findall(out)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("sql_file")
    ap.add_argument("--db", default=None)
    ap.add_argument("--memory-limit", default="4GB")
    ap.add_argument("--temp-dir", default=".duckdb_spill")
    ap.add_argument("--max-rows", type=int, default=60)
    ap.add_argument("--expect-statements", type=int, default=None,
                    help="pin the number of result sets; a lost statement then fails here")
    ap.add_argument("--min-rows", type=int, default=0,
                    help="every result set must have at least this many rows")
    ap.add_argument("--save", default=None, help="write run 1's output to this path")
    args = ap.parse_args()

    if not (REPO / args.sql_file).exists() and not pathlib.Path(args.sql_file).exists():
        print(f"no such query file: {args.sql_file}", file=sys.stderr)
        return 2

    print(f"query        : {args.sql_file}")
    outs, codes = [], []
    for i in (1, 2):
        code, out = run_once(args.sql_file, args.db, args.memory_limit,
                             args.temp_dir, args.max_rows)
        codes.append(code); outs.append(out)
        print(f"run {i}        : exit {code}, {len(statements(out))} result sets")

    problems = []

    # 1. exit codes
    for i, c in enumerate(codes, 1):
        if c != 0:
            problems.append(f"run {i} exited {c}, not 0")

    # 2. failure markers -- the check byte-identity cannot make
    for i, out in enumerate(outs, 1):
        for marker in FAILURE_MARKERS:
            if marker in out:
                line = next((l.strip() for l in out.splitlines() if marker in l), marker)
                problems.append(f"run {i} contains a failure marker: {line[:160]}")
                break

    st = [statements(o) for o in outs]

    # 3. same number of result sets -- the truncation signature
    if len(st[0]) != len(st[1]):
        problems.append(f"result-set count differs: {len(st[0])} vs {len(st[1])} "
                        "-- one run stopped early")

    # 3b. pinned count
    if args.expect_statements is not None and len(st[0]) != args.expect_statements:
        problems.append(f"expected {args.expect_statements} result sets, got {len(st[0])}")

    # 4. per-statement row counts
    for (n1, r1), (n2, r2) in zip(st[0], st[1]):
        if n1 != n2 or r1 != r2:
            problems.append(f"statement {n1}: {r1} rows vs statement {n2}: {r2} rows")

    # 5. unexpectedly empty result sets
    if args.min_rows:
        for n, r in st[0]:
            if r < args.min_rows:
                problems.append(f"statement {n} returned {r} rows, below --min-rows "
                                f"{args.min_rows} -- an upstream table may be empty")

    # 6. byte-identity, last
    identical = outs[0] == outs[1]
    if not identical:
        problems.append("outputs are not byte-identical")

    total_rows = sum(r for _, r in st[0]) if st[0] else 0
    print(f"result sets  : {len(st[0])}")
    print(f"total rows   : {total_rows:,}")
    print(f"byte-identical: {identical}")

    if args.save:
        pathlib.Path(args.save).write_text(outs[0], encoding="utf-8")
        print(f"saved run 1  : {args.save}")

    if problems:
        print("\nFAIL - verification failed:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        if not identical:
            import difflib
            d = list(difflib.unified_diff(outs[0].splitlines(), outs[1].splitlines(),
                                          "run1", "run2", lineterm="", n=1))
            for line in d[:30]:
                print(f"    {line}", file=sys.stderr)
        return 1

    print("\nOK - both runs completed successfully and agree "
          f"({len(st[0])} result sets, {total_rows:,} rows).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
