# CLAUDE.md — Canadian Grocery Price Analysis

## What this project is

An analysis and data-quality pipeline built on the Project Hammer dataset
(https://projecthammer.org / https://jacobfilipp.com/hammer/), a publicly published
time series of Canadian grocery prices scraped from 8 vendor websites since Feb 2024.

We are a **downstream consumer of a published dataset**. We do not scrape any grocery
vendor. Ever. If a task seems to require data the dataset doesn't have, the answer is
"that analysis isn't possible", not "let's scrape it".

## What this project is NOT

- Not a real-time price tracker
- Not a national price index (see scope limits below)
- Not a trading/arbitrage signal
- Not a machine learning project

## Locked decisions

These are decided. Do not relitigate them mid-task. If you think one is wrong, say so
explicitly and stop; do not silently work around it.

1. **No scraping of grocery vendor sites.** Downstream consumer only.
2. **Snapshot immutability.** Every downloaded copy of the dataset is recorded with its
   download timestamp, the sha256 of the archive and upstream's last-updated stamp, and is
   never modified in place. Analysis reads from a snapshot, never from a live download.

   **Amended 2026-09-12: provenance always; archives only from full rebuilds.** Until this
   date the rule also meant every downloaded archive was *kept*. That changed deliberately,
   when the tool's refresh was automated:
   - **The light refresh** (`scripts/refresh_light.py`) runs on a GitHub-hosted runner whose
     disk is discarded after every job, and it runs each time upstream publishes. Keeping a
     ~975 MB archive per run is not possible there and not proportionate. So it records
     provenance (download timestamps, sha256, byte size, upstream's last-updated stamp) in
     `data/provenance/`, commits that record with the extract it produced, and **retains no
     archive**.
   - **Archives are retained only by manual full rebuilds** (`scripts/refresh.py`, into
     `data/snapshots/`). The mirroring commitment in the licence section now lives there.

   **What this gives up, stated rather than hidden:** a light refresh's extract can be tied to
   the exact archive by hash, but that archive can be re-read later only if upstream still
   serves it or a full rebuild happened to capture the same publication. **What it keeps:**
   the light path still reads a downloaded archive, never a live query; every extract it
   ships names the hash of the file it came from; and its filter is proven rather than
   assumed. Every full rebuild asserts that its extract is byte-identical to the light extract
   for the same snapshot (`scripts/check_light_parity.py`), and a mismatch fails loudly.
3. **Scope is North York, Toronto pickup pricing** — and for Save-On-Foods, not Toronto at
   all. The upstream data is the "in store pickup" price for the North York area of Toronto
   for seven chains. No claim in this project may be phrased as a national, provincial,
   "Canadian" or GTA-wide price without that qualifier attached.

   **Corrected 2026-09-12. This decision was wrong from Phase 0 for one chain.** It read
   "one Toronto neighbourhood" for all eight chains, and nothing in the project ever checked
   it. Upstream's methodology page states North York "except for Save on Foods (that one is a
   location in Calgary)"; the data puts **97% of Save-On-Foods products at store 2210,
   Westsyde, Kamloops, BC**, 2 products at store 6634 (Calgary, used only until 2024-11-13)
   and 451 at store 1982, unidentified. Save-On-Foods has no stores in Ontario. Every
   cross-chain comparison involving it was a cross-city comparison, and they are withdrawn
   (Phase 2 findings, W6). Its within-chain results stand, relabelled to Kamloops.

   **North York itself rests on upstream's statement only.** Metro, Walmart and the other
   chains carry no store identifier in their URLs, so the data can neither confirm nor
   contradict it — and the same page was wrong in detail about the one chain that could be
   checked.
4. **Data range is the data range.** No claim about periods outside the dataset window,
   and no trend line that crosses a known regime change (see Known Contamination) without
   the break marked.
5. **The supplied row ID is not a product identity.** `product.id` / `raw.product_id`
   change daily. All product identity must be derived and must be explicit about its
   confidence tier.

## Licence and attribution (confirmed by maintainer, 2026-08-22)

The maintainer has confirmed by email:

- Publishing derived analysis publicly, with attribution: **permitted**.
- Redistributing a processed subset, or the whole dataset, in a public repo:
  **permitted and encouraged** — more copies is explicitly seen as a good thing.
- Required attribution wording: **"The underlying data was sourced from
  ProjectHammer.org"** (or close to it). This appears in the README, in the dashboard
  footer, and in every writeup.

Because redistribution is encouraged, we **mirror our own snapshots** rather than
depending on upstream availability at read time. Snapshots are kept with their download
timestamp and sha256 per the immutability rule below. **Since 2026-09-12 that mirror is kept
by manual full rebuilds only.** The automated light refresh records provenance and keeps no
archive; see locked decision 2 as amended.

## Upstream volatility (confirmed by maintainer, 2026-08-22)

1. **Publication is becoming intermittent.** The maintainer is reworking post-processing.
   Scraping continues daily, but the published dataset will sometimes be uploaded late.

   **Therefore: publication lag is not a data gap.** These are two distinct things and
   must be two distinct fields in our models:
   - the date a price was observed (`nowtime`, from the scrape)
   - the date we obtained the file containing it (our snapshot timestamp)

   A late upload must never be reported as missing scrape data. This is the same failure
   mode as forward-filling across a gap: a pipeline artifact masquerading as a finding.

2. **A breaking schema change is planned.** `raw.product_id` will change from a string to
   a number, to reduce SQLite file size.

   **Therefore: ingest asserts the schema and fails loudly.** On every load, check column
   presence and type against a committed expected-schema file. On mismatch, stop the run
   and report — never silently cast, coerce, or infer. When the change lands, the
   expected-schema file is updated deliberately, in its own commit, with a note.

   This reinforces locked decision 5: our product identity is derived and owned by us, so
   an upstream ID type change should be an ingest-layer event and nothing more. If a
   `product_id` type change would break anything downstream of staging, that is a design
   bug on our side.

## Known contamination (from upstream docs — verify magnitudes in Phase 0)

- **Feb 28 – Jul 10/11 2024:** small basket of products only, not the full catalogue.
  Any product-count or breadth metric crossing this boundary is meaningless.
- **Pre Sept 30 2024:** two distinct products can share an identical name and unit size
  with no way to tell them apart.
- **Save-On-Foods, extracts up to 2024-12-24:** product name/brand mismatched against
  detail_url for a small number of products per day. Fixed forward, NOT retroactively.
- **Duplicate rows:** the same product can appear multiple times in one day's scrape
  (listed under multiple categories, or advertised). Upstream estimated ~6,500 products
  per day affected as of Nov 2024.
- **Extract failures:** some vendors are missing on some days.
- **UPC reliability is tiered.** Direct from vendor: Metro, Galleria, Save-On-Foods.
  Matched from a Walmart-owned source: Walmart. Fuzzy-matched with a manual QC pass and
  known to possibly contain errors: Loblaws, No Frills, T&T, Voila.
- **`price_per_unit` is not trustworthy** and may not equal current_price / units.
- **Save-On-Foods is not priced in Toronto.** 97% of its products point at store 2210 in
  Kamloops, BC (see locked decision 3). It may appear in within-chain results with that
  location attached, and never in a cross-chain comparison with a Toronto chain.

## Honesty rules (non-negotiable)

### How this list changes

**Rule numbers are identifiers. Identifiers do not move.**

1. **New rules are APPENDED at the end. Never inserted.** Not even when a new rule
   obviously belongs beside a related one — grouping is a reading convenience, and it is
   not worth what it costs. Numbering has been broken twice by mid-list insertion; the
   second time it left stale `rule N` references in four files, each of which then
   pointed confidently at the wrong rule.
2. **A withdrawn rule is marked withdrawn in place, not removed.** Its number is retired
   with it and is never reused. A reference to a withdrawn rule should resolve to
   "withdrawn, and here is why", never to a different rule that happens to have inherited
   the number.
3. **Related rules cross-reference each other by number** instead of sitting next to each
   other. Rule 6 says how it differs from rule 3; that costs one sentence and survives
   any amount of appending.

**This is the same lesson as locked decision 5.** An identifier that reorders under you is
not an identifier — that is exactly why `raw.product_id` is not a product identity, and
the reasoning does not stop applying because the identifiers in question are ours. Citing
a rule by name as well as number is still good practice and much of the repo does it, but
it is a courtesy to the reader, not the mechanism. The mechanism is that the number never
changes.

1. **A missing day is not an unchanged price.** Never forward-fill a price across a gap
   without an explicit, named, documented rule. Gaps must be visible in the model, not
   smoothed away. This is the highest-risk failure mode in this project.
2. **Match confidence is a first-class column.** Every cross-vendor product match carries
   a tier (e.g. vendor_upc / matched_upc / fuzzy / unmatched). Headline numbers are
   computed from the top tier only. Lower tiers are **flagged and kept**, never deleted,
   and are auditable in the fact table.
3. **An ambiguous parse is excluded from headline numbers, kept, and counted.**
   Where the source text admits two readings and the evidence does not separate them, the
   parse carries `parse_confidence = 'ambiguous'` and the literal reading is retained.

   **Downstream semantics, decided:**
   - **D2 (sale behaviour) and D4 (cross-vendor basket) exclude ambiguous rows from
     headline numbers.** The exclusion is applied at query time, never at load time, and
     every published figure states how many rows it dropped.
   - Ambiguous rows are **never deleted and never silently converted**. They stay in
     `stg_price` with their raw text, so the set remains countable and a later decision
     can re-admit them.
   - A product is not excluded because *some* of its history is ambiguous — only the
     ambiguous rows are. A product whose history is mostly ambiguous will fail the
     existing coverage bars on its own; no separate rule is needed.

   **Why exclusion rather than a confidence tier:** an ambiguous price is not a weaker
   signal, it is possibly wrong by 100×. A tier invites averaging it in, and there is no
   average of $2.98 and $298 that means anything.

   This rule exists because "a bare integer means dollars" was an unevidenced default that
   proved wrong for 66,538 Walmart rows. The same default is still unproven for Galleria,
   so those rows are flagged rather than trusted.

4. **Every published number is reproducible.** Each figure that appears in a writeup or
   dashboard has a committed SQL file that regenerates it. No number exists only in a
   chat message or a notebook cell.

   **Reproducible means reproducible twice.** A query that returns a different answer on
   the same immutable snapshot and the same build is not reproducible, and this is harder
   to notice than a stale number because nothing looks wrong. `any_value()` over a
   non-unique group, and `row_number()` over a partition that is not the true grain, both
   do this — Phase 1 §5.8 found a published figure that moved by 614 between runs of the
   same query. **Any query whose result feeds a published number must impose a total
   order on every tie-break**, and where it aggregates, the partition must be the grain
   the source actually has. On this dataset that is rarely the obvious key: the same
   product appears many times in one day with conflicting prices (Phase 0 B6).

5. **Every published number carries the build stamp it was computed under.**
   Each findings section states the `_build_stamp` `built_utc` and the short sha256 of
   the model sources that produced its numbers, in a line at the top of the section:

   ```
   *Computed under build 2026-08-28T17:48:35Z — models d1f90ee/f6d7345/6d01e90/01ff1a1.*
   ```

   **Why:** `_build_stamp` records only the *current* build. It is a tripwire against
   using a stale model, not an archive, and it cannot retroactively date a number already
   written into a document. Git cannot either — on this project the model fix and the
   section that quotes it have landed in the *same commit* every time, so commit order
   proves nothing about which came first within the session.

   That gap is not hypothetical. §2.6's figures were published from a build predating the
   bare-integer-cents fix and were caught only because §5.5 forced an unrelated recompute;
   §2.2's `basis_rescaled` count matches no state that can now be reconstructed at all —
   its provenance is recorded as **lost, permanently**, not as an open question. This rule
   fixes that forward, not backward: numbers published before it existed have no record
   and never will.

   **Consequences, all of them binding:**
   - A section whose numbers were computed under different builds is **split**, or
     recomputed under one build. One stamp per section, or the stamp means nothing.
   - When a model or macro changes, **every section stamped with an older build is
     re-run before the change is committed**, and the ones that moved are restated with
     the delta shown, not silently overwritten.
   - A number with no stamp is treated as **unverified**, not as correct.
6. **A price row with no product row is excluded from headline numbers, kept, and
   counted.** 878,559 rows (1.22%) in snapshot 1 have a `product_id` matching nothing in
   `product` (Phase 0 E2). They carry a **NULL `product_key`** — not a shared placeholder,
   which is what they had until Phase 1 §5.1 and which silently merged all 878,559 into
   one product.

   **Downstream semantics, decided (Phase 1 §5.9):**
   - **D2 and D4 exclude rows with a NULL `product_key` from headline numbers**, at query
     time, with the dropped count stated. D4's exclusion is **0 additional rows** — an
     orphan has no product row, hence no UPC, hence no GTIN, so it could never reach the
     basket. D2 loses **15,936 sale-flagged rows across 246 product ids**.
   - They are **never deleted and never re-keyed to a placeholder.** They stay in
     `stg_price` with their raw text and a NULL key, so the set stays countable and a
     later decision can re-admit it.
   - **They stay in row-count denominators** where the denominator is "rows we parsed"
     (parse coverage is 100.000% of 71,809,333, orphans included) and are **absent from
     per-vendor denominators**, because they have no vendor. Any per-vendor table must
     say so and state the residual — the vendor rows sum to 70,930,774, not 71,809,333.

   **Why exclusion, and why it is not the same call as rule 3.** An ambiguous price has an
   identity and a doubtful value. An orphan row has a sound value — they parse at 99.999%
   and the median is $5.89, an ordinary grocery price — and **no identity at all**.
   Admitting one to D2 would mean keying a price series on `raw.product_id`, which locked
   decision 5 forbids, `scripts/check_layering.py` blocks mechanically, and upstream has
   announced will change type. The rows are not weak evidence; they are evidence we have
   no owned key for.

   **This is not a permanent verdict.** §5.9 established the cause is upstream, not us:
   `product` holds only the *currently listed* catalogue, so a delisted product's price
   history is orphaned, and 74% of the rows predate a retired `product_id` scheme. If
   upstream ever publishes a product-history table the exclusion should be revisited.

7. **Report the denominator.** Every percentage carries its n. Every exclusion states how
   many rows it dropped and why.
8. **Never report a pass rate for tests that don't exist.** If there are no tests, the
   answer is "0 of 0", not a percentage.
9. **Do not invent numbers.** If you have not run the query, say you have not run the
   query. An estimate must be labelled an estimate.
10. **Volunteer bad news.** If a finding is weaker than it looks, if a number is
    suspicious, if an earlier decision now looks wrong — say so unprompted, immediately,
    before continuing.

## File manifest (mandatory)

`docs/FILES.md` is a living manifest of every file in this repo. It exists so the repo
can be studied later, file by file, by someone who did not write it.

**Rules:**

1. Any commit that creates, renames, moves, or deletes a file **must** update
   `docs/FILES.md` in the same commit. A commit that changes the file tree without
   touching the manifest is incomplete.
2. When a file's *purpose* changes materially, update its entry even if the path didn't
   change.
3. Run `python scripts/check_manifest.py` before reporting any phase complete. It must
   pass. Do not paper over drift by deleting the check.
4. Entries explain **why the file exists and what breaks without it**, not what the code
   literally does line by line. The code already says what it does.
5. Files that are generated, downloaded, or otherwise not authored (data snapshots, build
   output) are listed as a directory-level entry, not one row per file.

## Working style

- Work in phases. Finish a phase, report, wait. Do not run ahead into the next phase.
- Prefer a small number of well-understood models over many clever ones.
- When a design choice has a tradeoff, state both sides and pick one, don't hedge.
- Long-running jobs must be runnable detached (nohup / background) and must log.

## Stack

- Python for ingest
- DuckDB as the analysis engine
- dbt for the modelling layer (staging → intermediate → marts)
- Airflow for scheduled refresh (later phase, not Phase 0)
- Static dashboard, single-page, deployed as a static site

No Kafka. This is a daily batch dataset; streaming infrastructure here would be
decoration.

## Context and handoff

A session ends whether or not the work is finished. What survives is the repository; what is
lost is everything that lived only in the session. These rules exist so the loss is bounded.

1. **Rewrite `.handoff/latest_handoff.md` in full at the end of every completed section, at
   the same time as the commit.** In full, from `.handoff/context_template.md` — not edited
   in place, not appended to. **Never write it under context pressure.** A note written as
   context runs out is written by the version of the session least able to judge what
   matters, and it is the note the next agent will trust most.

2. **Commit at the end of every completed section, before reporting.** Uncommitted work is
   the only thing a lost session actually destroys — the reasoning is recoverable from the
   docs, the diff is not.

3. **The handoff note records where work stopped. It never records what is true.** Ground
   truth is `CLAUDE.md`, the findings docs, the briefs and git history. **Never duplicate a
   standing rule into the handoff note**: two sources will drift, and the drifted copy is
   the one that gets read. A note that restates a rule is worse than one that omits it,
   because it looks authoritative while being stale.

4. **If you notice you are running low on context, say so plainly in your reply, update the
   handoff note, and stop.** Do not attempt to estimate a percentage — a made-up number is
   an invented number like any other (honesty rule 9), and the useful signal is that you
   noticed, not how far along you think you are. Stopping early with a good note costs one
   session. Continuing until context runs out costs the note as well.

`docs/RESUME.md` is the procedure for the agent arriving without context; `AGENTS.md` points
non-Claude agents at it. Neither restates the rules above — they point here.
