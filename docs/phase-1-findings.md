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

| Normalization | Rows | Vendors | Price range after repair |
|---|---|---|---|
| `basis_rescaled` | 105,540 | Metro, T&T, Save-On-Foods | $0.0005 – $19.60 |
| `cents_div100` | **47,992** | Loblaws | $1.00 – $84.17 |
| `now_prefix_cents_div100` | **11,506** | Walmart | $0.38 – $25.97 |
| `thousands_sep` | 353 | Walmart, Voila | $1,059 – $21,525 |

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
| Evaluable events | 279,593 |
| Lost **pre**-parse | **6,421** |
| Lost **post**-parse | **3** |
| **Recovered** | **6,418** |
| **Usable now** | **~279,590** |

> Figures restated after the §2.5 correctness fix. The recovery count (6,418) and the
> Metro multibuy recovery (925 of 925) are unchanged; the totals moved by 6 events due to
> a single hash collision in my own workaround, not the data. See §2.6.

Per vendor:

| Vendor | Evaluable | Lost pre-parse | Lost post-parse | **Recovered** |
|---|---|---|---|---|
| SaveOnFoods | 79,344 | 2,680 | 0 | **2,680** |
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

| | Long gaps (>30d) | Baseline (1–7d) |
|---|---|---|
| Events | 118,430 | 58,826,990 |
| Distinct keys | 76,824 | — |
| Median gap | 73 days | — |
| **Median price move** | **0.00%** | **0.00%** |
| **Moves > 50%** | **3,845 (3.25%)** | **0.41%** |
| Moves > 200% | 663 (0.56%) | — |

**The signal is real but small.** Large price moves are **8× more likely** after a long gap
than after a normal one (3.25% vs 0.41%). The median move is zero in both, so the typical
long gap is entirely benign — it is the tail that differs.

Per vendor, the >200% moves concentrate sharply:

| Vendor | Gap events | Median gap | Moves > 200% |
|---|---|---|---|
| **Walmart** | 27,828 | 51 days | **416** |
| Metro | 18,083 | 69 days | 95 |
| Galleria | 5,639 | 106 days | 59 |
| SaveOnFoods | 4,497 | 70 days | 55 |
| Loblaws | 23,467 | 73 days | 16 |
| NoFrills | 29,196 | 71 days | 15 |
| TandT | 5,925 | 76 days | 7 |
| Voila | 3,795 | 94 days | **0** |

The sample makes the mechanism visible — and it is **not grocery repricing**:

| Vendor | SKU | Gap | Before | After | Move |
|---|---|---|---|---|---|
| Metro | `4341` | 458 d | $16.90 | **$14,858.40** | 87,820% |
| Walmart | `226PJRK24U5X` | 37 d | $4.37 | $1,074.00 | 24,477% |
| Walmart | `3RGEXVPTBDWG` | 122 d | $0.99 | $170.90 | 17,163% |
| Walmart | `6000205233379` | 615 d | $13.47 | $2,196.00 | 16,203% |

Two things stand out. **Walmart's opaque marketplace IDs** (`226PJRK24U5X`) jump from
grocery scale to appliance scale, which is what a reused marketplace listing slot looks
like. And **Metro SKU `4341` is a four-digit PLU produce code** — exactly the shared,
non-unique code space Phase 0 B4c identified, where reuse is expected rather than
surprising.

**Verdict, as a risk statement.** An upper bound of **663 gap events across 76,824 keys
with gaps (0.56%)** show a discontinuity large enough to be consistent with SKU reuse.
That is an upper bound, not an estimate: a genuine relisting at a new price, a seasonal
item returning, or a unit-size change would all look identical here. The heuristic cannot
separate them and no attempt is made to.

**What this changes: nothing yet, deliberately.** It is not enough to complicate Section
4's key, and acting on 0.56% by adding a splice-detection layer would be building
machinery for a problem we have not confirmed exists. It is enough to justify two things
in a later phase: excluding four/five-digit PLU-style SKUs from single-vendor time series,
and treating Walmart marketplace IDs as a lower-confidence identity tier than grocery
SKUs. Both are Phase 2 decisions.

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

| Walmart magnitude | Adjudicable rows | Matches **dollars** | Matches **cents** | Verdict |
|---|---|---|---|---|
| < 10 | 1,631 | **1,189** | 0 | dollars |
| 10–99 | 3,008 | 1,767 | 1,048 | **genuinely ambiguous** |
| 100–999 | 58,267 | **0** | 56,567 | cents |
| 1000+ | 8,271 | **0** | 7,878 | cents |

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
| D2 evaluable events | 279,599 → **279,593** | yes, by 6 |
| D2 usable events | 279,596 → **279,590** | yes, by 6 |
| Sale events total | 566,564 → **566,558** | yes, by 6 |

**The 6-event drift is not from the price fix — it is a hash collision, and it is mine.**
To work around a DuckDB 1.5.5 statistics bug, the queries key on
`hash(vendor || '|' || sku)` rather than the string pair. There is **exactly 1 collision
in 161,300 keys**, which merges two products into one series and costs 6 sale events.
Measured, not estimated. It is a 0.0006% effect on a number reported to 6 significant
figures, so the honest statement is that D2's usable sample is **~279,590**, and the last
digit should not be leaned on.

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

## Section 3 — Unit representation

Not started. The §2.5 correctness sweep found a defect that required rebuilding the model
and recomputing every Section 2 figure, so those are reported first rather than building
Section 3 on numbers that had just moved.
