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

Phase 4, live and steady on Netlify at https://de-grocery-project.netlify.app/. Two
documentation sessions back to back, both on the same defect: the repository's own
descriptions of itself had drifted from what was built, and nothing checks them.

## Last commit

See `git log -1`. The automated refresh commits to `main` almost daily as
`github-actions[bot]`; commits nobody in the session made are normal here.

## What the last session completed

- **`CLAUDE.md` Stack section** rewritten to what exists, with a dated note naming what it
  used to claim: Airflow, a marts layer, dbt as the modelling layer, a static dashboard.
- **`docs/FILES.md`'s own `CLAUDE.md` entry** corrected: ten honesty rules, not seven; the
  North York scope as locked decision 3 now reads; and the load-bearing rules cited by name
  as well as number. It had cited "every number has a query" as rule 3, which is now the
  ambiguous-parse rule — the entry was an instance of the staleness its own Notes warn about.
- **Hand-maintained test counts removed** from `CLAUDE.md` and `dbt/dbt_project.yml`. Nothing
  verifies a count in a comment, and `check_claims.py` only covers the writeup, README and
  method note, so adding one test would have made both lie silently.
- **Verified before editing, each time:** `git grep` for the claims, `dbt/models/` contents,
  and the honesty rules counted from the file rather than remembered.

## Immediate next steps

Nothing is pending. The pipeline runs itself: the probe refreshes when upstream publishes,
Netlify builds the push, and the workflow verifies the live site and alerts if it is behind.

## Open questions and blockers

**Blocked on the owner:**

- The custom domain.
- Whether to refresh the stale four-chain figures in `scripts/verify_deploy.py`'s comment and
  failure message (7.5 MB / 360 KB / 3.3 s / 40 s), which describe a build that no longer
  ships. This is the last known instance of the defect both sessions were fixing.

## Known constraints

- **Nothing may disguise the client or defeat upstream's bot check** (owner, 2026-09-13).
- **`.gitattributes` pins `tool/data/*.json` to LF.** Without it this PC's checkout rewrites
  every line ending and a deploy made from here serves bytes that differ from the committed
  ones, which happened on 2026-09-30.
- **Netlify builds on push again.** A host that refuses freezes the site, as in September; the
  difference is that the live check and its alert surface it within a day.

## Anything the next agent should distrust

- **Counts written into prose go stale and nothing checks them.** `check_claims.py` covers
  `docs/writeup.md`, `README.md` and `docs/method-note.md` only. Everything else — CLAUDE.md,
  FILES.md, script comments, the briefs — is unguarded, and two sessions of corrections came
  out of exactly that gap.
- **"The refresh is broken" is the wrong first guess.** Check what the live site serves first;
  September's failure was the publish step, not the refresh.
- **The publish job watches, it does not publish.** A site found behind alerts and waits for a
  person. `scripts/vercel_publish.sh` is a proven alternate path, but its Vercel project was
  deleted and its token revoked, so `config/vercel_project.json` names nothing that exists.
- **The fallback task on the owner's PC has never done a real refresh** — it holds whenever the
  workflow got there first, which is most days. Its commit-and-push path is still untested.
- **The phase briefs' "No Airflow" and the findings' "no marts" are historical** scope
  statements, correct when written, and deliberately left alone.
