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

Phase 4. **The automated refresh is built and committed locally, and NOT pushed.** The owner
asked for a report before the first automated run goes live. Pushing this commit puts the
`refresh` workflow on `main`, and its next scheduled probe (05:00 UTC) would refresh straight
away: upstream published 2026-09-11 22:14 ET, which is newer than the live extract's
publication. The page fix and the vintage-scope fix ride in the same commit.

## Last commit

See `git log -1`. **`main` is ahead of `origin/main` by that one commit.** `5032c7a` (the
findings §3.8 ties and the phone re-measurement) was pushed, deployed and verified live
earlier the same day.

## What the last session completed

- **Light refresh and trigger:** `scripts/refresh_light.py` and `.github/workflows/refresh.yml`,
  replacing `probe.yml`.
- **Parity proof:** `scripts/check_light_parity.py`, wired into `refresh.py`.
- **Provenance records:** under `data/provenance/`, seeded from the live snapshot.
- **Locked decision 2** amended in place.
- **Page:** ages judged against today; the vintage limit applies to data deploys only.
- **Findings §10** holds the design, measurements, growth, and what is not yet verified.
- **Tests all passing:**
  - parity 7 of 7;
  - Netlify changes 12 of 12;
  - extract gate 19 of 19;
  - render test on the new page;
  - the render test fails the old page.

## Immediate next steps

1. **Wait for the owner's go to push.** Then watch the first scheduled run, or trigger it with
   `workflow_dispatch`. Check each of these:
   - the `--measure` table on the runner;
   - that the commit to `main` succeeds (`contents: write`);
   - that Netlify builds that push through its gates, with the age limit ENFORCED;
   - that `verify_deploy.py` passes on the new extract;
   - that a later documentation-only push is skipped by Netlify's `ignore`.
2. The owner to delete the failed `deploy.yml` run in the Actions tab, or authorise `gh`.
3. Later: the custom domain (the owner supplies it), and contacting the maintainer, now also
   about the automated fetch per publication.

## Open questions and blockers

**Blocked on the project owner:** the push; deleting the old failed run (needs GitHub auth);
the custom domain; whether to refresh the stale four-chain figures in `verify_deploy.py`'s
comment and failure message (owner earlier said keep that script as is).

## Known constraints

- **Netlify auto-builds are on.** A push of this commit builds (tool/ changed).
- **Two databases.** `hammer.duckdb` (snapshot `20260911T200435Z`) is the full tool build.
  `hammer-20260822T134045Z.duckdb` is the Phase 2/3 analysis build.

## Anything the next agent should distrust

- **Runner behaviour is unmeasured.** Every light-path number is from this Windows machine.
- **Linux and Windows byte identity is not demonstrated.** Parity was judged on one machine.
- **Netlify's `ignore` and `CACHED_COMMIT_REF` are tested locally against real commits, not on
  Netlify's builder.**
- **The page now withholds comparisons as data ages** — 29 of 1,938 one day after an update,
  all of them after 10 days. That is the intended correction, but it is a visible change for
  visitors if the automation ever stalls.
- **Repository growth of 160–200 KB per refresh comes from two intervals only.** The ~60–70
  MB per year figure is an estimate.
