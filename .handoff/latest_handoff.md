# Handoff — 2026-09-27, Claude Opus 5

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

Phase 4, live. **The site is stale and the refresh is not at fault.** Netlify has refused every
deploy since 2026-09-13 (`Skipped due to account credit usage exceeded`), so the public site
serves the 2026-09-11 extract while `main` holds 2026-09-26. Findings §12 is the record.

## Last commit

See `git log -1`. The automated refresh commits to `main` almost daily as
`github-actions[bot]`; do not be surprised by commits nobody in the session made.

## What the last session completed

- **Diagnosed** the stale site: pipeline healthy, publish step failing, nothing watching it.
- **`check_published.py`**: the live site must serve the extract the repository holds. Wired
  into the probe job daily and after every refresh commit, each with its own alert. Its test
  covers the exact outage shape (5 of 5).
- **Findings §12** records the incident, what the page got right, and what is still unfixed.
- **Prepared but not published:** `_site` assembled from the committed 2026-09-26 extract with
  the gates passed, ready for a direct upload.

## Immediate next steps

1. **Get the site current.** `netlify deploy --prod --dir _site --site 36972e0e-7430-455a-998a-a966c9a0a6a9`
   — a direct upload does not use Netlify's builder, so it may work while builds are refused.
   This session's permission rules refused it; the owner has to allow or run it.
2. **Then `python scripts/check_published.py`** — it should pass once the upload lands.
3. **Decide the lasting fix** (findings §12): publish a prebuilt `_site` from the workflow with
   a Netlify token in GitHub secrets, or move hosting to GitHub Pages. Both remove the
   component that failed; both need a credential or a decision.
4. **The account question is the owner's:** Netlify refuses deploys for credit usage while
   reporting 0 of 300 credits used and 1 build minute this period.

## Open questions and blockers

**Blocked on the owner:** the deploy itself; the hosting decision; the custom domain; whether to
update the stale four-chain figures in `verify_deploy.py`'s comment.

## Known constraints

- **Nothing may disguise the client or defeat upstream's bot check** (owner, 2026-09-13).
- **This PC converts line endings on checkout** (`core.autocrlf=true`, no `.gitattributes`), so
  a checked-out `tool/data/` never matches the committed bytes. Compare against
  `git cat-file blob`, not the working copy, or a parity check fails for no reason.

## Anything the next agent should distrust

- **"The refresh is broken" is the wrong first guess.** It has been running daily throughout.
  Check what the site serves before touching the pipeline.
- **The fallback task on the owner's PC has never done a real refresh** — it holds whenever the
  workflow got there first, which is most days. Its commit-and-push path is still untested.
- **`_site` in the working tree is a build artifact** (gitignored) and will go stale.
