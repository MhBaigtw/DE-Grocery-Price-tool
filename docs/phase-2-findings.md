# Phase 2 — Findings

Phase 1 built representation. Phase 2 produces the findings. This document carries every
number, its denominator, its build stamp, and — for every exclusion — a bias verdict.

Every number comes from a committed query in [analysis/phase2/](../analysis/phase2/).

---

## Section 1 — Exclusion accounting and bias audit

*Computed under build `2026-08-28T17:48:35Z` — models `d1f90ee`/`f6d7345`/`6d01e90`/`01ff1a1`/`b584c32`/`b2f47b3`/`bfc7be8`. Every figure below computed twice and compared.*

**Status: complete. Read the verdict before any Phase 2 finding is computed.**

> ### Headline: one of the three exclusions is biased, and it is biased badly enough to change how D2 must be framed.
>
> **The orphan exclusion removes 26.766% of Metro's 2024 D2 sale events and 0.409% of its
> 2025 events.** A Metro trend line crossing that boundary is reading an exclusion, not a
> price. No other vendor-year exceeds 4.5%.
>
> The other two classes are immaterial to D2 and near-immaterial to D4. And the one
> alarming *pooled* number — orphans looking 1.70× richer in sale rows — is mostly a
> composition artifact that collapses to 1.22× once vendor is controlled for.

### 1.1 The exclusion ledger

Three classes are in force: **ambiguous** (honesty rule 3), **orphan** (honesty rule 6),
and **unparsed**. A row can belong to more than one; the ledger assigns each row its most
severe class so the rows sum to the total, and the overlaps are stated separately.

| Class | Rows | % of all rows | Distinct keys | First date | Last date |
|---|---|---|---|---|---|
| retained | 70,883,862 | 98.7112% | 186,870 | 2024-02-28 | 2026-08-21 |
| **ambiguous** | **46,884** | **0.0653%** | 435 | 2024-06-10 | 2026-08-21 |
| **orphan** | **878,559** | **1.2235%** | 0 *(no key, by definition)* | 2024-02-28 | 2026-08-21 |
| **unparsed** | **28** | **0.00004%** | 20 | 2024-03-05 | 2026-02-01 |

**n = 71,809,333.** The four rows sum to it exactly.

**Class overlaps** — the classes are *not* disjoint, and one figure changes because of it:

| Overlap | Rows |
|---|---|
| orphan ∧ ambiguous | 0 |
| **orphan ∧ unparsed** | **5** |
| ambiguous ∧ unparsed | 0 |

This is why the table above says **28** unparsed rows where Phase 1 §2.2 says **33**. Both
are correct: 33 rows are unparsed, 5 of them are *also* orphans and are counted under
orphan here so the ledger sums. Stated rather than reconciled silently.

**By vendor**, against each vendor's own total rows. Orphans have no vendor — they have no
product row — so they sit on their own line and are attributed in §1.2 from the retired id
form instead:

| Vendor | Class | Rows | Vendor's total rows | % of vendor |
|---|---|---|---|---|
| *(orphan: no product row)* | orphan | 878,559 | 878,559 | — |
| Galleria | ambiguous | 26,306 | 5,892,146 | 0.4465% |
| Walmart | ambiguous | 20,555 | 6,372,804 | 0.3225% |
| Voila | ambiguous | 23 | 12,937,809 | 0.0002% |
| Loblaws | unparsed | 13 | 14,013,669 | 0.0001% |
| Metro | unparsed | 7 | 8,203,156 | 0.0001% |
| Walmart | unparsed | 4 | 6,372,804 | 0.0001% |
| SaveOnFoods | unparsed | 3 | 7,093,027 | 0.0000% |
| NoFrills | unparsed | 1 | 11,024,382 | 0.0000% |

**By year:**

| Year | Retained | Ambiguous | Orphan | Unparsed | % of year excluded |
|---|---|---|---|---|---|
| 2024 | 15,157,914 | 17,194 (0.1084%) | **680,397 (4.2912%)** | 7 | **4.3997%** |
| 2025 | 32,456,020 | 17,344 (0.0533%) | 95,133 (0.2921%) | 13 | 0.3454% |
| 2026 | 23,269,920 | 12,346 (0.0528%) | 103,029 (0.4406%) | 8 | 0.4934% |

*(8 rows carry an unparseable `nowtime` and fall in no year. They are retained.)*

#### D2 at event level

Rows are not events. An exclusion that strips many rows from few events costs less than
one stripping few rows from many.

| Measure | Value |
|---|---|
| Sale events in the keyed population | **576,200** |
| Events touching **any** ambiguous row | **25 (0.0043%)** |
| Sale events **lost to orphaning** | **14,624** across 6,728 ids, median run 7 days |
| Events lost as a share of the potential total | **2.48%** of 590,824 |

**Note on the 576,200.** Phase 1 §2.3 reports **566,564** sale events. The two are
different populations on purpose: `P2_3` restricts to `vendor_sku` keys and to
`observed_date >= 2024-06-11`, while this ledger counts every keyed product across the
whole window, because an exclusion ledger has to count what is excluded *before* a cohort
filter narrows it. The ledger's job is proportions; §2's job is the cohort. **They are
reconciled when D2 is rebuilt in Section 2, not here** — asserting they agree now would be
inventing a reconciliation I have not run.

The orphan event count is computed on `raw.product_id` **deliberately and only to size the
exclusion.** It measures what is missing. It is never an input to a finding, and locked
decision 5 still forbids keying a published series that way.

#### D4 at basket level

| Measure | Value |
|---|---|
| Reliable-tier basket GTINs | **5,222** |
| Price rows in the basket | **5,066,397** |
| Rows excluded — ambiguous | **676 (0.0133%)** |
| GTINs touched by an ambiguous row | **27 (0.52%)** |
| Rows excluded — unparsed | **0** |
| Rows excluded — orphan | **0, by construction** |

The orphan zero is structural, not lucky: an orphan has no product row, therefore no UPC,
therefore no GTIN, therefore no path into the basket. Confirmed as a number rather than
asserted.

Spread of the ambiguous exclusion across the basket:

| Share of a GTIN's history that is ambiguous | GTINs |
|---|---|
| none | 5,195 |
| <1% | 13 |
| 1–10% | 10 |
| 10–50% | 4 |
| **≥50% (unusable)** | **0** |

---

### 1.2 Bias audit — verdicts

The question is never "how many" but "are the removed rows a random slice of what
remains". A large unbiased exclusion costs precision; a small biased one costs
correctness.

#### Verdict table

| Class | Time | Promotion type | Depth | Category / brand | D2 impact | D4 impact |
|---|---|---|---|---|---|---|
| **ambiguous** | concentrated, immaterial | **distinct type** (sale-*depleted*) | random slice | **distinct type** | negligible | negligible |
| **orphan** | **BIASED — severe** | **distinct type**, inconsistent by vendor | **random slice** | **untestable** | **material** | none |
| **unparsed** | untestable (n=28) | untestable (n=28) | untestable | untestable | negligible | none |

---

#### Axis 1 — Time. The orphan exclusion is biased, and this is the finding.

Row-level, the orphan share steps 14.7× at the 2024/2025 boundary — the retired-id-scheme
break P5.9 identified. **Event-level, per vendor, it is far worse than the row figure
suggests:**

| Vendor | 2024 | 2025 | 2026 | Spread |
|---|---|---|---|---|
| **Metro** | **26.766%** | 0.409% | 0.537% | **26.4 pp** |
| Walmart | 1.124% | 4.406% | 1.813% | 3.3 pp |
| Galleria | 0.000% | 0.000% | 2.526% | 2.5 pp |
| SaveOnFoods | 1.727% | 0.231% | 0.181% | 1.5 pp |
| TandT | 1.687% | 0.195% | 0.237% | 1.5 pp |
| Voila | 0.450% | 0.252% | 0.223% | 0.2 pp |
| Loblaws | 0.362% | 0.192% | 0.346% | 0.2 pp |
| NoFrills | 0.320% | 0.228% | 0.306% | 0.1 pp |

*(share of that vendor-year's D2 sale events lost to orphaning; n per cell in `Q1b` result 8)*

**Metro loses more than a quarter of its 2024 sale events and less than half a percent of
its 2025 events.** 608,429 of Metro's 637,508 orphan rows — 95.4% — fall in 2024.

**Verdict: BIASED on time, severely, and specifically for Metro.** Consequences, which are
binding on Section 2:

- **No Metro D2 trend line may cross the 2024/2025 boundary** without the break marked.
  That is locked decision 4 already, but this is the specific number that triggers it.
- A cross-vendor D2 comparison **restricted to 2024 is not valid** — Metro is missing 27%
  of its events and No Frills is missing 0.3%.
- **D2 restricted to 2025–2026 is clean on this axis.** Every vendor-year from 2025 on is
  under 4.5%, and all but Walmart under 1%. This is the usable window.

#### Axis 2 — Promotion type. The pooled number lies; the controlled one is smaller and inconsistent.

Pooled, orphan rows look badly sale-enriched:

| Class | Rows | Sale rows | % sale |
|---|---|---|---|
| retained | 70,883,862 | 12,494,223 | **17.63%** |
| ambiguous | 46,884 | 167 | **0.36%** |
| orphan | 878,559 | 262,740 | **29.91%** |
| unparsed | 28 | 14 | 50.00% *(n=28)* |

**1.70× enrichment — and it is mostly a composition artifact.** 72.6% of orphan rows are
Metro, and Metro's baseline sale rate (29.5%) is far above the corpus average. Controlled
within vendor:

| Vendor | Orphan % sale | That vendor's retained % sale | Ratio |
|---|---|---|---|
| Walmart | 17.800 | 11.567 | **1.54** |
| Voila | 28.490 | 19.055 | **1.50** |
| TandT | 8.906 | 6.189 | **1.44** |
| **Metro** | 36.134 | 29.525 | **1.22** |
| SaveOnFoods | 30.503 | 33.070 | 0.92 |
| NoFrills | 11.362 | 13.983 | 0.81 |
| Loblaws | 11.441 | 18.531 | **0.62** |
| Galleria | 0.233 | 0.927 | **0.25** |

**This is the F1 mistake caught before it was made.** The pooled 1.70× would have been
reported as "orphaning removes sale rows preferentially". Within vendor it is 1.22× for
the dominant vendor, and **the direction is not even consistent** — four vendors enriched,
three depleted, one neutral.

**Verdict: distinct type, but weakly and inconsistently.** It does not invalidate a
within-vendor D2 number. It does mean a **cross-vendor** comparison of sale *frequency*
inherits a per-vendor distortion of between 0.25× and 1.54×, and must say so.

Same control on multibuy, the promotion type F5 found was once categorically excluded:

| Vendor | Orphan % multibuy | Retained % multibuy | Ratio |
|---|---|---|---|
| **Metro** | 12.883 | 7.287 | **1.77** |
| every other vendor | 0.000 | 0.000 | — |

The pooled figure looked like an 11× multibuy enrichment. **It is entirely Metro**: no
other vendor has multibuy pricing at all, in either population. Within Metro the real
effect is 1.77×.

#### Axis 3 — Discount depth. Random slice. F5's asymmetry is not repeating.

| Class | Comparable rows | Median discount |
|---|---|---|
| retained | 11,624,725 | **17.70%** |
| ambiguous | 167 | 16.67% |
| orphan | 261,510 | **16.69%** |

**Verdict: random slice.** This is the axis where F5 found the pre-parse exclusion was
~8 pp deeper — the failure that motivated all of Phase 1. It is not recurring: orphans are
1.0 pp *shallower*, which is noise at this n and in the harmless direction.

#### Axis 4 — Category and brand

Ambiguous rows, against the retained mix:

| Category | % retained | % ambiguous | Ratio |
|---|---|---|---|
| **produce** | 13.26 | **22.50** | **1.70** |
| **meat & fish** | 9.56 | **17.59** | **1.84** |
| beverages | 10.06 | 13.29 | 1.32 |
| bread & bakery | 3.79 | 4.41 | 1.16 |
| pantry staples | 7.77 | 5.33 | 0.69 |
| **dairy** | 15.14 | **8.02** | 0.53 |
| eggs | 1.33 | 0.44 | 0.33 |
| other | 39.10 | 28.43 | 0.73 |

**Verdict: distinct type.** Ambiguous rows lean produce and meat — loose goods where a
bare integer is genuinely ambiguous between $4.00 and $0.04. **But D4 absorbs almost none
of it:** 676 rows and 27 of 5,222 basket GTINs, none majority-ambiguous.

Brand class shows the same skew, driven by Galleria's absent brand data:
`unclassifiable_no_vendor_data` is 56.16% of ambiguous against 34.14% of retained.

**A limitation I cannot test, stated plainly: the category and brand axes cannot be
evaluated for orphan rows at all.** Category and brand live in `product`, and an orphan row
has no product row. This is not an oversight; it is unanswerable with the data we have.
**The orphan exclusion could be category-biased and we would not know.** The mitigating
facts are that its D4 impact is exactly zero, and that its per-vendor composition is known
even where its per-category composition is not.

---

### 1.3 Determinism

Every number in this section was computed **twice** and the two runs compared
byte-for-byte. Beyond re-running, the pattern is now prevented rather than detected:
`scripts/check_determinism.py` lints all 89 SQL files for non-deterministic aggregates
over groups not proven unique, and `scripts/test_check_determinism.py` proves the lint
fails when it should (**8 of 8** cases).

The lint found **44 hazards** on first run across the existing Phase 0 and Phase 1 queries:

| Disposition | Count | What was done |
|---|---|---|
| Made deterministic for free | 16 | `min()` for `any_value()` on display columns; `ORDER BY` added to `string_agg`; `ORDER BY` added to an unordered `LIMIT`; a tighter tie-break in `B5` |
| Justified with an adjacent annotation | 28 | Group proven unique, or the ordering proven total — each written next to the code as a checkable claim |
| **Latent defect found** | **1** | `P2_7`'s `any_value()` over `(key, basis, date)` — a group Phase 0 B6 proves is *not* unique |

That last one is the same defect class for the fourth time, found by the lint rather than
by an incident. It fed a diagnostic column rather than a headline number, so no published
figure moves; the fix is `min()`, annotated with why an arbitrary pick was wrong there.

**And then the compute-twice check caught a fifth — in a query written for this very
audit.** `Q1b`'s multibuy control ordered its output by `ratio DESC`, and every vendor
except Metro has no multibuy in either population, so seven rows tied and came back in a
different order on the second run. The **values were identical**; only the row order
moved.

**The lint could not have caught it, and that is the point.** The lint's scope is
aggregates and window functions — where all four prior incidents lived. A final `ORDER BY`
that exists but is not a *total* order is a different shape of the same disease, and it is
invisible to a static check because almost any `ORDER BY` could tie in principle. The two
controls are complementary: **the lint prevents the classes we have already been bitten
by, and running twice catches the ones we have not thought of yet.** Neither alone is
sufficient, which is an argument for keeping both rather than treating the lint as a
replacement for honesty rule 4.

Fixed by adding `vendor` as a tiebreak to every non-total `ORDER BY` in
`analysis/phase2/`, after which both files return byte-identical output across
consecutive runs.

---

### What would change these conclusions

- **The Metro 2024 bias disappears** if upstream publishes a mapping from retired
  `product_id` values to current ones — the single fix that would erase 74% of the orphan
  population (`docs/upstream-feedback.md` §5). Until then it is permanent.
- **The category axis for orphans becomes testable** only if upstream publishes a product
  history table. No downstream work recovers it: §5.9 tested both plausible recovery paths
  and both returned exactly zero matches.
- **The ambiguous exclusion shrinks** if Galleria's bare integers are ever adjudicated —
  26,306 of the 46,884 are Galleria, held ambiguous for want of evidence, not because the
  evidence is against them.
