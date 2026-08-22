#!/usr/bin/env python3
"""Run a saved Phase 0 query against the analysis DuckDB and print the result.

Honesty rule #3 (CLAUDE.md): every published number has a committed SQL file that
regenerates it. This is the runner that makes that cheap to do -- and to redo.

Opens the database READ ONLY, so a query can never mutate the analysis DB.
A file may contain several statements; only the last SELECT's result is printed by
default (--all prints every statement that returns rows).

Usage:  python scripts/run_query.py analysis/phase0/A1_shape.sql [--db hammer.duckdb]
                                    [--all] [--max-rows N] [--csv out.csv]
"""
import argparse
import pathlib
import sys

import duckdb

REPO = pathlib.Path(__file__).resolve().parent.parent


def split_statements(sql: str) -> list[str]:
    """Split on semicolons outside string literals and comments."""
    out, buf = [], []
    i, n = 0, len(sql)
    while i < n:
        ch = sql[i]
        if ch == "-" and sql[i:i + 2] == "--":
            j = sql.find("\n", i)
            j = n if j == -1 else j
            buf.append(sql[i:j]); i = j; continue
        if ch == "/" and sql[i:i + 2] == "/*":
            j = sql.find("*/", i + 2)
            j = n if j == -1 else j + 2
            buf.append(sql[i:j]); i = j; continue
        if ch in "'\"":
            j = i + 1
            while j < n:
                if sql[j] == ch:
                    if j + 1 < n and sql[j + 1] == ch:
                        j += 2; continue
                    j += 1; break
                j += 1
            buf.append(sql[i:j]); i = j; continue
        if ch == ";":
            out.append("".join(buf)); buf = []; i += 1; continue
        buf.append(ch); i += 1
    if "".join(buf).strip():
        out.append("".join(buf))
    return [s for s in (x.strip() for x in out) if s and not is_comment_only(s)]


def is_comment_only(stmt: str) -> bool:
    """True if the chunk is only comments/whitespace.

    The splitter treats a trailing comment block as a statement, but DuckDB's
    execute() returns None for it rather than a result object -- which then fails
    on .description. Filtering here keeps the runner honest about what it ran.
    """
    out, i, n = [], 0, len(stmt)
    while i < n:
        if stmt[i:i + 2] == "--":
            j = stmt.find("\n", i)
            i = n if j == -1 else j
            continue
        if stmt[i:i + 2] == "/*":
            j = stmt.find("*/", i + 2)
            i = n if j == -1 else j + 2
            continue
        out.append(stmt[i])
        i += 1
    return not "".join(out).strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("sql_file")
    ap.add_argument("--db", default=str(REPO / "hammer.duckdb"))
    ap.add_argument("--all", action="store_true", help="print every result set, not just the last")
    ap.add_argument("--max-rows", type=int, default=200)
    ap.add_argument("--csv", default=None, help="also write the final result set to this CSV")
    ap.add_argument("--memory-limit", default="6GB",
                    help="DuckDB memory budget before it spills to disk")
    ap.add_argument("--temp-dir", default=None,
                    help="spill directory for out-of-core queries (default: alongside the db)")
    args = ap.parse_args()

    path = pathlib.Path(args.sql_file)
    if not path.exists():
        sys.exit(f"no such query file: {path}")
    stmts = split_statements(path.read_text(encoding="utf-8"))
    if not stmts:
        sys.exit(f"{path} contains no statements")

    con = duckdb.connect(args.db, read_only=True)
    con.execute("PRAGMA disable_progress_bar;")
    # 71M-row aggregations exceed RAM; let DuckDB spill instead of dying.
    tmp = args.temp_dir or str(pathlib.Path(args.db).resolve().parent / ".duckdb_spill")
    pathlib.Path(tmp).mkdir(parents=True, exist_ok=True)
    con.execute(f"SET temp_directory='{pathlib.Path(tmp).as_posix()}';")
    con.execute(f"SET memory_limit='{args.memory_limit}';")
    con.execute("SET preserve_insertion_order=false;")

    print(f"-- {path}")
    last_df = None
    for k, stmt in enumerate(stmts, 1):
        try:
            rel = con.execute(stmt)
        except Exception as exc:
            print(f"\n!! statement {k} failed:\n{stmt}\n{exc}", file=sys.stderr)
            return 1
        if rel is None or rel.description is None:
            continue
        df = rel.fetchdf()
        last_df = df
        if args.all or k == len(stmts):
            print(f"\n-- statement {k}  ({len(df):,} rows)")
            with_pd_opts(df, args.max_rows)

    if args.csv and last_df is not None:
        last_df.to_csv(args.csv, index=False)
        print(f"\n-- wrote {args.csv}")
    con.close()
    return 0


def with_pd_opts(df, max_rows: int) -> None:
    import pandas as pd
    with pd.option_context("display.max_rows", max_rows,
                           "display.max_columns", None,
                           "display.width", 200,
                           "display.max_colwidth", 60):
        print(df.to_string() if len(df) else "(no rows)")
        if len(df) > max_rows:
            print(f"... {len(df) - max_rows:,} more rows not shown (--max-rows to raise)")


if __name__ == "__main__":
    raise SystemExit(main())
