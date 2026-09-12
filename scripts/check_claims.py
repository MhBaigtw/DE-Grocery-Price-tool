#!/usr/bin/env python3
"""Every figure in the published documents must trace to a committed source.

WHY THIS EXISTS. Honesty rule 4 says every published number has a committed query that
regenerates it. Until 2026-09-12 nothing enforced that. The writeup carried a rank correlation
of 0.196 that no committed query produced, and it was found by a human reviewer, not by any
check -- the same shape of failure as a file missing from the manifest before
check_manifest.py existed. This is that check, for figures.

THE CONVENTION: A CLAIMS MANIFEST WITH ANCHORS, NOT INLINE TAGS.
docs/CLAIMS.md lists, per document, each figure together with an "anchor" -- a short phrase
from the line it appears on that contains the figure -- and the committed file that
regenerates it. Chosen over inline comment tags because:
  - the published documents stay clean; they are written for readers, and a tag beside every
    number in a table cannot be placed without breaking the table;
  - one file makes provenance reviewable in one place, the same shape as docs/FILES.md;
  - the anchor ties an entry to a position, so "8" meaning eight categories and "8" meaning
    eighth rank need separate entries, and a reworded sentence fails loudly rather than
    silently keeping a stale source.

WHAT COUNTS AS A FIGURE. Any token made of digits, after removing things that are not
measured quantities: dates and years, snapshot ids, times, URLs, inline code spans (file names
and field names), section and item identifiers (§2.7, W6, R3, Phase 4, rule 9), and list
numbering. Everything else must be accounted for.

WHAT IT DOES NOT DO -- stated so nobody overclaims it:
  - It checks that a named source EXISTS and is committed. It does not re-run the source or
    prove the source produces the number. That is still a human's job, recorded in the Note
    column as "confirmed against <log>" or "traced".
  - It sees digits only. A figure written as a word ("sixfold", "eight chains") passes unseen.

Source kinds accepted in the manifest:
  <path>[, <path>...]           committed query or script (must be tracked by git)
  derived: <how> from <path>    arithmetic on a committed source's output (path must be tracked)
  provenance-lost               a figure whose origin cannot be reconstructed (note required)
  not-a-figure: <reason>        a digit token that is not a measured quantity (e.g. a parameter)

Exit 0 = every figure is accounted for. Exit 1 = at least one is not, or the manifest is stale.

  python scripts/check_claims.py              # the check
  python scripts/check_claims.py --inventory  # list every figure occurrence, for tracing
"""
from __future__ import annotations
import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ["docs/writeup.md", "README.md", "docs/method-note.md"]
MANIFEST = "docs/CLAIMS.md"

MONTHS = r"(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)"

# Removed before figures are looked for. Order matters: longer patterns first.
STRIP = [
    re.compile(r"`[^`]*`"),                                   # inline code: file and field names
    re.compile(r"\]\([^)]*\)"),                               # markdown link targets
    re.compile(r"https?://\S+"),                              # bare URLs
    re.compile(r"<[^>]+>"),                                   # HTML tags
    re.compile(r"\b\d{8}T\d{6}Z\b"),                          # snapshot ids
    re.compile(r"\b\d{4}-\d{2}-\d{2}(?:T[\d:.]+Z?)?\b"),      # ISO dates and timestamps
    re.compile(r"\b\d{1,2}:\d{2}(?::\d{2})?\b"),              # clock times
    re.compile(r"\b\d{1,2}\s+" + MONTHS + r"\b(?:\s+\d{4})?"),# 21 August 2026, 23 Aug
    re.compile(r"\b" + MONTHS + r"\.?\s+\d{4}\b"),            # Feb 2024
    re.compile(r"\b20\d{2}\s*[–-]\s*\d{2,4}\b"),              # 2025–26, 2024-2026
    re.compile(r"\b20\d{2}\b"),                               # a bare year
    re.compile(r"§\s*\d+(?:\.\d+)*[a-z]?"),                   # §2.7
    re.compile(r"\b[WRDQEFCABP]\d+[a-z]?(?:_\w+)?\b"),        # W6, R3, D4, Q2d, P1_4b
    re.compile(r"\b(?:Phase|phase|Section|section|rule|decision|Step|step|item|Item|statement|brief)[ -]?\d+(?:\.\d+)*\b"),
    re.compile(r"\bphase-?\d\b"),                             # phase-0, phase4
]
LIST_MARKER = re.compile(r"^\s*(?:#+\s*)?\d+\.\s")             # "1. " and "### 1. "
TABLE_RULE = re.compile(r"^\s*\|?[\s:|-]+\|[\s:|-]*$")
FIGURE = re.compile(
    r"(?<![\w.$])\$?\d[\d,]*(?:\.\d+)?(?:\s?(?:%|×|x\b|M\b|GB\b|MB\b|KB\b|pp\b|px\b|ms\b|s\b))?")


def figures_in(line: str) -> list[str]:
    if TABLE_RULE.match(line):
        return []
    text = LIST_MARKER.sub(" ", line, count=1)
    for pat in STRIP:
        text = pat.sub(" ", text)
    out = []
    for m in FIGURE.finditer(text):
        tok = m.group(0).strip().rstrip(",")
        if tok and any(ch.isdigit() for ch in tok):
            out.append(tok)
    return out


def tracked_files() -> set[str]:
    try:
        out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True,
                             check=True).stdout
    except Exception:                                          # noqa: BLE001
        return set()
    return {l.strip().replace("\\", "/") for l in out.splitlines() if l.strip()}


def parse_manifest(text: str) -> dict[str, list[dict]]:
    entries: dict[str, list[dict]] = {}
    doc = None
    for n, raw in enumerate(text.splitlines(), 1):
        h = re.match(r"^##\s+(\S+)\s*$", raw)
        if h:
            doc = h.group(1)
            entries.setdefault(doc, [])
            continue
        if doc is None or not raw.startswith("|") or TABLE_RULE.match(raw):
            continue
        # Cells split on unescaped pipes. An anchor for a table figure needs the pipes around
        # it ("| 2 |"), so a manifest cell writes them as "\|", the standard markdown escape.
        cells = [c.strip().replace("\\|", "|")
                 for c in re.split(r"(?<!\\)\|", raw.strip().strip("|"))]
        if len(cells) < 3 or cells[0].lower() == "figure":
            continue
        fig, anchor, source = cells[0], cells[1], cells[2]
        note = cells[3] if len(cells) > 3 else ""
        entries[doc].append({"figure": fig, "anchor": anchor, "source": source,
                             "note": note, "line": n, "hits": 0})
    return entries


def source_kind(source: str) -> str:
    s = source.strip().lower()
    if s.startswith("provenance-lost"):
        return "provenance-lost"
    if s.startswith("not-a-figure"):
        return "not-a-figure"
    if s.startswith("derived:"):
        return "derived"
    return "sourced"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--inventory", action="store_true",
                    help="print every figure occurrence with its line, then exit")
    ap.add_argument("--root", default=str(ROOT), help="repository root (for tests)")
    ap.add_argument("--docs", nargs="*", default=DOCS)
    ap.add_argument("--manifest", default=MANIFEST)
    args = ap.parse_args()
    root = pathlib.Path(args.root)
    # The documents contain typographic characters (en dashes, minus signs, ×). A Windows
    # console's default codepage cannot print them, which crashed the first inventory run.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:                                      # noqa: BLE001
            pass

    doc_lines: dict[str, list[str]] = {}
    for d in args.docs:
        p = root / d
        if not p.exists():
            print(f"FAIL - published document not found: {d}")
            return 1
        doc_lines[d] = p.read_text(encoding="utf-8").splitlines()

    if args.inventory:
        total = 0
        for d, lines in doc_lines.items():
            for i, line in enumerate(lines, 1):
                figs = figures_in(line)
                if figs:
                    total += len(figs)
                    print(f"{d}:{i}\t{' | '.join(figs)}\t{line.strip()[:140]}")
        print(f"\n{total} figure occurrences in {len(doc_lines)} documents")
        return 0

    mpath = root / args.manifest
    if not mpath.exists():
        print(f"FAIL - claims manifest not found: {args.manifest}")
        return 1
    manifest = parse_manifest(mpath.read_text(encoding="utf-8"))
    tracked = tracked_files() if root == ROOT else {
        str(p.relative_to(root)).replace("\\", "/") for p in root.rglob("*") if p.is_file()}

    fails: list[str] = []
    occurrences = 0
    kinds = {"sourced": 0, "derived": 0, "provenance-lost": 0, "not-a-figure": 0}

    # Each entry's source must exist, be committed, and be of a known kind.
    for d, ents in manifest.items():
        for e in ents:
            if e["figure"] not in e["anchor"]:
                fails.append(f"{args.manifest}:{e['line']}: anchor does not contain its figure "
                             f"{e['figure']!r}: {e['anchor']!r}")
            kind = source_kind(e["source"])
            if kind in ("sourced", "derived"):
                paths = re.findall(r"[\w./-]+\.(?:sql|py|js|sh|json|toml)", e["source"])
                if not paths:
                    fails.append(f"{args.manifest}:{e['line']}: {e['figure']!r} names no source file")
                for pth in paths:
                    if pth not in tracked:
                        fails.append(f"{args.manifest}:{e['line']}: {e['figure']!r} cites "
                                     f"{pth}, which is not a committed file")
            elif not e["note"]:
                fails.append(f"{args.manifest}:{e['line']}: {e['figure']!r} is {kind} with no "
                             "note explaining why")

    # Every figure occurrence must be covered by an entry anchored on its line.
    for d, lines in doc_lines.items():
        ents = manifest.get(d, [])
        for i, line in enumerate(lines, 1):
            figs = figures_in(line)
            if not figs:
                continue
            occurrences += len(figs)
            for tok in sorted(set(figs)):
                need = figs.count(tok)
                have = 0
                for e in ents:
                    if e["figure"] == tok and e["anchor"] in line:
                        # An anchor such as "(6 of 6)" holds the figure twice, so it covers
                        # two occurrences, not one. Counted as whole figures, so "2" is not
                        # found inside "22".
                        per = max(1, figures_in(e["anchor"]).count(tok))
                        c = line.count(e["anchor"]) * per
                        have += c
                        e["hits"] += c
                if have < need:
                    fails.append(f"{d}:{i}: figure {tok!r} has no traceable source "
                                 f"({have} of {need} occurrence(s) covered) -- "
                                 f"{line.strip()[:90]}")

    # A manifest entry that matches nothing is stale: its sentence changed or was removed.
    for d, ents in manifest.items():
        for e in ents:
            if d in doc_lines and e["hits"] == 0:
                fails.append(f"{args.manifest}:{e['line']}: stale entry -- {e['figure']!r} with "
                             f"anchor {e['anchor']!r} no longer appears in {d}")
            kinds[source_kind(e["source"])] += 1

    entries_total = sum(len(v) for v in manifest.values())
    print(f"documents          : {len(doc_lines)}")
    print(f"figure occurrences : {occurrences}")
    print(f"manifest entries   : {entries_total}")
    print(f"  sourced          : {kinds['sourced']}")
    print(f"  derived          : {kinds['derived']}")
    print(f"  provenance-lost  : {kinds['provenance-lost']}")
    print(f"  not-a-figure     : {kinds['not-a-figure']}")
    if fails:
        print()
        for f in fails[:40]:
            print(f"FAIL  {f}")
        if len(fails) > 40:
            print(f"      ... and {len(fails) - 40} more")
        print(f"\nFAIL - {len(fails)} problem(s). A published figure without a committed source "
              "is a number nobody can check.")
        return 1
    print("\nOK - every figure in the published documents traces to a committed source.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
