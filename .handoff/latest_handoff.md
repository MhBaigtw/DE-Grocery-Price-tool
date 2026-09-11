# Handoff — 2026-09-11 23:45, Claude Opus 5

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

Phase 4 (the price-lookup tool). Sections 1 to 5 built and committed; brief
`docs/phase-4-brief.md`, results `docs/phase-4-findings.md`.

Work is past the brief, on a refresh-and-deploy sequence the project owner gave directly.
**Steps 1 and 2 are done: the first real refresh has completed and is committed.** Step 3
(the push) is next and is gated on the owner's go.

## Last commit

See `git log -1`. The refresh commit contains the rebuilt `tool/data/`, the two pipeline
fixes that preceded it, findings §6, and this note. The tree was clean when written.

`main` is ahead of `origin/main`. **Nothing has been pushed and nothing is deployed.**

## What the last session completed

- First real refresh onto snapshot `20260911T200435Z` (upstream published 2026-09-10).
  Every gate passed, extract built twice and agreed, 1,474 s. See `docs/phase-4-findings.md`
  §6 and `logs/refresh-20260911T200433Z.log`.
- Built the handoff system (`docs/RESUME.md`, `AGENTS.md`, `.handoff/`, and the "Context and
  handoff" section of `CLAUDE.md`).
- Installed the Codex CLI (`@openai/codex`, `codex-cli 0.154.0`) and verified
  `.handoff/invoke_codex.sh` end to end.

## Immediate next steps

1. **The owner must decide the `is_reliable_only` question** — see "Open questions". It
   governs whether the tool's coverage keeps eroding, and it has a deadline.
2. **Step 3, the push.** Commands were shown to the owner and are awaiting a go. Repo is
   public, remote configured, `REPO_URL` set.
3. Step 4: phone parse time for the JSON on a mid-range device profile, **after** the first
   deploy. Phone *width* is already measured and holds at 380px.
4. Step 5: custom domain — the owner supplies the hostname for `tool/CNAME`, then check the
   tool and the writeup are both reachable from the domain's landing page.
5. GitHub Pages still needs enabling by hand: Settings → Pages → Source: *GitHub Actions*.

## Open questions and blockers

**Blocked on the project owner:**

- **`is_reliable_only` is degenerative and needs a decision.** It excludes any barcode a
  fuzzy-tier vendor (Loblaws, No Frills, T&T, Voila) also carries. Those vendors accumulate
  barcode sightings as the dataset grows, and a barcode once attached never detaches, so the
  set can only shrink: 5,222 → 3,599 in twenty days, taking the tool's basket from 3,190 to
  1,908 and comparability from 60.93% to 46.59%. Findings §6 has the full numbers and the
  argument that the filter may be unnecessary for this tool, since it compares three
  reliable-tier chains and never reads a fuzzy vendor's price. **Relaxing it would put the
  tool's basket out of agreement with the 3,190 and 3,477 published in Phase 3**, so it is a
  decision, not an edit. Do not change it unilaterally.
- **The push**, **enabling GitHub Pages**, and **the custom domain hostname**.

**Decided by the owner, recorded so it is not relitigated:** the maintainer's own listing of
downstream projects is out of scope — publish independently, tell him afterwards. Nothing
about the maintainer's site goes in the repo or the interface. The required attribution is
separate and unchanged.

## Known constraints

- **`hammer.duckdb` now holds snapshot `20260911T200435Z`, not the snapshot the Phase 2 and
  Phase 3 numbers were computed on.** That build is preserved as
  `hammer-20260822T134045Z.duckdb` — it was renamed rather than overwritten because
  `scripts/load_snapshot.py` deletes the target database before loading. Reproduce any
  published Phase 2/3 figure against that file. `hammer2.duckdb` still holds
  `20260824T132829Z`.
- **`check_extract.py`'s floors were set against the old, larger build** (1,500 products,
  40% comparable). The current extract clears them at 1,627 and 46.59%. At the observed rate
  of erosion the next refresh or two will trip the product floor and refuse to deploy. That
  is correct behaviour, and it is the deadline on the question above.
- The full rebuild does not fit a hosted CI runner (~10 GB working set). `scripts/refresh.py`
  runs locally; CI only validates and deploys the committed extract.

## Anything the next agent should distrust

- **The Section 2 and 3 numbers in `docs/phase-4-findings.md` describe the superseded
  2026-08-21 extract** — 2,921 products, 60.93% comparable, 1,137 offers past the measured
  horizon. They are correct for the build they are stamped to and stale as a description of
  what the tool now ships. §6 carries the current figures. The same applies to the 2,921 and
  60.9% quoted in `README.md`.
- **Neither GitHub Actions workflow has ever executed.** Both parse, and every script they
  call has been run by hand. That is not the same as the workflow having run.
- **Phone parse time is unmeasured.** Only width has been measured.
- **`.handoff/invoke_codex.sh`'s interactive "yes" path has never been exercised.** Every
  guard was tested and each exits 1, and the codex invocation was proven reachable with the
  real binary — but always by way of a non-interactive abort or a TTY error, never by a
  human confirming and a session actually starting.
