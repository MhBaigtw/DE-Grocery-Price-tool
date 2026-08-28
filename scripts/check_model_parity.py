#!/usr/bin/env python3
"""Assert that the dbt model bodies and the plain-SQL model bodies have not drifted.

WHY THIS EXISTS.

There are two build paths for the same models:

  * `scripts/build_models.py` runs `models/*.sql` directly against a snapshot DuckDB.
    Every Phase 0/1 query, `run_query.py` and `verify_reproducible.py` use this path,
    and none of them has dbt in it.
  * `dbt/models/**/*.sql` wraps the same SELECTs so dbt's ref/source graph can attach
    lineage and tests, which is what CLAUDE.md commits to for the modelling layer.

`dbt/dbt_project.yml` originally claimed "dbt does not own a second copy". It does. The
bodies are duplicated, and a duplicated definition drifts -- somebody fixes a parse rule
in one file, the other keeps the old one, and the two build paths silently disagree about
what `stg_price` means. That is the same class of failure as the stale-table incident in
findings 3.8: a build that reports success while the data underneath means something else.

Rather than pretend the duplication away, this makes it mechanical. The comparison strips
what is *supposed* to differ (comments, dbt config blocks, and the source references dbt
resolves through its graph) and requires everything else to match exactly.

Exit codes: 0 in parity, 1 drift, 2 usage/environment error.
"""
import difflib
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

# plain model  ->  dbt wrapper
PAIRS = [
    ("models/stg_price.sql",     "dbt/models/staging/stg_price.sql"),
    ("models/stg_product.sql",   "dbt/models/staging/stg_product.sql"),
    ("models/int_upc_match.sql", "dbt/models/intermediate/int_upc_match.sql"),
]


def normalise(sql: str) -> str:
    """Reduce a model body to the part that must be identical across both paths.

    Removed deliberately:
      * `-- ...` comments and `/* ... */` blocks -- the two files document different
        concerns (the plain one explains the contract, the dbt one points at it).
      * `{{ config(...) }}` and `{# ... #}` -- dbt plumbing with no plain-SQL equivalent.

    Rewritten so the two become comparable:
      * `{{ source('hammer', 'raw') }}` and `{{ ref('stg_product') }}` collapse to the
        bare relation name, which is exactly what the plain path writes. This is the ONLY
        difference the two files are allowed to have.
    """
    sql = re.sub(r"\{#.*?#\}", " ", sql, flags=re.S)
    sql = re.sub(r"\{\{\s*config\([^}]*\)\s*\}\}", " ", sql, flags=re.S)
    sql = re.sub(r"\{\{\s*source\(\s*['\"][^'\"]+['\"]\s*,\s*['\"]([^'\"]+)['\"]\s*\)\s*\}\}",
                 r"\1", sql)
    sql = re.sub(r"\{\{\s*ref\(\s*['\"]([^'\"]+)['\"]\s*\)\s*\}\}", r"\1", sql)
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", " ", sql)
    sql = re.sub(r"\s+", " ", sql)
    return sql.strip().lower()


def main() -> int:
    drift = []
    for plain_rel, dbt_rel in PAIRS:
        plain, dbtf = REPO / plain_rel, REPO / dbt_rel
        for f in (plain, dbtf):
            if not f.exists():
                print(f"FAIL - missing model file: {f.relative_to(REPO)}", file=sys.stderr)
                return 2
        a, b = normalise(plain.read_text(encoding="utf-8")), normalise(dbtf.read_text(encoding="utf-8"))
        status = "ok  " if a == b else "DRIFT"
        print(f"  {status} {plain_rel:26s} <-> {dbt_rel}")
        if a != b:
            drift.append((plain_rel, dbt_rel, a, b))

    if not drift:
        print(f"\nOK - {len(PAIRS)} model bodies are identical across both build paths.")
        return 0

    print(f"\nFAIL - {len(drift)} model body/bodies differ between the plain and dbt "
          "build paths:", file=sys.stderr)
    for plain_rel, dbt_rel, a, b in drift:
        print(f"\n  {plain_rel}  vs  {dbt_rel}", file=sys.stderr)
        for line in list(difflib.unified_diff(a.split(" "), b.split(" "),
                                              fromfile=plain_rel, tofile=dbt_rel,
                                              lineterm="", n=3))[:60]:
            print(f"    {line}", file=sys.stderr)
    print("\n  Fix the divergence; do not silence this check. Two build paths that "
          "disagree about\n  a model definition make every number ambiguous about which "
          "one produced it.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
