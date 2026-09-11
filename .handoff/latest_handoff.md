# Handoff — 2026-09-12 00:35, Claude Opus 5

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
**Steps 1 and 2 are done and `is_reliable_only` has been relaxed per the owner's decision
of 2026-09-12** (findings §7). Step 3 (the push) is next and is gated on the owner's go,
after they have seen the relaxed numbers.

## Last commit

See `git log -1`. The most recent commit relaxes `is_reliable_only` for the tool's basket,
rebuilds `tool/data/` under it, adds the guarantee assertion, and documents the divergence in
four places (findings §7, the writeup, the README, the tool's own coverage panel). The tree
was clean when written.

`main` is ahead of `origin/main`. **Nothing has been pushed and nothing is deployed.**

## What the last session completed

- First real refresh onto snapshot `20260911T200435Z` (upstream published 2026-09-10).
  Every gate passed, extract built twice and agreed, 1,474 s. See `docs/phase-4-findings.md`
  §6 and `logs/refresh-20260911T200433Z.log`.
- Built the handoff system (`docs/RESUME.md`, `AGENTS.md`, `.handoff/`, and the "Context and
  handoff" section of `CLAUDE.md`).
- Installed the Codex CLI (`@openai/codex`, `codex-cli 0.154.0`) and verified
  `.handoff/invoke_codex.sh` end to end.
- Relaxed `is_reliable_only` for the tool's basket on the owner's decision, with the
  guarantee it rests on asserted in SQL and demonstrated to fail. Findings §7.

## Immediate next steps

1. **Step 3, the push.** Commands were shown to the owner and are awaiting a go. Repo is
   public, remote configured, `REPO_URL` set.
2. Step 4: phone parse time for the JSON on a mid-range device profile, **after** the first
   deploy. Phone *width* is already measured and holds at 380px.
3. Step 5: custom domain — the owner supplies the hostname for `tool/CNAME`, then check the
   tool and the writeup are both reachable from the domain's landing page.
4. GitHub Pages still needs enabling by hand: Settings → Pages → Source: *GitHub Actions*.

## Open questions and blockers

**Blocked on the project owner:**

- **The push**, **enabling GitHub Pages**, and **the custom domain hostname**.
- **Whether to reset `check_extract.py`'s floors.** They are 1,500 products and 40%
  comparable, set against a build of 2,921/60.93%. The population is now 6,090/65.30%, so the
  product floor is a quarter of it. Findings §7 recommends 4,000 and 50% and explains why.
  **Recommended, not applied** — the owner has not ruled on it.


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
- **`is_reliable_only` is relaxed for the tool's basket only** (owner's decision,
  2026-09-12; findings §7). Phase 2's published figures are unchanged and were computed under
  the strict filter — **do not recompute them**. The relaxation rests on a guarantee asserted
  in `E1_tool_extract.sql`: no fuzzy-tier vendor's price can reach the extract. If that
  assertion ever fires, do not widen the allowed tiers to make it pass — re-examine the
  relaxation.
- The full rebuild does not fit a hosted CI runner (~10 GB working set). `scripts/refresh.py`
  runs locally; CI only validates and deploys the committed extract.

## Anything the next agent should distrust

- **The Section 2 and 3 numbers in `docs/phase-4-findings.md` describe the superseded
  2026-08-21 strict-filter extract** — 2,921 products, 60.93% comparable. §6 and §7 carry the
  current figures: **6,090 products, 65.30% comparable**. Both older sections are correct for
  the build they are stamped to and stale as a description of what the tool ships.
- **First paint doubled** with the relaxation, 189.2 KB → 353.5 KB gzipped, and the JSON the
  browser parses went 3.5 MB → 7.46 MB. Step 4's phone parse measurement now matters more.
- **Neither GitHub Actions workflow has ever executed.** Both parse, and every script they
  call has been run by hand. That is not the same as the workflow having run.
- **Phone parse time is unmeasured.** Only width has been measured.
- **`.handoff/invoke_codex.sh`'s interactive "yes" path has never been exercised.** Every
  guard was tested and each exits 1, and the codex invocation was proven reachable with the
  real binary — but always by way of a non-interactive abort or a TTY error, never by a
  human confirming and a session actually starting.
