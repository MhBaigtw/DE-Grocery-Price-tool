# Handoff — 2026-09-12 20:40, Claude Opus 5

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

Phase 4 (the price-lookup tool), end of the **scope-correction pass**. Save-On-Foods is
priced at a store in Kamloops, BC, so CLAUDE.md locked decision 3 was wrong from Phase 0 for
one chain; `docs/phase-4-findings.md` §9 is the record and Phase 2 findings carry it as W6.

Two rounds of owner review have been applied since the correction. **Everything requested is
done and committed. Nothing is pushed and nothing is redeployed.** The owner is reading the
writeup, README, method note and upstream feedback before the push, and said to hold.

## Last commit

See `git log -1`. The review round landed as one commit alongside this note. The tree was
clean when written.

**`main` is ahead of `origin/main`. NOTHING HAS BEEN PUSHED.** The public GitHub repository
still shows pre-correction content until the owner approves a push.

## What the last session completed

- **Dashboard retired**, not rebuilt: build guard added, `dashboard/RETIRED.md` records why.
  The guard was shown to fail.
- **Interface:** build line cut; the "each" basis label suppressed while every offer is
  `each`, with the render test made to fail on any unlabelled other basis (shown to fail); the
  basket disclosure cut to one sentence with a link, and it no longer makes a size claim.
- **Six README/writeup corrections from review:** the section 1 table and rank correlation,
  withdrawn claims removed from the README, dashboard references, the basket direction, the
  vintage, and README layout/duplication/unparsed wording.
- **Verified rather than inherited:** Walmart cheaper than Metro in all 8 categories for
  that pair alone, re-run on the analysis snapshot.

## Immediate next steps

1. **Wait for the owner's go on the push.** Do not push before it.
2. On a go to redeploy: push `main`, set Netlify `stop_builds` back to `false`, let the push
   build through the gate or deploy explicitly, then run `verify_deploy.py` against the live
   URL, compression included, and confirm the holding page is gone.
3. Later: custom domain (owner supplies the hostname), and contact the maintainer — upstream
   feedback item 12 is written to be sent.

## Open questions and blockers

**Blocked on the project owner:**

- **The push**, then **the redeploy** — separately approved, both pending.
- **The custom domain hostname.**

**Decided by the owner, recorded so it is not relitigated:**

- Scope is North York, Toronto; GTA-wide data is not available from this dataset. The tool
  compares Metro and Walmart only.
- The dashboard is retired permanently, not rebuilt.
- Down is better than wrong: the holding page stays up until the owner approves.
- Publish independently and tell the maintainer afterwards; nothing about his site in the
  repo or the interface. Attribution unchanged. Deploy target is Netlify.

## Known constraints

- **Netlify `stop_builds` is `true`** and the live URL serves a holding page. Pushes will not
  build or deploy until `stop_builds` is set back.
- **Two databases, two purposes.** `hammer.duckdb` is the newest snapshot (`20260911T200435Z`,
  prices to 2026-09-10) and feeds the tool. `hammer-20260822T134045Z.duckdb` is the Phase 2/3
  analysis build (prices to 2026-08-21); every published analysis figure, including the new
  `Q2e_flag_rank_correlation.sql`, is reproduced against it.
- **Deploy floors** are 2,300 products / 40% comparable, calibrated against the two-chain
  build; history in `scripts/check_extract.py`.

## Anything the next agent should distrust

- **North York rests on upstream's word only.** No store id exists in Metro's or Walmart's
  URLs, and the same methodology page was wrong in detail about Save-On-Foods.
- **Store 1982 is unidentified** (451 products under `/sm/planning/`).
- **The owner's review may surface further corrections.** Two rounds each found real errors in
  published text (withdrawn claims still in the README, a correlation computed over
  unmeasurable zeros with no committed query, a wrong vintage date). Assume a third pass is
  possible before the push.
- **Other published figures may lack a committed query**, as 0.196 did. That was found by
  review, not by any check. No sweep for others has been run.
- **The gates on Netlify's builder are inferred, not read from a log**, the refusal path has
  never run there, and `probe.yml` has never executed.
- Use `scripts/serve_gzip.py`, not `python -m http.server`, for anything performance-related.
