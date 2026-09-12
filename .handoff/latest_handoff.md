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

Phase 4 (the price-lookup tool). The site is **live** again on Netlify at deploy `adcfcb5`,
verified with `verify_deploy.py`. The owner asked for two corrections before announcing it:
Phase 2 findings §3.8 (the Metro / Save-On-Foods ties) and a phone re-measurement against the
live site. Both are done in this commit.

## Last commit

See `git log -1`. Written alongside the commit; the tree was clean apart from gitignored logs.
**This commit is not pushed** — pushing needs the owner's go, and a push now triggers a
Netlify build because auto-builds are back on.

## What the last session completed

- Phase 2 findings §3.8: headline, prose and summary restated. 611 of 666 dates had Metro
  cheaper, 55 were exact ties, none had Save-On-Foods cheaper. A correction note carries the
  build stamp.
- Phase 4 findings §8: re-measured on the live site. Interactive in 2.80 s against 3.31 s, 5 runs,
  with a before/after table. The earlier four-chain numbers are kept and labelled.
- Earlier the same day: the claims sweep and check, the Q3c tie case, the push, builds
  re-enabled, and the live verification.

## Immediate next steps

1. **Wait for the owner's go to push this commit.** It triggers a rebuild; after it goes live,
   run `verify_deploy.py` against the live URL again.
2. Later: the custom domain (the owner supplies the hostname), and contact the maintainer —
   upstream feedback item 12 is written to be sent.

## Open questions and blockers

**Blocked on the project owner:** the push of this commit; the custom domain hostname; whether
to refresh the stale four-chain figures quoted in `verify_deploy.py`'s comment and failure
message. The owner earlier said to keep that script exactly as is, so it was not edited.

**Not started, and not requested:** extending `check_claims.py` beyond its three documents.

## Known constraints

- **Netlify auto-builds are on** (`stop_builds` false). Every push to `main` builds and deploys
  through the gate.
- **Two databases, two purposes.** `hammer.duckdb` (snapshot `20260911T200435Z`) feeds the tool.
  `hammer-20260822T134045Z.duckdb` (build `2026-08-28T17:48:35Z`) is the Phase 2/3 analysis
  build.

## Anything the next agent should distrust

- **The phone before/after is not like for like:** localhost against the live CDN, gzip against
  Brotli, 3 runs against 5. Only 0.51 s of the predicted ~0.9 s saving showed up, and the cause is
  not isolated. Search keystroke got 15 ms slower, unexplained.
- **`check_claims.py` proves a source exists, not that it produces the number**, and covers
  three documents only.
- **North York rests on upstream's word only**; store 1982 is unidentified.
- **The gates on Netlify's builder passed in a successful build, but the build log was not
  read.**
