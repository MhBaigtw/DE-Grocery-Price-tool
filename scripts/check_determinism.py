#!/usr/bin/env python3
"""Flag SQL constructs that can return a different answer on the same data.

WHY THIS EXISTS. Three separate incidents, one class:

  * Phase 1 §2.6 / §3.5 -- `hash(vendor||'|'||sku)` collided, merging two products and
    moving the D2 event count by 6.
  * Phase 1 §5.8 -- `any_value()` over a non-unique group returned 57,008 / 57,212 /
    56,598 for the same published figure across three runs of the same query on the same
    immutable snapshot.
  * Phase 1 §5.8 again -- the fix for the above partitioned by `(key, date)`, which is
    NOT the grain (Phase 0 B6: one product appears many times a day with conflicting
    prices), so rows migrated between magnitude bands between runs.

Honesty rule 4 says "reproducible means reproducible twice", and running a query twice
DETECTS this. A lint PREVENTS it, which is cheaper and does not depend on anyone
remembering to look.

WHAT IT FLAGS, and why each one is a hazard:

  any_value / first / last / arg_min / arg_max
      Picks an arbitrary row from a group. Correct only when the group is proven unique
      on the selected column -- e.g. any_value(vendor) grouped by product_key, where the
      key determines the vendor. The linter cannot prove that; you assert it.
  row_number / rank / dense_rank with no ORDER BY
      There is no tie-break at all. This is never correct and cannot be annotated away.
  row_number / rank / dense_rank with an ORDER BY
      Deterministic only if the ORDER BY is a TOTAL order within the partition. Ties are
      broken arbitrarily and silently.
  LIMIT with no ORDER BY in the same statement
      An arbitrary sample. Fine for eyeballing, not for a published number.
  string_agg / list / array_agg with no ORDER BY
      The concatenation order varies, so the resulting string varies.
  DISTINCT ON with no ORDER BY
      Same problem as row_number with no ORDER BY.

HOW TO SILENCE ONE. Put an annotation on the construct's line or on one of the six
lines above it:

    -- determinism-ok: product_key determines vendor, 1:1 by construction (P3.5)
    SELECT product_key, any_value(vendor) AS vendor FROM stg_product GROUP BY 1;

The reason is mandatory and must be a real sentence. "determinism-ok: fine" is rejected.
The annotation is a claim you are making about the data, and it is reviewable precisely
because it is written down next to the thing it justifies.

WHAT IT DOES NOT CATCH. A final `ORDER BY` on a result set that exists but is not a
TOTAL order -- ties then come back in arbitrary order between runs. This is deliberately
out of scope: almost any `ORDER BY` could tie in principle, so flagging them all would
produce noise rather than signal. That case is caught by the other control instead --
running the query twice and comparing (honesty rule 4). Phase 2 §1.3 has a worked example
where exactly that happened, in a query written for the bias audit itself. The two checks
are complementary and neither replaces the other.

Exit codes: 0 clean, 1 unannotated hazards found, 2 usage/environment error.
"""
import argparse
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
SCAN = ["analysis", "models", "dbt"]

ANNOTATION = re.compile(r"--\s*determinism-ok\s*:\s*(?P<reason>.+?)\s*$", re.I)
MIN_REASON_WORDS = 3

# Constructs that pick arbitrarily from a group.
ARBITRARY_PICK = re.compile(r"\b(any_value|arg_min|arg_max)\s*\(", re.I)
# first()/last() are DuckDB aggregates; the word also appears in prose, so require a "(".
FIRST_LAST = re.compile(r"\b(first|last)\s*\(", re.I)
RANKING = re.compile(r"\b(row_number|rank|dense_rank)\s*\(\s*\)", re.I)
ORDERED_AGG = re.compile(r"\b(string_agg|list|array_agg)\s*\(", re.I)
DISTINCT_ON = re.compile(r"\bDISTINCT\s+ON\b", re.I)


def strip_comments(sql: str) -> str:
    """Blank out comments, preserving line structure so line numbers stay correct."""
    out, i, n = [], 0, len(sql)
    while i < n:
        if sql[i:i + 2] == "--":
            j = sql.find("\n", i)
            j = n if j == -1 else j
            out.append(" " * (j - i)); i = j; continue
        if sql[i:i + 2] == "/*":
            j = sql.find("*/", i + 2)
            j = n if j == -1 else j + 2
            out.append("".join(c if c == "\n" else " " for c in sql[i:j])); i = j; continue
        if sql[i] in "'\"":
            q = sql[i]; j = i + 1
            while j < n:
                if sql[j] == q:
                    if j + 1 < n and sql[j + 1] == q:
                        j += 2; continue
                    j += 1; break
                j += 1
            out.append(sql[i:j]); i = j; continue
        out.append(sql[i]); i += 1
    return "".join(out)


def annotated(lines: list[str], idx: int) -> str | None:
    """Return the justification if this line, or one of the 6 above it, carries one.

    Six rather than three because a single construct routinely spans several lines --
    the gaps-and-islands idiom is two `row_number()` calls on consecutive lines, and one
    annotation should cover the pair rather than needing to be repeated.
    """
    for k in range(max(0, idx - 6), idx + 1):
        m = ANNOTATION.search(lines[k])
        if m:
            return m.group("reason")
    return None


def over_clause_after(text: str, pos: int) -> tuple[bool, bool]:
    """(has_over, over_has_order_by) for a ranking function starting at `pos`."""
    tail = text[pos:pos + 400]
    m = re.search(r"\bOVER\s*\(", tail, re.I)
    if not m:
        return (False, False)
    depth, i = 0, m.end() - 1
    while i < len(tail):
        if tail[i] == "(":
            depth += 1
        elif tail[i] == ")":
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = tail[m.end():i]
    return (True, bool(re.search(r"\bORDER\s+BY\b", body, re.I)))


def statement_bounds(text: str, pos: int) -> str:
    """The statement containing `pos`, for LIMIT/ORDER BY co-occurrence checks."""
    start = text.rfind(";", 0, pos) + 1
    end = text.find(";", pos)
    return text[start: end if end != -1 else len(text)]


def scan_file(path: pathlib.Path) -> list[tuple[int, str, str | None]]:
    raw = path.read_text(encoding="utf-8", errors="replace")
    raw_lines = raw.splitlines()
    code = strip_comments(raw)
    code_lines = code.splitlines()
    findings = []

    def line_of(pos: int) -> int:
        return code.count("\n", 0, pos)

    for m in ARBITRARY_PICK.finditer(code):
        findings.append((line_of(m.start()), f"{m.group(1)}() picks an arbitrary row from the group", None))
    for m in FIRST_LAST.finditer(code):
        # `first`/`last` are also column names in places; only flag aggregate-looking use.
        findings.append((line_of(m.start()), f"{m.group(1)}() picks an arbitrary row from the group", None))
    for m in ORDERED_AGG.finditer(code):
        seg = code[m.start(): m.start() + 300]
        if not re.search(r"\bORDER\s+BY\b", seg, re.I):
            findings.append((line_of(m.start()), f"{m.group(1)}() with no ORDER BY -- concatenation order varies", None))
    for m in DISTINCT_ON.finditer(code):
        findings.append((line_of(m.start()), "DISTINCT ON with no guaranteed row choice", None))
    for m in RANKING.finditer(code):
        has_over, has_order = over_clause_after(code, m.start())
        if not has_over:
            continue
        if not has_order:
            findings.append((line_of(m.start()), f"{m.group(1)}() OVER (...) with NO ORDER BY -- never correct", "HARD"))
        else:
            findings.append((line_of(m.start()), f"{m.group(1)}() -- ORDER BY must be a TOTAL order within the partition", None))
    for m in re.finditer(r"\bLIMIT\b", code, re.I):
        stmt = statement_bounds(code, m.start())
        if not re.search(r"\bORDER\s+BY\b", stmt, re.I):
            findings.append((line_of(m.start()), "LIMIT with no ORDER BY in the statement -- arbitrary sample", None))

    out = []
    for ln, msg, hard in findings:
        just = annotated(raw_lines, ln) if ln < len(raw_lines) else None
        out.append((ln + 1, msg, ("HARD" if hard == "HARD" else just)))
    return sorted(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list-annotated", action="store_true",
                    help="also print the justified cases, so they can be reviewed")
    args = ap.parse_args()

    files = sorted(f for d in SCAN for f in (REPO / d).rglob("*.sql")
                   if "target" not in f.parts)
    if not files:
        print("no SQL files found -- wrong working directory?", file=sys.stderr)
        return 2

    bad, ok, hard = [], [], []
    for f in files:
        rel = f.relative_to(REPO).as_posix()
        for ln, msg, just in scan_file(f):
            if just == "HARD":
                hard.append((rel, ln, msg))
            elif just is None:
                bad.append((rel, ln, msg))
            elif len(just.split()) < MIN_REASON_WORDS:
                bad.append((rel, ln, f"{msg} -- justification too thin to review: {just!r}"))
            else:
                ok.append((rel, ln, msg, just))

    print(f"files scanned      : {len(files)}")
    print(f"justified          : {len(ok)}")
    print(f"unjustified        : {len(bad)}")
    print(f"never-justifiable  : {len(hard)}")

    if args.list_annotated and ok:
        print("\njustified cases (review these -- each is a claim about the data):")
        for rel, ln, msg, just in ok:
            print(f"  {rel}:{ln}  {msg}\n      because: {just}")

    if hard:
        print("\nFAIL - ranking function with no ORDER BY. This cannot be annotated away:",
              file=sys.stderr)
        for rel, ln, msg in hard:
            print(f"  {rel}:{ln}: {msg}", file=sys.stderr)
    if bad:
        print("\nFAIL - non-deterministic construct with no justification:", file=sys.stderr)
        for rel, ln, msg in bad:
            print(f"  {rel}:{ln}: {msg}", file=sys.stderr)
        print("\n  Either make it deterministic, or add an adjacent annotation stating why\n"
              "  the group is unique / the order is total:\n"
              "    -- determinism-ok: <reason someone else can check>", file=sys.stderr)

    if bad or hard:
        return 1
    print("\nOK - every non-deterministic construct is justified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
