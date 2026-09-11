# Handoff — 2026-09-11 23:15, Claude Opus 5

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

Phase 4 (the price-lookup tool). **Sections 1 to 5 are built and committed.** The brief is
`docs/phase-4-brief.md`; the results are in `docs/phase-4-findings.md`.

Work is now **past the brief**, on a refresh-and-deploy sequence the project owner gave
directly in five numbered steps: refresh, report the new extract, push, measure phone parse
time after the first deploy, then a custom domain. **Step 1 was in progress when this note
was written** — see "Anything the next agent should distrust".

## Last commit

`ac28c3f  Phase 4 Sections 4 and 5: refresh automation, deploy pipeline, phone-width check`

**The tree was NOT clean when this was written.** Uncommitted, deliberately:

- `analysis/phase4/E1_tool_extract.sql` — two fixes made just before the refresh run.
  `snapshot_id` now reads from the `_snapshot_provenance` table instead of the hardcoded
  literal `'20260822T134045Z'` (the literal would have made the refreshed `meta.json` state
  the wrong snapshot — a false provenance claim in a shipped file). The informational
  `basket_matches_published` field was renamed `basket_equals_phase3_figure`.
- `scripts/refresh.py` — `run()` now prints every step's output, not only a failing step's,
  so the schema gate result is readable in the log.

Both are complete and were exercised; they are held back only so they land in the same
commit as the refreshed extract they produce. **Do not discard them.**

`main` is **3 commits ahead of `origin/main`** (`58a6580`, `e01b67e`, `ac28c3f`).

## What the last session completed

- Phase 4 Sections 2 to 5: the static extract, the interface, the refresh pipeline and the
  deploy workflows. See `docs/phase-4-findings.md` and the three commits above.
- The Thursday cadence result was added to `docs/writeup.md` as a standalone finding, and
  the second identical-crash incident to `docs/method-note.md`.
- Started the first real refresh onto new upstream data (details below).

## Immediate next steps

1. **Finish and report step 2 of the owner's sequence**: the refreshed extract's product
   count, the comparability breakdown, and how the 60.93% comparable figure moved. The
   owner asked to be told *before anything deploys* if comparability shifted materially.
2. Then **step 3, the push** — `main` is 3 ahead. `REPO_URL` in `scripts/fetch_snapshot.py`
   is already set (commit `7cc1136`); the owner's message carried an unfilled
   `[your GitHub URL]` placeholder, so that part of the instruction is already satisfied.
3. Then step 4 (phone parse time for the JSON, on a mid-range device profile, after the
   first deploy) and step 5 (custom domain CNAME, plus checking the tool and the writeup
   are both reachable from the domain's landing page).

Commit the two held-back files together with the refreshed `tool/data/`.

## Open questions and blockers

**Blocked on the project owner** (not "not started"):

- **The push.** Explicitly gated: confirm before pushing.
- **GitHub Pages is not enabled.** Needs Settings → Pages → Source: *GitHub Actions*. A
  workflow cannot enable it for itself.
- **The custom domain hostname** for `tool/CNAME`. The owner is serving this from their own
  site and will supply the hostname.
- **Go-ahead before deploying**, per the owner's "stop between steps".

**Decided by the owner, recorded so it is not relitigated:** the maintainer's own listing of
downstream projects is out of scope — this project publishes independently and tells him
afterwards. Nothing about the maintainer's site goes in the repo or the interface. The
required attribution is separate and unchanged.

## Known constraints

- **`hammer.duckdb` no longer holds the snapshot the published numbers were computed on.**
  Before the refresh it was renamed to `hammer-20260822T134045Z.duckdb`, because
  `scripts/load_snapshot.py` deletes the target database before loading. Every figure in
  `docs/phase-2-findings.md` and `docs/phase-3-*` is stamped to snapshot `20260822T134045Z`
  and must be reproduced against that file, not against the current `hammer.duckdb`.
  `hammer2.duckdb` is unchanged and still holds snapshot `20260824T132829Z`.
- The full rebuild does not fit a hosted CI runner (~10 GB working set). `scripts/refresh.py`
  runs locally; CI only validates and deploys the committed extract.

## Anything the next agent should distrust

- **A refresh was running when this note was written and may not have finished.** Snapshot
  `20260911T200435Z`, upstream published 2026-09-10. The log is the file named in
  `logs/refresh.current`. Confirmed so far: fetch, load, and **the schema gate passed —
  `OK - schema matches: 2 tables, 15 columns`, so the announced `raw.product_id`
  string-to-number change has NOT landed**. Model build, the standing checks, the dbt
  contracts and the extract had not completed. **Check whether that run finished, and with
  what exit code, before trusting anything under `tool/data/`.**
- **Everything in `tool/data/` is from the 2026-08-21 extract until that run completes**,
  and the run rewrites those files in place. If it failed partway, verify them with
  `python scripts/check_extract.py` rather than assuming.
- **The Section 2 and 3 numbers in `docs/phase-4-findings.md` describe the old extract**:
  2,921 products, 60.93% comparable, 1,137 offers past the measured horizon. A refresh onto
  newer data moves all of them. They are correct for the build they are stamped to and stale
  as a description of what the tool now ships.
- **Neither GitHub Actions workflow has ever executed.** Both parse and every script they
  call has been run by hand. That is not the same as the workflow having run.
- **Phone parse time is unmeasured.** Phone *width* was measured at a true 380px viewport
  and holds; the cost of parsing ~3.5 MB of JSON on a mid-range phone is step 4 and has no
  number yet.
