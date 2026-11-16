# Handoff — 2026-11-16, Claude Fable 5.2

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

Phase 4, live on Netlify. An incident, in three stages, about upstream changing
`raw.nowtime` from text to an integer without notice (`docs/incident-nowtime-type-change.md`):

- **Stage 1, investigation: complete.** Sections 1 to 7 of the incident report.
- **Stage 2, the fix: committed.** Section 8 of the incident report. Whether the automated
  refresh then ran and the live site became current is recorded in the last commit that
  touches this file and in `data/provenance/` — check both, do not take it from here.
- **Stage 3, full rebuild and restatement: not started.** It needs a machine that can hold a
  full load (about 10 GB); the owner's laptop cannot.

## Last commit

See `git log -3`. Stage 2 is two commits made together: the schema contract version bump on
its own, then the decode, the tests and the documentation. The tree was clean when this was
written apart from this file's own commit.

## What the last session completed

- Schema contract version 2 (`raw.nowtime` BIGINT), with version 1 kept beside it.
- A strict integer date decode in both copies of `stg_price`, and two dbt tests on
  `observed_date`, which had none.
- The incident's queries committed under `analysis/incident_nowtime/` and re-run from the
  committed files.
- CLAUDE.md's Known contamination list gained two appended entries: the integer date form,
  and the fact that upstream rewrites history.

The incident report's section 8 is the account. This list is a pointer to it.

## Immediate next steps

**Stage 3, when a machine with room is available.** In this order:

1. Decide how the retained snapshots are built. They pass schema contract version 1 and the
   current models cannot build them (incident report 8.4, item 1). This is the owner's
   decision and it comes first, because a full rebuild of an old snapshot is otherwise
   impossible without checking out an older commit.
2. Full rebuild of the current upstream archive with `scripts/refresh.py`, retained under
   `data/snapshots/`. This is the first time the two new dbt tests run on a full load.
3. Restate every stamped figure that moves, with its delta (honesty rule 5), starting with
   the orphan-row figures honesty rule 6 quotes.
4. Restate the test counts in README, the method note and `docs/CLAIMS.md` (see below).

## Open questions and blockers

**Blocked on the owner:**

- The Stage 3 decision in step 1 above.
- A machine for the full rebuild.
- Whether the light refresh should get a date guard of its own (incident report 8.4, item 2).
  The new dbt tests do not run there.
- Still open from before the incident: the custom domain, and the stale four-chain figures in
  `scripts/verify_deploy.py`'s comment and failure message.

**Not started, not blocked:** the cause of the 125 history series that differ at their edges
between the last good extract and the first one from the new archive (8.4, item 3).

## Known constraints

- **The new-form archive the incident queries were written on was not retained.** They are
  reproducible only against upstream's 2026-11-14 publication, identified by hash in the
  report. If upstream stops serving it, those numbers cannot be regenerated.
- **A database and its schema contract must be named together.** `hammer.duckdb` and
  `hammer2.duckdb` on the owner's PC are in the old form:
  `python scripts/check_schema.py --schema config/expected_schema.v1.json`.

## Anything the next agent should distrust

- **The pinned NULL-date figure, 3, has never been seen in a built `stg_price`.** It comes
  from reading upstream's SQLite directly (N2). The dbt test that pins it has passed on the
  fixture and on a light load, where the figure is 0. Its first real run is Stage 3.
- **"40 dbt tests" and "23 of 23" in README, the method note and `docs/CLAIMS.md` are now
  two short.** The suite is 42 tests and `test_dbt_contracts.py` reports 25 of 25. They were
  left alone on purpose: "passing on both snapshots" cannot be re-established without a full
  rebuild, and the pinned-count test errors on the old databases.
- **`scripts/verify_reproducible.py` will fail against the local `hammer.duckdb`.** Its build
  stamp holds the digest of the old `stg_price.sql`, and the model cannot be rebuilt there.
  That is the Stage 3 decision showing up as a red check, not a new defect.
- **`docs/RESUME.md` Step 2 lists `check_schema.py` with no arguments.** On the owner's PC
  that now fails, correctly, until a database in the new form exists there.
- **Honesty rule 6's figures describe an archive upstream has since rewritten.** CLAUDE.md
  says so; the rule's own text has not been changed.
- **`raw.product_id` is NULL on 48 rows of the 2026-11-14 archive** (N1, last query). Nobody
  has looked at whether that is new.
- Carried over, still true: the fallback task on the owner's PC has never done a real
  refresh, and the publish job watches, it does not publish.
