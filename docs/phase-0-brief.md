# Phase 0 — Data Reconnaissance

**Build nothing. Model nothing. Answer questions.**

The output of this phase is a single document, `docs/phase-0-findings.md`, containing
real numbers from real queries, plus a go/no-go verdict on each proposed analysis.

Read `CLAUDE.md` first. Every honesty rule in it applies to this phase.

---

## Setup

1. Download both distributions of the dataset (the zipped CSVs and the SQLite file) from
   https://jacobfilipp.com/hammer/ . Record the download timestamp and the sha256 of each
   archive in the findings doc.
2. Also fetch `/hammerdata/hammer-lastupdated.txt` and record what it says. If the last
   update is stale by more than a couple of weeks, **stop and report that first** — it
   changes the viability of the whole project.
3. Load into DuckDB. Do not modify the source files.
4. Every query in this phase gets saved to `analysis/phase0/` as a numbered `.sql` file
   so every number in the findings doc can be regenerated.

---

## Section A — Shape and coverage

A1. Row count of `raw`. Row count of `product`. Full date range of `nowtime`.

A2. Rows per vendor per day, across the whole history. Present as a table or a small
    chart. Identify: (a) the small-basket → full-catalogue transition, (b) every day
    where a vendor is entirely missing, (c) any day with anomalously low volume.

A3. Distinct products per vendor per day. Same treatment.

A4. Total number of missing vendor-days, and the longest consecutive gap per vendor.

A5. Null / blank rate per column, per vendor: `units`, `brand`, `upc`, `sku`,
    `old_price`, `price_per_unit`, `other`.

---

## Section B — Product identity (the make-or-break section)

B1. Confirm the instability of `product.id`: pick 20 products, show that their `id`
    changes day to day. State plainly whether this is confirmed or not.

B2. Is `(vendor, sku)` a stable identity? For a sample of SKUs, check that the same
    `(vendor, sku)` maps to a consistent `product_name` and `units` over time. Report
    the rate at which it does not.

B3. UPC coverage: what fraction of products have a non-blank `upc`, **per vendor**.

B4. **The single most important number in this phase:** how many distinct UPCs appear at
    2 or more vendors? At 3+? At 5+? Break this down by whether the vendors involved are
    in the reliable-UPC group (Metro, Galleria, Save-On-Foods, Walmart) or the
    fuzzy-matched group (Loblaws, No Frills, T&T, Voila).

    Then: how many UPCs appear at 2+ vendors where **all** the vendors involved are in
    the reliable group? That number is the honest ceiling on trustworthy cross-vendor
    comparison. Report it prominently.

B5. Sanity-check the fuzzy matches. Take a sample of 30 UPCs that are shared between a
    reliable-group vendor and a fuzzy-group vendor, and compare the `product_name` and
    `units` on each side. Report roughly how many look like genuinely the same product.
    This is a judgement call — say so, show the sample, don't dress it up as precision.

B6. Duplicate magnitude: rows per `(product_id, date)`. Confirm or refute the upstream
    estimate of ~6,500 affected products per day, and show how it has changed over time.

---

## Section C — Units and price

C1. Unit string parseability. Write a simple parser for `units` targeting canonical
    (quantity, unit) — grams, mL, count. What fraction parses cleanly? Show the 30 most
    common unparseable strings with their counts. Do not silently drop the tail.

C2. `price_per_unit` agreement: for rows where units parse, what fraction of
    `price_per_unit` disagrees with `current_price / parsed_quantity` by more than 1%?
    Per vendor.

C3. Price movement: per `(vendor, sku)`, how many distinct prices were ever observed?
    What fraction of products **never changed price** across their entire observed
    history? If that fraction is very high, several time-series analyses are dead —
    say so.

C4. `old_price` coverage per vendor, and whether the presence of `old_price` agrees with
    `other` containing 'SALE'. Report the disagreement rate both ways. If a vendor
    never populates `old_price`, that vendor is excluded from all sale analysis — name
    which vendors those are.

---

## Section D — Feasibility of each proposed finding

For each of these, produce the specific coverage number and then a **GO** or **NO-GO**
with a one-line reason.

D1. **Price freeze verification (Nov 1 – Feb 5).** For each freeze window in the data
    (2024-25 and 2025-26) and each vendor: how many products have at least 90% daily
    coverage across the full window? How many have zero gaps? If the answer is small for
    the vendors that made the public claim, this finding is not supportable — say so.

D2. **Sale honesty (was the price raised before the sale).** How many distinct sale
    events can be identified — that is, transitions where `old_price` appears — and for
    how many of those do we have at least 14 days of continuous pre-sale price history?
    That intersection is the real sample size.

D3. **Shrinkflation.** How many `(vendor, sku)` pairs show a change in parsed unit size
    over time? Of those, how many hold or raise `current_price` across the change?
    Report the raw count, and eyeball a sample to estimate how many are genuine versus
    parsing artifacts or product relistings.

D4. **Cross-vendor basket comparison.** Using only the reliable-group-only UPC set from
    B4: how many products are available, and do they cover recognisable everyday
    categories (bread, milk, eggs, produce) or only a random long tail? A basket tool
    built on 40 obscure products is not a product.

---

## Section E — Bugs found

Keep a running list of every data defect discovered, with a reproducing query and an
estimate of magnitude. This becomes an upstream bug report — the maintainer explicitly
asks for exactly this.

## Section F — Ergonomics feedback (new)

The maintainer has asked directly for high-impact "ergonomic" changes that would make the
dataset easier to consume. Keep a second, separate list.

This is not a wishlist. Each entry states: the concrete friction encountered during this
audit, how much work it cost to get around, and the smallest upstream change that would
remove it. Ranked by impact, with the reasoning shown.

The obvious candidate to evaluate seriously: a stable product identity column, given that
`product_id` is explicitly not one and is about to change type. If Phase 0 shows
`(vendor, sku)` is stable, say so with the number behind it — that is a concrete,
evidenced proposal rather than an opinion.

Deliver as `docs/upstream-feedback.md`, written to be sent as-is.

## Section G — Snapshot and schema baseline (new)

G1. Record, per snapshot: download timestamp, sha256, the value of
    `hammer-lastupdated.txt`, and the maximum `nowtime` present in the data.

    Report the gap between the last-updated value and the max `nowtime`. This is
    **publication lag**, and it is a different quantity from a scrape gap. Section A4
    must not conflate them: a vendor-day absent from a file we downloaded before it was
    published is not a missing vendor-day.

G2. Write `config/expected_schema.json` capturing the current column names and types of
    `raw` and `product`, including the **current** type of `raw.product_id`.

    Write a check that validates a loaded snapshot against it and exits non-zero on any
    difference. Test it by deliberately corrupting a copy of the schema file and
    confirming the check fails. A check that has never failed has not been tested.

    The maintainer has stated `raw.product_id` will change from string to number. This
    check is the thing that should catch it.

---

## Deliverable

`docs/phase-0-findings.md` containing:

- Dataset provenance (download time, sha256, last-updated value)
- All numbers from sections A–C
- The D1–D4 go/no-go table
- The Section E bug list
- A closing section: **"what this dataset can and cannot support"**, written plainly

Then stop and report. Do not start building the pipeline.
