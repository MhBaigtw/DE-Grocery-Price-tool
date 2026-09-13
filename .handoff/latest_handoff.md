# Handoff — 2026-09-13, Claude Opus 5

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

Phase 4, automated refresh. The first run was refused by the upstream host's bot-verification
challenge. The diagnostic could not reproduce it (0 of 80 requests, four cloud addresses;
findings §11). Validation, retry and a Task Scheduler fallback are built. This commit is pushed
immediately before the owner's **watched first run**: the workflow is re-enabled and triggered
by hand straight after.

## Last commit

See `git log -1`. Written alongside the commit; the tree was clean apart from gitignored logs.

## What the last session completed

- **Validation** (`fetch_snapshot.py`): a stamp must be a stamp; an archive must be served as a
  zip and start with a zip header, checked before a file or record exists.
- **Retry** (`refresh_light.py`): at 0, +15 and +45 minutes, then fail and alert; longer
  schedules are refused in code. `test_upstream_validation.py`, 13 of 13.
- **Fallback:** `refresh_fallback.py`, plus a Task Scheduler task registered daily at 11:00 local
  (UTC+3). It runs only while the PC is on and the user is logged on.
- **Record:** findings §11, and the probe code in `docs/diagnostics/`.
- **Cleanup:** the temporary Netlify probe site and the diagnostic branch are deleted, the
  `access-probe` workflow is disabled, and the failed `deploy.yml` run is deleted.

## Immediate next steps

1. **Watch the first run** and report to the owner:
   - `--measure` against the Windows figures (269 s / 2.71 GiB / ~5.3 GiB);
   - whether the Linux-built extract is byte-identical to a Windows build of the same archive
     (download it locally, check the sha256 against the committed provenance record, build with
     `refresh_light.py --snapshot`, compare with `check_light_parity.py --light-dir`). Report any
     diff; do not normalise around it;
   - whether the commit to `main` succeeded;
   - Netlify's gated build;
   - `verify_deploy.py`;
   - the new extract's date, products and comparability against 3,465 / 55.93%.
2. If anything fails: stop and report. The site stays on the previous extract.

## Open questions and blockers

- **Blocked on the owner:** the custom domain; whether to update the stale four-chain figures in
  `verify_deploy.py`.
- **Not started:** contacting the maintainer about automated access and the challenge.

## Known constraints

- **Access:** nothing may disguise the client or defeat the bot check. No spoofed user agent,
  no headless browser, no proxies (owner, 2026-09-13).
- **This push should be skipped by Netlify's `ignore`.** It changes no path that ships. That
  is the first real test of the skip on Netlify's builder.

## Anything the next agent should distrust

- **The full 975 MB download from a cloud address has never succeeded.** The diagnostic used
  4-byte range requests only.
- **The challenged runner's address is unknown**; the cause of the challenge is not established.
- **The fallback task has never run.** Its preflight, race handling and alert are untested
  end to end.
