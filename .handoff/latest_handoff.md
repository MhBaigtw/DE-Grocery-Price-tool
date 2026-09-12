# Handoff — 2026-09-12, Claude Opus 5

> Rewritten in full at the end of every completed section, at the same time as the
> commit. Never written in a hurry at the end of a session — a note written while
> context is running out is exactly the note you cannot trust.
>
> This file records **where work stopped**. It is not a record of what is true about the
> project. Ground truth is the repository: `CLAUDE.md`, the findings docs, the briefs and
> git history. Anyone reading this reads `docs/RESUME.md` first.

## Orientation

Read `docs/RESUME.md` and follow it before doing anything. Do not treat the sections
below as verified state — verify them.

## Current phase and section

Phase 4 (the price-lookup tool). The claims sweep and the owner's two follow-ups are done:
the tie case behind "Walmart cheaper on 100% of 711 dates" is closed, and the method note says
plainly that the claims check covers three documents, not the repository. The owner gave the
go to push, re-enable Netlify builds and verify the live site; this note is committed
immediately before that push.

## Last commit

See `git log -1`. Written alongside the commit; the tree was clean apart from gitignored logs.

## What the last session completed

- **Tie case closed.** `Q3c_pairwise_stability.sql` gained a final statement that bins every
  date: Metro / Walmart has 711 of 711 with Walmart cheaper, 0 at exactly 1.0, closest 1.0264.
  Verified twice on the analysis snapshot. The claim stands as written.
- **Found along the way:** Metro / Save-On-Foods has 55 of 666 dates at exactly 1.0, and the
  writeup's quote of that withdrawn comparison gave its 91.7% the wrong pair's date count (606).
  Corrected to 666.
- **Method note:** the claims check covers the writeup, README and method note only; the five
  unchecked documents hold 6,613 figures by the same unreviewed extractor.

## Immediate next steps

1. If the push, the Netlify re-enable or the live verification did not complete, finish them:
   `git push origin main`; `stop_builds` to `false`; build the pushed commit; run
   `scripts/verify_deploy.py https://de-grocery-project.netlify.app/`, compression included.
2. Later: the custom domain (the owner supplies the hostname), and contact the maintainer —
   upstream feedback item 12 is written to be sent.

## Open questions and blockers

**Blocked on the project owner:** the custom domain hostname.

**Not started, and not requested:** extending `check_claims.py` to the findings documents,
`docs/upstream-feedback.md` and the Phase 3 thesis. The owner said not now.

## Known constraints

- **Two databases, two purposes.** `hammer.duckdb` (snapshot `20260911T200435Z`) feeds the tool
  and R6. `hammer-20260822T134045Z.duckdb` is the Phase 2/3 analysis build; published analysis
  figures are reproduced against it.
- **Any edit to a figure in the three published documents needs a `docs/CLAIMS.md` entry**, or
  `check_claims.py` fails. A reworded or re-wrapped sentence can make an anchor stale.

## Anything the next agent should distrust

- **`check_claims.py` proves a source exists, not that it produces the number.** Entries marked
  "traced" or "historical" in `CLAIMS.md` were not re-run. Logs are gitignored.
- **Phase 2 findings §3.8 still reads "Metro beats Save-On-Foods on 91.74% of dates"** without
  saying the remaining 55 dates are exact ties. The comparison is withdrawn (W6); the findings
  text was not edited.
- **North York rests on upstream's word only**; store 1982 is unidentified.
- **Whether the live deploy verified cleanly** is in the session report and `git log`, not
  here — this note was written before the push.
- Use `scripts/serve_gzip.py`, not `python -m http.server`, for anything performance-related.
