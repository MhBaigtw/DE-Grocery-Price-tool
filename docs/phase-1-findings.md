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

Not started. Awaiting sign-off on Section 1.
