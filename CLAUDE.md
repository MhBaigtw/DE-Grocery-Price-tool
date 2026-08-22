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
2. **Snapshot immutability.** Every downloaded copy of the dataset is stored with its
   download timestamp and a sha256 of the archive, and is never modified in place.
   Analysis reads from a snapshot, never from a live download.
3. **Scope is Toronto pickup pricing.** The upstream data is the "in store pickup" price
   for one Toronto neighbourhood. No claim in this project may be phrased as a national,
   provincial, or "Canadian" price without that qualifier attached.
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
timestamp and sha256 per the immutability rule below.

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

## Honesty rules (non-negotiable)

1. **A missing day is not an unchanged price.** Never forward-fill a price across a gap
   without an explicit, named, documented rule. Gaps must be visible in the model, not
   smoothed away. This is the highest-risk failure mode in this project.
2. **Match confidence is a first-class column.** Every cross-vendor product match carries
   a tier (e.g. vendor_upc / matched_upc / fuzzy / unmatched). Headline numbers are
   computed from the top tier only. Lower tiers are **flagged and kept**, never deleted,
   and are auditable in the fact table.
3. **Every published number is reproducible.** Each figure that appears in a writeup or
   dashboard has a committed SQL file that regenerates it. No number exists only in a
   chat message or a notebook cell.
4. **Report the denominator.** Every percentage carries its n. Every exclusion states how
   many rows it dropped and why.
5. **Never report a pass rate for tests that don't exist.** If there are no tests, the
   answer is "0 of 0", not a percentage.
6. **Do not invent numbers.** If you have not run the query, say you have not run the
   query. An estimate must be labelled an estimate.
7. **Volunteer bad news.** If a finding is weaker than it looks, if a number is
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
