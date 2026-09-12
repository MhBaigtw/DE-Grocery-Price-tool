# Handoff — 2026-09-12 05:10, Claude Opus 5

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

Phase 4 (the price-lookup tool), in a **scope-correction pass** directed by the project
owner. Save-On-Foods turned out to be priced at a store in Kamloops, BC, not Toronto, so
CLAUDE.md locked decision 3 was wrong from Phase 0 for one chain. `docs/phase-4-findings.md`
§9 has the record; Phase 2 findings carry it as withdrawal **W6**.

**All seven of the owner's correction steps are done, plus the interface simplification.
Nothing has been redeployed.** The owner asked to be shown the result before redeploying.

## Last commit

See `git log -1`. The correction landed as four local commits: the scope change on its own
(as the owner required), the two-chain rebuild, the simplified interface, and the
withdrawals and documentation with this note. The tree was clean when written.

**`main` is ahead of `origin/main` and NOTHING HAS BEEN PUSHED.** The public GitHub
repository still shows the old "one Toronto neighbourhood" scope in its README until a push.

## What the last session completed

1. **Took the live site down first.** Netlify `stop_builds` is set to `true`, and a holding
   page was deployed with `--no-build`. `/`, all three data files and `/dashboard/` were
   checked: the old claims are gone and the data returns 404.
2. **Store 1982 could not be identified**, and that is recorded rather than guessed. Findings
   §9 and upstream feedback item 12 have the evidence.
3. **Rebuilt the tool as Metro vs Walmart only.** 3,465 products shipped, 55.93% comparable.
   Deploy floors recalibrated to 2,300 / 40%, with a floor history in the code.
4. **Re-scoped to North York, Toronto** in the tool strip, writeup, README and CLAUDE.md
   decision 3, in its own commit.
5. **Withdrew every cross-chain comparison involving Save-On-Foods** as W6, in the writeup
   and both findings docs. Its within-chain results are relabelled to Kamloops.
6. **Method note** now leads with the headline failure: every check verified consistency,
   and none verified what the data was of.
7. **Upstream feedback item 12**: Calgary-vs-Kamloops evidence, framed as a probable
   configuration change rather than an error.
8. **Simplified the interface**, mobile-first, with every render-test rule still passing.
   The disclosures kept at a wording cost are listed in §9.

## Immediate next steps

1. **The owner reviews the rebuilt tool and the documents, then says whether to redeploy.**
   Do not redeploy before that.
2. On a go: push `main`, set Netlify `stop_builds` back to `false`, and let the push build
   through the gate, or deploy explicitly. Then run `verify_deploy.py` against the live URL,
   compression check included, and confirm the holding page is gone.
3. Custom domain: the owner supplies the hostname later. Do not configure one before then.
4. Contact the maintainer. Upstream feedback item 12 is written to be sent.

## Open questions and blockers

**Blocked on the project owner:**

- **Review and go-ahead to redeploy** — explicitly requested before any redeploy.
- **The push** — nothing from this correction is on GitHub yet.
- **Whether to rebuild the dashboard** without Save-On-Foods, or retire it. It is not
  published and is excluded from the Netlify build.
- **The custom domain hostname.**

**Decided by the owner, recorded so it is not relitigated:**

- Scope is North York, Toronto. GTA-wide data is not available from this dataset, and
  scraping is locked out (decision 1). The route to wider coverage is asking the maintainer.
- The tool compares Metro and Walmart only.
- Down is better than wrong: the site stays on the holding page until the owner approves.
- Publish independently and tell the maintainer afterwards; nothing about his site goes in
  the repo or the interface. The required attribution is separate and unchanged.
- Deploy target is Netlify. `is_reliable_only` is relaxed for the tool's basket only (§7).

## Known constraints

- **Netlify `stop_builds` is `true`.** Pushes will not build or deploy until it is set back.
  That is deliberate, and it is the reason the holding page stays up.
- **`hammer.duckdb` holds snapshot `20260911T200435Z`.** The Phase 2/3 build is preserved as
  `hammer-20260822T134045Z.duckdb`, renamed because `load_snapshot.py` deletes its target.
- **The tool's chain allowlist enforces two guarantees:** reliable tier, and priced in North
  York. It is asserted in `E1_tool_extract.sql` and in `check_extract.py`. Do not add a chain
  without establishing both from evidence, not from upstream's description.
- **Deploy floors** are 2,300 products / 40% comparable, calibrated 2026-09-12 against the
  two-chain build.

## Anything the next agent should distrust

- **North York itself rests on upstream's word only.** Metro, Walmart and the other chains
  carry no store id in their URLs. The same methodology page was wrong in detail about the
  one chain that could be checked. Item 12 asks the maintainer to confirm.
- **Store 1982 is unidentified.** Its 451 products sit under `/sm/planning/`, not
  `/sm/pickup/`. Whether they are pickup prices at any store is not established.
- **The gates running on Netlify's builder are inferred, not read from a log**, and the
  refusal path has never run on the builder.
- **`probe.yml` has never executed.**
- **Superseded figures remain in place as records**, each stamped to its build:
  §2–§8 three-chain numbers in `docs/phase-4-findings.md`, and the Save-On-Foods tables in
  Phase 2 §3. Current figures are in §9.
- Use `scripts/serve_gzip.py`, not `python -m http.server`, for anything performance-related.
