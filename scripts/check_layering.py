#!/usr/bin/env python3
"""Enforce that `product_id` appears nowhere below the staging layer.

CLAUDE.md ("Upstream volatility"): `raw.product_id` will change from a string to a number.
Our product identity is derived and owned, so that change must be an ingest-layer event
and nothing more. The brief states it as a hard rule: `raw.product_id` must not appear
below staging. If a `product_id` type change would break anything downstream, that is a
design bug on our side.

A rule nobody checks is a wish. This checks it:

  * models/stg_*.sql   MAY reference product_id -- they are the staging layer
  * models/int_*.sql   MUST NOT
  * models/mart_*.sql  MUST NOT

Exits 0 when clean, 1 on a violation, 2 on a usage error.
No third-party dependencies.
"""
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
MODELS = REPO / "models"

# `product_key` legitimately contains the substring "product_", so match the bare column
# name only -- not as part of a longer identifier.
PRODUCT_ID = re.compile(r"\bproduct_id\b")
COMMENT = re.compile(r"--.*?$", re.M)


def strip_comments(sql: str) -> str:
    """A rule stated in a comment is documentation, not a reference."""
    return COMMENT.sub("", sql)


def main() -> int:
    if not MODELS.is_dir():
        print(f"error: {MODELS} not found", file=sys.stderr)
        return 2

    staging, below = [], []
    for f in sorted(MODELS.glob("*.sql")):
        name = f.name
        if name.startswith("stg_"):
            staging.append(f)
        elif name.startswith(("int_", "mart_")):
            below.append(f)
        # macro files are neither; they define functions, not layers

    if not below:
        print("no models below the staging layer yet -- nothing to enforce")
        return 0

    violations = []
    for f in below:
        body = strip_comments(f.read_text(encoding="utf-8"))
        hits = [
            (i, line.strip())
            for i, line in enumerate(body.splitlines(), 1)
            if PRODUCT_ID.search(line)
        ]
        if hits:
            violations.append((f, hits))

    print(f"staging models    : {len(staging)} ({', '.join(f.name for f in staging)})")
    print(f"below-staging     : {len(below)} ({', '.join(f.name for f in below)})")

    if not violations:
        print("\nOK - product_id appears nowhere below the staging layer.")
        return 0

    print(f"\nFAIL - product_id referenced below staging in {len(violations)} model(s):",
          file=sys.stderr)
    for f, hits in violations:
        for lineno, line in hits:
            print(f"  {f.relative_to(REPO).as_posix()}:{lineno}: {line}", file=sys.stderr)
    print("\nDownstream models must key on product_key. The upstream product_id type\n"
          "change has to stay an ingest-layer event.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
