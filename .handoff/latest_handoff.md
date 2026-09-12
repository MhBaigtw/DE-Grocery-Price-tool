# Handoff — 2026-09-12 19:15, Claude Opus 5

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

Phase 4 (the price-lookup tool), after the scope correction and two owner review rounds. The
**claims sweep** is complete: the owner named it as the last item before the push. Every
figure in `docs/writeup.md`, `README.md` and `docs/method-note.md` is now in `docs/CLAIMS.md`
against a committed source, and `scripts/check_claims.py` enforces it.

## Last commit

See `git log -1`. The sweep landed as one commit alongside this note; the tree was clean when
written apart from gitignored logs.

**`main` is ahead of `origin/main`. NOTHING HAS BEEN PUSHED.** The public repository still
shows pre-correction content.

## What the last session completed

- **Sweep:** 197 figure occurrences in the three documents at `66ecb20`. One had no committed
  source (the Save-On-Foods 97%); `analysis/phase4/R6_save_on_foods_store_ids.sql` now
  regenerates it and was verified twice. The method note's controls section records the gap,
  that 0.196 was found by review rather than by a check, and what the check does not do.
- **Check:** `check_claims.py` plus `test_check_claims.py` (7 of 7). Convention: a claims
  manifest with anchor phrases, not inline tags — the reasoning is in the script's docstring.
- README Checks and Layout, `docs/RESUME.md` Step 2 and `docs/FILES.md` updated.

## Immediate next steps

1. **Wait for the owner's go on the push.** Do not push before it.
2. On a go to redeploy (approved separately): push `main`, set Netlify `stop_builds` back to
   `false`, deploy through the gate, run `verify_deploy.py` against the live URL, compression
   included, and confirm the holding page is gone.
3. Later: the custom domain (the owner supplies the hostname), and contact the maintainer —
   upstream feedback item 12 is written to be sent.

## Open questions and blockers

**Blocked on the project owner:** the push; then the redeploy; the custom domain hostname.

**Not started, and not requested:** extending `check_claims.py` to the findings documents and
`docs/upstream-feedback.md`, which carry far more figures and are not covered.

## Known constraints

- **Netlify `stop_builds` is `true`** and the live URL serves a holding page. Pushes will not
  build or deploy until it is set back.
- **Two databases, two purposes.** `hammer.duckdb` (snapshot `20260911T200435Z`) feeds the tool
  and R6. `hammer-20260822T134045Z.duckdb` is the Phase 2/3 analysis build; published analysis
  figures are reproduced against it.
- **Any edit to a figure in the three published documents needs a `docs/CLAIMS.md` entry**, or
  `check_claims.py` fails. Editing a sentence that holds a figure can make its anchor stale.

## Anything the next agent should distrust

- **`check_claims.py` proves a source exists, not that it produces the number.** In
  `CLAIMS.md`, 164 entries were confirmed against saved run output; 9 were only traced through
  a findings document that names the query (Phase 0/1 figures in the README, 279,596 in the
  writeup, 33 and 5 in the method note); 8 are historical (614, and 44/16/28, each appearing
  twice) and their scripts no longer print them. Logs are gitignored, so "confirmed" cannot be
  re-checked without re-running.
- **"Walmart cheaper on 100% of 711 dates"** is derived from `pct_dates_first_cheaper = 0.00`
  in Q3c, which counts Metro cheaper only where the daily median ratio is below 1.0. A date at
  exactly 1.0 would count for neither, and the query does not print that case. Not re-run.
- **North York rests on upstream's word only**; store 1982 is unidentified.
- **The gates on Netlify's builder are inferred, not read from a log**, the refusal path has
  never run there, and `probe.yml` has never executed.
- Use `scripts/serve_gzip.py`, not `python -m http.server`, for anything performance-related.
