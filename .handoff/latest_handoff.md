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

Phase 4, live and current on **Netlify** at https://de-grocery-project.netlify.app/. Hosting spent
one day on Vercel (§13) while this account's deploys were refused (§12); the plan was upgraded and
hosting returned the same day (§14). Netlify builds on push again through its own gates. The Vercel
publish path stays in the repository, wired to nothing, as a proven alternate; its project was
deleted and its token revoked.

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

1. Nothing is pending. The next scheduled run refreshes, Netlify builds the push, and the
   workflow verifies the live site and alerts if it is behind.
2. If a host refuses again: `scripts/vercel_publish.sh` is the alternate path. It needs a new
   Vercel project, fresh ids in `config/vercel_project.json` and a token in secrets — the old
   token was revoked on 2026-09-30 after being pasted in plaintext.

## Open questions and blockers

**Blocked on the owner:** the custom domain; whether to update the stale four-chain figures in
`verify_deploy.py`'s comment.

## Known constraints

- **Nothing may disguise the client or defeat upstream's bot check** (owner, 2026-09-13).
- **`.gitattributes` pins `tool/data/*.json` to LF** (added 2026-09-30). Before it, this PC's
  checkout rewrote every line ending, and a deploy made from here served bytes that differed from
  the committed ones. If that file is ever removed, both problems come back.

## Anything the next agent should distrust

- **"The refresh is broken" is the wrong first guess.** It has been running daily throughout.
  Check what the site serves before touching the pipeline.
- **The publish job no longer publishes; it watches.** Netlify builds on push, so a host that
  refuses freezes the site again — the difference from September is that the live check and its
  alert make it visible within a day. A site found behind is no longer republished automatically.
- **The fallback task on the owner's PC has never done a real refresh** — it holds whenever the
  workflow got there first, which is most days. Its commit-and-push path is still untested.
- **`_site` in the working tree is a build artifact** (gitignored) and will go stale.
