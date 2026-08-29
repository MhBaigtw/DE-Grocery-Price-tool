# Phase 1 — Representation: Findings

Phase 1 builds representation, not findings. This document records what each section
measured and decided, so the models built later are traceable to evidence.

Every number comes from a committed query in [analysis/phase1/](../analysis/phase1/).

---

## Section 1 — Second snapshot

**Status: complete.** Headline: **`(vendor, sku)` is stable across snapshots. Section 4
is straightforward.**

### 1.1 Provenance

| | Snapshot 1 | Snapshot 2 |
|---|---|---|
| Snapshot id | `20260822T134045Z` | `20260824T132829Z` |
| Upstream `hammer-lastupdated.txt` | `2026-08-21 21:26:00.11 (ET)` | `2026-08-23 20:20:35.14 (ET)` |
| Max `nowtime` | 2026-08-21 | 2026-08-23 |
| **Publication lag** | **1 day** | **1 day** |
| `raw` rows | 71,809,333 | 72,022,652 |
| `product` rows | 187,028 | 187,070 |
| `hammer-5-csv.zip` sha256 | `fb2a815ebce28377…` | `50d9fe3e5d56f6dd…` |
| `hammer-3-compressed.zip` sha256 | `2da260be76b3e441…` | `5307d80f30d250f5…` |

Both archives differ by sha256, so this is a genuinely distinct publication.
Net change: **+213,319 `raw` rows, +42 `product` rows, +2 dates.**

**Limitation, stated up front:** the brief asked for snapshots "at least several days
separated". These are **2 days apart** (2026-08-22 → 2026-08-24), because that is the
elapsed time available. A 2-day gap is a weaker test than a 2-week gap: slow-moving
instability would not show up. Every stability number below should be read as *stability
over 2 days and one upstream republication*, not as a general guarantee. This should be
re-run when a longer gap exists.

*Source: `P1_1_provenance_and_lag.sql`.*

### 1.2 Schema check

```
OK - schema matches: 2 tables, 15 columns.   (exit 0)
```

**`raw.product_id` is still VARCHAR.** The announced string→number change has **not**
landed. No stop condition; Phase 1 proceeds.

### 1.3 Cross-snapshot identity — the key test

Phase 0 showed `product.id = vendor||sku` is stable *within* a snapshot and flagged that
as tautological. This is the first non-circular test: two independently published files,
compared on the key we propose to own.

**Key population:** 161,300 keys in snapshot 1, 161,349 in snapshot 2, **161,290 shared**.
59 added, 10 dropped over two days.

**Disagreement rate per vendor, on shared keys:**

| Vendor | Shared keys | name | units | brand | upc | any | % disagree |
|---|---|---|---|---|---|---|---|
| NoFrills | 22,946 | 3 | 0 | 2 | **5,698** | 5,701 | 24.85% |
| Loblaws | 30,145 | 6 | 0 | 0 | **5,565** | 5,570 | 18.48% |
| Walmart | 24,330 | **375** | 12 | **539** | 0 | 542 | 2.23% |
| SaveOnFoods | 16,119 | 2 | 0 | 0 | 0 | 2 | 0.012% |
| Metro | 21,323 | 2 | 0 | 0 | 0 | 2 | 0.009% |
| Voila | 24,742 | 0 | 2 | 0 | 0 | 2 | 0.008% |
| TandT | 11,786 | 0 | 0 | 0 | 0 | 0 | **0.000%** |
| Galleria | 9,899 | 0 | 0 | 0 | 0 | 0 | **0.000%** |

The headline percentages look alarming for Loblaws and No Frills. **They are entirely
`upc`, and almost entirely benign.** Decomposing:

| Vendor | UPC changed | blank → populated *(enrichment)* | populated → blank | value → different value |
|---|---|---|---|---|
| NoFrills | 5,698 | **5,225** | 0 | 473 |
| Loblaws | 5,565 | **5,093** | 0 | 472 |
| All other vendors | **0** | 0 | 0 | **0** |

And of the 945 genuine value changes, most are **zero-padding, not different products**:

| Vendor | Value changed (raw) | Same after GTIN-14 normalisation | **Genuinely different** |
|---|---|---|---|
| Loblaws | 472 | 408 | **64** |
| NoFrills | 473 | 409 | **64** |

`041790001358` → `41790001358` is the dominant pattern — the same GTIN with a leading
zero stripped. Phase 0's B4 already normalises to GTIN-14 for exactly this reason, and
that normalisation absorbs 817 of the 945.

**By tier — the number that matters for D4:**

| Tier | Shared keys | UPC value changed | UPC gained |
|---|---|---|---|
| **Reliable** (Metro, Galleria, Save-On-Foods, Walmart) | 71,671 | **0** | **0** |
| Fuzzy (Loblaws, No Frills, T&T, Voila) | 89,619 | 945 *(128 genuine)* | 10,318 |

#### Verdict

**`(vendor, sku)` is a stable product identity across snapshots.**

- `product_name` and `units` — the fields that define what the product *is* — are stable
  to within **388 name changes and 14 unit changes across 161,290 keys**, and 375 of the
  388 are Walmart, the vendor already diagnosed with field misalignment.
- Genuine identity instability is **128 keys — 0.079% of shared keys** — all in the
  fuzzy-UPC banners, and all in `upc` rather than in what the product is.
- **The reliable tier shows zero UPC change of any kind.** D4's basket, which is
  reliable-tier only, is reproducible across these two snapshots.

**Section 4 is straightforward.** The owned surrogate key can be built on `(vendor, sku)`
without a reconciliation layer.

**Bad news to carry forward anyway:** fuzzy-tier UPCs are being actively re-matched
upstream — 10,318 gains and 128 genuine re-matches in two days. Any cross-vendor number
computed from fuzzy-tier UPCs **is not reproducible between snapshots**, and will drift
every time upstream re-runs its matching. This is a second, independent reason (beyond
B5's eyeball) to keep headline numbers on the reliable tier only, and it is stronger than
the first because it is measured rather than judged.

*Source: `P1_3_cross_snapshot_identity.sql`.*

### 1.4 Snapshot diff — is upstream append-only?

Per-date fingerprints (row count, distinct products, order-independent content checksum)
compared across all shared dates.

| Measure | Value |
|---|---|
| Dates in both snapshots | 887 |
| **Byte-identical** | **883** |
| Row count changed | **0** |
| Same row count, content changed | **4** |
| Dates only in snapshot 2 | 2 (2026-08-22, 2026-08-23) |
| Dates only in snapshot 1 | 0 |

The four rewritten dates are 2026-07-25, 2026-07-26, 2026-07-27 and 2026-08-03. A
duplicate-safe multiset diff shows the scale:

| Date | Distinct rows gained | Distinct rows lost | Copies gained | Copies lost |
|---|---|---|---|---|
| 2026-07-25 | 8 | 8 | 8 | 8 |
| 2026-07-26 | 1 | 1 | 1 | 1 |
| 2026-07-27 | 2 | 2 | 2 | 2 |
| 2026-08-03 | 1 | 1 | 1 | 1 |

**12 rows changed out of 71,809,333 — 0.0000167%.** Gains equal losses on every date, so
these are substitutions, not insertions or deletions.

**What changed:** the `product_id` was re-keyed. Rows swap between an opaque base64-style
id and a vendor-prefixed one — `LGwlbuu+EVyHYv7vaNRU2Q==` ↔ `Walmart6XQS4BK8VMKL`,
`ah9XHCr9XN9Ll7xPI9G1og==` ↔ `Walmart6000197471947` — at an unchanged price. This is
upstream **recovering a SKU it had previously failed to extract**, which changes the
derived id (Phase 0 B1b: the id is `vendor||sku` where a sku exists, and a hash of
`concatted` where it does not).

**Verdict: upstream is append-only in practice, with a rounding error of re-keying.**
"The archive" is a stable object. Honesty rule 3's assumption that a published number
stays reproducible holds — with one caveat: a number keyed on `raw.product_id` for a
blank-sku product could move. That is precisely what Section 4's owned key exists to
prevent, and it is now a measured justification rather than a precaution.

*Source: `P1_4_snapshot_diff.sql`, `P1_4b_rewritten_rows.sql`.*

#### A correction to my own analysis, recorded because the error is instructive

My first version of `P1_4b` joined the two snapshots on `(product_id, nowtime)` and
reported that upstream had **corrupted** past prices — `3.29` in snapshot 1 against
`329$` in snapshot 2. **That was wrong, and it was my error, not upstream's.**

Phase 0's own finding B6 established that one product can appear many times in a single
day's scrape with *conflicting* prices (49,329 such product-days at Loblaws alone). Joining
on `(product_id, nowtime)` therefore cross-products a clean row in one snapshot against a
duplicate malformed row in the other and reports a difference that does not exist. **Both
rows are present in both snapshots.** The malformed-price counts on those four dates are
identical across snapshots (171/171, 0/0, 172/172, 171/171).

The correct comparison is a multiset difference — group by full row content, count
occurrences, diff the counts — which is duplicate-safe by construction. `P1_4b` now does
that, and the method note is written into the query so the trap is not re-entered.

The general lesson, which applies to every model Phase 1 builds: **on this dataset, any
join whose key is not unique is a bug waiting to happen.** Section 5's uniqueness tests
are not bureaucracy.

### 1.5 New defect found: the `NNN$` malformed price shape

Chasing the false alarm above surfaced a real defect that Phase 0 had not isolated.

`current_price` sometimes holds a value like `329$`, `1400$`, `899$` — the price in
**cents with a trailing dollar sign**, decimal point removed.

| Snapshot | Malformed rows | Dates affected | First date | Last date |
|---|---|---|---|---|
| 1 | **47,992** | 286 | 2025-10-22 | 2026-08-21 |
| 2 | **48,342** | 288 | 2025-10-22 | 2026-08-23 |

- **Loblaws only.** Zero rows at any other vendor.
- Also affects `old_price`: 6,488 rows in snapshot 2.
- **Stable, not spreading** — the count grows only by the two new dates, at a steady
  ~175 rows/day.
- Present continuously since 2025-10-22, i.e. it survived at least one upstream
  post-processing rework.

**This is a subset of Phase 0's E8, not a contradiction of it.** E8 counted 262,732 rows
in an uncharacterised "other" bucket alongside multibuy and per-weight; ~48,000 of those
are this specific shape. It is newly *isolated*, not newly *discovered*.

**It is recoverable.** `329$` ÷ 100 = `3.29`, and spot checks against the same product's
price on adjacent uncorrupted days confirm the cents reading. Section 2 will treat it as a
fourth parseable shape rather than as unparsed — with the recovery rule documented and its
row count asserted, since a division by 100 applied to the wrong shape would be a silent
100× error.

**Upstream feedback:** this belongs in `upstream-feedback.md` §1, which already asks for a
scalar `current_price`. It is the same root request with a fourth concrete shape attached.

*Source: `P1_4c_price_corruption_regression.sql`.*

---

## Section 2 — Price representation

**Status: complete.** Headline: **100.00% of `current_price` rows now have a computable
unit price. The D2 exclusion fell from 6,421 events to 3, and all 925 Metro multibuy
events are recovered.**

### 2.1 Shape inventory

Every distinct form `current_price` takes, collapsed to a signature (digits → `N`,
letters → `a`). 23 shapes exist; 9 account for everything above a rounding error.

| Shape | Rows | % | Vendors | Meaning |
|---|---|---|---|---|
| `N.N` | 69,758,160 | 98.055% | all 8 | scalar |
| `N/$N.N` | 598,007 | 0.841% | Metro | multibuy `2/$7.00` |
| `N.N/Na` | 270,127 | 0.380% | SaveOnFoods, Metro | per-weight `3.69/100g` |
| `N.N a/a` | 203,003 | 0.285% | SaveOnFoods | average price `12.46 avg/ea` |
| `N` | 162,187 | 0.228% | 2 | scalar integer |
| `N.N/a` | 89,479 | 0.126% | TandT, SaveOnFoods, Metro | per-weight `36.90/kg` |
| `N$` | 48,055 | 0.068% | **Loblaws** | **cents-form `329$` = $3.29** |
| `a$N` | 12,466 | 0.018% | **Walmart** | **cents-form `Now$298` = $2.98** |
| `N,N.N` | 353 | 0.001% | Walmart, Voila | thousands separator |

`old_price` adds three more: `N¢` (`99¢`, Walmart, 586), `N.N/aN.N/a.`
(`19.82/kg8.99/lb.` — two prices concatenated, Metro, 4,172), and `N.Na.a`
(`17.61avg.kg`, Metro, 27,576).

*Source: `P2_1_price_shape_inventory.sql`.*

#### Correction to §1.5: the cents-form is not Loblaws-only

§1.5 reported the cents-form defect as "Loblaws only". **That was wrong** — an artifact of
testing only the bare `^[0-9]+\$$` pattern. Walmart has the same underlying defect wearing
two different disguises:

| Vendor | Shape | Rows | Field |
|---|---|---|---|
| Loblaws | `329$` | 48,055 | current_price |
| Loblaws | `329$` | 6,488 | old_price |
| **Walmart** | **`Now$298`** | **12,466** | current_price |
| **Walmart** | **`99¢`** | **586** | old_price |

Same root cause — a price rendered in cents without a decimal point — at two vendors, in
four syntactic variants. All four are parsed.

#### A second defect: `old_price` is not always a price

**869,495 rows carry the literal string `was` in `old_price`** (Loblaws 861,728, No Frills
7,775), plus 12 rows carrying a brand name (`Kelloggs`, `Mastro`, `from our chefs`). For
Loblaws that is **33.1% of every row D2 treats as a sale.**

This does **not** inflate D2's event count: 98.07% of those rows also carry a sale flag in
`other`, so they are genuine sales whose struck-out price was lost in extraction. The
event is real; only the old value is missing. But it does mean **Phase 0 C4's `old_price`
coverage of 18.53% for Loblaws is overstated** — the share of Loblaws rows with a *usable*
old price is closer to 12.4%.

The parser classifies `was` as `unparsed` with the raw text retained, rather than letting
it fall through as a price.

*Source: `P2_1b_old_price_junk.sql`.*

### 2.2 The model — `stg_price`

One row per raw price observation. **71,809,333 in, 71,809,333 out**; the build script
refuses to continue if those differ.

| Column | Meaning |
|---|---|
| `offer_type` | `scalar` / `multibuy` / `per_weight` / `unparsed` / `blank` |
| `unit_price` | price of one unit on the canonical basis |
| `min_qty` | 1 for scalar, n for multibuy |
| `price_basis` | `each` / `per_100g` / `per_100ml` |
| `price_basis_stated` | the denominator the vendor actually quoted (`kg`, `lb`, `450g`, …) |
| `normalization` | the encoding repair applied, or `none` |
| `parse_confidence` | `exact` / `derived` / `inferred` / `none` |
| `current_price_raw` | always retained, never discarded |

**Design decision: `offer_type` and `normalization` are separate columns.** `offer_type`
describes the *commercial offer* — what is sold and how many. `normalization` describes
the *encoding repair* needed to get a number out of the text. A cents-form price like
`329$` is commercially an ordinary single-unit offer that happens to be written oddly, so
it gets `offer_type='scalar'` and `normalization='cents_div100'`.

Per the instruction, the cents-form is a first-class parse case: it reaches `unparsed`
never, is stripped to `329` never, and every repair is named and countable. Folding the
encoding into `offer_type` would have made "how many single-unit offers are there?" —
exactly D2's question — unanswerable without knowing every encoding quirk.

**Design decision: per-weight prices are rescaled to a canonical basis.** Mass is
expressed per 100 g and volume per 100 mL, so `$36.90/kg`, `$3.69/100g` and `$8.80/1000g`
all become `3.69 per_100g` and are directly comparable.
*Tradeoff, stated:* `unit_price` is then not always the number printed on the vendor's
site. The alternative — one basis per denominator — preserves the printed number but
pushes unit conversion into every downstream query, where it will be done inconsistently
or not at all. Comparability is the column's entire purpose, so the conversion happens
once, here, and `price_basis_stated` preserves what the shopper saw.

**Materialisation:** a table, not a view. It began as a view (zero disk, cannot drift from
source), but the regex parse over 71.8M rows made every downstream query cost minutes.
2.1 GB of disk buys that time back on every subsequent query. `build_models.py
--materialize view` still works if disk becomes tighter than time.

#### Parse coverage

| Field | Rows | scalar | multibuy | per_weight | unparsed | **computable** |
|---|---|---|---|---|---|---|
| `current_price` | 71,809,333 | 70,566,164 | 679,923 | 563,213 | **33** | **100.000%** |
| `old_price` | 12,757,144 | 11,675,550 | 369 | 210,490 | 870,735 | 93.2% |

**33 unparsed rows out of 71.8 million.** They are genuine garbage — product names in the
price field, HTML fragments with embedded newlines, and one timestamp
(`13.42026-02-01 09:2…`). They are retained with `offer_type='unparsed'` and their raw
text, exactly as the brief requires, and they remain countable.

`old_price`'s 870,735 unparsed is the `was` population above — correctly refused rather
than silently priced.

Repairs applied, each named and counted:

> **Restated in §5.8.** This table previously showed four repairs and a `basis_rescaled`
> count of **105,540**, which matches no state that can now be reconstructed — not the
> current all-rows figure (106,264), not the current with-a-vendor figure (105,488). It
> also **omitted `bare_integer_cents` entirely**, the largest repair rule in the phase, in
> a table captioned "each named and counted". The §2.5 correction note below updated two
> of the four rows and stopped. Five rules, all five counted:

| Normalization | Rows (all) | Rows with a vendor | Vendors | Price range after repair |
|---|---|---|---|---|
| `basis_rescaled` | **106,264** | 105,488 | Metro, T&T, Save-On-Foods | $0.0005 – $19.60 |
| **`bare_integer_cents`** | **79,478** | 79,478 | **Walmart** | **$1.00 – $69.96** |
| `cents_div100` | **47,992** | 47,707 | Loblaws | $1.00 – $84.17 |
| `now_prefix_cents_div100` | **11,506** | 11,496 | Walmart | $0.38 – $25.97 |
| `thousands_sep` | 353 | 353 | Walmart, Voila | $1,059 – $21,525 |

> **Corrected after §2.5.** The first version of this table reported 47,707 and 11,496 —
> the counts from an INNER join to `product`, which silently drops the 878,559 rows that
> resolve to no product row (Phase 0 E2). Those are totals over a subset reported as
> totals over everything: a denominator error, and exactly the kind honesty rule 4 exists
> to catch. The query now LEFT joins and reports the orphan count separately. The
> **100.00% parse coverage figure was never affected** — it was computed on `stg_price`
> directly, with no join.
>
> For the same reason the per-vendor table above sums to 70,930,774, not 71,809,333: the
> orphan rows have no vendor to attribute to.

The post-repair price ranges are the sanity check that matters: a `cents_div100` applied
to the wrong shape would produce prices in the hundreds, and the observed $1.00–$84.17
range is what groceries cost.

*Source: `P2_2b_parse_coverage.sql`. Parser unit tests: `P2_2_parser_unit_tests.sql`,
**22 of 22 cases pass**, including the two that matter most — `329$` → 3.29 (not 329.00)
and `2/$7.00` → 3.50 (not 7.00).*

### 2.3 D2 reconciliation — the point of the whole section

Definitions held identical to F5; only the "is this price usable" test changes, from
`try_cast IS NOT NULL` to `stg_price.unit_price IS NOT NULL`.

| | Events |
|---|---|
| Evaluable events | **279,599** |
| Lost **pre**-parse | **6,421** |
| Lost **post**-parse | **3** |
| **Recovered** | **6,418** |
| **Usable now** | **279,596** |

> **Figures are exact as of §3.5.** They were briefly reported as 279,593 / ~279,590
> while the queries keyed on a 64-bit workaround hash that had one collision in 161,300
> keys. The owned key (`md5`, proved collision-free across both snapshots) restores the
> original counts exactly. The recovery count (6,418) and the Metro multibuy recovery
> (925 of 925) were never affected.

Per vendor:

| Vendor | Evaluable | Lost pre-parse | Lost post-parse | **Recovered** |
|---|---|---|---|---|
| SaveOnFoods | 79,350 | 2,680 | 0 | **2,680** |
| Metro | 23,472 | 1,787 | 1 | **1,786** |
| Walmart | 8,031 | 709 | 0 | **709** |
| TandT | 18,944 | 691 | 0 | **691** |
| Loblaws | 43,253 | 548 | 2 | **546** |
| Voila | 66,908 | 6 | 0 | 6 |
| NoFrills | 38,218 | 0 | 0 | 0 |
| Galleria | 1,423 | 0 | 0 | 0 |

> ### Metro's 925 multibuy events: 925 recovered. 100.0%.

The categorical exclusion F5 identified is gone. D2's sample is no longer restricted to
single-unit markdowns, and the depth asymmetry that came with it — excluded events being
~8 pp deeper at the median, the direction that flatters retailers — is resolved, because
the deep multibuy markdowns are back in the sample.

`docs/phase-0-findings.md` has been updated: the D2 caveat now reads as resolved rather
than as a standing scope limit, in the verdict table, the D2 section, F5, and §8.

*Source: `P2_3_d2_reconciliation.sql`.*

### 2.5 Cents-form contamination inside D1's surviving freeze window

D1's 2024-25 window is already a NO-GO. The **2025-26 window (2025-11-01 → 2026-02-05)**
is the only one still standing, on a provisional GO — and the cents-form defect began
2025-10-22, ten days before that window opens.

| Measure | Value |
|---|---|
| Loblaws rows in window | 2,135,450 |
| **cents-form `current_price`** | **15,789 (0.739%)**, across 96 dates |
| **cents-form `old_price`** | **2,086 (0.098%)** |
| Every other vendor | **0** |
| Loblaws sale events starting in window | 14,357 |
| **…touched by cents-form** | **194 (1.35%)** |

**Why this matters more than 0.7% suggests.** A price freeze is a claim about prices *not
changing*. An unparsed reader comparing `4.49` on 2025-10-31 against `449$` on 2025-11-01
sees a **100× price increase on the first day of the freeze window**. The sample confirms
exactly that pattern — `449$`, `479$`, `569$` all appearing on 2025-11-01 for products
priced $4.49, $4.79 and $5.69 the day before.

That is not a subtle bias; it is a spectacular false finding waiting to be published, and
it sits inside the one D1 window still alive. **Parsed, it is a non-issue: all 15,789 rows
resolve correctly.** Unparsed, D1 on Loblaws would have been worthless.

Recorded in `docs/phase-0-findings.md` against D1's provisional GO.

*Source: `P2_5_cents_form_in_freeze_window.sql`.*

### 2.4 `price_per_unit` cross-check — **blocked on Section 3, and that is the finding**

The brief frames 2.4 as "now that units and prices both parse, quantify the agreement".
**Units do not parse yet — that is Section 3.1.** Running the comparison anyway produced
numbers that look like a devastating indictment of upstream and are actually an indictment
of my comparison:

| Vendor | Comparable rows | Agree within 1% | Median abs % diff |
|---|---|---|---|
| Walmart | 16 | 0.00% | 9900% |
| SaveOnFoods | 45,580 | 22.42% | 83.3% |
| Voila | 17,494 | 38.38% | 83.3% |
| Loblaws | 38,264 | 45.15% | 67.0% |
| Metro | 32,200 | 45.43% | 9.75% |
| NoFrills | 22,414 | 56.49% | 0.00% |

*(4% deterministic sample of rows with a non-blank `price_per_unit`: 2,313,447 sampled,
2,227,517 parsed, 155,972 comparable on a matching basis.)*

**Do not read those percentages as disagreement rates.** Adjudicating ten of them shows
the two fields measure **different quantities**:

| Vendor | `price_per_unit` | upstream says | we say | What is actually going on |
|---|---|---|---|---|
| Loblaws | `$1.00/1ea` | 1.00 | 23.99 | ours is the **pack** price, upstream's is the **per-item** price |
| Loblaws | `$399.00/100ea` | 399.00 | 3.99 | upstream quotes per *100* each |
| SaveOnFoods | `$1.30 each` | 1.30 | 25.99 | same: pack vs item |
| Voila | `$0.41/item` | 0.41 | 6.49 | same |
| Metro | `$4.49 ea.$0.94 /100ml` | 4.49 | 4.00 | multibuy: ours is the unit price after division, upstream's is the single-unit shelf price |

`price_per_unit` is `current_price ÷ pack_count`. `stg_price.unit_price` is the price of
the *listing*. **Reconciling them requires `pack_count`, which comes from parsing `units`
— Section 3.1.** Until that exists, any agreement rate computed here is comparing a
6-pack's price against one can's price and calling the difference an error.

**So 2.4 is deferred to Section 3, and the brief's ordering has a dependency it does not
state.** Two things are worth recording now:

1. **Where the bases genuinely match and no pack count is involved, agreement is good.**
   No Frills shows a median absolute difference of **0.00%** across 22,414 comparable rows,
   and Metro 9.75% — the latter inflated by multibuy rows where upstream quotes the shelf
   price and we quote the divided price. Both are consistent with Phase 0 C2's finding
   that `price_per_unit` is *better* than CLAUDE.md implies.
2. **`price_per_unit` carries a pack count we do not otherwise have.** `$1.00/1ea` against
   a $23.99 listing implies a 24-pack. That makes it a **cross-check on the unit parser**
   in Section 3, not merely a field to validate — which is a more useful role than the
   brief anticipated.

*Source: `P2_4_price_per_unit_crosscheck.sql`. Reported as a sample, with n stated.*

### 2.6 SKU-reuse risk heuristic — **risk measured, nothing built on it**

Explicitly not a deliverable. Section 4's owned key rests on `(vendor, sku)` being a
stable identity; §1.3 verified that across two snapshots two days apart, which cannot rule
out a slower failure — a vendor retiring a SKU and later reusing the string for a
different product. If that happens, one key silently splices two unrelated price series.

Heuristic: for keys with an observation gap > 30 days, does the price level shift
discontinuously on resumption? Compared against a baseline of normal 1–7 day gaps.

> ### RESTATED in §5.5. The figures below are the corrected ones.
> The originally published values — 3,845 moves >50% (3.25%), 663 >200% (0.56%), a 0.41%
> baseline — were computed on a build that **predated the §2.5 bare-integer-cents fix**.
> They are not wrong arithmetic; they are arithmetic on 79,478 Walmart prices that were
> wrong by 100×. §2.5's "Ordering of the fixes, stated" audited §2.3's numbers for exactly
> this and did not extend to §2.6. Every figure in this section is now from the fixed
> build. See §5.5 for the delta and what it costs this section's conclusion.

| | Long gaps (>30d) | Baseline (1–7d) |
|---|---|---|
| Events | 118,430 | 58,827,148 |
| Distinct keys | 76,824 | — |
| Median gap | 73 days | — |
| **Median price move** | **0.00%** | **0.00%** |
| **Moves > 50%** | **3,484 (2.94%)** | **0.23%** |
| Moves > 200% | **296 (0.25%)** | — |

**The signal is real but small.** Large price moves are **12.8× more likely** after a long
gap than after a normal one (2.94% vs 0.23%). The median move is zero in both, so the
typical long gap is entirely benign — it is the tail that differs.

Note that the *ratio* got **stronger** under the corrected figures (12.8× against the
originally reported 8×) even though both numbers fell, because the baseline fell
proportionally further. The qualitative conclusion survives; the absolute risk upper bound
more than halves.

Per vendor, the >200% moves concentrate sharply:

| Vendor | Gap events | Median gap | Moves > 200% | *(as first published)* |
|---|---|---|---|---|
| **Walmart** | 27,828 | 51 days | **49** | *416* |
| Metro | 18,083 | 69 days | 95 | 95 |
| Galleria | 5,639 | 106 days | 59 | 59 |
| SaveOnFoods | 4,497 | 70 days | 55 | 55 |
| Loblaws | 23,467 | 73 days | 16 | 16 |
| NoFrills | 29,196 | 71 days | 15 | 15 |
| TandT | 5,925 | 76 days | 7 | 7 |
| Voila | 3,795 | 94 days | **0** | 0 |

**The entire correction is Walmart, 416 → 49. Every other vendor is unchanged to the
row.** That is the signature of a parser artifact rather than a data change, and it is
what §5.5 confirms directly.

The sample makes the mechanism visible — and it is **not grocery repricing**:

| Vendor | SKU | Gap | Before | After | Move | Still present? |
|---|---|---|---|---|---|---|
| Metro | `4341` | 458 d | $16.90 | **$14,858.40** | 87,820% | **yes** |
| NoFrills | `20891206001_KG` | 71 d | $0.01 | $2.75 | 27,400% | **yes** |
| Walmart | `3RGEXVPTBDWG` | 122 d | $0.99 | $170.90 | 17,163% | **yes** |
| Walmart | `226PJRK24U5X` | 37 d | $4.37 | ~~$1,074.00~~ | ~~24,477%~~ | **no — parser** |
| Walmart | `6000205233379` | 615 d | $13.47 | ~~$2,196.00~~ | ~~16,203%~~ | **no — parser** |

**Two of the four originally published examples were parser artifacts, and this is the
bad news of §5.5.** `226PJRK24U5X` reads `1074` in the source and now parses as **$10.74**,
not $1,074.00; `6000205233379` reads `2196` and now parses as **$21.96**. Both are
`bare_integer_cents` rows — the exact defect §2.5 found and fixed — and both were quoted
here as evidence of SKU reuse.

What survives, and what does not:

- **Metro `4341` survives.** It is a four-digit PLU produce code — the shared, non-unique
  code space Phase 0 B4c identified, where reuse is expected rather than surprising. This
  half of the conclusion is unaffected, and Metro/Galleria's counts did not move at all.
- **The Walmart marketplace-ID story is substantially weakened.** It rested on opaque IDs
  jumping from grocery scale to appliance scale; most of that jump was our parser reading
  cents as dollars. Walmart's >200% count falls from 416 to 49 — from **the largest** such
  count of any vendor to **fourth**, behind Metro, Galleria and Save-On-Foods.
  `3RGEXVPTBDWG` is a genuine case and the mechanism is real, but 49 events is not the
  evidence 416 looked like.

**Verdict, as a risk statement.** An upper bound of **296 gap events across 76,824 keys
with gaps (0.25%)** show a discontinuity large enough to be consistent with SKU reuse.
That is an upper bound, not an estimate: a genuine relisting at a new price, a seasonal
item returning, or a unit-size change would all look identical here. The heuristic cannot
separate them and no attempt is made to.

**What this changes: nothing yet, deliberately.** It is not enough to complicate Section
4's key, and acting on 0.25% by adding a splice-detection layer would be building
machinery for a problem we have not confirmed exists.

It is enough to justify **one** thing in a later phase — excluding four/five-digit
PLU-style SKUs from single-vendor time series, where the evidence is unchanged. The
second recommendation this section originally made, **treating Walmart marketplace IDs as
a lower-confidence identity tier, is withdrawn to "worth a look" rather than "justified"**:
it was carried by 416 events of which 367 were our own 100× parse error. Both remain Phase
2 decisions, but they no longer have the same weight behind them and should not be
presented as if they did.

*Source: `P2_6_sku_reuse_heuristic.sql`.*

### 2.5 Correctness sweep — **it found a fifth variant, and that one was silently wrong**

Coverage said 100.00%. Coverage says a number came out; it says nothing about whether the
number is right. The four cents-form variants in §2.1 were found by *looking twice* —
reading a shape census, noticing `a$N`, asking what it was. That method finds the defects
someone thought to look for.

**The method that finds the fifth without looking:** a magnitude error in a price parser
has a signature. Within one product's own history the price jumps by exactly a power of
ten and back. Real prices do not do that. So: within each `(vendor, sku)`, flag adjacent
observations (≤3 days apart, same `price_basis`) whose ratio sits near 100×, 0.01×, 10× or
0.1×.

#### What it caught

| Vendor | Flagged pairs | x100 | x0.01 | x10 | x0.1 | **Per million pairs** |
|---|---|---|---|---|---|---|
| **Walmart** | **104,640** | 52,991 | 51,617 | 21 | 11 | **22,145** |
| NoFrills | 29 | 4 | 4 | 5 | 16 | 3.4 |
| Galleria | 14 | 0 | 0 | 9 | 5 | 2.5 |
| Voila | 18 | 4 | 3 | 4 | 7 | 1.7 |
| TandT | 3 | 0 | 0 | 0 | 3 | 0.6 |
| Loblaws | 7 | 3 | 3 | 1 | 0 | 0.6 |
| Metro | 3 | 1 | 2 | 0 | 0 | 0.5 |
| SaveOnFoods | 2 | 0 | 0 | 1 | 1 | 0.3 |

Walmart sat **four orders of magnitude above every other vendor**. That is not a price
pattern; that is a parser bug.

The sample showed the mechanism immediately: the same SKU reads `298` one day (parsed as
**$298.00**) and `Now$298` the next (parsed correctly as **$2.98**).

#### The fifth variant: Walmart bare-integer cents

Walmart writes some prices as a **bare integer in cents with no marker at all**. `298`
means $2.98. There is no `$`, no `Now`, nothing to distinguish it from a dollar amount —
so it parsed cleanly, produced a plausible number, and was wrong by 100×. **This is the
defect class the sweep exists to catch: not a parse failure, a parse success at the wrong
magnitude.** Nothing in the coverage report could ever have shown it.

#### Adjudication, before writing any rule

Rather than assume "Walmart bare integer = cents", each bare-integer row was checked
against the same SKU's nearest non-bare price within 7 days:

> **Restated in §5.8, and the reason is not staleness.** This query resolved multiple
> candidate reference prices with `any_value()`, which picks arbitrarily. Three runs over
> the same immutable snapshot and the same build returned **57,008 / 57,212 / 56,598** for
> the 100–999 cents count. The published figures were not wrong-for-their-build; they were
> **irreproducible**, which honesty rule 4 now names explicitly. The query takes the
> genuinely nearest reference price and is verified identical across three runs. The
> **adjudicable row counts never moved** — 1,631 / 3,008 / 58,267 / 8,271 then and now —
> and neither did the verdict.

| Walmart magnitude | Adjudicable rows | Matches **dollars** | Matches **cents** | Verdict | *(as published)* |
|---|---|---|---|---|---|
| < 10 | 1,631 | **1,190** | 0 | dollars | *1,189 / 0* |
| 10–99 | 3,008 | 1,769 | 1,067 | **genuinely ambiguous** | *1,767 / 1,048* |
| 100–999 | 58,267 | **0** | 57,587 | cents | *0 / 56,567* |
| 1000+ | 8,271 | **0** | 8,091 | cents | *0 / 7,878* |

**The load-bearing claim is unmoved and was never at risk: `matches_dollars = 0` for both
bands ≥ 100, in every run of both versions.** The rule rests on 0 of 66,538, not on the
cents counts, which is why an irreproducible supporting figure did not produce a wrong
decision. It could have, on a different question.

Galleria also has 26,306 bare integers, but only 131 are adjudicable and they split 21/21
— **no evidence, so no rule.** Galleria keeps the literal reading. Assuming the two
vendors shared one defect would have introduced a new error while fixing another.

#### The rule, and its cost

`normalization = 'bare_integer_cents'` for Walmart bare integers ≥ 100: **79,478 rows**,
now reading $1.00–$69.96 instead of $100–$6,996.

The 10–99 band is **not converted**. The evidence is genuinely mixed there, so those rows
keep the literal reading and get `parse_confidence = 'ambiguous'` — flagged, never
guessed. **20,555 Walmart rows** carry that flag.

**This is a vendor-specific rule and therefore a maintenance liability.** It is justified
because the evidence is one-sided rather than suggestive — 0 of 66,538 rows ≥100 matched a
dollars reading — and because the alternative is knowingly leaving 79,478 rows wrong by
100×. The magnitude bands are not arbitrary: each is where the evidence changes sign.

#### Did the fix hold? Re-sweep

| | Before fix | After fix |
|---|---|---|
| Flagged pairs | **104,716** | **1,825** |
| Walmart | 104,640 | 1,749 |

**A 98.3% reduction.** The residual 1,825 is itself informative:

- **~1,700 Walmart pairs are the 10–99 ambiguous band** — the rows deliberately flagged
  rather than converted. The sweep confirming they still flip 98.00 ↔ 0.98 is the system
  working: the uncertainty is marked, not hidden.
- **7 Voila pairs are a sixth defect.** Voila SKUs read `19.26` one day and `1,926.25` the
  next, so Voila's thousands-separator form is *also* cents. Walmart's thousands-separator
  values (`4,898.99`) are marketplace electronics and appear genuine, so this is not a
  general rule about the shape. **23 Voila rows** — too few to justify a third
  vendor-specific *conversion* rule, so they are flagged `ambiguous` on the same principle
  as the Walmart band. Documented rather than silently converted.

**Total flagged `ambiguous`: 20,578 rows** (Walmart 20,555, Voila 23). These have a
`unit_price` that may be wrong by 100×, and downstream must filter on
`parse_confidence <> 'ambiguous'` for any magnitude-sensitive analysis.

**What this changes in the Section 2 numbers:** the D2 recovery figure (6,418) is
unchanged, because those rows always parsed — just wrongly. Coverage stays 100.00%. What
changed is that **79,478 rows now carry the right value instead of a plausible wrong one**,
and 20,578 carry an honest warning instead of false confidence.

*Source: `P2_7_magnitude_sweep.sql`, `P2_9_bare_integer_adjudication.sql`.*

### 2.6 Ordering of the fixes, stated

**Question: were the Walmart `Now$NNN` and `NN¢` variants fixed before or after the
100.00% and 6,418 figures were computed?**

**Before.** Verified from git rather than from memory: `models/price_parse_macros.sql` has
exactly one committed version, and it contains `p_is_now_cents` and `p_is_cent_sym` from
the first line of it. The sequence was: P2.1 shape census surfaced the `a$N` and `N¢`
signatures → examples retrieved (`Now$298`, `99¢`) → P2.1b quantified them → **then** the
macros were written with all four variants → model built → coverage and recovery computed.

No recomputation was needed for those two. **The bare-integer variant found in §2.5 is a
different matter** — it was found *after*, and both figures were recomputed against the
fixed build. The current numbers are:

| Figure | Value | Changed by the §2.5 fix? |
|---|---|---|
| `current_price` computable | 100.000% | no |
| Unparsed rows | 33 | no |
| D2 events recovered | **6,418** | no |
| Metro multibuy recovered | **925 of 925** | no |
| D2 evaluable events | 279,599 → 279,593 → **279,599** | no — the 6-event dip was a hash collision, fixed in §3.5 |
| D2 usable events | 279,596 → 279,590 → **279,596** | no — same cause, fixed in §3.5 |
| Sale events total | 566,564 → 566,558 → **566,564** | no — same cause, fixed in §3.5 |

**The 6-event drift was not from the price fix — it was a hash collision, and it was
mine. §3.5 replaces the workaround with a collision-free owned key and the counts return
to their exact original values.**
To work around a DuckDB 1.5.5 statistics bug, the queries key on
`hash(vendor || '|' || sku)` rather than the string pair. There is **exactly 1 collision
in 161,300 keys**, which merges two products into one series and costs 6 sale events.
Measured, not estimated. It was a 0.0006% effect on a number reported to 6 significant
figures. **Resolved in §3.5: D2's usable sample is 279,596, exactly.**

### 2.7 `old_price`: value versus presence

D2 is not one analysis. Its sub-questions need `old_price` differently, and the 869,495
`'was'` rows are usable for some and useless for others.

| D2 sub-analysis | Needs old_price as… | Affected by `'was'`? |
|---|---|---|
| **Was the price raised before the sale?** *(the one that matters)* | **flag only** — locate the event; the pre-sale level comes from `current_price` over the prior 14 days | **No** |
| How often does this product go on sale? | flag only | No |
| Time since previous sale | flag only | No |
| Is it "always on sale"? | flag only | No |
| **How deep was the discount?** | **numeric value** | **Yes** |
| Did the discount deepen over the sale run? | numeric value | Yes |
| Sale price vs cross-vendor comparison | numeric value | Yes |

**The pre-sale-inflation test — the one that matters — needs `old_price` only as a flag.**
It locates the sale event; the pre-sale price level comes from `current_price` across the
preceding 14 days, which parses at 100%. So the `'was'` rows do not touch it.

Row-level coverage, presence vs usable value:

| Vendor | Rows | old_price **present** | old_price **usable value** | Present but valueless |
|---|---|---|---|---|
| **Loblaws** | 14,013,669 | 18.53% | **12.38%** | **33.18%** |
| NoFrills | 11,024,382 | 13.98% | 13.91% | 0.50% |
| SaveOnFoods | 7,093,027 | 33.07% | 33.07% | 0.00% |
| Metro | 8,203,156 | 29.53% | 29.52% | 0.00% |
| Voila | 12,937,809 | 19.05% | 19.05% | 0.00% |
| Walmart | 6,372,804 | 11.53% | 11.53% | 0.00% |
| TandT | 5,393,781 | 6.19% | 6.19% | 0.00% |
| Galleria | 5,892,146 | 0.92% | 0.92% | 0.00% |

#### D2's Loblaws exposure, stated

The row-level figure (33.18% of Loblaws sale rows carry no usable value) **does not
translate to a 33% loss at the event level**, because a sale event spans several days and
needs only one day with a value:

| Vendor | D2 evaluable events | With a usable `old_price` value | **Flag-only** |
|---|---|---|---|
| **Loblaws** | 43,253 | **39,274 (90.80%)** | **3,979 (9.20%)** |
| NoFrills | 38,218 | 38,014 (99.47%) | 204 |
| Every other vendor | — | **100.00%** | 0 |

**So D2's Loblaws exposure is:**

- **Pre-sale-inflation test: 43,253 of 43,253 events usable — zero exposure.** It needs
  the flag, not the value.
- **Any discount-depth analysis: 39,274 of 43,253 usable (90.80%), losing 3,979 events.**
  That loss is Loblaws-specific and must be reported with its denominator whenever depth
  is quoted, because no other vendor loses anything.

The practical consequence: **a cross-vendor discount-depth comparison silently
under-samples Loblaws by 9.2%** unless the exclusion is stated. Given Loblaws is the
largest vendor by row count, that is worth carrying forward rather than discovering later.

*Source: `P2_8_old_price_value_vs_presence.sql`.*

### Reproducibility of the materialisation — asserted, not claimed

`stg_price` is a **cache, not an artifact**. Every value is a pure function of (a) the
immutable snapshot under `data/snapshots/<id>/`, verified by sha256, and (b) the committed
SQL in `models/`. Nothing is hand-edited, nothing accumulates across builds — the model is
dropped and recreated in full each run.

`scripts/verify_reproducible.py` checks this rather than asserting it: it recomputes the
model definition as a view over `raw` and compares an order-independent checksum per
column against the materialised table.

```
cached rows     : 71,809,333
recomputed rows : 71,809,333
  ok  src_rowid ... ok  other_raw      (21 columns)

OK - stg_price matches its definition across 21 columns.
     The materialisation is a cache and can be deleted safely.
```

The verifier attaches the database **read-only** and creates its macros in a separate
in-memory catalog — a verifier that can modify what it verifies is not a verifier.

Rebuilding from nothing:

```bash
python scripts/load_snapshot.py 20260822T134045Z --db hammer.duckdb
python scripts/build_models.py --db hammer.duckdb --materialize table
python scripts/verify_reproducible.py --db hammer.duckdb
```

**One build bug found and fixed while establishing this.** `build_models.py` issued
`DROP VIEW IF EXISTS` before `DROP TABLE IF EXISTS`; DuckDB *raises* rather than no-ops
when the type mismatches, so the first rebuild after the §2.5 fix failed — and, worse,
the subsequent queries ran happily against the **stale** table while the log showed a
failure several screens earlier. The script now checks the existing object's type before
dropping. A build step that can silently leave old data in place is exactly the failure
mode Section 5's reconciliation tests are meant to catch, arriving early.
---

## Section 2 — what changed, in one place

| Item | Before | After |
|---|---|---|
| `current_price` computable | 98.06% (naive cast) | **100.000%** |
| Unparsed `current_price` rows | 1,303,020 | **33** |
| D2 events lost to price shape | 6,421 | **3** |
| Metro multibuy events in D2 | 0 of 925 | **925 of 925** |
| Price shapes handled | 1 (scalar) | 9 named, **5 repair rules** |
| Cents-form vendors known | Loblaws | **Loblaws + Walmart**, **5 variants** |
| Rows silently wrong by 100× | **79,478** (undetected) | **0** |
| Rows flagged `ambiguous` | — | **20,578** (honest uncertainty) |
| `old_price` junk identified | — | **869,495 rows of `was`** |
| Materialisation verified reproducible | — | **21 of 21 columns** |

**Not done in Section 2, and why:** 2.4's agreement quantification is deferred to Section
3, which now has an additional job: `price_per_unit`'s implied `pack_count` becomes a
**cross-check on the unit parser**, not a field to be validated against it.
**Resolved in §3.4** — and it earned its keep immediately by finding a representation flaw
in the unit parser on first run.

## Section 3 — Unit representation

**Status: complete.** Headline: **88.84% of products with a units string parse to a
canonical (quantity, unit, pack_count).** The pack-count cross-check found and fixed a
representation flaw that no amount of re-reading the parser would have surfaced.

### 3.1 Canonical unit parse

`stg_product` resolves every product to:

| Column | Meaning |
|---|---|
| `unit_qty` | size of ONE item, in g / mL / count |
| `unit_uom` | `g` \| `ml` \| `count` |
| `pack_count` | how many items in the listing (`2 x 500 mL` → 2) |
| `total_qty` | `unit_qty × pack_count` — the size you actually buy |
| `unit_parse_confidence` | `exact` \| `derived` \| `inferred` \| `none` |
| `units_raw` | always retained |

Per-item size and pack count are kept **separate** deliberately: `2 x 500 mL` and `1 L`
are the same total volume but not the same product. Collapsing them at parse time discards
a distinction that cannot be recovered downstream.

| Vendor | Products | No units text | Parsed | **% of text parsed** |
|---|---|---|---|---|
| SaveOnFoods | 16,158 | 1 | 16,155 | **99.99%** |
| Voila | 26,320 | 750 | 25,565 | 99.98% |
| Loblaws | 31,688 | 1,718 | 29,754 | 99.28% |
| NoFrills | 24,398 | 839 | 23,359 | 99.15% |
| Metro | 26,311 | 661 | 25,157 | 98.08% |
| TandT | 13,542 | 964 | 12,021 | 95.57% |
| Galleria | 10,697 | 112 | 10,062 | 95.06% |
| **Walmart** | 37,914 | 249 | 19,375 | **51.44%** |
| **All** | **187,028** | **5,294** | **161,448** | **88.84%** |

The two denominators are reported separately on purpose: 5,294 products have **no units
text at all** (nothing to parse) and are a different problem from text that fails to parse
(something to fix). A single percentage hides which is which.

| Unit | Products | Multipacks | Median item size | Median total | Max pack |
|---|---|---|---|---|---|
| g | 112,177 | 4,926 | 280 g | 300 g | 800 |
| ml | 39,407 | 5,285 | 473 mL | 510 mL | 800 |
| count | 9,864 | 7,614 | 1 | 10 | 2,036 |

`2 x 500 mL` is handled, as are `12x355.0ml`, `4 x 100g`, `60gx6` and `93ML*6`.

**One parser bug found while building this.** The trailing-multiplier form (`60gx6`) failed
entirely: the unit token `g` is followed by `x`, a word character, so the `\b` anchor never
matched. It is stripped before token extraction now. Unit tests: **16 of 16 pass.**

The unparsed tail is unchanged from Phase 0 C1 and is dominated by Walmart marketing text
(`perfect every time™`, `shelf stable`, `sold in singles`), the `error` sentinel (409
products) and Galleria's bare `ea` / `current price: lb`.

*Source: `P3_1_unit_parse_rate.sql`.*

### 3.2 Walmart's 51% — is the size recoverable? **Recommendation: no. Do not build it.**

The brief asks for a recommendation, not a decision. Here is the evidence.

**The cause is confirmed, and it is worse than "bad formatting".** `concatted` has the form
`vendor~product_name@units^brand`, and for **6,898 Walmart products (18.19%)** the units
slot holds a **verbatim copy of the product name**. Every other vendor: 0.00%. So the size
was never captured into that field — it is not hiding in `concatted` either.

That leaves the product name itself, which for Walmart often ends `..., 90 g`.

| Vendor | Unparsed products | Size suffix in name | **% recoverable** |
|---|---|---|---|
| **Walmart** | **18,290** | **6** | **0.03%** |
| TandT | 557 | 22 | 3.95% |
| NoFrills | 200 | 4 | 2.00% |
| Metro | 493 | 1 | 0.20% |
| Voila | 5 | 4 | 80.00% |
| Galleria | 523 | 0 | 0.00% |
| Loblaws | 216 | 0 | 0.00% |
| SaveOnFoods | 2 | 0 | 0.00% |

*(The Save-On-Foods row was missing from this table until §5.8 re-ran the query. It
changes nothing — 2 products, none recoverable — but a table with a vendor silently
absent is the shape of a real error, so it is filled in rather than left short.)*

**Six products.** Out of 18,290.

The rule would be *accurate* — validated against 14,700 Walmart products where `units`
already parses AND the name carries a size suffix, the two agree **99.39%** of the time.
That control matters: a rule tested only on the rows it was built for is not tested. So
this is not a case of an unreliable heuristic. It is a reliable heuristic with almost
nothing to work on.

**Recommendation: do not build it.**

- **Cost:** a vendor-specific extraction rule, permanently in the codebase, needing
  maintenance whenever Walmart's naming changes, and a second place where size can come
  from — which means a second place for size bugs to hide.
- **Benefit:** 6 products, 0.03% of the target population. Walmart's parse rate would go
  from 51.44% to 51.46%.
- **The honest framing:** Walmart's missing sizes are not a parsing problem we can solve.
  They are absent from the published data. §2 already recommends this to the maintainer as
  a field-assignment bug; that is where the fix belongs.

**What to do instead:** treat Walmart's unit coverage as a stated limit. Any size-normalised
analysis (price per 100 g, shrinkflation, unit-price comparison) covers ~51% of Walmart's
catalogue and must say so. That is a smaller loss than it sounds, because the products that
*do* parse are the packaged goods those analyses target; the ones that do not are largely
marketplace items.

**Where I would change my mind:** if Walmart's share of the D4 reliable-tier basket turned
out to depend on the unparsed half, 6 products would not fix it either — the answer would
still be an upstream fix, not a downstream rule.

*Source: `P3_2_walmart_size_recovery.sql`.*

### 3.3 Junk handling — junk does not default to a real category

`brand_class` in `stg_product` now has an explicit unclassifiable verdict, split three ways
so the **reason** is visible rather than collapsed:

| Vendor | Products | Private label | National brand | Blank | Junk | No vendor data | **% unclassifiable** |
|---|---|---|---|---|---|---|---|
| Voila | 26,320 | 0 | 0 | 0 | 0 | 26,320 | **100.00%** |
| TandT | 13,542 | 0 | 0 | 0 | 0 | 13,542 | **100.00%** |
| Galleria | 10,697 | 0 | 0 | 0 | 0 | 10,697 | **100.00%** |
| Walmart | 37,914 | 1,084 | 24,080 | 12,316 | **434** | 0 | 33.63% |
| SaveOnFoods | 16,158 | 2,967 | 11,463 | 1,714 | **14** | 0 | 10.69% |
| Loblaws | 31,688 | 4,607 | 24,114 | 2,967 | 0 | 0 | 9.36% |
| Metro | 26,311 | 3,568 | 20,754 | 1,986 | **3** | 0 | 7.56% |
| NoFrills | 24,398 | 3,880 | 19,129 | 1,389 | 0 | 0 | 5.69% |

All **451 junk values** land in `unclassifiable_junk`, none in `national_brand`:

| Vendor | Value | Products |
|---|---|---|
| Walmart | `Unbranded` / `unbranded` | 260 |
| Walmart | `Out of stock` | 174 |
| SaveOnFoods | `-` | 11 |
| SaveOnFoods | `N/A` | 3 |
| Metro | `.` | 3 |

Symmetrically, the `error` sentinel in `units` (409 products) and `n/a` (1) parse to
**NULL, not a size** — `wrongly_parsed = 0` for both.

#### Why this mattered — the bias it removes

If unknowns had fallen through to national brand, private-label share would have been
understated by exactly the invisible amount:

| Vendor | PL share if junk defaults | PL share, classifiable only | **Understatement** |
|---|---|---|---|
| SaveOnFoods | 18.36% | 20.56% | **2.20 pp** |
| Loblaws | 14.54% | 16.04% | **1.50 pp** |
| Walmart | 2.86% | 4.31% | **1.45 pp** |
| Metro | 13.56% | 14.67% | **1.11 pp** |
| NoFrills | 15.90% | 16.86% | **0.96 pp** |

Metro's freeze claim is scoped to *"all private label and national brand grocery
products"*. Understating private-label share by 1.11 pp at Metro is not catastrophic on its
own — but it is a **one-directional** error, and it would have been invisible, which is the
combination that turns a small bias into a wrong conclusion.

The three-way split also makes the T&T / Galleria / Voila situation legible: they are not
0% private label, they have **no brand data at all**. `unclassifiable_no_vendor_data` says
that; `national_brand` would have silently claimed the opposite.

*Source: `P3_3_brand_classification.sql`.*

### 3.4 `price_per_unit` as a cross-check ON the parser (brief 2.4, folded in)

§2.4 established that comparing `price_per_unit` against our `unit_price` measures nothing,
because they are different quantities. But their **ratio is a pack count**, derived from
upstream's own arithmetic — sharing no inputs and no code with our text parsing:

```
implied_pack = unit_price / price_per_unit_value        (both per-each)
```

**This immediately found a flaw in my unit parser.**

`24ea` was parsing as `unit_qty=24, pack_count=1`. Upstream's arithmetic implied
`pack_count=24`. Both encode "24 items", so total size was right — but the count was in the
**wrong column**, and a caller asking *how many items am I buying* was told **one**.

For a count-type unit there is no separate per-item size: the number *is* the pack count.
Fixed: `24ea` → `unit_qty=1, pack_count=24, total_qty=24`.

**Agreement before and after, on 137,898 comparable rows** (4% deterministic sample, rows
flagged `ambiguous` excluded):

| Vendor | Before fix | **After fix** |
|---|---|---|
| Voila | 0.01% | **52.20%** |
| SaveOnFoods | 0.59% | **68.33%** |
| Loblaws | 45.33% | **67.15%** |
| NoFrills | 56.98% | **70.26%** |
| Metro | 44.96% | **59.90%** |
| Walmart | 0.00% | 0.00% *(n=16 — negligible)* |

Count-type multipacks detected went from **83 to 7,614**.

**The residual disagreement is upstream rounding, not parser error.** `price_per_unit` is
published to 2 decimals, so dividing by it cannot recover an exact integer — $5.99 / $0.50
gives 11.98, not 12:

| Tolerance | Agreement |
|---|---|
| ±0.05 absolute | 65.15% |
| **±2% relative** | **85.05%** |
| ±5% relative | 88.80% |
| ±10% relative | 90.32% |

**Two genuine parser gaps remain**, both stated rather than fixed:

1. **Compound size-and-count strings.** `355ml cans12 each` is a 12-pack of 355 mL cans.
   The parser sees `355ml` first and reports `pack_count=1`. Concentrated at Save-On-Foods.
2. **Pack size stated only in the product name.** `Romaine Hearts, 2-Pack` with
   `units = '1ea'`. The pack count is in the name, and per §3.2 I am not building
   name-extraction rules.

**Recommendation on importing upstream's pack count: not in Phase 1.** It is tempting —
`price_per_unit` demonstrably knows things `units` does not. But it is a *derived* upstream
figure with its own rounding and its own defects (§2 found four price-encoding bugs in the
same family of fields), and adopting it would make our parse depend on a column CLAUDE.md
already flags as untrustworthy. Its correct role is the one it just played: **an independent
check that catches our errors**, kept separate so it can keep catching them. Using it as an
input would destroy exactly the independence that made it useful.

*Source: `P3_4_packcount_crosscheck.sql`.*

### 3.5 The owned key — collision-free, proved, and D2 restated exactly

The analysis queries in §2 and §3 keyed on DuckDB's 64-bit `hash()` as a workaround for a
statistics bug on VARCHAR `sku` columns. That workaround produced **one collision in
161,300 keys**, silently merging two distinct products into a single price series and
moving the D2 event count by 6. Acceptable in a throwaway query; **not acceptable in the
owned key**, and collision probability grows with the catalogue.

**Construction** (`models/product_key_macros.sql`):

```
product_key = md5( vendor || chr(31) || sku )                    where sku is present
product_key = md5( vendor || chr(31) || '#c:' || concatted )     where it is not
```

Two deliberate choices:

- **`chr(31)`, ASCII UNIT SEPARATOR, as the delimiter.** It cannot occur in a vendor name
  or a SKU, so `('Metro','12'||'34')` and `('Metro','1234')` cannot collide through
  concatenation. A `'|'` would be a *guess* about the data; `chr(31)` is a *guarantee*
  about the encoding.
- **md5, 128-bit.** At 64 bits the birthday bound puts a collision near 2^32 keys — but
  the bound is probabilistic, and 161,300 keys already hit one. 128 bits removes the
  concern rather than deferring it. md5's hex output is also pure ASCII, which sidesteps
  the invalid-UTF-8 statistics bug that motivated the workaround in the first place. Both
  problems, one construction. (Used as a checksum, not for security — adversarial
  collisions are not a threat model for a grocery price key.)

#### The proof

| Scope | Distinct key sources | Distinct keys | **Collisions** |
|---|---|---|---|
| Snapshot 1 | 187,028 | 187,028 | **0** |
| Snapshot 2 | 187,070 | 187,070 | **0** |
| **Union of both** | **187,087** | **187,087** | **0** |
| *64-bit workaround, same data* | *161,300* | *161,299* | ***1*** |

Zero — not "few". The union matters as much as the per-snapshot result: a key that is
collision-free within one publication but not across them reintroduces the problem on the
first cross-snapshot join.

**Key composition and cross-snapshot behaviour:**

| Basis | Products | Share |
|---|---|---|
| `vendor_sku` | 161,300 | 86.24% |
| `vendor_concatted` *(blank sku)* | 25,728 | 13.76% |

| Check | Result |
|---|---|
| Keys matching across snapshots on the owned key | 161,290 |
| Keys matching across snapshots on `(vendor, sku)` | 161,290 |
| **Disagreement** | **0** |

The owned key behaves exactly like `(vendor, sku)` across publications — it adds
collision-freedom and a blank-sku branch without changing identity semantics.

#### D2 evaluable count, restated exactly

Re-running the D2 reconciliation on the collision-free key **restores the original figures
exactly**. The 6-event drift was entirely the hash collision:

| | With 64-bit hash | **With owned key** |
|---|---|---|
| Sale events | 566,558 | **566,564** |
| Evaluable events | **279,599** | **279,599** |
| Lost pre-parse | 6,421 | **6,421** |
| Lost post-parse | 3 | **3** |
| Recovered | 6,418 | **6,418** |
| **Usable** | ~279,590 | **279,596** |
| Metro multibuy recovered | 925 of 925 | **925 of 925** |

**D2's usable sample is 279,596 events. No tilde.**

*Source: `P3_5_key_collision_proof.sql`, `P2_3_d2_reconciliation.sql`.*

### 3.6 Galleria bare integers — flagged, not left as dollars

Galleria has **26,306 bare-integer prices**. §2.5 declined to convert them, because P2.9
found only 131 adjudicable rows splitting 21 dollars / 21 cents — no evidence either way.
Declining to convert was right. **Leaving them parsed as dollars was not.**

"A bare integer means dollars" is an *unevidenced default*, and it is the same default that
was wrong for Walmart on 66,538 rows. Keeping it is not neutrality — it is picking one of
two readings and hiding the choice. They are now flagged `parse_confidence = 'ambiguous'`.

| Vendor | Price rows | Ambiguous rows | **% of vendor rows** | Distinct products |
|---|---|---|---|---|
| **Galleria** | 5,892,146 | **26,306** | **0.446%** | 90 |
| Walmart | 6,372,804 | 20,555 | 0.323% | 340 |
| Voila | 12,937,809 | 23 | 0.000% | 5 |
| All others | — | **0** | 0.000% | 0 |

**Total ambiguous: 46,884 rows across 435 distinct products.**

Galleria's 26,306 rows concentrate in just **90 products** — an average of 292 daily
observations each, i.e. a handful of long-lived listings, not a broad contamination.

#### Does D4 depend on any of them?

D4's basket is the reliable-tier UPC set, and **Galleria and Walmart are two of its four
vendors**, so this is not hypothetical.

| Measure | Value |
|---|---|
| D4 reliable-tier basket GTINs | 5,222 |
| **GTINs with any ambiguous price row** | **27** |
| **% of basket touched** | **0.52%** |

And of those 27, how much of their history is ambiguous:

| Share of history ambiguous | GTINs |
|---|---|
| <1% | 13 |
| 1–10% | 10 |
| 10–50% | 4 |
| **≥50% (unusable)** | **0** |

**No basket product is majority-ambiguous.** D4 loses 27 of 5,222 GTINs' worth of
*partial* history, and nothing wholesale.

D2's exposure is smaller still: of the 46,884 ambiguous rows, only **167 fall on a sale
day** (Walmart 162, Voila 5, Galleria 0) — Galleria's ambiguous products are never on sale
in a way `old_price` records.

*Source: `P3_6_ambiguous_semantics.sql`.*

### 3.7 Downstream semantics for ambiguous prices — decided and written into CLAUDE.md

**Decision: D2 and D4 exclude ambiguous rows from headline numbers. Excluded at query
time, never at load time, with every published figure stating how many rows it dropped.**

Added to `CLAUDE.md` as honesty rule 3 (existing rules 3–7 renumbered to 4–8).

**Why exclusion rather than a confidence tier.** A tier says "this signal is weaker" and
invites averaging it in with a lower weight. That is the wrong mental model here: an
ambiguous price is not *less precise*, it is **possibly wrong by 100×**. There is no
average of $2.98 and $298 that means anything. The two readings are not a distribution
around a true value; they are two different claims, one of which is false.

**Three supporting rules, also written down:**

- Ambiguous rows are **never deleted and never silently converted**. They stay in
  `stg_price` with their raw text, so the set remains countable and a later decision — a
  third snapshot, an upstream fix, a vendor confirmation — can re-admit them.
- **A product is not excluded because *some* of its history is ambiguous.** Only the
  ambiguous rows are. A product whose history is mostly ambiguous will fail the existing
  coverage bars on its own; no separate rule is needed, and the §3.6 numbers confirm none
  is close (worst case 10–50%, zero at ≥50%).
- The exclusion is at **query time**, so the count is always reportable. Dropping at load
  time would make "how many rows did we exclude?" unanswerable, which is precisely the
  question honesty rule 7 (report the denominator) requires an answer to.

**Category concentration.** The ambiguous set does lean toward produce:

| Category | Ambiguous rows | Share |
|---|---|---|
| other | 13,328 | 28.43% |
| **produce** | **10,550** | **22.50%** |
| meat & fish | 8,246 | 17.59% |
| beverages | 6,230 | 13.29% |
| dairy | 3,759 | 8.02% |
| pantry staples | 2,500 | 5.33% |
| bread & bakery | 2,066 | 4.41% |
| eggs | 205 | 0.44% |

Produce at 22.5% is over its share of the catalogue, which is unsurprising — loose produce
is exactly where a bare integer like `4` is genuinely ambiguous between $4.00 and $0.04.
**But this does not translate into a D4 problem**, because the categories D4 relies on are
reached through the reliable-tier UPC set, and only 27 of those 5,222 GTINs are touched at
all. The concentration is real and worth knowing; the impact on the basket is 0.52%.

### 3.8 No Section 3 number came from the stale-table window — and the build now halts

**Verified, not assumed.** The stale window occurred during the §2.5 rework, when a failed
rebuild left `stg_price` untouched while later queries ran against it. `stg_product` **did
not exist** at that point — it was introduced in a later build that succeeded ("stg_price
… OK / stg_product: table, 187,028 rows … OK"). Every `P3_*` query reads `stg_product`, so
none could have read a stale table.

Confirmed against the current build:

| Check | Value | Meaning |
|---|---|---|
| `stg_product` rows | 187,028 | exists, 1:1 with `product` |
| count-type multipacks | 7,614 | post-count-fix semantics |
| `bare_integer_cents` rows | 79,478 | post-§2.5-fix semantics |
| `ambiguous` rows | 46,884 | post-§3.6 semantics |

**Two changes so this cannot recur:**

1. **The build halts loudly.** Every model build is wrapped, and any failure prints a
   banner to stderr — `BUILD FAILED -- MODELS MAY BE STALE. DO NOT TRUST ANY QUERY RUN
   AFTER THIS.` — and returns non-zero. The original failure was a `DROP VIEW` type
   mismatch whose traceback scrolled several screens above the queries that then ran
   happily against old data.
2. **A build stamp makes staleness detectable after the fact.** `_build_stamp` records the
   sha256 of every macro and model file that produced the current tables.
   `verify_reproducible.py` compares those digests against the committed files and fails
   if the model was built from source that has since changed:

   ```
   build stamp   : OK, 6 source files match
   ```

   A build step that can silently leave old data in place while later steps report success
   is worse than one that simply fails — this makes both failure modes visible.

### 3.9 The `60gx6` fix preceded the 88.84% parse rate

**Verified empirically rather than from memory.** The rate was recomputed from the current
build, and that build parses the trailing-multiplier form correctly:

| units_raw | unit_qty | uom | pack_count | total_qty | confidence |
|---|---|---|---|---|---|
| `60gx6` | 60 | g | 6 | 360 | derived |
| `250mlx6` | 250 | ml | 6 | 1,500 | derived |
| `185gx4` | 185 | g | 4 | 740 | derived |
| `330mlx6` | 330 | ml | 6 | 1,980 | derived |

Across the whole catalogue: **2,280 products carry a trailing multiplier, 2,249 parse
(98.6%), 2,269 have `pack_count > 1`.**

88.84% was computed twice — once before the count-representation fix and once after — and
came out identical both times, from builds that both included the `u_core` strip.
**No recomputation needed.**

---

## Section 3 — what changed, in one place

| Item | Before | After |
|---|---|---|
| Unit parse rate (of products with text) | 88.12% *(Phase 0 ad-hoc)* | **88.84%** *(committed parser)* |
| `2 x 500 mL` handled | — | **yes**, plus `60gx6`, `93ML*6` |
| Count-type multipacks detected | 83 | **7,614** |
| Pack-count agreement with upstream (Voila) | 0.01% | **52.20%** |
| Junk brand values in `national_brand` | 451 | **0** |
| Private-label understatement | up to 2.20 pp | **0** |
| `error` in units parsing to a size | — | **0** |
| Owned-key collisions (both snapshots) | 1 *(64-bit workaround)* | **0** *(md5, proved)* |
| D2 usable events | ~279,590 | **279,596, exact** |
| Ambiguous rows flagged | 20,578 | **46,884** *(Galleria added)* |
| Build failure leaving stale models | possible, silent | **halts loudly + build stamp**|

**Not done, and why:** Walmart size recovery from product names — accurate rule, 6
products, recommended against. Compound size-and-count strings and name-stated pack sizes
remain unparsed and are documented above rather than papered over.

**Ambiguous-price semantics are now a project rule**, not a Phase 1 implementation detail:
CLAUDE.md honesty rule 3. D2 and D4 exclude ambiguous rows from headline numbers at query
time, always with the dropped count stated.

## Section 4 — Product identity

**Status: complete.** Headline: **the owned key covers 100% of products including the
blank-sku 13.8%, `raw.product_id` appears nowhere below staging and that is enforced
mechanically, and the cross-vendor tier model reconciles with Phase 0 exactly.**

### 4.1 The owned key

Defined in `models/product_key_macros.sql`, proved collision-free in §3.5:

```
product_key = md5( vendor || chr(31) || sku )                    where sku is present
product_key = md5( vendor || chr(31) || '#c:' || concatted )     where it is not
```

| Measure | Value |
|---|---|
| Products | 187,028 |
| **With an owned key** | **187,028 (100%)** |
| Missing a key | **0** |
| Distinct keys | **187,028** — one per product, no collisions |
| Keyed on `vendor_sku` | 161,300 (86.24%) |
| **Keyed on `vendor_concatted`** *(the blank-sku 13.8%)* | **25,728** |

The blank-sku population is covered rather than excluded. `product_key_basis` records
which branch produced each key, because the two are not equally strong: §1.4 found 12 rows
where upstream re-keyed a product from the hash form to the `vendor||sku` form after
recovering a SKU. A consumer that needs the stronger identity can filter on the basis; one
that just needs *a* key does not have to care.

#### `raw.product_id` below staging: zero, and enforced

`scripts/check_layering.py` parses the model files and fails if `product_id` appears in
any `int_*` or `mart_*` model. Staging models may reference it — they are the layer whose
job is to translate it away.

```
staging models    : 2 (stg_price.sql, stg_product.sql)
below-staging     : 1 (int_upc_match.sql)

OK - product_id appears nowhere below the staging layer.
```

**Shown to fail when it should.** Injecting `sp.product_id` into `int_upc_match.sql` and
re-running:

```
FAIL - product_id referenced below staging in 1 model(s):
  models/int_upc_match.sql:33: sp.product_id,
                                                                   (exit 1)
```

The line was reverted and the check returns to green. A rule nobody checks is a wish; this
one is now mechanical, so the announced `product_id` type change stays an ingest-layer
event by construction rather than by discipline.

*Source: `P4_1_identity_model.sql`, `scripts/check_layering.py`.*

### 4.2 Cross-vendor identity — `int_upc_match`

One row per product (187,028, 1:1 with `stg_product`). **Nothing is filtered out**: a
product with no usable UPC still appears, tiered `no_upc`. That keeps the denominator
available for every percentage and keeps lower tiers auditable rather than deleted.

#### The tier of a match is the weakest tier of its participants

Per-vendor UPC reliability comes from CLAUDE.md's Known Contamination section, but a
*match* spans two vendors, and its trustworthiness is set by the weaker one. A
Metro↔Loblaws match is not a `vendor_upc` match — it is only as good as its fuzzy side, so
it is tiered `fuzzy`.

Taking the *strongest* participant instead would let one reliable vendor launder a fuzzy
match into a headline number. That is exactly the failure honesty rule 2 exists to prevent,
and the effect is large:

| Match tier | This vendor's own tier | Products |
|---|---|---|
| fuzzy | fuzzy | 15,756 |
| **fuzzy** | **vendor_upc** | **8,920** |
| **fuzzy** | **matched_upc** | **2,964** |
| matched_upc | vendor_upc | 4,692 |
| matched_upc | matched_upc | 3,147 |
| vendor_upc | vendor_upc | 4,209 |

**8,920 products whose own UPC is vendor-direct are demoted to `fuzzy`** because the GTIN
they share is also carried by a fuzzy-tier vendor. Under a strongest-participant rule
those would have counted as reliable matches.

#### The tier census

| Match tier | Products | Distinct GTINs | % of products |
|---|---|---|---|
| `no_upc` | 114,869 | 0 | 61.42% |
| `unmatched` | 31,373 | 31,351 | 16.77% |
| `fuzzy` | 27,640 | 8,114 | 14.78% |
| `matched_upc` | 7,839 | 3,142 | 4.19% |
| **`vendor_upc`** | **4,209** | **2,080** | **2.25%** |
| `plu_short` | 1,098 | 0 | 0.59% |

`plu_short` is the 4–5 digit PLU produce codes Phase 0 B4c identified. They are **real
cross-vendor identifiers** — `4312` is Eddoes at four vendors — but they name a *commodity*
rather than a package, so mixing them into a packaged-goods basket would compare a loose
apple against a bagged one. They are kept, tiered, and excluded from the basket by tier
rather than by a silent filter.

#### Reconciliation with Phase 0 — the model must agree with the finding it was built from

| Measure | Model | Phase 0 | **Difference** |
|---|---|---|---|
| Reliable-only GTINs (2+ vendors, all reliable) | 5,222 | B4: 5,222 | **0** |
| …with 90+ co-observed days | 3,477 | B4d: 3,477 | **0** |
| …with 365+ co-observed days | 1,560 | B4d: 1,560 | **0** |

And the full vendor-count breakdown, reproducing B4's table exactly:

| Vendors on GTIN | GTINs | Reliable-only | Fuzzy-only | Mixed |
|---|---|---|---|---|
| 1 | 31,351 | 31,008 | 343 | 0 |
| 2 | 6,859 | 3,721 | 2,485 | 653 |
| 3 | 2,780 | 1,410 | 0 | 1,370 |
| 4 | 1,628 | 91 | 0 | 1,537 |
| 5 | 1,503 | 0 | 0 | 1,503 |
| 6 | 473 | 0 | 0 | 473 |
| 7 | 77 | 0 | 0 | 77 |
| 8 | 16 | 0 | 0 | 16 |

**No GTIN reaches 5+ vendors without a fuzzy participant** — unchanged from Phase 0, and
now a property of a materialised model rather than a one-off query.

The co-observation reconciliation is the first downstream use of the owned key: it joins
`stg_price` to `int_upc_match` on `product_key`, never on `product_id`, and lands on
Phase 0's number exactly.

**Headline filtering is at query time**, not at load: `WHERE is_reliable_only` or
`WHERE match_tier = 'vendor_upc'`. Lower tiers stay in the table, so "how many rows did
this exclude?" always has an answer.

*Source: `P4_1_identity_model.sql`, `models/int_upc_match.sql`.*

### 4.3 Fuzzy cross-vendor matching — not attempted

Per the brief. The `fuzzy` tier in this model is **upstream's** fuzzy UPC matching, carried
through and labelled; no new matching was performed on our side.

Two Phase 1 findings reinforce that this was the right call, beyond the brief's own
reasoning that B5's 26/30 eyeball is not a basis for shipping:

- **§1.3 / F8:** fuzzy-tier UPCs are *not stable between publications* — 10,318 gained and
  128 re-pointed to different GTINs in two days, against zero movement in the reliable
  tier. Building our own fuzzy layer on top of a base that is itself being rewritten would
  produce matches that cannot be reproduced next week.
- **§4.2:** the weakest-participant rule already demotes 11,884 products to `fuzzy`. Adding
  a second, home-grown fuzzy source would make the tier a mixture of two different error
  processes with no way to tell them apart in the fact table.

---

## Section 4 — what changed, in one place

| Item | Before | After |
|---|---|---|
| Products with an owned key | 0 | **187,028 (100%)** |
| Blank-sku products covered | — | **25,728** |
| Key collisions | 1 *(64-bit workaround)* | **0** *(proved, both snapshots)* |
| `product_id` below staging | unenforced | **0, enforced + shown to fail** |
| Cross-vendor tiers | ad-hoc per query | **materialised, 6 tiers, nothing dropped** |
| Reliable-only GTINs | B4 query | **model, reconciles exactly (0 difference)** |
| Matches laundered by a strong participant | possible | **8,920 correctly demoted** |

## Section 5 — Contracts and tests

**Status: complete.** Headline: **40 dbt tests, all passing on both snapshots; 23 of 23
fail-when-they-should cases behave as expected; and the suite found a real defect in the
owned key on its first run against real data.**

Section 5 was supposed to be bookkeeping. It was not. Writing a relationships test between
the price model and the product model surfaced a defect in Section 4's key that had been
sitting in the model since it was built, and the correctness sweep this section was asked
to re-verify turned out to have been published from a stale build. Both are below, before
the test counts, because they matter more than the counts do.

---

### 5.1 The defect the test suite found on its first run — 878,559 rows sharing one identity

**This is the worst thing in Phase 1 and it was found by a test, which is the entire
argument for writing tests.**

`stg_price` LEFT JOINs `product`, deliberately: **878,559 rows resolve to no product row
at all** (Phase 0 E2) and an INNER join would silently drop them, breaking the 1:1
contract. Those rows therefore reach the key macro with `vendor`, `sku` and `concatted`
all NULL. The macro read:

```sql
coalesce(vendor, '?') || chr(31) || '#c:' || coalesce(concatted, '')
```

`coalesce(vendor, '?')` kept the key non-null — and gave **every one of the 878,559 rows
the same md5**.

| Measure | Snapshot 1 | Snapshot 2 |
|---|---|---|
| Rows resolving to no product | 878,559 | 880,787 |
| Distinct keys among them | **1** | **1** |
| Rows whose key exists in `stg_product` | **0** | **0** |

That is not a missing key. It is a **manufactured identity**: 878,559 price rows of
unknown provenance presented as one product. §3.5 spent an entire section removing exactly
this failure from the 64-bit hash, where it merged **two** products and moved a count by 6.
This merged 878,559 rows and nobody noticed, because it was in a branch no published query
happened to reach.

#### Blast radius: zero published numbers, checked one by one

Volunteering the bad news first: it is a real defect and it was in the model for the whole
of Sections 2–4. Then the actual exposure, which I checked rather than assumed — every
Phase 1 query that touches `stg_price` reaches products through a join that excludes the
orphan key:

| Query | How it joins | Orphans reached? |
|---|---|---|
| `P2_3` D2 reconciliation | INNER `JOIN product ON p.id = s.product_id` | no |
| `P2_6` sku-reuse | INNER join to `product` / `stg_product` | no |
| `P2_7` magnitude sweep | INNER join to `product` / `stg_product` | no |
| `P2_8` old_price coverage | INNER `JOIN product` | no |
| `P3_6` ambiguous semantics | INNER `JOIN product` | no |
| `P4_1` identity model | INNER `JOIN int_upc_match USING (product_key)` | no |
| §2.2 parse coverage | reads `stg_price` directly, no join | n/a — no key used |

**No published Phase 1 figure moves.** But "every consumer happened to filter it out" is
luck, not a guarantee, and the next consumer — a D2 or D4 query in Phase 2 aggregating by
`product_key` — would have had 878,559 rows collapse into one product with no error.

#### The fix

A NULL vendor means "no product row" and nothing else: `product.vendor` is **never NULL
and never blank in either snapshot** (verified on both, not assumed). So the key is NULL
where there is no product:

```sql
CREATE OR REPLACE MACRO k_source(vendor, sku, concatted) AS
  CASE WHEN vendor IS NULL THEN NULL
       WHEN k_has_sku(sku) THEN vendor || chr(31) || trim(sku)
       ELSE vendor || chr(31) || '#c:' || coalesce(concatted, '')
  END;
```

Unknown identity is now representable, and a NULL propagates into a join as an **absence**
rather than as a false match. `coalesce(vendor, '?')` was not a safety net; it was a
non-null constraint satisfied by inventing a value.

**The fix changes exactly one column and nothing else.** `verify_reproducible.py` compares
a per-column checksum, so this is measurable rather than asserted — of 22 columns, 21 have
byte-identical checksums before and after, and `product_key` is the only one that moved:

| Column | Before fix | After fix |
|---|---|---|
| `product_key` | 660906526141231848679888005 | **659391862899380406995276451** |
| all other 21 | *unchanged* | *unchanged* |

Both databases were rebuilt and re-verified. `stg_product` and `int_upc_match` are
unaffected — `product.vendor` is never NULL there, so every one of the 187,028 / 187,070
product keys is byte-identical to before.

*Source: `dbt/models/staging/schema.yml` (the relationships test that found it),
`models/product_key_macros.sql`, `P5_6_both_snapshots_parse.sql` result 7.*

---

### 5.5 Did the retired 64-bit hash contaminate §2.5 or §2.6? **No. Zero.**

The question: §3.5 restated D2's counts after replacing the colliding 64-bit hash with the
owned md5 key, but §2.5's correctness sweep and §2.6's sku-reuse heuristic were left on
the old keying. A merged key is *especially* dangerous in both — it interleaves two price
series under one identity, manufacturing precisely the adjacent-day ratio the sweep detects
and precisely the gap-then-discontinuity the heuristic counts.

**Method.** Both keyings computed in one run from one base table, so the delta is measured
rather than compared across two runs that could differ for other reasons. A control
confirms the population is identical under both joins (**70,132,782 rows either way**), so
what changes is the key and nothing else.

**The collision, named:** hash bucket `918118051070506723`, holding

- SaveOnFoods / `00014100283522` — Goldfish Mega Bites Crackers, Cheddar Jalapeno, 167 g
- SaveOnFoods / `00064100283022` — Nutri-Grain Bars, Raspberry, 8 Each

#### §2.5 magnitude sweep — identical, to the bucket

| Keying | Flagged pairs | x100 | x0.01 | x10 | x0.1 |
|---|---|---|---|---|---|
| **md5 (owned key)** | **1,825** | 876 | 866 | 40 | 43 |
| hash64 (retired) | **1,825** | 876 | 866 | 40 | 43 |
| **Delta** | **0** | **0** | **0** | **0** | **0** |

#### §2.6 sku-reuse heuristic — identical

| Keying | Gap events | Distinct keys | Median gap | >50% | >200% | % >50 |
|---|---|---|---|---|---|---|
| **md5 (owned key)** | **118,430** | 76,824 | 73 d | 3,484 | 296 | 2.9418% |
| hash64 (retired) | **118,430** | 76,824 | 73 d | 3,484 | 296 | 2.9418% |
| **Delta** | **0** | **0** | **0** | **0** | **0** | **0** |

#### The only measurable trace of the collision anywhere

| Measure | md5 | hash64 | Delta |
|---|---|---|---|
| 1–7 day baseline adjacency events | 58,827,148 | 58,826,990 | **158** |
| Baseline % moving >50% | 0.2306% | 0.2306% | **0** |
| Flagged pairs on the colliding bucket | 0 | 0 | 0 |
| Long-gap events on the colliding bucket | 0 | 0 | 0 |

**158 adjacency pairs out of 58.8 million — 0.00027%** — and it does not move the reported
percentage at four decimal places. The two merged products simply never produced a large
adjacent-day ratio or a long gap between them.

**Answer: zero.** Not "small". Zero, on every published figure in both sections.

*Source: `P5_5_hash_collision_impact.sql`. The committed `P2_6` and `P2_7` were re-keyed
onto the owned key and re-run; both reproduce these numbers exactly.*

#### But the recomputation found a different error, and this one is real

**§2.6's published figures were computed on a build that predated the §2.5
bare-integer-cents fix.** Not a collision — a stale build:

| Figure | As published | Corrected | Cause |
|---|---|---|---|
| Moves > 50% | 3,845 (3.25%) | **3,484 (2.94%)** | §2.5 fix |
| **Moves > 200%** | **663 (0.56%)** | **296 (0.25%)** | §2.5 fix |
| Baseline % > 50% | 0.41% | **0.23%** | §2.5 fix |
| Long-gap : baseline ratio | 8× | **12.8×** | both fell, baseline further |

**The whole correction is Walmart: >200% events fall 416 → 49, and every other vendor is
unchanged to the row.** That is a parser signature, not a data change. Verified directly
against the published sample: `226PJRK24U5X` was quoted jumping $4.37 → $1,074.00; the raw
text is `1074` and it now parses as **$10.74**, `normalization = bare_integer_cents`.
`6000205233379` was quoted $13.47 → $2,196.00; raw `2196`, now **$21.96**. Two of the four
headline examples of "SKU reuse" were our own 100× error.

**What this costs.** §2.6's PLU-code conclusion is unaffected (Metro and Galleria did not
move). Its **Walmart marketplace-ID conclusion is withdrawn from "justified" to "worth a
look"** — Walmart drops from the largest >200% count of any vendor to fourth. §2.6 has been
restated in place with the correction marked rather than silently edited.

**Why this was not caught earlier.** §2.5 has a subsection, "Ordering of the fixes,
stated", written specifically to check which figures predated which fix. It audited §2.3's
numbers. It did not extend to §2.6. The lesson is that a one-off audit of "which numbers
came from which build" is not a substitute for the `_build_stamp` mechanism §3.8 added,
and the stamp only tells you the *current* build is consistent — it cannot retroactively
date a number already written into a document.

---

### 5.6 Both snapshots are parsed — the exit criterion was unmet and is now met

**Volunteering this plainly: Phase 1's exit criteria say "Every price row in *both
snapshots* has an `offer_type` and either a `unit_price` or an explicit `unparsed`
verdict." Section 2 reported 71,809,333 rows — snapshot 1 only. Snapshot 2's 213,319
additional rows and 2 additional dates had never been through the parser, and the findings
document did not say so.** `hammer2.duckdb` had also been deleted for disk space, which
made the cross-snapshot claims in §1.3, §1.4 and §3.5 unreproducible.

**Resolution: extend coverage, not amend the criterion.** Snapshot 2 was reloaded and the
models built on it.

**Why both rather than only the newer one.** Snapshot 2 carries every date snapshot 1 has
plus two more, so it is *nearly* a superset — but not exactly: §1.4 found 12 rows upstream
re-keyed between the publications. "Nearly a superset" is not a basis for discarding a
snapshot, and locked decision 2 retains both regardless. So both are parsed and both
reported. Snapshot 1 stays the basis for the published Section 2–4 numbers because that is
what they were computed on; snapshot 2 is evidence the parser holds on a publication it
never saw.

#### Row-count reconciliation, both snapshots

| Snapshot | `raw` rows | `stg_price` rows | Difference |
|---|---|---|---|
| 1 (`20260822T134045Z`) | 71,809,333 | 71,809,333 | **0** |
| 2 (`20260824T132829Z`) | 72,022,652 | 72,022,652 | **0** |

#### The exit criterion, as a number

| Snapshot | Rows | Missing `offer_type` | **Silently lost** | `unparsed` | **% resolved** |
|---|---|---|---|---|---|
| 1 | 71,809,333 | 0 | **0** | 33 | **100.000000%** |
| 2 | 72,022,652 | 0 | **0** | 33 | **100.000000%** |

"Silently lost" is the count that matters: a row with no `unit_price` *and* no explicit
`unparsed`/`blank` verdict. Zero on both.

#### The parser holds on data it never saw

| `offer_type` | Snapshot 1 | Snapshot 2 | Delta |
|---|---|---|---|
| scalar | 70,566,164 | 70,777,694 | +211,530 |
| multibuy | 679,923 | 680,161 | +238 |
| per_weight | 563,213 | 564,764 | +1,551 |
| **unparsed** | **33** | **33** | **0** |

**No new shape appeared, and the unparsed set did not grow by a single row** across two
days and 213,319 new observations.

| `normalization` | Snapshot 1 | Snapshot 2 | Delta |
|---|---|---|---|
| none | 71,563,707 | 71,769,435 | +205,728 |
| basis_rescaled | 106,264 | 106,325 | +61 |
| **bare_integer_cents** | **79,478** | **85,688** | **+6,210** |
| cents_div100 | 47,992 | 48,342 | +350 |
| now_prefix_cents_div100 | 11,506 | 12,476 | +970 |
| thousands_sep | 353 | 353 | 0 |

The `cents_div100` growth of **+350 over 2 days** matches §1.5's measured ~175 rows/day
exactly — the Loblaws defect is still accruing at a steady rate and is not spreading.

| `parse_confidence` | Snapshot 1 | Snapshot 2 | Delta |
|---|---|---|---|
| exact | 70,380,304 | 70,584,089 | +203,785 |
| derived | 818,899 | 826,667 | +7,768 |
| inferred | 563,213 | 564,764 | +1,551 |
| **ambiguous** | **46,884** | **47,099** | **+215** |
| none | 33 | 33 | 0 |

#### §3.5's cross-snapshot collision proof, now reproducible again

This is the claim that could not be re-run after `hammer2.duckdb` was deleted:

| Scope | Distinct key sources | Distinct keys | **Collisions** |
|---|---|---|---|
| **Union of both snapshots** | **187,087** | **187,087** | **0** |

**§3.5's number is confirmed exactly.** One caveat on method, recorded because I got it
wrong first: comparing distinct `(product_key, vendor, sku, concatted)` tuples reports
**559 "collisions"**, and they are not collisions. They are products whose `concatted`
changed between publications (§1.3 measured 388 name and 541 brand changes, and `concatted`
embeds both) while vendor and sku held steady. `concatted` is not an input to the key where
a sku exists, so it cannot change the key. The unit of comparison must be the **key source
string** — the exact input to md5 — not the product row.

*Source: `P5_6_both_snapshots_parse.sql`.*

---

### 5.7 Rewrite detector — added to the retention design

Appended to `docs/retention-design.md` as **Tier 2a**. The short version: §1.4's
"upstream is append-only" rests on **12 changed rows across 2 dates over one 2-day
window**, the maintainer has announced he is reworking post-processing, and honesty rule 4
silently depends on the conclusion. A per-`observed_date` row count plus a price checksum,
carried in the weekly slim delta, turns it into a monitored property without touching
archive cadence.

**One design note that changes the ask.** A price-only checksum — literally what was asked
for — **would have been blind to the only rewrite ever observed**: §1.4's 12 rows were
re-keyed at an *unchanged price*. So the detector carries two checksums, a price one and
an identity one that includes `product_id`, and they separate "our published numbers
moved" from "upstream re-keyed something". The second costs 8 bytes per date.

**Cost, measured on the real 889-date history rather than estimated:**

| Measure | Value |
|---|---|
| Rows (one per observed date, 2024-02-28 → 2026-08-23) | **889** |
| Price rows fingerprinted | 72,022,644 |
| **Parquet + zstd** | **16.77 KiB** |
| Per date | 19.3 bytes |
| Growth | ~7 KB/year |
| **Against the 8.09 MB slim delta** | **0.2%** |
| **Weekly cadence cost** | **+0.9 MB/year** |

*Source: `P5_7_rewrite_detector_size.sql`. Full detail and the "what it does not do"
section are in `docs/retention-design.md` Tier 2a.*

---

### 5.2 The tests — 40 of them, on both snapshots

Reported as counts, per brief 5.4 and honesty rule 8 ("pass rates only for tests that exist"). **These are counts of tests that
exist. They are not a pass rate for Phase 1.**

| Target | Tests | Passed | Failed |
|---|---|---|---|
| `dev` (snapshot 1) | 40 | **40** | 0 |
| `snapshot2` (snapshot 2) | 40 | **40** | 0 |

Run with `python scripts/run_dbt_tests.py`.

**31 generic tests** from `schema.yml` — uniqueness and not-null on the owned key and on
`src_rowid`, accepted values on `offer_type`, `price_basis`, `parse_confidence`,
`brand_class`, `product_key_basis`, `vendor`, `match_tier` and `vendor_upc_tier`, and the
relationships test between `stg_price` and `stg_product` that found §5.1.

**9 singular tests** in `dbt/tests/`, one per rule that would otherwise be a comment:

| Test | What it forbids | Why it exists |
|---|---|---|
| `assert_stg_price_rowcount_matches_raw` | `stg_price` ≠ `raw` | reconciliation (5.2); silent row loss |
| `assert_stg_product_rowcount_matches_product` | `stg_product` ≠ `product` | same |
| `assert_int_upc_match_rowcount_matches_stg_product` | tiers dropped at load | keeps denominators available |
| `assert_no_price_row_lost_to_parsing` | no price *and* no `unparsed` verdict | the naive-CAST failure |
| `assert_multibuy_never_stripped_to_total` | `2/$7.00` → 7.00 | doubles the true price |
| `assert_cents_form_never_read_as_dollars` | `329$` → 329.00 | 100× error, 79,478 rows |
| `assert_junk_brand_never_national` | junk → `national_brand` | biases private-label share down |
| `assert_match_tier_is_weakest_participant` | strongest-participant tiering | launders fuzzy into headline |
| `assert_reliable_only_excludes_fuzzy` | `is_reliable_only` on a fuzzy GTIN | D4's basket filter |
| `relationships` (generic) | a price key with no product | **found §5.1** |

#### The reconciliation test (brief 5.2), stated

Row count in equals row count out at every layer, with any deliberate reduction named. The
deliberate reduction is **zero** at all three layers — nothing is filtered anywhere, which
is itself the design commitment (honesty rule 2: lower tiers kept and flagged, never
deleted; honesty rule 7: the denominator is always available).

| Layer | Source | Model | Deliberate reduction |
|---|---|---|---|
| `raw` → `stg_price` | 71,809,333 / 72,022,652 | same | **none** |
| `product` → `stg_product` | 187,028 / 187,070 | same | **none** |
| `stg_product` → `int_upc_match` | 187,028 / 187,070 | same | **none** |

### 5.3 Every test demonstrated to fail when it should — 23 of 23

A test that has never failed has not been tested. `scripts/test_dbt_contracts.py` proves
each one fails, and the result is **23 of 23 cases behaved as expected**: 1 control plus 22
injected violations.

**Method, and why it does not run against the real database.** The obvious approach —
break a row in `stg_price` and watch the test go red — would mutate a 71.8M-row
materialisation that locked decision 2 and `verify_reproducible.py` both require to be a
pure function of an immutable snapshot. Testing a test by destroying the property the test
protects is not a trade worth making, and the rebuild costs the better part of an hour.

So the harness builds a **fixture database**: small tables with the same names and columns,
built from the **same committed model SQL**, populated with rows that satisfy every
contract. Then per test: rebuild clean, inject one violation aimed at that test, run only
that test with `dbt test --select`, require a non-zero exit.

**The control is not decoration.** A clean fixture must pass **all 40** tests — without it,
a suite that failed on everything would score a perfect 22 of 22. That is the same trap
`test_check_schema.py` documents, and it caught something real here: **the control failed
on the first run**, and the cause was not the fixture. It was §5.1.

| Case | Injection | Result |
|---|---|---|
| **CONTROL** | *(nothing)* | all 40 pass |
| `assert_stg_price_rowcount_matches_raw` | delete one row | fails |
| `assert_stg_product_rowcount_matches_product` | delete a vendor's row | fails |
| `assert_int_upc_match_rowcount_matches_stg_product` | delete a tier row | fails |
| `assert_no_price_row_lost_to_parsing` | NULL price, `offer_type='scalar'` | fails |
| `assert_multibuy_never_stripped_to_total` | `2/$7.00` → 7.00 | fails |
| `assert_cents_form_never_read_as_dollars` | `329$` → 329.00 | fails |
| `assert_junk_brand_never_national` | `Out of stock` → `national_brand` | fails |
| `assert_match_tier_is_weakest_participant` | fuzzy GTIN → `vendor_upc` | fails |
| `assert_reliable_only_excludes_fuzzy` | fuzzy GTIN → `is_reliable_only` | fails |
| 13 generic tests | duplicate row / NULL / out-of-domain / orphan key | all fail |

Two of the 22 injections did **not** fail on the first attempt. The cause was mine — a
14-digit GTIN written as a 17-character literal, so the injection updated no rows. That is
the harness working: an injection that changes nothing must not be reported as a caught
violation, and the "TEST DID NOT RUN" path exists for exactly that.

**Also demonstrated to fail, outside dbt:**

| Check | Injection | Result |
|---|---|---|
| `check_layering.py` | `sp.product_id` into `int_upc_match.sql` | exit 1, names file and line (§4.1) |
| `check_model_parity.py` | `p_min_qty(...)` → `1` in the dbt copy | exit 1, word-level diff |
| `test_check_schema.py` | 6 schema mutations incl. `product_id` → number | 6 of 6 |

### 5.4 Two problems in the test framework itself, fixed

Volunteered because both would have produced a green suite that meant nothing.

**1. dbt was testing an empty database.** `profiles.yml` said `path: ../hammer.duckdb`.
dbt resolves that against the **current working directory**, not against the profile — so
run from the repo root it points one level *above* the repo, and DuckDB cheerfully
**created** an empty database there. The visible symptom was a missing-macro catalog error,
which looks nothing like the cause. The dangerous outcome is the other one: a suite that
passes against an empty database and reports 40 of 40. Paths now come from environment
variables that `scripts/run_dbt_tests.py` sets to absolute values.

**2. The dbt models are a second copy of `models/*.sql`, and `dbt_project.yml` claimed
they were not.** They are. dbt cannot include a plain `.sql` file and the plain path has no
Jinja renderer, so one file cannot serve both. The comment was corrected, and — because
correcting a comment does not stop drift — `scripts/check_model_parity.py` now normalises
both bodies and fails on any difference beyond comments, `{{ config }}` and source
references. They are currently identical.

**3. The price-parser test could not be run by committed tooling.** `P2_2` opens with
`.read models/price_parse_macros.sql`, a DuckDB **CLI dot-command** that the Python API
rejects, and there is no `duckdb` CLI in this environment. The published "22 of 22 pass"
therefore had **no committed way to regenerate it** — honesty rule 4 unmet for precisely
the test that guards the 100× errors. `run_query.py` now expands `.read` and, when a query
file declares macros, gives them an in-memory catalog with the database ATTACHed read-only
so the snapshot never becomes writable. **22 of 22, reproducibly.**

## Section 5.8 — Build-provenance sweep

*Computed under build `2026-08-28T17:48:35Z` — models `d1f90ee`/`f6d7345`/`6d01e90`/`01ff1a1`, both snapshots.*

**Status: complete.** Headline: **of 14 parser-dependent queries re-run, 11 are unchanged
to the digit, 3 carry corrections — and one of the three was not stale but
irreproducible.** No Phase 0 number is affected. No conclusion is withdrawn.

### The method the task asked for does not work, and here is what replaces it

The brief says to determine which build produced each number **using `_build_stamp`**.
It cannot do that, and saying so is the first result:

- **`_build_stamp` has no history.** It records the sha256 of the model sources behind
  the *current* tables and nothing else. It is a tripwire against querying a stale model,
  not an archive of past builds. A number written into a document three days ago has no
  stamp attached to it anywhere.
- **Git cannot substitute.** On this project the model fix and the section quoting it
  have landed in the *same commit* every time — `cf21e02` carries both the
  bare-integer-cents fix and the §2.5 write-up. Commit order therefore proves nothing
  about ordering *within* a session, and within-session ordering is exactly how §2.6
  slipped.

So the sweep is done by **recomputation**, which does not depend on the archaeology at
all, and the archaeology is used only to prioritise. This is also why honesty rule 5 now
requires the stamp to be written into the section at the time the number is published:
the check has to be made possible going forward, because it cannot be reconstructed
backwards.

### Fix timeline, from git

| Fix | Landed | Commit |
|---|---|---|
| `bare_integer_cents` (Walmart ≥100 → cents, 79,478 rows) | 2026-08-24 19:35 | `cf21e02` |
| `60gx6` trailing multiplier + count-type pack (`24ea`) | 2026-08-26 19:52 | `eaf1d1f` |
| Galleria `ambiguous` flag | 2026-08-28 14:35 | `8282905` |
| Owned md5 key replaces the 64-bit hash in queries | 2026-08-28 14:35 | `8282905` |
| **Orphan-key fix** (NULL for rows with no product) | 2026-08-28 22:35 | `aba3b6f` |

### Phase 0 is not exposed to any of them — structurally, and verified

**No Phase 0 number can be affected by any model-layer fix, because no Phase 0 query
reads the model layer.** Checked mechanically across all 43 queries rather than assumed:

| Property | Result |
|---|---|
| Phase 0 queries reading `stg_price` / `stg_product` / `int_upc_match` | **0 of 43** |
| Phase 0 queries reading `models/*.sql` via `.read` | **0 of 43** |
| Phase 0 queries defining their own `TEMP MACRO`s inline | **all of them** |
| Phase 0 queries modified since Phase 0 | 3, at `36f8ddf` — **before the first fix** |
| Snapshot archives verified by sha256 | **4 of 4 OK** |

Phase 0's numbers are a pure function of unchanged inputs and unchanged, self-contained
queries. `C1`'s unit parse rate (88.12%) uses an inline ad-hoc parser, not the committed
one — which is why §3.1's 88.84% is reported as a *different measurement* rather than a
correction of it.

**The exception, and it is the one that mattered:** `docs/phase-0-findings.md` was edited
at `b37234a` (08-24 18:17) to import Phase 1's parser-derived figures into D2's verdict
and D1's provisional GO — **77 minutes before the bare-integer-cents fix landed**. Those
imported numbers were the real exposure in the Phase 0 document. All of them were re-run:

| Imported figure | Published | Recomputed | Delta |
|---|---|---|---|
| D2 sale events | 566,564 | 566,564 | **unchanged** |
| D2 evaluable | 279,599 | 279,599 | **unchanged** |
| D2 lost pre-parse / post-parse | 6,421 / 3 | 6,421 / 3 | **unchanged** |
| D2 recovered / usable | 6,418 / 279,596 | 6,418 / 279,596 | **unchanged** |
| Metro multibuy recovered | 925 of 925 | 925 of 925 | **unchanged** |
| D1 window cents-form `current_price` | 15,789 (0.739%), 96 dates | identical | **unchanged** |
| D1 window cents-form `old_price` | 2,086 (0.098%) | identical | **unchanged** |
| D1 window sale events touched | 194 of 14,357 (1.35%) | identical | **unchanged** |

**Phase 0's document needs no correction.**

### The sweep: 14 queries re-run

| Query | Section | Verdict |
|---|---|---|
| `P2_2b` parse coverage | §2.2 | **corrected** — `basis_rescaled`, and a missing repair rule |
| `P2_3` D2 reconciliation | §2.3 | unchanged, every figure and the full per-vendor table |
| `P2_4` price_per_unit cross-check | §2.4 | unchanged |
| `P2_5` cents-form in D1 window | §2.5 | unchanged |
| `P2_6` sku-reuse heuristic | §2.6 | **corrected in §5.5** (bare-integer-cents) |
| `P2_7` magnitude sweep | §2.5 | unchanged (1,825 flagged, per-vendor identical) |
| `P2_8` old_price value vs presence | §2.7 | unchanged |
| `P2_9` bare-integer adjudication | §2.5 | **corrected — non-deterministic, now fixed** |
| `P3_1` unit parse rate | §3.1 | unchanged (88.84%, and the full uom table) |
| `P3_2` Walmart size recovery | §3.2 | **table completed** — a vendor row was missing |
| `P3_3` brand classification | §3.3 | unchanged (451 junk, PL understatement table) |
| `P3_4` pack-count cross-check | §3.4 | unchanged (137,898 comparable) |
| `P3_5` key collision proof | §3.5 | unchanged (187,087 → 187,087, 0 collisions) |
| `P3_6` ambiguous semantics | §3.6, §3.7 | unchanged (46,884; D4 27 of 5,222) |
| `P4_1` identity model | §4.1, §4.2 | unchanged (tier census, B4 reconciliation 0 difference) |

**11 unchanged. 3 corrected.** All three corrections are restated in place, above, with
the superseded values shown rather than overwritten.

### Correction 1 — §2.2's repairs table was wrong and incomplete

`basis_rescaled` was published as **105,540**. That figure matches **no state that can now
be reconstructed**: not the current all-rows count (106,264), not the current
with-a-vendor count (105,488). The macro governing per-weight rescaling has not changed
since it was written, and switching `stg_price` from `p_normalization` to the vendor-aware
`p_normalization_v` provably changes nothing outside `bare_integer_cents` (verified: the
only disagreement between the two macros across all 71.8M rows is those 79,478 rows). So
the 52-row gap against the inner-join count has no committed explanation. The most likely
candidate is the stale-table window documented in §3.8, but **I cannot reproduce it, and I
am not going to invent a cause for it.**

Worse than the wrong number: the table was captioned "**Repairs applied, each named and
counted**" and listed **four** rules while the section's own summary table said "**5 repair
rules**". The missing one was `bare_integer_cents` — 79,478 rows, the largest correction in
the phase. The §2.5 correction note updated two of the four rows and stopped there.

### Correction 2 — §2.5's adjudication table was irreproducible, not stale

This is the finding that changed a project rule. `P2_9` resolved multiple candidate
reference prices with `any_value()`, which picks **arbitrarily**. Three runs over the same
immutable snapshot and the same build:

| Run | 100–999 matching cents | 1000+ matching cents | <10 matching dollars |
|---|---|---|---|
| 1 | 57,008 | 8,036 | 1,211 |
| 2 | 57,212 | 8,045 | 1,211 |
| 3 | 56,598 | 7,884 | 1,209 |

**A spread of 614 on a published figure, with nothing stale and nothing wrong with the
data.** The published values (56,567 / 7,878 / 1,189) sit inside that spread. A staleness
sweep would never have caught this, because there is no stale build to find.

The query's own header claimed it took the "nearest non-bare price within 7 days". It did
not. It now does — ranked by absolute day difference, ties broken by earlier date then by
price, so the order is total. **Verified identical across three consecutive runs.**

Fixing it exposed a second bug and the same old hazard. Partitioning by `(key, date)`
still varied, because Phase 0 B6 established that one product appears many times in a
single day's scrape **with conflicting prices** — so `(key, date)` is not the grain, and
rows migrated between magnitude bands between runs. The partition is `(key, date, bare
value)`. **This is the third time on this dataset that a non-unique key has produced a
moving number** (§1.4 was the first, the fixture-control failure in §5.1 the second).

**The verdict is unmoved.** `matches_dollars = 0` for both bands ≥ 100 in every run of
both versions, and the adjudicable row counts (1,631 / 3,008 / 58,267 / 8,271) never
changed. The rule rests on *0 of 66,538*, which is deterministic. It could easily have
rested on a number that was not.

### Correction 3 — §3.2's table was missing a vendor

Save-On-Foods (2 unparsed products, 0 recoverable) was absent. It changes no conclusion,
but a vendor silently missing from a per-vendor table is the shape of a real error.

### What this says about the three named fixes

| Fix | Numbers it could have contaminated | Found |
|---|---|---|
| bare-integer cents | every price-magnitude figure | **§2.6 only** (caught in §5.5) |
| `60gx6` / count-type pack | §3.1, §3.4, §3.2 | **none** — §3.9 had already verified this empirically |
| orphan key | anything aggregating `stg_price` by key | **none** — every consumer joins through `product` or `int_upc_match`, both of which excluded the orphan key |

The orphan-key result is worth stating plainly because it is the one I most expected to
find damage in: **zero published numbers moved.** §5.1 called that luck rather than
design, and the sweep confirms the luck held.

**The honest summary of this section: the systematic check found one real number error
(§2.2), one reproducibility defect that no staleness check could have found (§2.5), and
one incomplete table (§3.2) — and confirmed 11 of 14 queries and all of Phase 0
unchanged.** §2.6 remains the only case where a conclusion had to be weakened, and it was
found by accident before this sweep existed.

*Source: the 14 queries above, re-run under one build; `P2_9` restated after the
determinism fix.*

---

## Section 5.9 — The 878,559 orphan price rows

*Computed under build `2026-08-28T17:48:35Z` — models `d1f90ee`/`f6d7345`/`6d01e90`/`01ff1a1`.*

**Status: complete.** Headline: **they are real grocery prices for products that have left
the catalogue, 74% of them keyed under a `product_id` scheme upstream has retired. They
are not a scrape artifact and not our bug. None is recoverable. They are excluded from D2
and D4 headline numbers at query time, counted, and kept.**

### What they are

| Measure | Value |
|---|---|
| Orphan rows (snapshot 1) | **878,559** — 1.2235% of 71,809,333 |
| Distinct orphan `product_id`s | **10,625** |
| `product` rows for comparison | 187,028 |

By vendor, with each vendor's own row count as the denominator:

| Vendor prefix | Orphan rows | Distinct ids | Rows for that vendor | **% of vendor** |
|---|---|---|---|---|
| **Metro** | **637,508** | 6,906 | 8,203,156 | **7.211%** |
| Walmart | 56,125 | 1,742 | 6,372,804 | 0.873% |
| Galleria | 46,254 | 145 | 5,892,146 | 0.779% |
| Loblaws | 43,270 | 302 | 14,013,669 | 0.308% |
| NoFrills | 32,413 | 222 | 11,024,382 | 0.293% |
| TandT | 23,726 | 217 | 5,393,781 | 0.438% |
| Voila | 21,120 | 102 | 12,937,809 | 0.163% |
| SaveOnFoods | 18,064 | 966 | 7,093,027 | 0.254% |
| *malformed / unattributable* | *78* | *21* | — | — |

**Metro is an order of magnitude worse than anyone else** and holds 72.6% of the orphan
rows — consistent with Phase 0 E11, which found Metro's daily extract captures a rotating
subset of its catalogue.

### They cluster, and the break is a known regime change

| Regime | Orphan rows | All rows | **% orphan** | Distinct ids |
|---|---|---|---|---|
| **Before 2024-10-01** | 649,605 | 7,722,502 | **8.412%** | 8,252 |
| **2024-10-01 onward** | 228,954 | 64,086,831 | **0.357%** | 2,430 |

A **24× step**, falling between 2024-09 (8.500%) and 2024-10 (0.358%). That boundary is
already in `CLAUDE.md`'s Known Contamination as "Pre Sept 30 2024", and Phase 0 B1b
independently found a `product_id` scheme change there. **74% of all orphan rows sit on
the old side of it.**

The post-2024-10 rate is not flat either: it falls to 0.141% (2025-09) then climbs back to
0.542% (2026-06). So there are two populations, not one — a large historical block and a
live, slowly growing background.

### Three id generations, which is the mechanism

Metro's *current* `product.id` values are opaque base64 (`YRnfY16EEimWdPCI1S5mVw==`). The
orphan rows carry something else entirely:

| Generation | Form | Ids | Orphan rows | Share |
|---|---|---|---|---|
| **gen-C** | `Metro~Old Cheddar Cheese Slices@200 g^Cracker Barrel` (the `concatted` form) | 8,604 | **670,189** | **76.28%** |
| **gen-B** | `Metro062020000064` (`vendor \|\| sku`) | 1,992 | 208,293 | 23.71% |
| malformed | URL-slug fragments, e.g. `Loblawshoney-bunches-of-oat-honey-roasted-cere` | 21 | 67 | 0.01% |
| gen-A | base64 hash | 8 | 10 | 0.00% |

So the join does not fail because the `product_id` is junk. It fails because these rows
were written under **id schemes upstream has since retired**, and the migration was never
applied to history.

### None of it is recoverable — tested, not assumed

The id forms are so legible that recovery looks easy: `Metro062020000064` is plainly
vendor + sku, and the gen-C form is exactly the `concatted` string our own blank-sku key
branch already uses. Both were tested against the current catalogue:

| Generation | Ids | Rows | **Recoverable** |
|---|---|---|---|
| gen-B — split to (vendor, sku), match `product` | 2,012 | 208,314 | **0** |
| gen-C — match the id against `product.concatted` | 8,604 | 670,189 | **0** |

**Zero, on both paths.** The skus and the concatted strings are not in the catalogue under
any key. The products are genuinely gone, not merely re-keyed — which also means no clever
join recovers them, and a Phase 2 attempt to do so would be wasted work.

Two further checks agree:

| Check | Orphan ids | Joined ids |
|---|---|---|
| Average days observed | **62.1** | 322.2 |
| Median days since last observed | **690** | **2** |
| Still observed in the final 7 days | 403 of 10,625 | 95,844 of 187,027 |

And the decisive test against snapshot 2: of 10,625 orphan ids, **6 appear in snapshot 2's
`product` table and 10,619 do not.** Upstream does not backfill. **This is not publication
lag** — the distinction `CLAUDE.md` insists on — it is absence.

### Verdict on the three hypotheses

- **Scrape artifact — no.** These are real prices. 878,554 of 878,559 parse; the median
  unit price is **$5.89** and the multibuy median $3.50. Ordinary groceries.

  | `offer_type` | Rows | With a unit price | Median | Range |
  |---|---|---|---|---|
  | scalar | 794,271 | 794,271 | $5.89 | $0.12 – $2,197.00 |
  | multibuy | 82,130 | 82,130 | $3.50 | $0.60 – $21.99 |
  | per_weight | 2,153 | 2,153 | $0.88 | $0.54 – $65.43 |
  | unparsed | 5 | 0 | — | — |

- **Product-table completeness gap — yes, and this is the main answer.** `product` is a
  snapshot of the **currently listed** catalogue, while `raw` is the full price history.
  A delisted product is removed from `product` outright, orphaning its history. The
  median orphan id was last seen **690 days ago**.

- **Upstream defect — yes, in two distinct and separately reportable forms.** (1) A
  `product_id` scheme migration applied to the catalogue but **not retroactively to
  history**, which is what makes the pre-2024-10 block unjoinable — 74% of the total.
  (2) A small malformed-id defect: 21 ids that are truncated URL slugs, of which the
  Loblaws ones on 2026-02-01 were already noted in Phase 0 E2.

**It is not our bug**, and the one part that *was* ours — giving all 878,559 rows a single
shared key — was fixed in §5.1.

### Downstream semantics — decided, and written into CLAUDE.md

**Decision: D2 and D4 exclude rows with a NULL `product_key` from headline numbers, at
query time, with the dropped count stated. The rows are never deleted and never re-keyed
to a placeholder.** Added as honesty rule 6.

**D4 exposure: zero additional rows.**

| Measure | Value |
|---|---|
| Orphan rows reachable through `int_upc_match` | **0** |

An orphan row has no product row, therefore no UPC, therefore no GTIN. It could never
reach the basket. There is nothing to exclude and the rule is a formality for D4 — stated
as a number rather than asserted.

**D2 exposure: 15,936 sale-flagged rows across 246 product ids.**

| Measure | Value |
|---|---|
| Orphan rows | 878,559 |
| …with a non-blank `old_price` | 262,740 |
| …with a sale flag in `other` | **15,936** |
| …distinct ids carrying a sale flag | **246** |

That is the real cost, it is small, and it must be quoted whenever a D2 figure is
published.

**Why exclusion, and why it is a different call from §3.7's.** An ambiguous price has an
identity and a doubtful value. An orphan row has a **sound value and no identity at all**.
Admitting one to D2 means building a price series keyed on `raw.product_id` — which locked
decision 5 forbids, `check_layering.py` blocks mechanically, and upstream has announced
will change type from string to number. Two of the three id generations here are already
retired; keying on the third would be building on the next one to be retired. These rows
are not weak evidence. They are evidence we have no owned key for.

**Denominator treatment, stated because it is the easiest thing to get wrong.** Orphans
**stay** in row-count denominators where the denominator is "rows we parsed" — parse
coverage is 100.000% of 71,809,333 *including* them. They are **absent** from per-vendor
denominators, because they have no vendor, which is why §2.2's per-vendor table sums to
70,930,774 and not 71,809,333. Any per-vendor table must state that residual.

**This is not permanent.** The cause is upstream and could be removed upstream. If a
product-history table is ever published, or if the retired id schemes are backfilled, the
exclusion should be revisited — and because the rows are kept with a NULL key rather than
dropped, that revisit is a query change and nothing more.

**Upstream feedback.** The non-retroactive id migration belongs in
`docs/upstream-feedback.md`: it costs a downstream consumer 1.22% of all price rows and
7.2% of Metro's, for no benefit, and a single published mapping from retired ids to
current ones would erase it. Added there.

*Source: `P5_9_orphan_price_rows.sql`.*

### 5.10 Full check status

| Check | Result |
|---|---|
| `check_manifest.py` | **OK** — 118 tracked files, 28 manifest entries |
| `check_schema.py` — snapshot 1 | **OK** — 2 tables, 15 columns |
| `check_schema.py` — snapshot 2 | **OK** — 2 tables, 15 columns; `raw.product_id` still VARCHAR |
| `check_layering.py` | **OK** — 0 `product_id` references below staging |
| `check_model_parity.py` | **OK** — 3 of 3 model bodies identical across build paths |
| `verify_reproducible.py` — snapshot 1 | **OK** — 22 of 22 columns, build stamp 7 of 7 |
| `verify_reproducible.py` — snapshot 2 | **OK** — 22 of 22 columns, build stamp 7 of 7 |
| `test_check_schema.py` | **6 of 6** cases |
| Unit parser tests | **16 of 16** |
| Price parser tests | **22 of 22** |
| **dbt tests, snapshot 1** | **40 of 40** |
| **dbt tests, snapshot 2** | **40 of 40** |
| **dbt fail-when-they-should** | **23 of 23** |
| Build-provenance sweep (§5.8) | **14 of 14** parser-dependent queries re-run under one build |
| `P2_9` determinism | **3 of 3** consecutive runs byte-identical |
| Snapshot archives, sha256 | **4 of 4** verify against their manifests |

**Counts, not a pass rate.** Adding those up needs care, because two of them are the same
tests run twice and one is those tests being deliberately broken:

| | Count |
|---|---|
| Distinct test cases that exist | **84** — 40 dbt + 22 price parser + 16 unit parser + 6 schema |
| Executions of them in this run | **124** — the 40 dbt tests ran against both snapshots |
| Fail-when-they-should demonstrations | **23** — 1 control + 22 injections, over the same 40 dbt tests |
| Standing checks (not test cases) | **5** — manifest, layering, model parity, reproducibility ×2 |

**84 distinct test cases exist and 84 passed.** That is a count of what exists, not a
percentage of some larger set of tests that ought to. Phase 1 has no test-coverage
percentage and this document does not report one. (Honesty rule 8.)

---

---

---

## Section 5 — what changed, in one place

| Item | Before | After |
|---|---|---|
| dbt tests | 0 | **40, passing on both snapshots** |
| Tests shown to fail when they should | 0 of 0 | **23 of 23** |
| Rows sharing one manufactured product identity | **878,559** | **0** |
| Snapshots with every price row parsed | 1 of 2 | **2 of 2** |
| Cross-snapshot key collision proof | unreproducible | **187,087 → 187,087, 0 collisions** |
| §2.6 figures | pre-§2.5-fix build | **restated, correction marked** |
| Hash-collision contamination of §2.5 / §2.6 | unknown | **measured: zero** |
| Price-parser test regenerable by committed tooling | no | **yes** |
| dbt database path | CWD-dependent, could test an empty DB | **absolute** |
| Model-body drift between build paths | unmanaged | **checked, shown to fail** |
| Append-only assumption | assumed | **monitored, +0.9 MB/year** |
| Parser-dependent numbers verified against one build | 2 of 14 | **14 of 14** |
| Published numbers that move between runs of the same query | **1** (undetected) | **0** |
| Repair rules listed in the "each named and counted" table | 4 of 5 | **5 of 5** |
| Orphan price rows: what they are | counted, uncharacterised | **diagnosed, cause upstream, 0 recoverable** |
| Orphan rows: downstream semantics | undefined | **excluded from D2/D4 at query time, counted, kept** |

**Not done in Section 5, and why:** no marts, no D2 or D4 numbers, no dashboard — all
Phase 2. Orphan-row recovery is not deferred but **closed**: §5.9 tested both plausible
recovery paths and both return zero, so there is nothing for Phase 2 to attempt unless
upstream changes what it publishes. The `plu_short` and `no_upc` tiers carry no tests beyond domain membership because
there is no invariant to assert about them yet; that arrives when a Phase 2 query first
depends on one.

**Phase 1 exit criteria — all met:**

- ✅ Two snapshots archived with provenance; cross-snapshot identity stability measured per vendor (§1.3)
- ✅ Every price row **in both snapshots** has an `offer_type` and a `unit_price` or explicit `unparsed` (§5.6)
- ✅ Post-parse D2 exclusion reported against the pre-parse 5,726 / 6,421 (§2.3)
- ✅ Owned key exists, `product_id` nowhere below staging (enforced), cross-vendor tier model materialised (§4)
- ✅ All tests pass and each has been demonstrated to fail when it should (§5.2, §5.3)
- ✅ `docs/FILES.md` current, `check_manifest.py` passes (§5.8)
