# Phase 0 — Data Reconnaissance: Findings

**Status:** complete. Nothing was built. No pipeline, no dbt models, no schema.
**Scope:** Toronto "in store pickup" pricing only. Nothing here is a national,
provincial, or "Canadian" price.

Every number below comes from a committed query in [analysis/phase0/](../analysis/phase0/).
Query filenames are cited inline. Where a result is a judgement call rather than a
count, it is labelled as such and the sample is shown.

---

## 0. Dataset provenance

| Item | Value |
|---|---|
| Snapshot id | `20260822T134045Z` |
| Upstream last-updated (`hammer-lastupdated.txt`) | `2026-08-21 21:26:00.11 (Eastern Time)` |
| Checked at | 2026-08-22 13:39 UTC |
| Staleness at download | ~16 hours — **fresh, not stale. Proceeded.** |
| `hammer-5-csv.zip` | 498,288,065 bytes · sha256 `fb2a815ebce28377a530f51bb6a900e9bce19dacfced89619cc2ef37aa0110e8` · downloaded 2026-08-22T13:41:29Z |
| `hammer-3-compressed.zip` | 950,260,692 bytes · sha256 `2da260be76b3e441f632c92b22c0b7ffece495d18f80bf69a0199c6508ad2cc9` · downloaded 2026-08-22T13:42:48Z |
| **Max `nowtime` in the data** | **2026-08-21** |
| **Publication lag** | **0 days** (see G1) |

The SQLite distribution is what was loaded into DuckDB. Both archives were downloaded,
hashed, and stored read-only; the snapshot is never modified in place.

### G1. Publication lag is not a scrape gap

Upstream publication is becoming intermittent, so two quantities must be kept apart:

- **scrape gap** — the scraper did not observe a vendor on a day the published file
  otherwise covers. A real hole.
- **publication lag** — the scrape happened, but the file we downloaded was published
  before that day's data was added. Not a hole; a later snapshot will have it.

For this snapshot: upstream last-updated `2026-08-21`, max `nowtime` `2026-08-21`,
**publication lag = 0 days**. All 8 vendors reach the trailing edge (0 days behind).

**A4 is therefore not contaminated.** Recomputing missing vendor-days with a deliberately
generous 3-day trailing exclusion gives byte-identical counts — Walmart 85, Voila 31,
NoFrills 31, Loblaws 29, TandT 26, Galleria 25, Metro 22, SaveOnFoods 22. Every missing
day reported in A4 is a genuine scrape gap, not an unpublished one.

This will not stay true. Once uploads start lagging, the trailing-edge exclusion becomes
load-bearing and A4 must apply it rather than assuming a lag of zero.
*Source: `G1_publication_lag.sql`.*

### G2. Schema baseline and drift check

`config/expected_schema.json` records the current column names, types and positions of
`raw` and `product` — including the **current** `VARCHAR` type of `raw.product_id`, which
upstream has announced will become a number.

`scripts/check_schema.py` validates a loaded snapshot against it and exits non-zero on
any difference. It reports missing columns, unexpected columns, type mismatches, position
drift, and absent tables. It never casts, coerces, or infers around a mismatch.

**The check has been tested by deliberate corruption — 6 of 6 cases behaved as expected**
(`scripts/test_check_schema.py`):

| Case | Result |
|---|---|
| control: unmodified schema passes | PASS (exit 0) |
| `product_id` becomes a number | PASS — `TYPE MISMATCH`, exit 1 |
| expected column dropped | PASS — `UNEXPECTED`, exit 1 |
| expected column added | PASS — `MISSING`, exit 1 |
| column position moved | PASS — `POSITION DRIFT`, exit 1 |
| expected table absent | PASS — `TABLE MISSING`, exit 1 |

The announced `raw.product_id` string→number change is caught precisely:
`[raw.product_id] TYPE MISMATCH - expected BIGINT, found VARCHAR`.

---

## 1. Headline: the number that decides the project

> ### 5,222 UPCs appear at 2+ vendors where every vendor involved is in the reliable-UPC group.
>
> Of those, **4,957 (94.9%)** are actually priced at 2+ reliable vendors on the *same day*
> at least once, and **3,477** have 90+ shared days — enough history to compare.
>
> *Source: `B4_cross_vendor_upc_overlap.sql`, `B4d_co_observation.sql`.*

That is the honest ceiling on trustworthy cross-vendor comparison. It is a real number
and it is big enough to build on — see D4.

---

## 2. Bad news, volunteered up front

Four things contradict either CLAUDE.md or the upstream documentation. None of them were
worked around silently.

### 2.1 The small-basket transition date in CLAUDE.md is wrong by a month

CLAUDE.md ("Known contamination") and the upstream docs both say the small basket ran
**Feb 28 – Jul 10/11 2024**. The data says the regime change is **2024-06-10/11**:

| Date | Rows, all vendors | × previous day |
|---|---|---|
| 2024-06-09 | 1,226 | 1.02 |
| **2024-06-10** | **8,703** | **7.10** |
| **2024-06-11** | **87,735** | **10.08** |
| 2024-06-12 | 64,592 | 0.74 |
| 2024-07-10 | 51,680 | 0.87 |
| 2024-07-11 | 44,161 | 0.85 |

*Source: `A2b_basket_transition.sql`.*

July 10/11 shows a mild dip, not a regime change. **Every breadth metric should use
2024-06-11 as the cutoff, not 2024-07-11.** All full-catalogue analysis in this document
uses `>= 2024-06-11`. CLAUDE.md should be corrected.

### 2.2 Locked decision #5's stated premise is false in this snapshot

CLAUDE.md locks: *"The supplied row ID is not a product identity. `product.id` /
`raw.product_id` change daily."* The upstream docs say the same.

**In this snapshot the id does not change at all.** Across all 8 vendors, 100% of
(vendor, sku) series observed on 30+ days carry exactly **one** `product_id`. A sample
of 20 products observed 441–756 days each carried a single id throughout.

The reason is structural: `product.id` is literally `vendor || sku` for every product
with a non-blank sku (161,300 of 187,028 rows). Where sku extraction failed, the id
falls back to an opaque base64-style hash — and those are stable too (7,339 series,
100% single-id). The two id shapes coexist across the whole date range; this is a
fallback, not a scheme change over time.

*Source: `B1_product_id_stability.sql`, `B1b_id_scheme_change.sql`.*

**Important limit on that claim:** I have **one** snapshot. Stability *within* a snapshot
is not stability *across* snapshots. I cannot test whether the next download reuses these
ids, and I have not tested it. Do not rely on cross-snapshot id stability on the strength
of this finding.

The locked decision's *conclusion* — derive product identity explicitly, with a confidence
tier — remains correct and should stand. Only its stated reason is wrong. Flagging rather
than working around it, per the rule.

### 2.3 Shrinkflation (D3) — claim narrowed after challenge

An earlier draft of this document said shrinkflation was "structurally impossible". That
**overclaimed**, and the corrected argument is set out in full in D3 below. The short
version: it is structurally impossible for the 86.2% of the catalogue that has a sku, and
merely *empirically absent* for the other 13.8%, where it would be representable. The
practical verdict (NO-GO) is unchanged; the reasoning is now narrower and falsifiable.

*Source: `B2b_vendor_sku_uniqueness_caveat.sql`, `D3_shrinkflation.sql`,
`F4_d3_claim_boundary.sql`.*

### 2.4 Section B2 as briefed cannot be answered with evidence

B2 asks whether `(vendor, sku)` maps to a consistent `product_name` and `units` over
time. The measured answer is 0.00% unstable across all 161,300 keys — but that result is
**tautological**, for the reason in 2.3: the table cannot represent an inconsistency.
Reporting "0% unstable" as evidence of a stable key would be false precision.

What can honestly be said: `(vendor, sku)` is a *usable* identity because it is unique
and total within the catalogue — not because it was observed to be stable over time.

---

## 3. Section A — Shape and coverage

### A1. Shape

| Metric | Value |
|---|---|
| `raw` rows | **71,809,333** |
| `product` rows | **187,028** |
| Vendors | 8 |
| Date range (`nowtime`) | **2024-02-28 → 2026-08-21** |
| Distinct dates present | **887** |
| Calendar days in span | 906 |
| Rows with unparseable/NULL `nowtime` | **8** (see E1) |

`nowtime` is a date-only string (`YYYY-MM-DD`), not a timestamp — there is no
intra-day resolution. *Source: `A1_shape_and_date_range.sql`.*

### A2 / A3. Rows and distinct products per vendor per day

Full monthly series in `A2_rows_per_vendor_per_day.sql` and
`A3_distinct_products_per_vendor_per_day.sql`.

- **(a) Transition:** 2024-06-11 (see 2.1). Pre-transition each vendor contributes
  ~85–265 rows/day; post-transition ~3,000–15,000.
- **(b) Missing vendor-days:** see A4.
- **(c) Anomalously low volume:** measured as a day whose distinct-product count is below
  50% of that vendor's trailing-28-day median. The threshold is a judgement call, stated
  so it can be changed; 25% and 10% given for sensitivity.

| Vendor | Present days | <50% of median | <25% | <10% | % of days |
|---|---|---|---|---|---|
| Loblaws | 778 | **47** | 28 | 17 | 6.04% |
| NoFrills | 778 | **36** | 24 | 17 | 4.63% |
| Voila | 774 | 23 | 1 | 1 | 2.97% |
| Metro | 779 | 11 | 5 | 2 | 1.41% |
| Walmart | 716 | 10 | 4 | 2 | 1.40% |
| TandT | 782 | 10 | 8 | 8 | 1.28% |
| Galleria | 782 | 5 | 1 | 0 | 0.64% |
| SaveOnFoods | 670 | 1 | 0 | 0 | 0.15% |

*Source: `A2c_partial_extract_days.sql`.*

**These partial days are more dangerous than missing days.** The vendor is present, so a
naive coverage check counts the day as good, while most of the catalogue is absent.

### A4. Missing vendor-days and longest gaps

Expected span runs from each vendor's first observed date to 2026-08-21.

| Vendor | First observed | Expected days | Missing | % missing | Longest gap |
|---|---|---|---|---|---|
| Walmart | 2024-03-04 | 901 | **85** | 9.43% | **49 days** |
| NoFrills | 2024-02-28 | 906 | 31 | 3.42% | 19 |
| Voila | 2024-02-28 | 906 | 31 | 3.42% | 20 |
| Loblaws | 2024-02-28 | 906 | 29 | 3.20% | 19 |
| TandT | 2024-02-28 | 906 | 26 | 2.87% | 19 |
| Galleria | 2024-02-28 | 906 | 25 | 2.76% | 19 |
| SaveOnFoods | **2024-09-28** | 693 | 22 | 3.17% | 19 |
| Metro | 2024-02-28 | 906 | 22 | 2.43% | 19 |

**Total missing vendor-days: 271.**

> **A 19-day dataset-wide blackout runs 2025-08-11 → 2025-08-29.** No vendor reported at
> all. Every vendor's "longest gap" of 19 days is this one event. Any series crossing
> August 2025 has a three-week hole in it, and per honesty rule #1 that hole must stay
> visible.

Walmart is additionally absent 2025-08-11 → 2025-09-28 (49 days) and 2026-03-15 →
2026-04-09 (26 days). **Save-On-Foods does not exist before 2024-09-28** — the "8 vendors
since Feb 2024" framing is wrong; there were 6 at the start, 7 from 2024-03-04.

*Source: `A4_missing_vendor_days.sql`, `A4b_gap_windows.sql`.*

### A5. Null / blank rates

Product-level (denominator = product rows for that vendor):

| Vendor | Products | units | brand | upc | sku | detail_url |
|---|---|---|---|---|---|---|
| Galleria | 10,697 | 1.05% | **100.00%** | 13.77% | 7.39% | 7.39% |
| Loblaws | 31,688 | 5.42% | 9.36% | **75.97%** | 4.87% | 4.87% |
| Metro | 26,311 | 2.51% | 7.55% | 25.18% | 18.95% | 18.95% |
| NoFrills | 24,398 | 3.44% | 5.69% | **68.27%** | 5.95% | 5.95% |
| SaveOnFoods | 16,158 | 0.01% | 10.61% | 2.51% | 0.24% | 0.24% |
| TandT | 13,542 | 7.12% | **100.00%** | **97.77%** | 12.97% | 12.97% |
| Voila | 26,320 | 2.85% | **99.19%** | **95.11%** | 6.00% | 6.00% |
| Walmart | 37,914 | 0.66% | 32.48% | **70.88%** | 35.83% | 35.83% |

Observation-level (denominator = price rows for that vendor):

| Vendor | Price rows | old_price | price_per_unit | other | current_price |
|---|---|---|---|---|---|
| Galleria | 5,892,146 | 99.08% | **100.00%** | 64.47% | 0.00% |
| Loblaws | 14,013,669 | 81.47% | 0.00% | 64.79% | 0.00% |
| Metro | 8,203,156 | 70.47% | 0.00% | **99.99%** | 0.00% |
| NoFrills | 11,024,382 | 86.02% | 0.00% | 71.41% | 0.00% |
| SaveOnFoods | 7,093,027 | 66.93% | 3.32% | 83.16% | 0.00% |
| TandT | 5,393,781 | 93.81% | **100.00%** | 99.22% | 0.00% |
| Voila | 12,937,809 | 80.95% | 0.00% | 77.07% | 0.00% |
| Walmart | 6,372,804 | 88.47% | 25.56% | 47.30% | 0.00% |

Consequences worth naming now:

- **Brand is unusable for Galleria, T&T and Voila** (≥99% blank).
- **`price_per_unit` does not exist for Galleria or T&T** (100% blank) — they are
  excluded from C2 entirely.
- **`other` is 99.99% blank for Metro** — Metro cannot be sale-flagged via `other`.

*Source: `A5_null_blank_rates.sql`.*

---

## 4. Section B — Product identity

### B1. `product.id` stability — **refuted**, see §2.2.

### B2. `(vendor, sku)` stability — **question is unanswerable as briefed**, see §2.4.

### B3. UPC coverage per vendor

| Tier | Vendor | Products | With UPC | % catalogue | % of price rows |
|---|---|---|---|---|---|
| Vendor-direct | SaveOnFoods | 16,158 | 15,752 | **97.49%** | 97.97% |
| Vendor-direct | Galleria | 10,697 | 9,224 | **86.23%** | 92.48% |
| Vendor-direct | Metro | 26,311 | 19,687 | **74.82%** | 89.10% |
| Walmart-matched | Walmart | 37,914 | 11,042 | 29.12% | 82.31% |
| Fuzzy | NoFrills | 24,398 | 7,741 | 31.73% | 47.05% |
| Fuzzy | Loblaws | 31,688 | 7,614 | 24.03% | 37.41% |
| Fuzzy | Voila | 26,320 | 1,288 | 4.89% | 8.16% |
| Fuzzy | TandT | 13,542 | 302 | **2.23%** | 3.62% |

Catalogue % and price-row % differ a lot because UPC-bearing products are observed far
more often than the long tail. Both are reported; use the one that matches the question.

*Source: `B3_upc_coverage.sql`.*

### B4. Cross-vendor UPC overlap — the headline

UPC values arrive at lengths 4–14. An 11-digit value is almost always a UPC-A with the
leading zero stripped, so joining on the raw string misses real matches. Values are
normalised to **GTIN-14** (strip non-digits, left-pad to 14) and require ≥11 digits.
Zero-padding rescued **5,050** GTINs that the raw-string join would have split.

| Measure | Count |
|---|---|
| Distinct GTINs (≥11 digits) | 44,687 |
| At **2+** vendors | 13,336 |
| At **3+** vendors | 6,477 |
| At **5+** vendors | 2,069 |
| **At 2+ vendors, ALL reliable group** | **5,222** |
| At 3+ vendors, all reliable | 1,501 |
| At 4+ vendors, all reliable | 91 |
| At 2+ vendors, all fuzzy | 2,485 |
| At 2+ vendors, mixed tiers | 5,629 |

By vendor count and composition:

| Vendors | GTINs | Reliable-only | Fuzzy-only | Mixed |
|---|---|---|---|---|
| 1 | 31,351 | 31,008 | 343 | 0 |
| 2 | 6,859 | 3,721 | 2,485 | 653 |
| 3 | 2,780 | 1,410 | 0 | 1,370 |
| 4 | 1,628 | 91 | 0 | 1,537 |
| 5 | 1,503 | 0 | 0 | 1,503 |
| 6+ | 566 | 0 | 0 | 566 |

**No GTIN reaches 5+ vendors without involving a fuzzy-matched vendor.** Any "compare
across 5 grocers" claim is a fuzzy-tier claim by construction.

Largest reliable-only overlapping pairs: Metro–SaveOnFoods 1,831; Metro–Walmart 968;
SaveOnFoods–Walmart 594; Galleria–Metro 135; Galleria–Walmart 122; Galleria–SaveOnFoods 71.

The largest 2-vendor overlap overall is **Loblaws–NoFrills at 2,485** — both fuzzy-tier,
and both Loblaw-owned banners, so it is neither reliable nor a comparison between
independent competitors.

#### A judgement call inside B4: PLU produce codes

Excluding <11-digit codes drops 485 short codes that appear at 2+ vendors (127 of them
reliable-only). Inspection shows these are **not junk** — they are PLU produce codes
(`4312` Eddoes, `40174` Granny Smith Apples, `46640` Tomato On The Vine). PLU is a
genuine cross-vendor standard, so these are real matches for loose produce.

They are excluded from the 5,222 because a PLU identifies a *commodity*, not a package,
and its price basis (per lb / per each) is not comparable to a packaged GTIN without
extra work. **This is a judgement call, and it costs real produce coverage.** Revisit it
if the basket needs fresh produce.

*Source: `B4_cross_vendor_upc_overlap.sql`, `B4b_normalisation_sensitivity.sql`,
`B4c_junk_upc_false_matches.sql`.*

### B4d. Co-observation — the stricter test

A shared UPC is only useful if both vendors priced it on the same days. Of the 5,222
reliable-only GTINs (full-catalogue era only):

| Co-observed days | GTINs |
|---|---|
| 0 (never comparable) | 265 |
| 1–29 | 691 |
| 30–89 | 789 |
| 90–179 | 757 |
| 180–364 | 1,160 |
| **365+** | **1,560** |

4,957 (94.9%) have at least one co-observed day. *Source: `B4d_co_observation.sql`.*

### B5. Fuzzy-match sanity check — **judgement call, not a metric**

30 GTINs shared between a reliable-group and a fuzzy-group vendor, selected
deterministically by hash (not cherry-picked). Full side-by-side sample in
`B5_fuzzy_match_sample.sql`.

My eyeball verdict, offered as exactly that:

| Verdict | Count |
|---|---|
| Clearly the same product | **26 / 30** |
| Clearly different | **1 / 30** |
| Ambiguous | **3 / 30** |

The clear miss: GTIN `00068100907155` — Metro *"Pumpkin Spice Cream Cheese, Limited
Edition, 227g"* vs Loblaws *"Pineapple Cream Cheese Product, 227g"*. Same size, different
flavour: a wrong match.

The three ambiguous: a Ristorante pizza variety ("Pepperoni, Ham And Mushroom" vs
"Speciale"), a sprouted bread ("Whole Grain" vs "Soft Wheat"), and Mizkan sushi vinegar
("Sushi Vinegar" vs "Sushi **Seasoned** Vinegar" — plain and seasoned rice vinegar are
different products).

**Do not read this as "87% accurate."** n=30, one assessor, no ground truth. It is
consistent with the upstream warning that fuzzy UPCs contain errors, and it is a reason
to keep fuzzy matches flagged rather than promoted — not a calibrated error rate.

Two matches were correct on product but **disagreed on units in kind**: `1un` vs `25g`
(gravy mix) and `6un` vs `202g` (Twinkies). Unit disagreement is not by itself evidence
of a bad match.

### B6. Duplicate magnitude

Upstream estimated ~6,500 affected products/day as of Nov 2024. **Confirmed almost
exactly — and it has roughly doubled since.**

| Month | Mean duplicated products/day | Surplus rows | % of product-days | Duplicates with *conflicting* price |
|---|---|---|---|---|
| 2024-06 | 4,263 | 168,568 | 11.84% | 2,143 |
| **2024-11** | **6,529** | 273,941 | 8.24% | 619 |
| 2025-06 | 6,872 | 278,267 | 7.89% | 1,157 |
| 2025-11 | 13,014 | 554,131 | 15.85% | 4,827 |
| 2026-03 | 11,212 | 436,384 | 13.56% | 7,301 |
| **2026-07** | **14,189** | 580,335 | 15.60% | **9,025** |

Per vendor, full-catalogue era:

| Vendor | Mean dup products/day | Worst single product-day | Product-days with conflicting price |
|---|---|---|---|
| Voila | 2,614 | 8 | 164 |
| Metro | 1,564 | **1,062** | 5,104 |
| Loblaws | 1,470 | 437 | **49,329** |
| NoFrills | 1,322 | 280 | 1,329 |
| SaveOnFoods | 805 | 16 | 1,083 |
| Walmart | 625 | 110 | 14,026 |
| TandT | 158 | 6 | 2,388 |
| Galleria | 97 | 33 | 1,714 |

The conflicting-price cases matter most: those cannot be deduplicated by `DISTINCT`,
because the duplicate rows disagree about the price. A deliberate, documented tie-break
rule will be required. One Metro product appeared **1,062 times in a single day**.

*Source: `B6_duplicate_rows.sql`.*

---

## 5. Section C — Units and price

### C1. Unit-string parseability

A deliberately simple parser to canonical (quantity, unit) in grams / millilitres /
count. Handles `500g`, `1.36kg`, `2 l`, `250 millilitre`, `6x93.0ml`, `93ML*6`,
`4 per pack`, `1ea`. Conversions: kg×1000, lb×453.592, oz×28.3495, l×1000, floz×29.5735.

| Vendor | Products with units | Parsed | % | mass | volume | count |
|---|---|---|---|---|---|---|
| SaveOnFoods | 16,157 | 16,155 | **99.99%** | 10,269 | 3,335 | 2,551 |
| Voila | 25,570 | 25,565 | 99.98% | 16,773 | 7,246 | 1,546 |
| Loblaws | 29,970 | 29,754 | 99.28% | 20,566 | 7,716 | 1,472 |
| NoFrills | 23,559 | 23,359 | 99.15% | 16,965 | 5,716 | 678 |
| Metro | 25,650 | 25,157 | 98.08% | 16,570 | 6,591 | 1,996 |
| Galleria | 10,585 | 10,062 | 95.06% | 7,889 | 2,056 | 117 |
| TandT | 12,578 | 10,749 | 85.46% | 8,973 | 1,712 | 64 |
| **Walmart** | 37,665 | 19,352 | **51.38%** | 13,102 | 4,810 | 1,440 |

**Overall: 160,153 of 181,734 products with a units string parse = 88.12%.**
Against all 187,028 products (5,294 have blank units): **85.63%**.

Most common unparseable strings (full 30 in the query):

| units | Products | Vendors |
|---|---|---|
| `error` | **409** | Walmart, NoFrills, Voila, Loblaws |
| `ea` | 246 | Galleria |
| `bottle` | 138 | Walmart |
| `sold in singles` | 127 | Walmart |
| `sold individually` | 112 | Walmart, Metro |
| `lb` | 84 | Galleria, TandT |
| `cans` / `can` | 141 | Walmart |
| `current price: lb` | 59 | Galleria |
| `Cold` / `cold` | 92 | TandT |
| `perfect every time™` | 49 | Walmart |
| `shelf stable`, `casein-free`, `raw`, `15x20cm` | ~120 | Walmart |
| `60gx6`, `250mlx6`, `185gx4`, `330mlx6` | ~116 | TandT |

Two distinct causes, worth separating:

- **Walmart's `units` field contains marketing copy**, not size — `perfect every time™`,
  `shelf stable`, `casein-free`, `15x20cm`. This is an upstream extraction defect and is
  why Walmart sits at 51%, not a parser weakness.
- **T&T uses a trailing-multiplier form** (`60gx6`) my parser does not handle. That is a
  parser gap, ~116 products, cheap to fix later.

*Source: `C1_unit_parseability.sql`.*

### C2. `price_per_unit` agreement

Evaluable = both sides computable and the unit classes match. **50,359,399 of 71,809,333
rows (70.13%) are evaluable.** Galleria and T&T are excluded entirely (100% blank
`price_per_unit`); Walmart loses 25.56% of rows the same way.

| Vendor | Evaluable rows | Disagree >1% | % | Disagree >10% | Median abs % diff |
|---|---|---|---|---|---|
| **Walmart** | 2,077,558 | 228,787 | **11.01%** | **9.05%** | 0.14% |
| NoFrills | 10,362,050 | 785,149 | 7.58% | 1.36% | 0.15% |
| Metro | 6,933,602 | 466,814 | 6.73% | 2.26% | 0.14% |
| Loblaws | 13,017,411 | 802,242 | 6.16% | 1.72% | 0.12% |
| Voila | 12,485,532 | 382,853 | 3.07% | 0.27% | 0.13% |
| SaveOnFoods | 5,483,246 | 138,687 | 2.53% | 0.09% | 0.12% |

**This is better than CLAUDE.md implies.** Median disagreement is ~0.13% — consistent
with rounding, not corruption. CLAUDE.md's "not trustworthy" is directionally right but
overstated for six vendors. **Walmart is the genuine problem:** 9.05% of its evaluable
rows are off by more than 10%, which is not rounding.

Recommendation: keep `price_per_unit` as a cross-check, not a source of truth, and treat
Walmart's separately. *Source: `C2_price_per_unit_agreement.sql`.*

### C3. Price movement — **time-series analysis is viable**

Per (vendor, sku), full-catalogue era, ≥30 observed days. n = 142,364 series.

| Vendor | Series | Mean days | Never changed | % never changed | Median distinct prices |
|---|---|---|---|---|---|
| **Galleria** | 9,824 | 583 | 4,736 | **48.21%** | 2.0 |
| Voila | 21,156 | 505 | 4,648 | 21.97% | 3.0 |
| Walmart | 15,660 | 306 | 3,146 | 20.09% | 3.0 |
| Loblaws | 28,240 | 405 | 4,195 | 14.85% | 4.0 |
| TandT | 11,224 | 463 | 1,658 | 14.77% | 3.0 |
| NoFrills | 21,828 | 405 | 3,008 | 13.78% | 4.0 |
| Metro | 19,721 | 316 | 1,881 | 9.54% | 4.0 |
| SaveOnFoods | 14,711 | 442 | 743 | **5.05%** | 6.0 |

**Overall: 24,015 of 142,364 (16.87%) never changed price. 83.13% moved at least once;
56,172 (39.5%) took 5+ distinct prices.**

| Distinct prices | Series | % |
|---|---|---|
| 1 (flat) | 24,015 | 16.87% |
| 2 | 23,936 | 16.81% |
| 3–4 | 38,241 | 26.86% |
| 5–9 | 45,537 | 31.99% |
| 10–19 | 10,462 | 7.35% |
| 20+ | 173 | 0.12% |

This is the good news of Section C: **the "everything is flat" failure mode did not
happen.** Galleria is the one vendor where nearly half of products never move — treat
Galleria price-dynamics claims with care. *Source: `C3_price_movement.sql`.*

### C4. `old_price` coverage and sale-flag agreement

Sale signal in `other` = contains `sale` or `rollback` (Walmart's markdown word).

| Vendor | Price rows | With old_price | % | `other` says sale | old_price but no flag | flag but no old_price |
|---|---|---|---|---|---|---|
| SaveOnFoods | 7,093,027 | 2,345,653 | 33.07% | 0 | 100.00% | — |
| Metro | 8,203,156 | 2,421,984 | 29.53% | 0 | 100.00% | — |
| Voila | 12,937,809 | 2,465,274 | 19.05% | 2,434,593 | 1.75% | 0.51% |
| Loblaws | 14,013,669 | 2,596,818 | 18.53% | 3,215,741 | 4.30% | **22.72%** |
| NoFrills | 11,024,382 | 1,541,523 | 13.98% | 1,444,302 | 6.83% | 0.56% |
| Walmart | 6,372,804 | 734,937 | 11.53% | 486,052 | **34.33%** | 0.70% |
| TandT | 5,393,781 | 333,846 | 6.19% | 0 | 100.00% | — |
| **Galleria** | 5,892,146 | **54,369** | **0.92%** | 0 | 100.00% | — |

**No vendor never populates `old_price`** — the brief anticipated some might. But:

- **Metro, SaveOnFoods, T&T and Galleria never populate a sale word in `other`.** For
  them the cross-check is impossible; their 100% "old_price but no flag" is an artifact
  of that, not a disagreement.
- **Galleria at 0.92% is effectively unusable for sale analysis** and should be excluded
  in practice even though it is not literally empty.
- **Loblaws: 22.72% of sale flags (730,582 rows) carry no `old_price`.** These are the
  multibuy format (`sale\n$3.50 MIN 2`), which has no struck-out single-unit price.
  Loblaws sale counts based on `old_price` alone will undercount by roughly a fifth.
- **Walmart: 34.33% of old_prices have no sale flag** — its markdowns are not
  consistently labelled.

*Source: `C4_old_price_and_sale_flag.sql`.*

---

## 6. Section D — Feasibility verdicts

| # | Finding | Coverage number | Verdict |
|---|---|---|---|
| **D1** | Price freeze (Nov 1 – Feb 5) | **2024-25: Metro 474 of 14,288 SKUs (3.32%) at ≥90% coverage; 20 with zero gaps — and the 474 is a frozen/packaged slice, not a sample (F2).** 2025-26: Metro 5,977 (54.23%); **0** with zero gaps, composition unchecked | **NO-GO for 2024-25 · *provisional* GO for 2025-26** |
| **D2** | Sale honesty (price raised pre-sale) | 566,564 events; 279,599 with 14d continuous history; **273,873 after removing E8 price-dirty events (F1)** | **GO** |
| **D3** | Shrinkflation | Structural for the 86.2% with a sku; representable but **0 credible cases in 1,004 pairs** for the rest (F4) | **NO-GO** |
| **D4** | Cross-vendor basket | **3,477** reliable-only GTINs with 90+ shared days; 1,560 with 365+ | **GO** |

### D1 — Price freeze verification

Both freeze windows are 97 days. Metro is the vendor that made the public claim.

| Window | Vendor | SKUs seen | ≥90% coverage | % | Zero gaps | % |
|---|---|---|---|---|---|---|
| 2024-25 | **Metro** | 14,288 | **474** | **3.32%** | **20** | 0.14% |
| 2024-25 | Voila | 13,232 | 11,178 | 84.48% | 4,116 | 31.11% |
| 2024-25 | Loblaws | 19,092 | 16,018 | 83.90% | 4,698 | 24.61% |
| 2024-25 | SaveOnFoods | 11,246 | 8,632 | 76.76% | 5,616 | 49.94% |
| 2024-25 | NoFrills | 17,732 | 11,372 | 64.13% | 625 | 3.52% |
| 2024-25 | TandT | 8,298 | 5,262 | 63.41% | 1,744 | 21.02% |
| 2024-25 | Galleria | 8,663 | 4,312 | 49.77% | 1,636 | 18.88% |
| 2024-25 | Walmart | 11,924 | 4,760 | 39.92% | 751 | 6.30% |
| 2025-26 | Galleria | 9,373 | 9,137 | 97.48% | 4,823 | 51.46% |
| 2025-26 | Voila | 16,692 | 13,501 | 80.88% | 626 | 3.75% |
| 2025-26 | TandT | 8,689 | 5,957 | 68.56% | 3,606 | 41.50% |
| 2025-26 | SaveOnFoods | 11,394 | 7,577 | 66.50% | 984 | 8.64% |
| 2025-26 | **Metro** | 11,022 | **5,977** | 54.23% | **0** | **0.00%** |
| 2025-26 | Walmart | 11,633 | 4,424 | 38.03% | 549 | 4.72% |
| 2025-26 | NoFrills | 16,774 | 4,649 | 27.72% | 1,451 | 8.65% |
| 2025-26 | Loblaws | 22,459 | 5,444 | 24.24% | 2,687 | 11.96% |

**The vendor that made the claim has the worst coverage in the window where the claim
was first made.** 474 SKUs at ≥90% coverage, 20 with no gaps at all, out of a 14,288-SKU
Metro catalogue.

Diagnosed cause: **not** extract failure. Metro was present on **all 97 days** of the
2024-25 window. The problem is per-day catalogue churn — only 351 Metro SKUs appear on
90+ of those days, while 9,052 appear on 60–89 days. Metro's daily extract captures a
rotating subset of its catalogue.

Among the well-covered SKUs that do exist, the share holding a flat price all window was
15.19% (Metro 2024-25) and 20.66% (Metro 2025-26) — but with n=474 and known gaps, the
2024-25 figure should not be published.

**Verdict: the 2024-25 Metro freeze claim is not verifiable at a defensible sample size.
Say so plainly rather than reporting 15.19% of 474.** The 2025-26 window is workable at
n=5,977, with the caveat that no Metro SKU has a gapless record.

*Source: `D1_price_freeze_coverage.sql`, `D1b_metro_freeze_diagnosis.sql`.*

### D2 — Sale honesty

A sale event is a transition where `old_price` goes absent → present for a (vendor, sku);
consecutive sale days are one event. "Continuous history" means a row on **every one** of
the 14 calendar days before the event — not 14 rows scattered across a month.

| Vendor | Sale events | With 14d continuous history | % | With ≥10 days | SKUs with any sale |
|---|---|---|---|---|---|
| SaveOnFoods | 111,138 | **79,350** | 71.40% | 96,467 | 13,619 |
| Voila | 105,328 | 66,908 | 63.52% | 92,237 | 16,512 |
| Loblaws | 95,936 | 43,253 | 45.09% | 75,850 | 18,893 |
| NoFrills | 87,953 | 38,218 | 43.45% | 67,494 | 13,877 |
| Metro | 110,604 | 23,472 | **21.22%** | 65,060 | 16,955 |
| TandT | 28,220 | 18,944 | 67.13% | 23,667 | 6,455 |
| Walmart | 25,524 | 8,031 | 31.46% | 15,048 | 10,181 |
| Galleria | 1,861 | 1,423 | 76.46% | 1,574 | 540 |

**Total: 566,564 events, 279,599 (49.35%) evaluable.** Comfortably the largest usable
sample in the phase. **See F1: after excluding events whose prices are non-scalar (E8),
the usable figure is 273,873** — that, not 279,599, is the number to quote for any
analysis that needs numeric prices. Metro's low rate is the same catalogue-churn problem as D1.

Caveat carried forward from C4: this counts `old_price` transitions only, so it
**undercounts Loblaws sales by ~22.7%** (multibuy offers with no struck-out price).

*Source: `D2_sale_events_with_history.sql`.*

### D3 — Shrinkflation: **NO-GO**

#### The argument, stated so it can be attacked

> Shrinkflation requires observing one product's package size fall while its price holds
> or rises. This dataset cannot support that, for two different reasons in two different
> populations. **(a)** For the 161,300 products that carry a sku — 86.2% of the catalogue
> — `product.id` is exactly `vendor||sku` and is unique, so the `product` table can
> physically store only one `units` string per sku. A size revision must overwrite the
> old value; no within-sku size history can exist, and we measure zero (vendor, sku)
> pairs holding more than one units value. This part is structural: it follows from the
> key, not from the data. **(b)** For the 25,728 blank-sku products — 13.8% — the id is
> instead a hash of `concatted`, which embeds the unit string (confirmed for 94.75% of
> populated cases). A size change there *would* mint a second row, so size history **is**
> representable in this population. We tested it: 1,004 unit-differing row pairs share a
> vendor and product name, of which **838 (83.5%) have overlapping observation windows** —
> two sizes on the shelf at once, not a change — and only 166 are sequential. Inspecting
> those 166 shows they are dominated by Walmart's `units`/product-name field misalignment
> (E4), the literal `units='error'` bug (E3), same-name different-brand collisions, and
> non-food items. None is a credible size change. So for population (b) the claim is not
> "impossible" but "representable, and empirically zero out of 1,004."

**What would falsify this.** For (a): a single (vendor, sku) with two distinct `units`
values — we measure zero, and the key makes it unrepresentable, so this is the strong
half. For (b): a blank-sku name-group whose two sizes are sequential, food, same brand,
and price-consistent — we found none among 166 sequential candidates, but this half rests
on a sample judgement and is the half worth attacking.

**What we did not test, and cannot from one snapshot.** Whether upstream reissues a *new
sku* when a package shrinks. That is the most likely real-world mechanism, and it is
invisible here: the two skus look like two unrelated products, and we have no second
snapshot to compare against. We tried searching blank-sku `concatted` values for other
products' sku strings and abandoned it — quadratic over 161,300 × 25,728, and short
numeric skus collide with digits inside product names badly enough to swamp any signal.

**So the honest claim is narrower than "impossible":** *this snapshot contains no usable
unit-size history, and the mechanism that would most plausibly carry one (sku reissue) is
untestable from a single snapshot.*

#### The proxy, and why it does not rescue the finding

The only available proxy for population (a) is *same vendor + same product name +
different size + different sku*: **4,863 name-groups covering 12,767 SKUs**. Eyeballing a deterministic sample of 20
(shown in the query output), essentially all are **concurrent shelf sizes, not shrinkage**:

- `original all purpose flour` — 2.5kg | 5kg | 10kg
- `reduced-sodium soy sauce` — 148ml | 296ml | 591ml
- `genoa salami` — 85g | 100g | 150g
- `super golden basmati rice, 10 lbs` — 4.535kg | 4.536kg *(a rounding artifact)*

At most one candidate in 20 looked like a possible genuine shrink (`medium salsa`
437ml → 430ml), and even that is ambiguous against a third size of 650ml. **This is a
judgement call on a sample of 20, and it is not a measurement.**

**Recommendation: drop shrinkflation from Phase 1 scope, and start the experiment that
would answer it.** Detecting size changes requires comparing snapshots taken months
apart. We cannot do that retroactively — one snapshot, and upstream overwrites — but we
*can* start now: `fetch_snapshot.py` already stores immutable, hashed snapshots, so
diffing `(vendor, sku) -> units` across two snapshots months apart is a small, concrete
experiment rather than an aspiration. Revisit in a year. That is a Phase 1+ decision, not
a Phase 0 finding.

*Source: `D3_shrinkflation.sql`, `B2b_vendor_sku_uniqueness_caveat.sql`.*

### D4 — Cross-vendor basket: **GO**

Starting from the 5,222 reliable-only GTINs and requiring 90+ co-observed days:

| Bar | GTINs |
|---|---|
| B4 reliable-only | 5,222 |
| **≥90 shared days** | **3,477** |
| ≥365 shared days | 1,560 |

Category coverage of the 3,477 (crude keyword match on product name — a coverage probe,
not a taxonomy):

| Category | GTINs |
|---|---|
| Dairy | 864 |
| Beverages | 680 |
| Produce | 612 |
| Pantry staples | 312 |
| Meat & fish | 261 |
| Bread & bakery | 172 |
| Eggs | 38 |
| Other / long tail | 1,421 |

**This is not 40 obscure products.** It is a recognisable everyday basket. Concrete
examples with long shared histories:

| Product | Shared days | Vendors |
|---|---|---|
| Natrel Fine-filtered 2% Milk, 2 L | 768 | Galleria, Walmart, Metro |
| Natrel Fine-filtered 1% Milk, 4 L | 757 | Walmart, Metro, Galleria |
| Honey & Oatmeal Bread, 600 g | 743 | SaveOnFoods, Walmart, Metro |
| Eggs 2 Go Omega 3 Hard Boiled, 6 Pack | 740 | Walmart, Metro, SaveOnFoods |
| NESCAFÉ Rich Colombian Instant Coffee 100 g | 734 | Galleria, Walmart, Metro |
| Mexicana 3 Cheese Blend Shredded, 320 g | 732 | Walmart, Metro, SaveOnFoods |

Two limits to state whenever this is published:

- The basket spans **Metro, Galleria, Save-On-Foods and Walmart only**. Loblaws, No
  Frills, Voila and T&T cannot enter it at the reliable tier. A "which grocer is
  cheapest" claim from this basket covers four of eight vendors.
- **Eggs are thin (38 GTINs)** and produce is mostly packaged, because loose produce
  lives in the excluded PLU codes.

*Source: `D4_basket_feasibility.sql`.*

---

## 7. Section E — Bug list (for upstream)

Ordered by severity. Each has a reproducing query.

### E8. `current_price` is not always a scalar price — **HIGH**

`current_price` sometimes holds a **multibuy offer** (`2/$7.00`) or a **per-weight rate**
(`1.99/100g`), and sometimes a raw HTML fragment with embedded newlines.

**1,303,020 rows (1.81% of all rows) will not cast to a number.**

| Shape | Rows |
|---|---|
| Multibuy `N/$X.XX` | 679,923 |
| Per-weight `X.XX/100g` | 360,365 |
| Other (embedded newlines / `$13.49\n…sale…`) | 262,732 |

| Vendor | Non-scalar rows | % of vendor rows |
|---|---|---|
| **Metro** | 623,001 | **7.59%** |
| **SaveOnFoods** | 458,511 | **6.46%** |
| TandT | 77,351 | 1.43% |
| Loblaws | 47,720 | 0.34% |
| Walmart | 11,830 | 0.19% |

Why this is the worst bug in the list: it is **silent** (`try_cast` returns NULL, no
error), it is **concentrated in Metro and Save-On-Foods** — two of the three
vendor-direct-UPC vendors that B4 and D4 depend on — and the obvious fix is wrong:
stripping `2/$7.00` to `7.00` gives double the true unit price of `$3.50`.

Peaked at 3.16% of rows in Nov 2024; ~1.0–1.35% through 2026.
*Query: `E8_nonscalar_current_price.sql`.*

### E2. 878,559 raw rows do not join to any product — **HIGH**

**1.22% of all price rows** have a `product_id` with no matching `product.id`: a price
with no vendor, name, sku or UPC. Persistent, not a one-off.

| Apparent vendor (from id prefix) | Unjoined rows | Distinct ids | Days affected |
|---|---|---|---|
| **Metro** | **637,508** | 6,906 | 884 |
| Walmart | 56,125 | 1,742 | 795 |
| Galleria | 46,254 | 145 | 881 |
| Loblaws | 43,270 | 302 | 731 |
| NoFrills | 32,413 | 222 | 732 |
| TandT | 23,726 | 217 | 778 |
| Voila | 21,120 | 102 | 832 |
| SaveOnFoods | 18,064 | 966 | 671 |

Metro alone loses 637K rows across 884 of 887 days.

A related, smaller defect: on **2026-02-01** a handful of Loblaws `product_id` values are
malformed URL slugs (`Loblawshoney-bunches-of-oat-honey-roasted-cere`,
`Loblawsready-to-serve-chicke`), suggesting a truncated field in that day's extract.

*Query: `E2_join_coverage.sql`, `E2b_unjoined_profile.sql`.*

### E9. 19-day dataset-wide blackout — **HIGH**

**2025-08-11 → 2025-08-29: no vendor reported at all.** Walmart extends to 2025-09-28
(49 days) and is out again 2026-03-15 → 2026-04-09 (26 days). Total 271 missing
vendor-days. *Query: `A4b_gap_windows.sql`.*

### E10. Documented small-basket end date is wrong by a month — **HIGH (documentation)**

Upstream docs say Jul 10/11 2024; the data says **2024-06-10/11**. Anyone trusting the
documented date will include ~30 days of full-catalogue data in their "small basket"
period, or exclude it from breadth metrics unnecessarily.
*Query: `A2b_basket_transition.sql`.*

### E11. Metro's daily extract captures a rotating subset of its catalogue — **HIGH**

Metro was present on all 97 days of the 2024-25 freeze window, yet only **351 of 14,288
SKUs** appear on 90+ of those days. This is invisible to any "was the vendor present?"
check and it is what makes D1's 2024-25 window unusable.
*Query: `D1b_metro_freeze_diagnosis.sql`.*

### E-dup. Duplicate rows have doubled, and increasingly disagree on price — **MEDIUM**

Upstream's ~6,500/day (Nov 2024) is confirmed (6,529) but is now **~14,189/day** (Jul
2026). Duplicates that **disagree on price** grew from 619 product-days (Nov 2024) to
9,025 (Jul 2026). Worst single case: one Metro product, 1,062 rows in one day.
*Query: `B6_duplicate_rows.sql`.*

### E12. Loblaws sale flags without `old_price` — **MEDIUM**

730,582 rows (**22.72%** of Loblaws sale flags) indicate a sale in `other` but carry no
`old_price`. These are multibuy offers (`sale\n$3.50 MIN 2`). Any sale analysis keyed on
`old_price` undercounts Loblaws by about a fifth. *Query: `C4_old_price_and_sale_flag.sql`.*

### E3/E4. `units` field contamination — **MEDIUM**

- **`units` literally equals `'error'`** for **409 products** across Walmart, NoFrills,
  Voila and Loblaws. An error token was written into a data field.
- **Walmart's `units` contains marketing copy** — `perfect every time™`, `shelf stable`,
  `casein-free`, `sold in singles`, `15x20cm`. This is why only 51.38% of Walmart units
  parse vs 99%+ for five other vendors.

*Query: `E7_field_level_defects.sql`, `C1_unit_parseability.sql`.*

### E5. Non-breaking space (U+00A0) inside `units` — **LOW but insidious**

**257 products** (Metro 235, Walmart 22) contain U+00A0 in `units`. It is visually
identical to a space, and `\s` in DuckDB (and many regex engines) does **not** match it,
so `2<nbsp>l` silently fails to parse while `2 l` succeeds. Found only by hexdumping
values that "obviously should have parsed."
*Query: `E7_field_level_defects.sql`.*

### E7. `price_per_unit` garbage denominators — **LOW**

| Denominator | Rows |
|---|---|
| *(empty)* | 1,033,415 |
| `100kg` | 20,974 |
| `100356g` | 17,293 |
| `100ea` | 8,149 |
| `100un.` | 7,277 |
| `100lb.` | 2,963 |
| `100l` | 1,507 |
| `100lt` | 860 |

`100356g` is not a unit. The `100`-prefixed forms look like a `100` basis glued onto the
wrong token. *Query: `E7_field_level_defects.sql`.*

### E1. 8 rows with NULL `nowtime` — **LOW**

Eight Loblaws rows (contiguous rowids ~23,592,279–23,596,007) carry a price with no date.
They are invisible to any date filter. Small, but a price with no date should not exist.
*Query: `E1_null_nowtime_rows.sql`.*

### E13. `old_price` not greater than `current_price` — **LOW**

A "sale" where the old price is not higher:

| Vendor | Rows with old_price | old ≤ current | % |
|---|---|---|---|
| Galleria | 54,369 | 1,372 | **2.52%** |
| NoFrills | 1,541,523 | 6,331 | 0.41% |
| Walmart | 734,937 | 609 | 0.08% |
| Metro | 2,421,984 | 1,760 | 0.07% |
| SaveOnFoods | 2,345,653 | 21 | 0.00% |
| TandT / Voila / Loblaws | — | **0** | 0.00% |

*Query: `E7_field_level_defects.sql`.*

### E14. Out-of-stock rows carry prices — **LOW / by design, but must be handled**

**4,471,218 rows** (6.2% of the dataset) are flagged `Out of Stock` in `other` yet carry
a positive `current_price`. That is probably the listed price of an unavailable item.
Any "what did this cost" claim must decide explicitly whether to include them.
*Query: `E7_field_level_defects.sql`.*

### E15. Non-brand values in the `brand` field — **LOW**

| Vendor | Value | Products |
|---|---|---|
| Walmart | `Unbranded` / `unbranded` | 260 |
| Walmart | **`Out of stock`** | **174** |
| SaveOnFoods | `-` | 11 |
| SaveOnFoods | `N/A` | 3 |

Stock status leaking into a brand field is the same class of defect as `units='error'`
(E3): a non-value written where a value belongs. It inflates Walmart's apparent brand
coverage and would silently create an "Out of stock" brand in any group-by.
*Query: `F3_private_label_detectability.sql`.*

### E16. `brand` is case-inconsistent — **LOW, but it breaks GROUP BY**

The same label is stored under multiple spellings, so a naive `GROUP BY brand` splits one
brand into several:

| Vendor | Brand | Spellings | Products affected |
|---|---|---|---|
| SaveOnFoods | Western Family | `western family` / `Western Family` | 1,800 |
| Metro | Selection | `SELECTION` / `Selection` | 1,160 |
| Metro | Irrésistible | `IRRÉSISTIBLE` / `Irrésistible` | 962 |
| Metro | Front Street Bakery | 2 spellings | 524 |
| Metro | Life Smart | 2 spellings | 403 |

These are private-label brands, so the split lands squarely on the private-vs-national
classification that F3 depends on. Case-folding fixes it downstream, but the field should
be normalised at source. *Query: `F3_private_label_detectability.sql`.*

### E4b. Walmart's `units` contamination is field misalignment, not stray text — **MEDIUM**

E4 recorded that Walmart's `units` contains marketing copy. Inspecting `concatted` — whose
format is `vendor~product_name@units^brand` — shows the sharper diagnosis: **the units
slot frequently holds a verbatim copy of the product name**, and the brand slot sometimes
holds price text with embedded newlines:

```
Walmart~SkinnyPop Skinnypack Gluten Free Popcorn@SkinnyPop Skinnypack Gluten Free Popcorn^$5.57
current price $5.57
$5.16/100g
Walmart~LA COSTENA TAQUERA SAUCE, TAQUERA SAUCE@TAQUERA SAUCE^La Costeña
```

This is a **field-assignment bug in the Walmart extractor**, not a formatting quirk, and it
explains both the 51.38% unit parse rate and part of the 32.48% blank-brand rate in one
cause. It is a more actionable report than "marketing copy appears in units".
*Query: `F4_d3_claim_boundary.sql`, `C1_unit_parseability.sql`.*

### Checked and clean

- **All-zero UPCs:** 0 products.
- **UPC → product-name collisions within a vendor:** 70,943 (vendor, UPC) pairs map to
  one name; 54 map to two; 1 maps to three. Essentially clean.
- **Blank `current_price`:** 0 rows.

*Query: `E6_allzero_and_shared_upc_defects.sql`, `E7_field_level_defects.sql`.*

---

## 7b. Section F — ergonomics feedback (delivered separately)

Section E above is "this is wrong". Section F is "this is not wrong, but it is expensive
to consume" — and it is delivered as its own document,
[docs/upstream-feedback.md](upstream-feedback.md), written to be sent to the maintainer
as-is. Keeping them separate is deliberate: mixing ergonomics into the bug list would
bury the correctness defects.

Eight items, ranked by impact on a downstream consumer, each evidenced with numbers from
this audit. The top two:

1. **Make `current_price` a scalar** and move multibuy offers to their own column. The
   only item that makes downstream numbers *actively wrong* (2×) rather than merely
   absent.
2. **Ship a stable product key, or document that `product.id` already is one.** Best
   effort-to-value ratio in the document — potentially a single sentence — and made
   urgent by the announced `product_id` type change. Evidenced by B1/B1b/B2b:
   161,300 `(vendor, sku)` keys, 161,300 rows, zero collisions, 100% single-id.

It also records what is *good* and worth not losing — chiefly the published UPC
reliability tiering, without which this project's headline number could not have been
computed honestly.

---

## 7c. Follow-ups: E8 vs D2, and the Metro freeze cohort

### F1. Does E8 contaminate D2? **No exclusion. 2.05% attrition. Not biased.**

**Nothing was excluded.** D2 keys entirely off `old_price` presence and never references
`current_price`, so no sale event was dropped by E8. **566,564 events and 279,599
evaluable events stand exactly as reported.**

The real exposure is the opposite one: those counts *overstate the usable sample*,
because the analysis D2 enables ("was the price raised before the sale?") needs a numeric
price on the sale day and across the 14-day pre-window. Events touching a non-scalar price
will silently drop out at that point.

| Measure | Events |
|---|---|
| All sale events | 566,564 |
| D2 evaluable (14d continuous history) | 279,599 |
| …of which price-dirty (would be lost) | **5,726** |
| **…evaluable AND price-clean** | **273,873** |
| Attrition | **2.05%** |

Per vendor, the loss rate is very uneven:

| Vendor | D2 evaluable | Lost to E8 | Surviving | % lost |
|---|---|---|---|---|
| **Metro** | 23,472 | 1,692 | 21,780 | **7.21%** |
| TandT | 18,944 | 669 | 18,275 | 3.53% |
| SaveOnFoods | 79,350 | 2,673 | 76,677 | 3.37% |
| Walmart | 8,031 | 199 | 7,832 | 2.48% |
| Loblaws | 43,253 | 488 | 42,765 | 1.13% |
| Voila | 66,908 | 5 | 66,903 | 0.01% |
| NoFrills | 38,218 | 0 | 38,218 | 0.00% |
| Galleria | 1,423 | 0 | 1,423 | 0.00% |

**Is the sample biased, or merely smaller? Merely smaller.** The loss *rate* is skewed —
Metro loses proportionally 7× more than Loblaws and infinitely more than No Frills — but
because the absolute loss is small, the vendor composition barely moves:

| Vendor | Share before | Share after | Shift |
|---|---|---|---|
| Metro | 8.39% | 7.95% | −0.44 pp |
| SaveOnFoods | 28.38% | 28.00% | −0.38 pp |
| TandT | 6.78% | 6.67% | −0.10 pp |
| Walmart | 2.87% | 2.86% | −0.01 pp |
| Galleria | 0.51% | 0.52% | +0.01 pp |
| Loblaws | 15.47% | 15.61% | +0.15 pp |
| NoFrills | 13.67% | 13.95% | +0.29 pp |
| Voila | 23.93% | 24.43% | +0.50 pp |

No vendor's share of the sample moves by more than **0.5 percentage points**. **D2 remains
a GO at n = 273,873.** Report that number, not 279,599, as the sample for any analysis
that needs numeric prices.

One caveat that is *not* about E8: Metro's evaluable rate is 21.22% of its own events —
the catalogue-churn problem from D1/E11, which costs Metro far more than E8 does.

*Source: `F1_e8_contamination_of_d2.sql`.*

### F2. What are D1's 474 Metro SKUs? **A frozen-and-packaged slice, not a sample.**

Compared against the other 13,814 Metro SKUs in the same window:

| Cohort | SKUs | Brand populated | Private label | National brand |
|---|---|---|---|---|
| Well-covered (D1's 474) | 474 | 87.76% | 19.41% | 68.35% |
| Rest of catalogue | 13,814 | 92.97% | 16.13% | 76.84% |

The private/national split looks similar — but the composition underneath it does not.
Retention = the share of that brand's window SKUs that reach ≥90% coverage; the baseline
is 474/14,288 = **3.3%**.

| Brand | % of the 474 | % of catalogue | Retention | Over/under |
|---|---|---|---|---|
| HIGH LINER | 9.78% | 0.68% | **55.0%** | **14× over** |
| MCCAIN | 4.89% | 0.88% | 21.2% | 5.6× over |
| SILK | 4.00% | 0.83% | 18.4% | 4.8× over |
| KRAFT | 3.56% | 1.05% | 12.9% | 3.4× over |
| IRRÉSISTIBLE (PL) | 31.11% | 13.51% | 8.8% | 2.3× over |
| *(blank brand)* | 25.78% | 17.49% | 5.6% | 1.5× over |
| SELECTION (PL) | 8.44% | 14.46% | **2.2%** | 1.7× under |
| LIFE SMART (PL) | 0.89% | 5.40% | **0.6%** | 6× under |
| FRONT STREET BAKERY (PL) | 0.44% | 5.64% | **0.3%** | 13× under |

Category probe (keyword on product name — indicative, not a taxonomy; the dataset has no
category column):

| Category | % of the 474 | % of rest | Skew |
|---|---|---|---|
| Meat & fish | **20.25%** | 7.89% | **2.6× over** |
| Frozen | **9.07%** | 3.10% | **2.9× over** |
| Bread & bakery | 8.44% | 5.05% | 1.7× over |
| Eggs | 1.27% | 0.97% | 1.3× over |
| Dairy | 11.39% | 16.96% | 1.5× under |
| Beverages | 10.97% | 14.41% | 1.3× under |
| Produce | 11.39% | 14.25% | 1.3× under |
| Pantry staples | **4.22%** | 10.29% | **2.4× under** |

**The 474 is a frozen-and-packaged-goods slice.** High Liner (frozen fish) and McCain
(frozen potato) are the two most over-represented brands; meat/fish and frozen are the two
most over-represented categories; fresh-adjacent and in-store-bakery lines (Front Street
Bakery, Life Smart) are almost entirely absent. That is mechanically sensible — frozen
packaged goods have stable listings that neither churn nor go out of stock — but it means
the 474 cannot stand in for Metro's catalogue.

**This strengthens the D1 NO-GO.** The 2024-25 window fails not only on sample size
(n=474) but on composition: a freeze measured on this cohort would be a freeze measured
on frozen fish and packaged desserts. **The same check must be run on the 2025-26 window's
n=5,977 before that one is treated as a GO** — it has not been, and the qualified GO
should be read as provisional until it is.

*Source: `F2_metro_freeze_sku_profile.sql`.*

### F3. Can private label be told from national brand? **For 4 vendors yes, 1 partly, 3 no.**

Metro's freeze claim is scoped to "all private label and national brand grocery products",
so the distinction is load-bearing.

| Vendor | Products | Brand populated | Private label | National brand | Unclassifiable | Verdict |
|---|---|---|---|---|---|---|
| NoFrills | 24,398 | **94.31%** | 3,880 | 19,129 | 1,389 | **YES** |
| **Metro** | 26,311 | **92.45%** | 3,503 | 20,822 | 1,986 | **YES** |
| Loblaws | 31,688 | **90.64%** | 4,439 | 24,282 | 2,967 | **YES** |
| SaveOnFoods | 16,158 | **89.39%** | 2,718 | 11,726 | 1,714 | **YES** |
| Walmart | 37,914 | 67.52% | 1,084 | 24,514 | 12,316 | **PARTIAL** |
| Voila | 26,320 | **0.81%** | 23 | 190 | 26,107 | **NO** |
| TandT | 13,542 | **0.00%** | 0 | 0 | 13,542 | **NO** |
| Galleria | 10,697 | **0.00%** | 0 | 0 | 10,697 | **NO** |

**For Metro specifically — the vendor whose claim this is — yes, at 92.45% coverage.**
The classification rests on a written-out list of retailer labels (SELECTION, IRRÉSISTIBLE,
LIFE SMART, FRONT STREET BAKERY, metrogo!, …) that is a judgement input and is stated in
the query so it can be argued with and extended. Brand-field *coverage*, which caps how
far any such list can reach, is not a judgement call.

**For T&T and Galleria it is impossible** — the brand field is 100% empty, so a
private-label-scoped claim cannot be evaluated for them at all. **Voila is effectively
impossible at 0.81%.** Walmart is partial and additionally polluted (see E15).

*Source: `F3_private_label_detectability.sql`.*

---

## 8. What this dataset can and cannot support

### It can support

**Cross-vendor price comparison on a real everyday basket — for four vendors.**
3,477 products with reliable, vendor-direct UPCs and 90+ days of simultaneous pricing at
2+ of Metro, Galleria, Save-On-Foods and Walmart. 1,560 have a year or more. The basket
contains actual milk, bread, eggs, cheese and coffee, not only a long tail. Every such
claim must say *four of eight vendors*, and *Toronto pickup pricing*.

**Sale-behaviour analysis at scale.** 273,873 sale events with a full 14 days of
continuous pre-sale daily history *and* numeric prices throughout (279,599 before removing
E8-affected events — a 2.05% attrition that does not shift the vendor mix by more than
0.5 pp, so the sample is smaller, not biased). This is the strongest thing in the dataset. "Was the
price raised before the sale" is answerable with a large sample — provided Loblaws
multibuy offers are handled (E12) and non-scalar prices are parsed rather than dropped (E8).

**Price-dynamics work generally.** 83% of products changed price at least once; 39.5%
took 5+ distinct prices. The "everything is flat" failure mode did not occur. Galleria is
the exception at 48% flat.

**A genuinely useful upstream bug report.** Section E has 14 defects with reproducing
queries and magnitudes, several of which the maintainer is unlikely to know about —
particularly E8 (non-scalar prices in two key vendors), E2 (878K orphaned rows), and
E10 (the documented transition date being a month off).

### It cannot support

**Shrinkflation.** Not "hard" — impossible. The schema stores one unit size per SKU and
overwrites. No amount of query cleverness recovers history that was never written.

**The 2024-25 Metro price-freeze verification.** The vendor that made the claim has 474
usable SKUs of 14,288 in that window, 20 with no gaps — and those 474 are a
frozen-and-packaged-goods slice (High Liner and McCain over-represented 14× and 5.6×;
meat/fish and frozen 2.6× and 2.9×; in-store bakery lines almost absent). It fails on
composition as well as on size. The 2025-26 window is workable on size (n=5,977) but its
composition has not been checked, so treat that GO as provisional.

**A private-label-scoped freeze claim for T&T or Galleria.** Their `brand` field is 100%
empty, so the two groups the claim names cannot be separated at all. Voila at 0.81% is
effectively the same.

**Any five-vendor comparison at the reliable tier.** Zero GTINs reach 5+ vendors without
a fuzzy-matched vendor. Breadth beyond four vendors requires accepting fuzzy matches, and
B5 found a clear mismatch in a sample of 30.

**Anything national, provincial, or "Canadian."** One Toronto neighbourhood, pickup price.

**Anything about brand for Galleria, T&T or Voila** (≥99% blank), **sale behaviour for
Galleria** (0.92% `old_price`), or **`price_per_unit` for Galleria or T&T** (100% blank).

**Unbroken time series across August 2025.** A 19-day hole affects every vendor, and
Walmart is out for 49 days. Per honesty rule #1, that gap must remain visible in the
model, not be interpolated away.

### The single largest risk to this project

**E8.** A pipeline that does `CAST(current_price AS DOUBLE)` will silently discard 7.59%
of Metro rows and 6.46% of Save-On-Foods rows — the two vendors the cross-vendor basket
most depends on — and will do so without raising a single error. The naive repair
(strip to the trailing number) turns `2/$7.00` into $7.00 when the true unit price is
$3.50, producing prices that are wrong by 2× while looking perfectly plausible.

Whatever is built in Phase 1, `current_price` parsing needs an explicit typed parser with
a rejected-rows count that is asserted on, not a cast.

---

## 9. Reproducing this

```bash
python scripts/fetch_snapshot.py                       # new snapshot + sha256 manifest
python scripts/load_snapshot.py --workdir /tmp/hammer  # -> hammer.duckdb
python scripts/check_schema.py                         # MUST pass before any analysis
python scripts/run_query.py analysis/phase0/B4_cross_vendor_upc_overlap.sql --all
```

Queries over the full 71M-row table need a memory budget and a spill directory:

```bash
python scripts/run_query.py analysis/phase0/B6_duplicate_rows.sql --all \
  --memory-limit 3GB --temp-dir /tmp/spill
```

## Checks and tests

| Check | Result |
|---|---|
| `scripts/check_schema.py` | PASS — 2 tables, 15 columns match |
| `scripts/test_check_schema.py` | **6 of 6** cases behaved as expected |
| `scripts/check_manifest.py` | PASS — 44 tracked files, 11 manifest entries |
| Query smoke test (every `.sql` in `analysis/phase0/` executes) | **35 of 35** run without error |

The only tests that exist are the 6 schema-check cases. There is no test suite for the
analysis queries themselves — they are verified by execution, not by assertion — so
**"6 of 6" refers to `test_check_schema.py` alone** and must not be read as a pass rate
for the phase.

`check_manifest.py` was itself verified to fail in both directions (an undocumented file
in the repo, and a manifest entry pointing at nothing), so its PASS is meaningful rather
than vacuous.
