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
| **orphan** | **BIASED — severe** | **distinct type**, inconsistent by vendor | **random slice** | **random slice** (§1.4, 76.3% coverage) | **material** | none |
| **unparsed** | untestable (n=28) | untestable (n=28) | untestable | untestable | negligible | none |
| **`vendor_sku` filter** *(§1.5)* | **2024-concentrated** | **distinct type** (2.3× multibuy) | shorter runs | **distinct type** | **biased but immaterial — 539 of 280,138 evaluable** | none |

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

> **Superseded by §1.4.** This section originally recorded category and brand as
> **untestable** for orphan rows, because both live in `product` and an orphan has no
> product row. That was true of the *join* and false of the *data*: 76.28% of orphan rows
> carry the retired `vendor~name@units^brand` id, which contains both fields. §1.4 parses
> them and returns a verdict — **category is a random slice** for the Metro-dominated 89.66%
> of that population, and **private-label share is 1.09×**, near-neutral. The residual
> 23.72% carries the `vendor||sku` id form, which has no name or brand, and remains
> genuinely untestable. The limitation shrank from all orphans to a quarter of them.

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

**A practical note on how the twice-check must be run.** Two of the paired runs for §1.4
and §1.5 initially came back different, and neither was a determinism failure — one run of
each pair had hit an out-of-memory error because it was competing with another query for
the same 3 GB budget. **A crashed run and a non-deterministic run look identical to a
byte-comparison.** The pairs are therefore run sequentially and alone, and a pair that
differs is inspected before being called a defect rather than after. Re-run that way,
`Q1c` and `Q1d` are both byte-identical across two clean runs, as are `Q1` and `Q1b`.

---

---

### 1.4 Orphan category and brand bias — tested, not untestable

*Computed under build `2026-08-28T17:48:35Z` — models `d1f90ee`/`f6d7345`/`6d01e90`/`01ff1a1`/`b584c32`/`b2f47b3`/`bfc7be8`. Computed twice and compared.*

**§1.2 recorded category and brand as "untestable" for orphan rows. That was true of the
join and false of the data, and it is now replaced with a result.** 76.28% of orphan rows
carry a `product_id` in the retired `vendor~name@units^brand` form, which contains the
name and the brand outright. Parsed — not joined, not keyed.

**On locked decision 5.** This is not a breach and the distinction is worth stating.
Locked decision 5 forbids the supplied row id as a **product identity** — keying, joining,
matching, or following a product through time — and its stated hazard is that the id
"changes daily", which is a claim about identity *over time*. `Q1c` parses descriptive
text out of a string and counts distributions: no key, no join on the id, no product
tracked across dates, no orphan row admitted to any finding. The precedent was accepted at
Section 1 sign-off, where `Q1b` derived the orphan vendor prefix from `product_id` and
sized orphan events on it. `check_layering.py` governs `models/`; this is `analysis/`, and
the check still passes.

#### Coverage, stated before the result

| Measure | Value |
|---|---|
| Orphan rows | 878,559 |
| **Parsable (`vendor~name@units^brand`)** | **670,189 — 76.28%** |
| Rows with an empty name slot | **0** |
| Rows with an empty brand slot | 27,451 (4.10% of parsable) |

**The uncovered 23.72% is genuinely untestable and stays that way.** Those rows carry the
`vendor||sku` id form, which contains no name and no brand — there is nothing to parse.
The limitation shrinks from *all* orphans to *a quarter* of them; it does not vanish.

**The parsable set is not Metro-only, but it is Metro-dominated:**

| Vendor | Parsable rows | % of parsable |
|---|---|---|
| **Metro** | 600,909 | **89.66%** |
| Walmart | 38,533 | 5.75% |
| TandT | 13,897 | 2.07% |
| Galleria | 4,334 | 0.65% |
| Voila | 3,507 | 0.52% |
| NoFrills | 3,090 | 0.46% |
| Loblaws | 3,074 | 0.46% |
| SaveOnFoods | 2,845 | 0.42% |

The parse is legible on inspection — `Metro / Old Cheddar Cheese Slices / Cracker Barrel`,
`Walmart / Rao's Tomato Basil Sauce, 660ml / Rao's Homemade` — rather than trusted.

#### The pooled result is wrong, and the within-vendor result is the answer

Pooled across vendors, brand looks dramatic: national brand 1.79×, private label 1.73×,
`unclassifiable_no_vendor_data` 0.10×. **That is the F1 confound for the third time in one
audit.** 89.66% of parsable orphans are Metro, while the retained pool includes Voila,
T&T and Galleria — all 100% `unclassifiable_no_vendor_data` (§3.3). The retained side is
diluted with brandless vendors that barely appear in the orphan set.

Within vendor, for Metro — the 89.66% that carries the result:

| Category | % orphan | % retained | Ratio |
|---|---|---|---|
| bread & bakery | 4.68 | 5.12 | 0.91 |
| dairy | 17.85 | 18.11 | **0.99** |
| eggs | 0.74 | 1.02 | 0.73 |
| produce | 13.58 | 12.67 | 1.07 |
| meat & fish | 7.00 | 8.77 | 0.80 |
| pantry staples | 9.10 | 6.98 | 1.30 |
| beverages | 12.55 | 12.26 | **1.02** |
| other | 34.50 | 35.07 | **0.98** |

**Verdict on category: random slice.** No Metro category departs from its retained share
by more than 30%, and the four largest categories are within 2%. Walmart shows a real skew
(produce 1.81×, meat & fish 1.78×) but is 5.75% of the parsable set; T&T's beverages run
2.11× on 13,897 rows.

| Metro brand class | % orphan | % retained | Ratio |
|---|---|---|---|
| national_brand | 79.35 | 73.48 | **1.08** |
| private_label | 20.61 | 18.95 | **1.09** |
| unclassifiable_blank | 0.04 | 7.56 | 0.01 |

**Private-label share, the number D4 would inherit: 20.608% orphan against 18.950%
retained — 1.09×.** Near-neutral.

#### A limitation in the method itself, volunteered

**The brand comparison is partly measuring the parse condition, not orphaning.** The
`vendor~name@units^brand` form *requires* a brand slot, so parsable orphans are selected
toward rows that have a brand recorded at all. That is why `unclassifiable_blank` runs
0.01× at Metro and 0.17× at Walmart — those rows are largely in the unparsable 23.72%, not
absent from the orphan population.

The conditioning bites least where the retained blank rate is already low. Metro's retained
rows are 7.56% blank, so Metro's ratios are close to honest. **Walmart's retained rows are
79.92% blank**, which is why its brand ratios read 4.22× and 5.23× — those are the parse
condition, not a finding, and they should not be quoted as one.

**So: category is a random slice for the dominant population and mildly skewed for two
small ones; brand is near-neutral where it can be measured cleanly and confounded where it
cannot.** The verdict table is updated from "untestable" to "random slice (category) /
near-neutral where measurable (brand), 76.28% coverage".

*Source: `Q1c_orphan_attribute_bias.sql`.*

---

### 1.5 The `vendor_sku` filter — a fourth exclusion class, undeclared until now

*Computed under the same build. Computed twice and compared.*

**Where it came from.** Phase 0's F5 partitioned literally by `(vendor, sku)`. A blank sku
under that partition collapses every blank-sku product at a vendor into one price series,
so F5 **had** to write `WHERE p.sku IS NOT NULL AND trim(p.sku) <> ''`. The filter was
never a judgement about which products deserve measuring; it was a consequence of the key.

`P2_3` inherited it verbatim, for the stated reason that "definitions are held identical to
F5 so the comparison is like-for-like". But `P2_3` keys on `product_key`, and §4.1 built
the `concatted` fallback **specifically so the 25,728 blank-sku products would have a
key**. The filter now removes exactly the population the owned key was designed to cover,
for a reason that no longer applies.

#### The reconciliation: 576,200 → 566,564, line by line

Every cell counted, none derived by subtraction:

| Population | Events |
|---|---|
| **A.** all keys, all dates *(Q1b)* | **576,200** |
| **B.** all keys, date ≥ 2024-06-11 | 575,078 |
| **C.** `vendor_sku` only, all dates | 567,403 |
| **D.** `vendor_sku` only, date ≥ 2024-06-11 *(P2_3)* | **566,564** |

| Effect | Events |
|---|---|
| Total difference A − D | **9,636** |
| Lost to the date floor (all keys) | **1,122** |
| Lost to the sku filter (all dates) | **8,797** |
| Overlap — lost to both | **283** |
| **1,122 + 8,797 − 283** | **= 9,636** ✓ |

**The two are reconciled exactly.** The undeclared sku filter removes **8× more events
than the declared date floor** — 8,797 against 1,122.

The date floor is recomputed rather than filtered after the fact, because the floor
*truncates* an event spanning it rather than removing it, and a filtered-afterwards count
would get that wrong.

#### Per vendor and year — and it lands almost entirely on 2024

| Vendor | 2024 removed | 2024 % | 2025 % | 2026 % |
|---|---|---|---|---|
| **Walmart** | 2,568 | **26.293%** | 0.000% | 0.000% |
| **Galleria** | 130 | **21.886%** | 0.000% | 0.000% |
| Metro | 2,406 | 7.475% | 0.000% | 0.000% |
| TandT | 479 | 5.933% | 0.000% | 0.000% |
| Voila | 772 | 3.322% | 0.000% | 0.000% |
| NoFrills | 442 | 2.136% | 0.018% | 0.030% |
| Loblaws | 419 | 1.876% | 0.024% | 0.039% |
| SaveOnFoods | 18 | 0.092% | 0.000% | 0.000% |

**This is the second exclusion that concentrates in 2024, and it stacks on the first.**
2024 already loses 26.8% of Metro's events to orphaning; it also loses 26.3% of Walmart's
and 21.9% of Galleria's to the sku filter. The two classes hit different vendors hardest,
which makes a 2024 cross-vendor comparison worse than either number alone suggests.

#### Is the removed set a random slice? No.

| Measure | Removed (`vendor_concatted`) | Kept (`vendor_sku`) | Ratio |
|---|---|---|---|
| Events | 8,514 | 566,564 | — |
| Median run days | **6.0** | 8.0 | 0.75 |
| % with an `old_price` value | 99.58 | 98.56 | 1.01 |
| **% multibuy** | **5.485** | 2.371 | **2.31** |
| national_brand share | 76.60% | 59.02% | 1.30 |
| **private_label share** | **4.02%** | 10.41% | **0.39** |
| beverages share | 16.65% | 10.91% | 1.53 |
| dairy share | 15.12% | 19.31% | 0.78 |

**Verdict: distinct type, on every axis tested.** Blank-sku events are shorter, 2.3× richer
in multibuy, 1.3× more national-brand, 2.6× less private-label, and almost entirely 2024.

#### But at the level D2 is actually built on, it is 539 events

The evaluable cohort — events with 14 days of continuous pre-window history, which is what
every D2 number rests on:

| Basis | Evaluable events |
|---|---|
| `vendor_sku` | **279,599** *(matches P2_3 exactly)* |
| `vendor_concatted` | **539** |

**Admitting blank-sku products adds 539 events to 279,599 — 0.19%.** The 8,797 sale events
collapse to 539 evaluable ones because blank-sku products are short-lived and sparsely
observed (median run 6 days, overwhelmingly 2024 small-basket era), so few accumulate 14
continuous pre-window days.

**So the class is biased and immaterial at the same time**, and both halves have to be said
together. Reporting only "distinct type on every axis" would overstate it; reporting only
"0.19%" would hide that the 0.19% is not a random 0.19%.

#### Decision: the filter is removed as a filter and replaced by a reported tier

Justified on current grounds, not inherited ones:

1. **Its original necessity is gone.** F5 needed it because of the `(vendor, sku)`
   partition. `product_key` covers blank-sku products via `concatted`, which is the whole
   reason §4.1 built the fallback.
2. **Keeping it silently breaks honesty rule 7.** It has been removing 8,797 sale events
   with no count stated anywhere — larger than the date floor, which *is* documented.
3. **Admitting them unmarked would break honesty rule 2.** `vendor_concatted` is a weaker
   identity: §1.4 found 12 rows where upstream re-keyed a product from the concatted form
   to `vendor||sku` after recovering a sku, so a concatted key can split one product into
   two series across snapshots. Match confidence is first-class; a weaker tier is flagged
   and kept, never deleted and never silently mixed in.
4. **The choice barely moves the headline either way** — 0.19% of the evaluable cohort.
   That makes the honest option cheap, which is the best reason to take it.

**Implementation for Section 2:** D2 headline figures are computed on
`product_key_basis = 'vendor_sku'` and the `vendor_concatted` contribution is reported
alongside with its count and its bias verdict — the same pattern honesty rule 2 prescribes
for match tiers. Nothing is dropped at load time and the count is always answerable.

**This does not change any published Phase 1 number.** §2.3's 566,564 / 279,599 stand
exactly as published; what changes is that the filter behind them is now declared, counted
and tiered rather than inherited and invisible.

*Source: `Q1d_sku_filter_audit.sql`.*

---

---

## Section 2 — D2, sale honesty

*Computed under build `2026-08-28T17:48:35Z` — models `d1f90ee`/`f6d7345`/`6d01e90`/`01ff1a1`/`b584c32`/`b2f47b3`/`bfc7be8`.*

**Scope is set by §1's bias audit, not by preference. Headline window: 2025-01-01 →
2026-08-21.** Every vendor-year in it loses under 4.5% of its events to orphaning and
essentially 0% to the sku filter. **2024 is reported separately and never pooled**, because
it loses 26.8% of Metro's events to orphaning, 26.3% of Walmart's and 21.9% of Galleria's
to the sku filter, and a cross-vendor comparison across those measures exclusions rather
than prices.

### 2A — Pre-sale price inflation

> ### Headline: between 3.39% and 21.27% of 2025–26 sale events advertise a regular price not supported by the fortnight before the sale.
>
> **A bracket, not a point — see §2.6.** The lower bound is built to exonerate (one high
> observation anywhere in 14 days clears the retailer, including a price held for a single
> day). The upper bound is built to accuse (a genuine mid-window price rise flags a
> truthful claim). Most of the gap between them is genuine price increases followed by
> sales, which is quantified below — so the truth sits nearer the lower bound, but
> "nearer" is not a number and neither bound may be quoted alone.

#### The cohort, and every step that narrows it

| Step | Events |
|---|---|
| a. sale events, all keys, all dates ≥ 2024-06-11 | 575,036 |
| b. + 14 continuous pre-window days | 279,962 |
| c. + a usable claimed regular (`old_price` value) | 275,779 |
| d. + `vendor_sku` tier only | 275,240 |
| **e. HEADLINE: 2025–2026** | **228,608** |

The identity-tier split, per §1.5 — reported, not dropped:

| Tier | Events | of which 2025–26 |
|---|---|---|
| `vendor_sku` | 275,240 | 228,608 |
| `vendor_concatted` | **539** | 81 |

**539 — the same number `Q1d` produced by a completely different route.** §1.5 reached it
from the sku-filter side; 2A reaches it from the cohort side. An independent
cross-validation of the §1.5 decision.

#### The comparison statistic is an argument, and the argument matters enormously

Three candidates for "what was the price before the sale", all computed:

| Statistic | n | % of events where the claimed regular exceeds it |
|---|---|---|
| **modal** (most frequently charged in the 14 days) | 228,608 | **21.27%** |
| median | 228,608 | 20.59% |
| **last observed** (day before the sale) | 228,608 | **4.41%** |
| **max observed** (strictest — exceeds *every* price seen) | 228,608 | **3.39%** |

**A 6× spread between the loosest and strictest reading.** Any single number quoted from
this without its statistic named is meaningless, which is why the sensitivity table is part
of the headline rather than an appendix.

The headline uses **modal** for the flag and **max observed** for the finding. Modal
answers "what was the shopper habitually paying" — "regular" means habitually charged, not
centrally located. But modal alone cannot distinguish a fabricated regular price from a
real price rise, which is what the innocent-explanation analysis below is for.

#### 2A.3 Per vendor, with n

| Vendor | n events | % above modal | % above median | % above last | **% above MAX** |
|---|---|---|---|---|---|
| Galleria | 1,138 | 34.27 | 34.36 | 30.40 | **24.08** |
| SaveOnFoods | 67,952 | 28.88 | 28.94 | 3.26 | **3.24** |
| Metro | 22,611 | 26.70 | 26.44 | 6.79 | **6.20** |
| NoFrills | 29,231 | 21.55 | 19.08 | 8.81 | **4.97** |
| Voila | 56,222 | 17.48 | 17.38 | 0.86 | **0.85** |
| Loblaws | 31,068 | 15.81 | 13.46 | 5.73 | **3.41** |
| TandT | 14,934 | 8.26 | 8.15 | 6.41 | **5.02** |
| Walmart | 5,452 | 5.28 | 5.23 | 3.32 | **2.27** |

**Loblaws' under-sampling is in the result, not beneath it:** §2.7 established that 3,979
of Loblaws' 43,253 evaluable events (9.20%) carry a sale flag with no usable `old_price`
value, because 869,495 rows hold the literal string `was`. Those events cannot enter 2A at
all — 2A requires a claimed *value*. **Loblaws' 31,068 here is a 90.80% sample of its
eligible events; every other vendor is at 100%.** Loblaws' figures are therefore computed
on a slightly different base and should not be ranked against the others without that
stated.

Magnitude of the excess where it exists, against modal:

| Vendor | n flagged | median excess | p25 | p75 | p95 |
|---|---|---|---|---|---|
| Galleria | 390 | 30.04% | 20.35 | 43.12 | 73.21 |
| SaveOnFoods | 19,627 | 29.75% | 16.62 | 45.08 | 76.33 |
| Voila | 9,830 | 28.03% | 16.69 | 49.67 | 87.72 |
| Metro | 6,038 | 25.06% | 12.52 | 46.73 | 100.40 |
| Walmart | 288 | 20.51% | 11.26 | 37.78 | 74.31 |
| NoFrills | 6,298 | 20.00% | 11.60 | 34.50 | 69.90 |
| Loblaws | 4,912 | 18.63% | 10.00 | 33.33 | 71.14 |
| TandT | 1,233 | 10.03% | 10.01 | 24.75 | 55.16 |

#### 2A.4 Innocent explanations, quantified before anything is concluded

Three explanations would each produce a flag with no dishonesty. All three are measured on
the flagged events:

| Vendor | n flagged | Claim **was** actually charged in the window | Price **rose** during the window | Volatile window (>2 prices) |
|---|---|---|---|---|
| Voila | 9,830 | **95.15%** | 96.11% | 2.16% |
| SaveOnFoods | 19,627 | **88.77%** | 92.48% | 6.59% |
| Loblaws | 4,912 | **78.46%** | 73.25% | 6.45% |
| NoFrills | 6,298 | **76.93%** | 71.78% | 3.24% |
| Metro | 6,038 | **76.78%** | 81.53% | 3.46% |
| Walmart | 288 | 56.94% | 46.53% | 7.64% |
| TandT | 1,233 | 39.17% | 36.98% | 5.60% |
| Galleria | 390 | 29.74% | 25.90% | 3.85% |

**Between 77% and 95% of flagged events at the five largest vendors are explained by the
retailer having genuinely charged that price at some point in the 14 days**, and a similar
share show the price rising within the window. That is a price increase followed by a sale
— entirely ordinary retail behaviour, and not what "pre-sale inflation" means.

**This is the bad news for the naive reading and it is the main result of 2A.** A headline
of "21% of sales advertise an inflated regular price" would have been wrong, and it would
have been wrong in the direction that generates a story.

#### The residual: the claim exceeds *every* price observed in the 14-day window

No innocent explanation above covers these. The retailer struck out a price it did not
charge at any point in the fortnight before the sale.

| Vendor | n events | Claim never charged | **%** | Median excess over the highest observed |
|---|---|---|---|---|
| **Galleria** | 1,138 | 274 | **24.08%** | 28.62% |
| **Metro** | 22,611 | 1,402 | **6.20%** | 12.53% |
| TandT | 14,934 | 750 | 5.02% | 10.01% |
| NoFrills | 29,231 | 1,453 | 4.97% | 14.50% |
| Loblaws | 31,068 | 1,058 | 3.41% | 11.60% |
| SaveOnFoods | 67,952 | 2,204 | 3.24% | 6.36% |
| Walmart | 5,452 | 124 | 2.27% | 20.00% |
| Voila | 56,222 | 477 | 0.85% | 6.40% |
| **Pooled** | **228,608** | **7,742** | **3.39%** | — |

**Galleria's 24.08% is the standout and its n is 1,138 — the smallest cohort of any
vendor.** It is a real rate on a small base, not a large finding, and it must be quoted
with its n every time.

**Caveats that belong in the headline, not a footnote:**

- The window is **14 days**. A regular price charged 20 days before the sale and raised in
  between would be flagged here and is not necessarily dishonest. A longer window would
  lower the residual; we have not measured by how much.
- The residual is a **lower bound on innocence, not an upper bound on dishonesty**: it
  excludes every event where the claim matched a price actually charged, even if that price
  was charged for a single day specifically to justify the claim. This analysis cannot
  distinguish that from ordinary repricing, and it does not try.
- `min()` is used for the daily charged price where a product has conflicting same-day rows
  (Phase 0 B6). That is the **conservative** choice for this test: it lowers the observed
  level, which makes a claim *more* likely to be flagged, so the residual is if anything
  slightly overstated.

#### 2A.2 Basis and multibuy handling

Comparisons are made only within a matching `price_basis`; the cohort is 226,758 `each`
and 1,850 `per_100g`. Multibuy events compare on derived `unit_price` with `min_qty`
stated:

| | n events | median `min_qty` | % above modal |
|---|---|---|---|
| single-unit | 227,806 | 1 | 21.19% |
| **multibuy** | **802** | **2** | **42.14%** |

Multibuy events flag at twice the rate — but **n = 802**, and this is a flag rate against
modal, not the residual. It is a lead for Phase 3, not a finding.

#### 2024, separately caveated

Never pooled with the headline. Reported so the difference is visible:

| Vendor | 2024 n / % above modal | 2025 | 2026 |
|---|---|---|---|
| Metro | 861 / 35.31% | 4,505 / 35.87% | 18,106 / 24.42% |
| SaveOnFoods | 11,380 / 29.77% | 49,248 / 28.64% | 18,704 / 29.51% |
| NoFrills | 8,783 / 20.76% | 16,146 / 23.67% | 13,085 / 18.93% |
| Voila | 10,681 / 18.06% | 34,607 / 18.10% | 21,615 / 16.50% |
| Loblaws | 8,205 / 15.99% | 17,074 / 14.24% | 13,994 / 17.73% |
| TandT | 3,924 / 17.71% | 7,474 / 12.56% | 7,460 / 3.94% |
| Galleria | 285 / 31.93% | 715 / 32.31% | 423 / 37.59% |
| Walmart | 2,513 / 5.33% | 3,510 / 4.50% | 1,942 / 6.69% |

**Metro's 2024 n is 861 against 18,106 in 2026** — a 21× difference in sample size for the
same vendor, which is exactly the orphaning loss §1.2 measured. Any 2024-to-2025 movement
for Metro is uninterpretable, and this table is presented for completeness rather than as
a trend.

**T&T falls from 17.71% to 3.94% across the three years.** That is a large movement in a
vendor with no material exclusion problem, and it is the most interesting thing in this
table. It is not explained here.

*Source: `Q2a_presale_inflation.sql`.*

---

### 2B — Sale frequency

> ### Headline (WITHIN VENDOR ONLY — the cross-vendor ranking is withdrawn, see §2.7).
>
> At Save-On-Foods the median product carries a struck-out price on **32.12%** of its
> observed days and **21.08%** of its products do so on more than half of them; at Metro,
> **26.44%** and **18.28%**. A product on sale most of the time does not have a sale
> price — it has a price.
>
> **These are not comparable across vendors.** §2.7 found that `old_price` presence is
> corroborated by an independent promotional signal on 99.50% of rows at No Frills and
> **21.46%** at Save-On-Foods, with Metro untestable — and Save-On-Foods and Metro are
> exactly the two vendors this table ranks first and second. Every table below is a
> within-vendor statement.

**2B.3 — this finding is untouched by the `was` loss, and here is the number proving it.**
2B uses `old_price` as a **flag only**, never as a value. §2.7 found 869,495 rows carrying
the literal string `was`, and the exposure is entirely Loblaws:

| Vendor | Sale rows (2025–26) | With no usable value | % flag-only |
|---|---|---|---|
| **Loblaws** | 2,012,425 | 577,054 | **28.67%** |
| NoFrills | 1,247,314 | 5,521 | 0.44% |
| every other vendor | — | 0 | **0.00%** |

**28.67% of Loblaws' sale rows carry a flag with no value.** 2A cannot use those rows at
all; 2B uses every one of them. That is the entire reason for running two independent D2
findings rather than one.

#### Cohort

| Step | Products |
|---|---|
| observed at all in 2025–26 | 163,118 |
| + observed on 90+ days | 117,910 |
| **+ `vendor_sku` tier (headline)** | **117,803** |

Tier split per §1.5: `vendor_concatted` contributes **107 products** with a median
on-sale share of 0.88%, against 117,803 at 9.91%. Reported, not dropped.

**The denominator is days OBSERVED, never days elapsed.** Honesty rule 1: a day a product
was not observed is not a day it was off sale. This matters on a dataset with a 19-day
dataset-wide blackout and 271 missing vendor-days (Phase 0 E9), and it is why the 90-day
observation floor is applied before any share is computed.

#### 2B.1 Distribution per vendor

| Vendor | n products | median days observed | **median % of days on sale** | p75 | p90 | mean |
|---|---|---|---|---|---|---|
| **SaveOnFoods** | 12,389 | 545 | **32.12%** | 46.49 | 61.01 | 32.20 |
| **Metro** | 14,970 | 298 | **26.44%** | 43.72 | 60.99 | 28.48 |
| Loblaws | 24,323 | 412 | 12.12% | 27.55 | 43.68 | 17.02 |
| Voila | 18,854 | 509 | 11.41% | 31.06 | 45.66 | 17.25 |
| NoFrills | 18,638 | 383 | 8.98% | 23.17 | 32.26 | 12.70 |
| Walmart | 9,750 | 338 | 2.62% | 17.37 | 29.43 | 10.23 |
| TandT | 9,299 | 487 | 1.38% | 9.84 | 18.23 | 5.93 |
| **Galleria** | 9,580 | 489 | **0.00%** | 0.00 | 0.00 | 0.78 |

**Galleria's median, p75 and p90 are all zero.** Phase 0 established Galleria's `old_price`
coverage at 0.92% — the lowest of any vendor — so this is a measurement of Galleria's
*reporting*, not of its promotional behaviour. Galleria should not be read as "never
discounts"; it should be read as "does not publish a struck-out price". Stated here rather
than left for a reader to infer.

#### 2B.2 "Always on sale"

| Vendor | n products | ≥50% of days | **%** | ≥75% | % | ≥90% | % |
|---|---|---|---|---|---|---|---|
| **SaveOnFoods** | 12,389 | 2,611 | **21.08%** | 482 | 3.89% | 132 | 1.07% |
| **Metro** | 14,970 | 2,737 | **18.28%** | 511 | 3.41% | 126 | 0.84% |
| Loblaws | 24,323 | 1,515 | 6.23% | 292 | 1.20% | 202 | 0.83% |
| Voila | 18,854 | 1,048 | 5.56% | 17 | 0.09% | 2 | 0.01% |
| Walmart | 9,750 | 172 | 1.76% | 88 | 0.90% | 73 | 0.75% |
| NoFrills | 18,638 | 108 | 0.58% | 17 | 0.09% | 0 | 0.00% |
| Galleria | 9,580 | 42 | 0.44% | 30 | 0.31% | 16 | 0.17% |
| TandT | 9,299 | 12 | 0.13% | 2 | 0.02% | 1 | 0.01% |

**More than one in five Save-On-Foods products, and nearly one in five Metro products, is
advertised as on sale for at least half the days it appears.** The steep fall from ≥50% to
≥75% (21.08% → 3.89% at Save-On-Foods) says this is a broad pattern of frequent promotion
rather than a small set of permanently-discounted items.

The permanent extreme is genuinely rare:

| Vendor | On sale on **every** observed day | % | median days observed |
|---|---|---|---|
| Loblaws | 140 | 0.576% | 175 |
| SaveOnFoods | 32 | 0.258% | 105 |
| Walmart | 16 | 0.164% | 101 |
| Metro | 10 | 0.067% | 120 |
| Galleria | 2 | 0.021% | 290 |
| NoFrills / TandT / Voila | 0 | 0.000% | — |

#### Where the always-on-sale products concentrate

> **WITHDRAWN as a pooled result (§2.7).** The two tables below pool all vendors, which
> weights them by their flag rates — and those rates are not measuring the same thing
> (99.50% corroboration at No Frills against 21.46% at Save-On-Foods). Save-On-Foods and
> Metro together supply most of the ≥50% population, so a pooled category mix is close to
> a Save-On-Foods-and-Metro mix. Retained below as a description of the pooled data, not
> as a cross-vendor finding; re-deriving it within vendor is Section 3 work.

Category, as a concentration ratio against each category's share of the whole cohort:

| Category | % of all products | % of ≥50% products | Ratio |
|---|---|---|---|
| **dairy** | 15.03 | 19.85 | **1.32** |
| beverages | 10.68 | 12.59 | 1.18 |
| produce | 13.04 | 14.37 | 1.10 |
| eggs | 1.32 | 1.36 | 1.03 |
| pantry staples | 7.87 | 7.45 | 0.95 |
| bread & bakery | 3.59 | 3.17 | 0.88 |
| other | 39.04 | 34.37 | 0.88 |
| **meat & fish** | 9.43 | 6.84 | **0.73** |

**No category exceeds 1.32×.** Frequent promotion is spread broadly across the catalogue
rather than concentrated in one aisle — dairy leans in mildly, meat and fish lean out.

By brand class:

| Brand class | n products | median % on sale | % ≥50% |
|---|---|---|---|
| national_brand | 54,655 | 19.75% | 10.58% |
| **private_label** | 12,258 | 9.87% | 9.15% |
| unclassifiable_blank | 13,149 | 3.03% | 1.79% |
| unclassifiable_no_vendor_data | 37,733 | 0.00% | 2.92% |

**National brands are promoted about twice as often as private label at the median**
(19.75% vs 9.87%), while the share crossing the 50% threshold is close (10.58% vs 9.15%).
The `unclassifiable_no_vendor_data` median of 0.00% is Galleria, T&T and Voila — the three
vendors with no brand data — and is a reporting artifact, not behaviour.

#### 2024, separately caveated

| Vendor | n products | median % on sale 2024 | % ≥50% 2024 |
|---|---|---|---|
| SaveOnFoods | 8,339 | 35.11% | 31.77% |
| Metro | 5,591 | 26.72% | 22.68% |
| Loblaws | 16,453 | 13.71% | 19.60% |
| Voila | 12,079 | 9.95% | 13.39% |
| NoFrills | 14,079 | 3.23% | 3.44% |
| Galleria | 4,945 | 0.00% | 1.31% |
| TandT | 6,954 | 0.00% | 0.04% |
| Walmart | 7,608 | 0.00% | 0.71% |

Not pooled with the headline. The vendor ordering is stable between 2024 and 2025–26,
which is mild reassurance that the exclusion concentration in 2024 has not reversed the
ranking — but Metro's 2024 product count is 5,591 against 14,970 in 2025–26, so its 2024
figures rest on a third of the sample and should not be differenced against the later
period.

*Source: `Q2b_sale_frequency.sql`.*

#### What 2A and 2B say together — and how much less than it first appeared

The first version of this section synthesised the two findings into a claim about
"these two vendors". **§2.7 removed the basis for that**, and the synthesis is narrowed
accordingly.

What still holds, within vendor:

- **2A**: between 3.39% and 21.27% of sale events advertise a regular price not supported
  by the prior fortnight, with most of the gap attributable to genuine price rises.
- **2B**: at Save-On-Foods, 21.08% of products carry a struck-out price on more than half
  their observed days; at Metro, 18.28%.

What does **not** hold: any statement that Save-On-Foods or Metro promote *more than* other
vendors, because their flag is the least corroborated of the eight and Metro's cannot be
corroborated at all.

**Phase 2 has not found retailers lying about prices, and it has not found that any
retailer discounts more than another.** It has found that the struck-out price is often
not supported by the recent past (bracketed, mostly explicable), and that at two vendors
the struck-out price is present on a large share of days — which may be promotional cadence
or may be a field populated for other reasons. Distinguishing those needs a signal this
dataset does not carry.

---

### 2.5 Galleria's 2A cohort — characterised, and 24.08% is now quotable only with its qualifier

*Computed under build `2026-08-28T17:48:35Z`. Verified with `verify_twice.py`: 14 result sets, both runs clean and identical.*

**The concern was correct.** Galleria's 2A cohort is not a sample of Galleria; it is a
sample of one corner of Galleria.

#### The selection funnel

| Step | Products |
|---|---|
| Galleria products in catalogue | **10,697** |
| with any price row | 10,651 |
| with any sale flag | **658** |
| with a usable `old_price` **value** | **658** |

**658 of 10,697 — 6.15% of the catalogue supplies the entire cohort.** Row-level, 53,487
of 5,864,799 rows carry a sale flag: **0.912%**, which reproduces Phase 0 C4's 0.92%
independently.

Note that sale-flag products and usable-value products are the *same* 658. Unlike Loblaws,
Galleria has no `was` problem — when it populates `old_price` it populates a number.

#### Composition against the full catalogue

| Category | % of catalogue | % of eligible | **Over-representation** |
|---|---|---|---|
| **pantry staples** | 12.15 | 25.84 | **2.13×** |
| eggs | 0.79 | 1.06 | 1.35× |
| dairy | 7.04 | 6.84 | 0.97× |
| meat & fish | 8.51 | 8.36 | 0.98× |
| other | 49.14 | 45.74 | 0.93× |
| produce | 11.32 | 9.73 | 0.86× |
| **bread & bakery** | 1.58 | 0.46 | **0.29×** |
| **beverages** | 9.48 | 1.98 | **0.21×** |

| Unit type | % of catalogue | % of eligible |
|---|---|---|
| **g** (dry/packaged) | 73.75 | **84.35** |
| **ml** (liquids) | 19.22 | **8.51** |
| unparsed | 5.94 | 5.02 |
| count | 1.09 | 2.13 |

**The cohort is skewed toward packaged dry pantry goods and away from beverages and
liquids** — pantry staples 2.13× over-weighted, beverages 0.21× and bread 0.29×
under-weighted, and mass-denominated products 84.35% of the cohort against 73.75% of the
catalogue.

This is structurally the same finding Phase 0 made about D1's 474 Metro SKUs: the slice
that survives a coverage filter is a *kind* of product, not a random draw.

#### The ambiguous overlap: essentially nil

| Measure | Value |
|---|---|
| Galleria products with ambiguous bare-integer rows | 90 |
| Galleria ambiguous rows | 26,305 |
| 2A-eligible products | 658 |
| **Overlap** | **2 products** |
| Overlapping products | `CHEETOS PUFFS`, `CHEETOS CRUNCHY` (each ~1% ambiguous) |
| **Eligible rows on an ambiguous product** | **14 of 53,487 — 0.026%** |

**The ambiguous exclusion does not touch Galleria's 24.08%.** The two populations are
effectively disjoint, so no pre-window maximum in the Galleria cohort is computed from a
thinned set of observations. That question is closed.

#### Verdict

**24.08% is quotable, but only as this sentence:** *"24.08% of the 1,138 evaluable sale
events at Galleria — drawn from 658 products, 6.15% of its catalogue, over-weighted 2.13×
to packaged pantry staples and under-weighted 5× to beverages — advertise a regular price
never charged in the 14 days prior."*

It is **not** quotable as "Galleria's rate", and it must never be ranked against other
vendors' rates without that qualifier, because the other vendors' cohorts are not selected
the same way. Galleria's 0.912% flag coverage makes its cohort roughly 30× more selected
than Save-On-Foods' (32.394% of rows carry a flag).

*Source: `Q2c_galleria_cohort.sql`.*

---

### 2.6 Direction of error — the 2A finding is a bracket, not a point

**The previous framing gave 3.39% as "the finding" and 21.27% as "the naive statistic".
That was wrong in a specific way: it presented the lower bound as the answer.** Both are
bounds, both err, and they err in opposite directions.

| Statistic | Rate | **Direction of error** | Why |
|---|---|---|---|
| **modal** | **21.27%** | **over-detects** | A genuine mid-window price rise leaves the *old, lower* price as the mode, so a truthful claim about the *new* regular price is flagged. Every real price increase followed by a sale counts as a hit. |
| median | 20.59% | over-detects | Same mechanism, marginally less sensitive to a short high spell. |
| last observed | 4.41% | mixed | Captures a genuine rise (the claim matches the new level, no flag) but is a single observation — one anomalous day before the sale either exonerates or condemns on n=1. |
| **max observed** | **3.39%** | **under-detects** | **One** high observation anywhere in 14 days clears the retailer, including a price held for a single day. A price raised for one day specifically to justify a struck-out claim is scored innocent. |

**The finding is therefore: between 3.39% and 21.27% of 2025–26 sale events advertise a
regular price not supported by the fortnight before the sale — with the lower bound
constructed to exonerate and the upper bound constructed to accuse.**

Per vendor, the bracket:

| Vendor | n | **Lower (max-observed)** | **Upper (modal)** | Width |
|---|---|---|---|---|
| Galleria | 1,138 | **24.08%** | **34.27%** | 10.2 pp |
| SaveOnFoods | 67,952 | 3.24% | 28.88% | 25.6 pp |
| Metro | 22,611 | 6.20% | 26.70% | 20.5 pp |
| NoFrills | 29,231 | 4.97% | 21.55% | 16.6 pp |
| Voila | 56,222 | 0.85% | 17.48% | 16.6 pp |
| Loblaws | 31,068 | 3.41% | 15.81% | 12.4 pp |
| TandT | 14,934 | 5.02% | 8.26% | 3.2 pp |
| Walmart | 5,452 | 2.27% | 5.28% | 3.0 pp |
| **Pooled** | **228,608** | **3.39%** | **21.27%** | **17.9 pp** |

**Where in the bracket the truth sits is not uniform across vendors**, and the bracket
width is itself informative. T&T and Walmart have narrow brackets (3.0–3.2 pp): their
flagged events are mostly *not* explained by an intra-window price rise, so the two bounds
nearly agree. Save-On-Foods has a 25.6 pp bracket: almost all of its apparent inflation is
absorbed by observed prices, which is why its innocent-explanation rate is 88.77%.

**Neither bound should be quoted alone.** The earlier headline ("3.39%, not 21%") is
replaced by the bracket. Reporting only the lower bound understates in exactly the
direction that flatters retailers, which is the failure mode honesty rule 10 exists for —
and it is the same error, in the same direction, that F5 caught pre-parse in Phase 0.

*Source: `Q2a_presale_inflation.sql` results 14 and 16.*

---

### 2.7 The 2B sale flag is NOT semantically equivalent across vendors — the cross-vendor comparison is withdrawn

*Verified with `verify_twice.py`: 8 result sets, both runs clean and identical.*

> ### Verdict: equivalence fails. 2B is republished as a within-vendor result only.

#### `other` is a per-vendor vocabulary, not a shared flag

| Vendor | Example `other` content | Rows |
|---|---|---|
| Voila | `SALE` | 1,923,684 |
| Walmart | `Rollback`, also `Best seller`, `Made In Canada`, `1000+ bought in past month` | 353,568 |
| Loblaws | `sale\n$3.50 MIN 2` (multibuy promo text) | 86,764 |
| SaveOnFoods | `2 for $7` (multibuy text, no "sale" word) | 88,036 |
| Galleria | `Out of Stock` (availability, not promotion) | 2,082,759 |
| NoFrills | `Low Stock` (availability, not promotion) | 285,449 |

`other` therefore cannot be a cross-vendor sale signal. It can, however, act as an
**independent witness**: if `old_price` presence means "on sale" everywhere, then at
vendors whose `other` carries promotional vocabulary the two should corroborate at
comparable rates.

| Vendor | % of rows with promotional `other` | **% of `old_price` rows corroborated** |
|---|---|---|
| NoFrills | 14.13% | **99.50%** |
| Loblaws | 24.07% | **99.06%** |
| Voila | 19.39% | **98.20%** |
| Walmart | 17.11% | **79.02%** |
| **SaveOnFoods** | 8.62% | **21.46%** |
| **TandT** | 0.88% | **0.04%** |
| Galleria | **0.00%** | untestable — no promotional `other` |
| **Metro** | **0.00%** | untestable — **`other` is empty on all 6,003,385 rows** |

**Spread across the six testable vendors: 0.04% to 99.50% — 99.46 percentage points.**

That is not "comparable rates". At No Frills, Loblaws and Voila the two mechanisms are
effectively the same signal. At Save-On-Foods, **fewer than a quarter** of `old_price`-
present rows carry any promotional text. At T&T, essentially none do.

#### Why this specifically breaks 2B's headline

**The two vendors 2B ranked first and second are precisely the two whose flag cannot be
corroborated.**

| Vendor | 2B median % of days on sale | Corroboration of the flag |
|---|---|---|
| **SaveOnFoods** | **32.12%** (rank 1) | **21.46%** |
| **Metro** | **26.44%** (rank 2) | **untestable — no `other` data at all** |
| Loblaws | 12.12% | 99.06% |
| Voila | 11.41% | 98.20% |
| NoFrills | 8.98% | 99.50% |

Save-On-Foods populates `old_price` in a large set of situations that its own free-text
field does not describe as promotional. That may be a genuine promotion the vendor simply
does not label, or it may be `old_price` carrying a list price, a former price, or a
unit-size comparison. **This analysis cannot distinguish those**, and until it can, "Save-On-
Foods discounts more often than Loblaws" is not a supported claim — it may be "Save-On-
Foods populates `old_price` more often than Loblaws".

Ordering under the two mechanisms differs materially:

| Vendor | % rows `old_price` present | % rows promotional `other` |
|---|---|---|
| SaveOnFoods | **32.39%** (1st) | 8.62% (5th) |
| Metro | 28.98% (2nd) | 0.00% (7th=) |
| Voila | 19.12% (3rd) | 19.39% (2nd) |
| Loblaws | 17.78% (4th) | **24.07%** (1st) |
| NoFrills | 14.11% (5th) | 14.13% (4th) |
| Walmart | 12.24% (6th) | 17.11% (3rd) |

**The vendor ranking depends on which flag you pick.** Save-On-Foods is first under one
and fifth under the other; Loblaws is fourth under one and first under the other. A
cross-vendor ranking that reverses under an equally defensible definition of the same
concept is not a finding.

#### What 2B still supports

- **Within-vendor statements stand.** "At Save-On-Foods, the median product carries a
  struck-out price on 32.12% of observed days, and 21.08% of its products do so on more
  than half of them" is a claim about Save-On-Foods' own data under one consistent
  definition. It is unaffected by what `old_price` means at Metro.
- **Within-vendor comparisons over time stand**, for the same reason.
- **The category and brand-class breakdowns stand within vendor** but not pooled, since
  pooling weights vendors by their flag rates.

#### What is withdrawn

- The cross-vendor **ranking** of sale frequency.
- The pooled category concentration table and pooled brand-class table in 2B, which mix
  vendors with 99.50% and 21.46% flag corroboration.
- Any statement of the form "vendor X promotes more than vendor Y".

**Also corrected:** §2.7 of Phase 1 established that `old_price` presence and value diverge
only at Loblaws (71.33% of present rows carry a value; every other vendor is ~100%). That
remains true and is a *different* problem from this one. Presence-vs-value is about whether
the number is usable; this is about whether the presence means the same thing at all.

*Source: `Q2d_flag_semantics.sql`.*

---

### 2.8 The compute-twice check, hardened

**The hole:** `diff run1 run2` reports agreement when **both runs fail the same way**.
§1.3 already recorded the near-miss — paired runs that differed because one had OOM'd. The
dangerous case is the symmetric one: both runs OOM at the same statement, both truncate
identically, and the check passes.

`scripts/verify_twice.py` replaces the bare diff and asserts, in order:

| # | Assertion | Catches |
|---|---|---|
| 1 | both runs exited 0 | outright failure |
| 2 | no failure marker in either output (`!! statement`, `Out of Memory`, `Binder Error`, `Segmentation fault`, …) | **two runs failing identically** |
| 3 | both runs produced the same **number of result sets** | truncation |
| 4 | every result set has the same row count | partial divergence |
| 5 | `--min-rows`: no result set unexpectedly empty | a silently empty upstream temp table |
| 6 | **then** byte-identity | non-determinism |

`--expect-statements N` pins the result-set count, so a query that quietly loses a
statement fails here rather than being certified reproducible.

`scripts/test_verify_twice.py` proves it fails when it should — **5 of 5 cases**, including
the one that matters: a probe forced to OOM deterministically, where both runs truncate to
identical output and the checker **still refuses**. A plain `diff` passes that probe.

One note on building the test itself: the non-determinism probe first used
`ORDER BY random()` over 3 rows, which returned the same order twice often enough to make
the *test* flaky. It now uses 200 rows. A flaky test for flakiness would have been a poor
advertisement.

**Every Section 2 number from this point is verified with `verify_twice.py`, not with
`diff`.** §1's numbers were verified before this existed; they were re-run sequentially and
alone at the time, and their result-set counts and row counts are recorded in the logs, but
they predate assertion 2 and should be re-verified under the new checker when next touched.

*Source: `scripts/verify_twice.py`, `scripts/test_verify_twice.py`.*

---

## What would change these conclusions

- **The Metro 2024 bias disappears** if upstream publishes a mapping from retired
  `product_id` values to current ones — the single fix that would erase 74% of the orphan
  population (`docs/upstream-feedback.md` §5). Until then it is permanent.
- **The category axis for orphans becomes testable** only if upstream publishes a product
  history table. No downstream work recovers it: §5.9 tested both plausible recovery paths
  and both returned exactly zero matches.
- **The ambiguous exclusion shrinks** if Galleria's bare integers are ever adjudicated —
  26,306 of the 46,884 are Galleria, held ambiguous for want of evidence, not because the
  evidence is against them.

**On 2A specifically:**

- **A longer pre-window would lower the 3.39% residual**, and we have not measured by how
  much. 14 days is inherited from F1/F5 and is a choice, not a fact. Recomputing at 28 and
  60 days is the single most valuable robustness check outstanding.
- **A price charged for one day to justify a claim is counted as innocent here.** This
  analysis cannot separate that from ordinary repricing. Doing so would need either
  intraday data or a model of what a "real" price spell looks like — the first does not
  exist in this dataset and the second is a modelling choice we have not made.
- **Galleria's 24.08% rests on n = 1,138**, the smallest cohort of any vendor. A second
  snapshot with more Galleria history would move it more than any methodological change.

---

## Status

**Section 1 complete** (1.1–1.5). **Section 2 complete** (2A, 2B). Every number computed
twice and compared byte-for-byte, sequentially and alone.

**Section 3 (D4 basket comparison) and Section 4 (D1 bounded secondary) are not started.**
