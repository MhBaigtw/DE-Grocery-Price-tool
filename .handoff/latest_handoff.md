# Handoff — 2026-10-08, Claude Opus 5

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

Phase 4, live and steady on Netlify at https://de-grocery-project.netlify.app/. This session
did documentation only: `CLAUDE.md`'s Stack section described a Phase 0 plan rather than what
was built, and three files pointed at the part of that plan which never existed.

## Last commit

See `git log -1`. The automated refresh commits to `main` almost daily as
`github-actions[bot]`; commits nobody in the session made are normal here.

## What the last session completed

- **`CLAUDE.md` Stack section rewritten** to what exists, with a dated correction naming what
  it used to claim: Airflow (never built; GitHub Actions schedules), a marts layer (never
  existed), dbt as the modelling layer (it runs tests; `build_models.py` owns the build), and a
  static dashboard (retired 2026-09-12).
- **Three dependent references corrected** in the same commit: `dbt/dbt_project.yml`'s first
  line, the `dbt/` entry in `docs/FILES.md`, and the docstring of
  `scripts/check_model_parity.py`.
- **Verified before editing**, not taken on trust: `git grep` for Airflow and marts,
  `dbt/models/` holding staging and intermediate only, and the test counts recounted from the
  schema files and `dbt/tests/` — 31 generic plus 9 singular, which is the published 40.

## Immediate next steps

Nothing is pending from this work. The pipeline runs itself: the daily probe refreshes when
upstream publishes, Netlify builds the push, and the workflow verifies the live site.

## Open questions and blockers

**Blocked on the owner:**

- The custom domain.
- Whether to refresh the stale four-chain figures in `scripts/verify_deploy.py`'s comment and
  failure message (7.5 MB / 360 KB / 3.3 s / 40 s), which describe a build that no longer ships.
- Whether to correct one stale sentence in `docs/FILES.md`'s own `CLAUDE.md` entry: it says
  "seven non-negotiable honesty rules" and there are ten. Found this session, deliberately not
  changed — the brief for the work was specific about what to touch.

## Known constraints

- **Nothing may disguise the client or defeat upstream's bot check** (owner, 2026-09-13).
- **`.gitattributes` pins `tool/data/*.json` to LF.** Without it this PC's checkout rewrites
  every line ending and a deploy made from here serves bytes that differ from the committed
  ones, which happened on 2026-09-30.
- **Netlify builds on push again.** A host that refuses freezes the site, as in September; the
  difference is that the live check and its alert surface it within a day.

## Anything the next agent should distrust

- **"The refresh is broken" is the wrong first guess.** Check what the live site serves before
  touching the pipeline; the failure in September was the publish step, not the refresh.
- **The publish job watches, it does not publish.** A site found behind alerts and waits for a
  person. `scripts/vercel_publish.sh` is a proven alternate path, but its Vercel project was
  deleted and its token revoked, so `config/vercel_project.json` names nothing that exists.
- **The fallback task on the owner's PC has never done a real refresh** — it holds whenever the
  workflow got there first, which is most days. Its commit-and-push path is still untested.
- **The phase briefs and findings still say "No Airflow" and "no marts".** Those are historical
  scope statements, correct when written, and were deliberately left alone.
