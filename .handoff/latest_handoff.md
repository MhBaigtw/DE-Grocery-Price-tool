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

Phase 4, live and current. **Hosting moved to Vercel on 2026-09-30** (findings §13): the refresh
workflow publishes the prebuilt site itself, so no hosted builder can freeze it again, as one did
for fourteen days in September (§12). Live at https://de-grocery-price-tool.vercel.app/. Netlify
is configured but unused, builds stopped, still serving its last good deploy because that URL is
published on the owner's resume.

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

1. **The owner should rotate `VERCEL_TOKEN`.** It was pasted into a chat transcript on
   2026-09-30. Create a replacement in Vercel, update the repository secret, revoke the old one.
   A Vercel token is account-wide; it cannot be limited to one project.
2. Nothing else is pending. The next scheduled run refreshes, publishes and verifies on its own.

## Open questions and blockers

**Blocked on the owner:** rotating the token; the custom domain; whether to update the stale
four-chain figures in `verify_deploy.py`'s comment; whether the old Netlify URL should keep
serving an increasingly old extract or say where the tool moved.

## Known constraints

- **Nothing may disguise the client or defeat upstream's bot check** (owner, 2026-09-13).
- **This PC converts line endings on checkout** (`core.autocrlf=true`, no `.gitattributes`), so
  a checked-out `tool/data/` never matches the committed bytes. Compare against
  `git cat-file blob`, not the working copy, or a parity check fails for no reason.

## Anything the next agent should distrust

- **"The refresh is broken" is the wrong first guess.** It has been running daily throughout.
  Check what the site serves before touching the pipeline.
- **The publish job re-runs the gates and uploads; it never builds on the host.** If someone
  connects Vercel's Git integration, the dependency that caused §12 is back.
- **The fallback task on the owner's PC has never done a real refresh** — it holds whenever the
  workflow got there first, which is most days. Its commit-and-push path is still untested.
- **`_site` in the working tree is a build artifact** (gitignored) and will go stale.
