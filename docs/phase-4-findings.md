# Phase 4 — Findings

# §1 — Refresh cadence, measured

The brief says: *do not pick a schedule, derive it.* This document is the derivation. It
builds nothing, and it recommends one thing, at the end, from numbers that exist first.

*Computed under build `2026-08-28T17:48:35Z` — models
`d1f90ee`/`f6d7345`/`6d01e90`/`01ff1a1`/`b584c32`/`b2f47b3`/`bfc7be8`, snapshot
`20260822T134045Z`, data through 2026-08-21. Every figure below was computed twice with
`scripts/verify_twice.py` and both runs agreed.*

Queries: [R1](../analysis/phase4/R1_refresh_cadence.sql) (cadence),
[R2](../analysis/phase4/R2_publication_and_coverage.sql) (coverage),
[R3](../analysis/phase4/R3_staleness_by_interval.sql) (staleness by interval),
[R4](../analysis/phase4/R4_refresh_day_matrix.sql) (refresh-day matrix),
[R5](../analysis/phase4/R5_staleness_on_tool_basket.sql) (staleness on the tool basket).

## What was measured on

From 2024-06-11 — the full-catalogue era; the small-basket period before it cannot support
a cadence claim — there are **71,672,743** price rows. Excluded per the standing rules:

| Exclusion | Rows | Rule |
|---|---|---|
| no product record | 868,910 | honesty rule 6 |
| ambiguous price | 46,858 | honesty rule 3 |
| unparseable price | 31 | — |

Leaving **60,096,683 product-days** — one row per product, per date, per price basis. Basis
is carried through every measurement below, because a move between a per-weight price and
an each-price is not a price change.

---

## 1.1 Day-of-week distribution — the flyer cycle is real, and it is Thursday

Restricted to changes observed across a **one-day** gap, so the change is attributable to a
single weekday. n = **56,176,157** adjacent-day observation pairs.

Share of each chain's price changes that fall on its busiest weekday, against the 14.29% an
even split would give:

| Chain | Busiest day | Share of that chain's changes | Quietest day | Excess over even split |
|---|---|---|---|---|
| Voila | Thursday | **92.62%** | 0.10% | +78.33 pp |
| Metro | Thursday | **92.50%** | 0.44% | +78.21 pp |
| Save-On-Foods | Thursday | **89.40%** | 0.23% | +75.11 pp |
| Loblaws | Thursday | **86.50%** | 0.56% | +72.21 pp |
| No Frills | Thursday | **85.41%** | 1.51% | +71.12 pp |
| Walmart | Thursday | **63.13%** | 2.44% | +48.84 pp |
| Galleria | Friday | 46.74% | 4.83% | +32.45 pp |
| T&T | Friday | 44.93% | 4.86% | +30.64 pp |

This is the sharpest single pattern in the project. Six chains change prices on Thursday and
effectively nowhere else; the two Asian-grocery chains run a Friday cycle instead, less
tightly. Put the other way round: on a Thursday, **22.21% of Metro's observed products
change price**. On a Sunday, 0.10%.

**It is not a 2024 artefact.** Measured within each year separately, every chain keeps the
same busiest weekday in 2024, 2025 and 2026:

| Chain | 2024 | 2025 | 2026 |
|---|---|---|---|
| Voila | Thu 92.54% | Thu 92.88% | Thu 92.30% |
| Metro | Thu 91.61% | Thu 92.03% | Thu 93.62% |
| Loblaws | Thu 87.53% | Thu 85.95% | Thu 86.57% |
| Save-On-Foods | Thu 81.85% | Thu 90.08% | Thu 91.70% |
| No Frills | Thu 81.47% | Thu 82.31% | Thu 91.77% |
| Walmart | Thu 57.81% | Thu 66.06% | Thu 65.64% |
| T&T | Fri 32.49% | Fri 57.31% | Fri 75.79% |
| Galleria | Fri 55.45% | Fri 42.10% | Fri 46.22% |

Two chains have *tightened* markedly (T&T 32% → 76%, No Frills 81% → 92%). None has
dissolved. A schedule built on this is built on a live pattern, not on history.

**One caveat I should state rather than let a reader infer it.** This measures the day a
change was *observed in the extract*, not the day the retailer moved the shelf price. If
the upstream scraper runs at a fixed hour, a Wednesday-evening change surfaces as a
Thursday observation. That does not weaken the scheduling conclusion — the tool consumes
the extract, so the extract's cycle is the one that binds it — but the supported claim is
"prices in this dataset move on Thursdays", not "supermarkets reprice on Thursdays". I am
making the weaker one.

---

## 1.2 How long a price holds

A spell is a run of constant price. A new spell starts when the price changes **or when the
observation gap exceeds 3 days** — beyond that the price was not observed to hold, and
counting it as held would be forward-filling across a gap (honesty rule 1). Only completed
spells count; a spell still running at the end of the data is right-censored and would drag
the median down. n = **2,443,095** completed spells.

| Chain | Completed spells | Median days held | p90 | p25 | Share holding ≤ 7 days |
|---|---|---|---|---|---|
| No Frills | 440,503 | **7** | 52 | 3 | 52.19% |
| Metro | 421,437 | **8** | 36 | 5 | 48.25% |
| T&T | 177,934 | **8** | 84 | 2 | 49.37% |
| Save-On-Foods | 354,650 | **10** | 35 | 7 | 46.88% |
| Walmart | 217,312 | **10** | 65 | 3 | 45.59% |
| Loblaws | 453,607 | **13** | 58 | 6 | 44.21% |
| Voila | 320,447 | **16** | 98 | 7 | 36.99% |
| Galleria | 57,205 | **39** | 297 | 8 | 18.13% |

The three chains the tool compares are Metro (8 days), Save-On-Foods (10) and Walmart (10).
**Roughly half of all price spells end within a week**, and the p90 is 35–65 days — so this
is not "stable prices with rare jumps". It is bimodal: a large population of weekly
promotional prices sitting on top of a long tail of prices that hold for months.

Splitting spells by whether the price was ever flagged on sale makes that explicit:

| Chain | Median days at a sale price | Median days at a regular price | Sale spells | Regular spells |
|---|---|---|---|---|
| Loblaws | **7** | 14 | 141,352 | 312,255 |
| Metro | **7** | 13 | 183,957 | 237,480 |
| No Frills | **7** | 10 | 114,539 | 325,964 |
| Save-On-Foods | **7** | 14 | 171,443 | 183,207 |
| Voila | **7** | 28 | 126,179 | 194,268 |
| Galleria | 9 | 41 | 2,180 | 55,025 |
| Walmart | 9 | 10 | 39,453 | 177,859 |
| T&T | 9 | **7** | 29,777 | 148,157 |

A median of **exactly 7 days** at five chains is the flyer week arriving a second time from
an independent direction. The refresh has to track the shorter of the two populations, not
the average of them.

T&T is the one inversion — its sale prices last *longer* than its regular ones. Its flag
semantics were already found to differ from other chains (Phase 2 §2.7), and it is outside
the tool's scope, so I note it and build nothing on it.

---

## 1.3 Publication lag — n = 2, and reported as n = 2

The brief asks for the distribution. **I hold two snapshots, so there is no distribution and
I am not going to manufacture one.** What exists:

| Snapshot | Latest scrape date in file | Upstream `hammer-lastupdated` | Downloaded | Lag |
|---|---|---|---|---|
| `20260822T134045Z` | 2026-08-21 | 2026-08-21 21:26:00.11 ET | 2026-08-22 13:40 UTC | **1 day** |
| `20260824T132829Z` | 2026-08-23 | 2026-08-23 20:20:35.14 ET | 2026-08-24 13:28 UTC | **1 day** |

A third observation exists as a live reading of `hammer-lastupdated.txt` on 2026-09-10, with
no archive downloaded: `2026-09-09 21:48:16.67 (Eastern Time)` — again one day. Three points,
all identical. Three points are still not a distribution.

**The reliable part of this is the time of day, not the lag.** All three publication
timestamps are evening Eastern — 20:20, 21:26, 21:48 — clustered inside 90 minutes. That
constrains *when* a refresh should run far more usefully than the lag figure does, and it is
the part most likely to survive the maintainer's warning: if publication becomes irregular,
the hour it lands at is what stays put, because it is a job's schedule.

**Scrape continuity is excellent, and must not be confused with this.** Across the whole
history there is exactly **one** gap in scrape dates: 2025-08-10 → 2025-08-30, **20 days**.
Every other calendar day from 2024-06-11 to 2026-08-21 is present. Publication lag and
scrape gaps are two different things and the models keep them as two different fields
(CLAUDE.md, upstream volatility §1).

**The forward-looking risk is not measurable from what I hold.** The maintainer has said
publication is becoming intermittent while post-processing is reworked. Two clean August
observations do not bound that, and a schedule that *assumes* a one-day lag will be wrong
the first time it is not. The design consequence is in §1.4: the refresh must be
pull-and-check, and the interface must display the **actual date of the data it is
showing**, never a computed "expected" date.

---

## 1.3b Coverage — the term the brief did not ask for, and the one that dominates

A refresh interval only bounds staleness if the data behind it is current. Two things break
that independently of how often the job runs, and only one of them is publication lag. The
other is that a chain is simply **absent** from a day's extract — a known upstream
condition (CLAUDE.md, extract failures), and honesty rule 1 says an absent day is not an
unchanged price.

Over 598 days from 2025-01-01, per chain:

| Chain | Days present | Days missing | Present | Longest absence | Absences |
|---|---|---|---|---|---|
| **Walmart** | 513 | **85** | **85.79%** | **49 days** | 4 |
| Voila | 573 | 25 | 95.82% | 20 | 4 |
| Save-On-Foods | 576 | 22 | 96.32% | 19 | 4 |
| Metro | 577 | 21 | 96.49% | 19 | 3 |
| Loblaws | 578 | 20 | 96.66% | 19 | 2 |
| No Frills | 578 | 20 | 96.66% | 19 | 2 |
| Galleria | 579 | 19 | 96.82% | 19 | 1 |
| T&T | 579 | 19 | 96.82% | 19 | 1 |

**Read the 19s and the 85 completely differently.** The 19–22 days everyone shares are the
one dataset-wide gap of §1.3 — 2025-08-10 to 2025-08-30 — appearing once per chain. Strip
it out and six of eight chains are missing 0–3 days in twenty months. Walmart's 85 is its
own, and it is not one bad patch:

| Chain | Absent from | Absent to | Days |
|---|---|---|---|
| **Walmart** | 2025-08-11 | 2025-09-28 | **49** |
| **Walmart** | 2026-03-15 | 2026-04-09 | **26** |
| Metro | 2025-08-11 | 2025-08-29 | 19 |
| Save-On-Foods | 2025-08-11 | 2025-08-29 | 19 |
| **Walmart** | 2026-04-11 | 2026-04-19 | **9** |
| Metro | 2025-11-18 | 2025-11-18 | 1 |
| Metro | 2026-01-14 | 2026-01-14 | 1 |
| Save-On-Foods | 2026-05-20 | 2026-05-20 | 1 |
| Save-On-Foods | 2026-05-27 | 2026-05-27 | 1 |
| Save-On-Foods | 2026-08-16 | 2026-08-16 | 1 |
| Walmart | 2026-05-27 | 2026-05-27 | 1 |

Walmart's 49-day run *begins* with the shared gap and then continues for 29 days after every
other chain had resumed. It went out again for 26 days in March–April 2026 and for 9 more
days a week later. That is 84 of its 85 missing days in three episodes, the most recent of
them five months before the snapshot.

**This is the largest single term in worst-case staleness and no refresh schedule touches
it.** A tool refreshing hourly against an upstream that has not seen Walmart for a month
still shows a month-old Walmart price. It is a disclosure problem and a pipeline-behaviour
problem, not a cadence problem — and it is exactly what brief §3.2 anticipated: a chain with
no recent observation shows as **"no recent price"**, never as absent and never silently
dropped from the comparison. §1.4 makes that a hard rule with a number attached.

**Partial extracts are a much smaller problem, but they are not zero.** A chain can be
present and nearly empty, which an absence count cannot see:

| Chain | Days present | Median basket coverage | Days under half | Days under a tenth |
|---|---|---|---|---|
| Metro | 577 | 1,633 products | 7 (1.21%) | 2 |
| Walmart | 513 | 1,610 products | 4 (0.78%) | 2 |
| Save-On-Foods | 576 | 2,408 products | 1 (0.17%) | 0 |

Metro's basket bottoms out at **1 product** on its worst day against a median of 1,633.
Twelve days across three chains in twenty months is rare, but a refresh that happened to
land on one of them would publish a nearly-empty comparison with a fresh date on it. That
needs a floor check in the pipeline, not a schedule change.

---

## 1.3c What a refresh interval actually costs

This is the number the schedule turns on, and it is the one place where I had to throw work
away and redo it.

**R1's first attempt at this was wrong and is withdrawn.** It asked "what share of prices
change within k days" and divided by consecutive-observation pairs with a gap of at most k
days. Because the dataset is near-daily, that denominator is roughly 97% one-day pairs, so
it re-measured the one-day rate k times. It reported Metro at 3.40% for k=1 and 4.19% for
k=7, and the flatness should have been the tell. The correct 7-day figure is **27.45%** —
the broken measure understated it **6.5×**.

The replacement is forward-looking: take a price captured on date d, find the same product
at the same chain on the same basis on date d+k, and ask whether it differs. A pair counts
only when the product is observed on **both** days; counterparts that do not exist are
dropped and counted rather than assumed unchanged. Basket of 5,188 barcodes, 3,143,456
product-days, 2025-01-01 to 2026-08-21.

**Share of displayed prices that are wrong, by age of the data:**

| Chain | 1 day | 2 days | 3 days | 7 days | 14 days |
|---|---|---|---|---|---|
| Save-On-Foods | 5.15% | 10.37% | 15.53% | **35.45%** | 49.07% |
| Metro | 4.04% | 7.92% | 11.90% | **27.45%** | 37.44% |
| Walmart | 1.47% | 2.78% | 4.08% | **9.19%** | 17.16% |

n per cell ranges from 635,578 (Walmart, 14 days) to 1,332,890 (Save-On-Foods, 1 day); the
unobserved counterparts dropped range from 35,370 to 243,901.

**And the refresh day does not change the worst case.** I expected Friday to beat Wednesday,
because the Thursday cycle is so sharp. It does not, at a 7-day horizon — every 7-day window
contains exactly one Thursday:

| Chain | Best capture weekday | Worst | Spread |
|---|---|---|---|
| Metro | Saturday 27.31% | Tuesday 27.59% | **0.28 pp** |
| Save-On-Foods | Thursday 35.14% | Sunday 35.68% | **0.54 pp** |
| Walmart | Saturday 9.13% | Friday 9.29% | **0.16 pp** |

That is a flat line, and it is worth stating because the intuition it kills is a strong one.
Aligning a weekly refresh to the flyer cycle cannot reduce how wrong the tool gets before
its next refresh. What it can change is how *long* the tool spends in that state, which is a
different quantity, measured separately in §1.4.

---

## 1.3d Which day to refresh on — the worst case is flat, the mean is not

§1.3c showed the refresh day cannot lower the worst case. That left an obvious follow-up: if
the day does not change how wrong the tool gets, does it change how long it stays wrong?
It does, by a factor of five and a half.

The full matrix — for a price captured on weekday W, the share wrong h days later:

**Metro** (n per cell ≥ 107,362)

| Captured on | +1d | +2d | +3d | +4d | +5d | +6d | +7d |
|---|---|---|---|---|---|---|---|
| **Thursday** | **0.68** | **1.02** | **1.07** | **1.32** | **1.45** | **1.45** | 27.50 |
| Friday | 0.46 | 0.50 | 0.70 | 0.90 | 0.92 | 27.14 | 27.37 |
| Saturday | 0.11 | 0.28 | 0.47 | 0.55 | 26.99 | 27.27 | 27.31 |
| Sunday | 0.27 | 0.43 | 0.50 | 26.81 | 27.16 | 27.16 | 27.44 |
| Monday | 0.27 | 0.35 | 26.62 | 26.94 | 26.99 | 27.27 | 27.50 |
| Tuesday | 0.16 | 26.65 | 26.88 | 27.02 | 27.11 | 27.41 | 27.59 |
| Wednesday | **26.67** | 26.95 | 27.03 | 27.23 | 27.50 | 27.75 | 27.46 |

**Save-On-Foods** (n per cell ≥ 173,194)

| Captured on | +1d | +2d | +3d | +4d | +5d | +6d | +7d |
|---|---|---|---|---|---|---|---|
| **Thursday** | **0.99** | **2.11** | **2.23** | **2.27** | **2.65** | **2.68** | 35.14 |
| Friday | 1.15 | 1.26 | 1.31 | 1.69 | 1.71 | 34.80 | 35.25 |
| Saturday | 0.05 | 0.10 | 0.50 | 0.50 | 34.27 | 34.73 | 35.60 |
| Sunday | 0.06 | 0.47 | 0.46 | 34.36 | 34.84 | 35.60 | 35.68 |
| Monday | 0.42 | 0.42 | 34.17 | 34.65 | 35.53 | 35.61 | 35.49 |
| Tuesday | 0.30 | 34.00 | 34.48 | 35.37 | 35.46 | 35.34 | 35.55 |
| Wednesday | **33.87** | 34.41 | 35.31 | 35.37 | 35.26 | 35.48 | 35.45 |

**Walmart** (n per cell ≥ 90,653)

| Captured on | +1d | +2d | +3d | +4d | +5d | +6d | +7d |
|---|---|---|---|---|---|---|---|
| **Thursday** | **0.67** | **0.98** | **0.99** | **1.57** | **1.94** | **2.44** | 9.21 |
| Friday | 0.42 | 0.41 | 1.01 | 1.42 | 1.93 | 8.73 | 9.29 |
| Saturday | 0.09 | 0.70 | 1.15 | 1.64 | 8.49 | 9.08 | 9.13 |
| Sunday | 0.70 | 1.14 | 1.61 | 8.35 | 8.97 | 9.03 | 9.16 |
| Monday | 0.58 | 1.06 | 7.90 | 8.49 | 8.63 | 8.69 | 9.17 |
| Tuesday | 0.61 | 7.50 | 8.02 | 8.20 | 8.31 | 8.80 | 9.20 |
| Wednesday | **6.98** | 7.59 | 7.75 | 7.81 | 8.33 | 8.73 | 9.15 |

The step is the Thursday reprice, and it lands wherever the next Thursday falls. Collapsed
to the two numbers a schedule is chosen on:

| Chain | Refresh on | Worst before next refresh | Mean across the week |
|---|---|---|---|
| Metro | **Thursday's data** | 27.50% | **4.93%** |
| Metro | Wednesday's data | 27.75% | 27.23% |
| Save-On-Foods | **Thursday's data** | 35.14% | **6.87%** |
| Save-On-Foods | Wednesday's data | 35.48% | 35.02% |
| Walmart | **Thursday's data** | 9.21% | **2.54%** |
| Walmart | Wednesday's data | 9.15% | 8.05% |

Every refresh day between the two ranks in calendar order between them. The worst case
varies by at most **0.44 pp** across all seven days; the mean varies by **5.5×** at Metro and
**5.1×** at Save-On-Foods.

### The uncomfortable comparison: daily buys about one percentage point

The natural assumption is that a daily refresh is obviously better and the only question is
whether it is affordable. The matrix says otherwise. Under a daily refresh the tool always
shows yesterday's scrape, so its error on any given day is the `+1d` cell for the *previous*
weekday — and one of those cells is the Thursday step, which no refresh frequency can avoid,
because the data is published after the day it describes.

Reading the seven `+1d` cells straight off the matrix (no compounding, no model — these are
seven measured values averaged):

| Chain | Daily refresh, mean error | Weekly on Thursday's data, mean error | Difference |
|---|---|---|---|
| Metro | 4.09% | 4.93% | **0.84 pp** |
| Save-On-Foods | 5.26% | 6.87% | **1.61 pp** |
| Walmart | 1.44% | 2.54% | **1.10 pp** |

And on the worst case, daily is 26.67% / 33.87% / 6.98% against weekly's 27.50% / 35.14% /
9.21% — **under 2.3 pp apart**.

**A daily refresh is seven times the work for about one percentage point.** That is the
finding, and it is not the one I expected to write.

---

## 1.3e The same measure, on the products the tool actually shows

R3 and R4 measure every reliable barcode the three chains carry — 5,188. The tool does not
ship 5,188. It ships the comparison basket: barcodes co-observed at two or more of the three
chains on 90+ dates, which is **3,190** (3,477 is the wider figure that includes Galleria,
and Galleria is out of scope per Phase 2 §3.7). A staleness figure printed in the interface
is a claim about the prices on the screen, so it has to be computed on the prices on the
screen.

The query independently rebuilds the basket and gets 3,190, matching the dashboard extract,
so the two cannot silently drift apart. 3,282,137 product-days.

| Chain | 1 day | 2 days | 3 days | 7 days | 14 days |
|---|---|---|---|---|---|
| Save-On-Foods | 5.32% | 10.71% | 16.06% | **36.68%** | 50.42% |
| Metro | 4.17% | 8.18% | 12.29% | **28.39%** | 38.33% |
| Walmart | 1.51% | 2.87% | 4.21% | **9.48%** | 17.68% |

**The tool's basket is more volatile than the population it came from**, at every chain and
every horizon: +1.23 pp at Save-On-Foods, +0.94 at Metro, +0.29 at Walmart on the 7-day
figure. That is a selection effect and it points the wrong way for us — selecting barcodes
for being well observed also selects for being widely stocked and heavily promoted. **The
narrower, worse numbers govern the disclosure.** Had I only measured the wider set I would
have published a figure about 1 pp too flattering.

**Do not print the pooled figure.** Pooled across the three chains the 7-day rate is 27.52%,
which is a weighted average dominated by Save-On-Foods' larger basket and understates the
chain a user is most likely to be wrong about by 9 pp. This is the same pooling confound
that overturned three separate Phase 2 results, and the answer is the same: report per
chain, and where one number is needed, report the worst one.

---

## 1.4 The recommendation

**Refresh weekly, consuming Thursday's scrape, with a daily cheap check that it arrived.**

Concretely:

| | |
|---|---|
| **Full refresh** | Weekly, **Friday 05:00 UTC** (01:00 EDT / 00:00 EST Friday) |
| **Consumes** | Thursday's scrape — the file published Thursday evening Eastern |
| **Daily probe** | `hammer-lastupdated.txt` every day at 05:00 UTC. Hundreds of bytes, not 1.4 GB |
| **If Thursday's file is late** | The probe sees it; the full refresh runs the next day it appears, and every day after until it does |
| **Gates before deploy** | Schema contract, determinism and reconciliation checks, and a coverage floor (below). A failed gate keeps the previous deploy live |

### Why weekly and not daily

Because the measured difference is about one percentage point, and the cost is a volunteer's
bandwidth.

- Daily refresh, mean share of displayed prices wrong: 4.09% (Metro), 5.26% (Save-On-Foods),
  1.44% (Walmart).
- Weekly on Thursday's data: 4.93%, 6.87%, 2.54%. **Between 0.84 and 1.61 pp worse.**
- Worst case, daily against weekly: 26.67% vs 27.50%, 33.87% vs 35.14%, 6.98% vs 9.21%.
  **Under 2.3 pp apart.**

Daily cannot do better than that, because the Thursday reprice is published *after* the day
it describes. Every refresh strategy shows Wednesday's prices to a Thursday visitor. Raising
the frequency does not buy back a blind spot created by the publication lag.

Against that ~1 pp: each snapshot is **1.45 GB** (498 MB + 950 MB). Weekly is ~75 GB a year
off the maintainer's server; daily is ~529 GB. This project exists on that maintainer's
goodwill and an explicit non-commercial undertaking. Seven times the load for one percentage
point is not a trade I would make, and it is not one I would want to have to explain.

*(The daily-refresh means above are read off §1.3d's matrix, which uses the wider 5,188
basket. §1.3e shows the tool's own basket runs ~1 pp worse at 7 days, so both columns are
slightly optimistic by about the same amount. The gap between them is what the decision
rests on, and the gap is unaffected.)*

### Why Thursday, and why the choice matters less than it looks

Six of eight chains reprice on Thursday and effectively nowhere else (§1.1), stably across
three years. Consuming Thursday's scrape puts the refresh immediately after the weekly move.

But be clear about what that buys. It does **not** lower the worst case — the worst case is
flat to within 0.44 pp across all seven candidate days (§1.3d), because every seven-day
window contains exactly one Thursday. What it lowers is the *time spent* at the worst case:
5.5× at Metro, 5.1× at Save-On-Foods. Refreshing on Thursday's data means the tool is under
1.5% wrong for six days and then wrong for one. Refreshing on Wednesday's means it is 27%
wrong for six days out of seven. Same peak, entirely different week.

### The worst-case staleness this implies, and where it goes

**Two different worst cases, and they must be disclosed differently.**

**1. Scheduled staleness — bounded, and the interface can state it as a number.** At the
moment just before a refresh, the displayed data is 8 days old: 7 days of interval plus the
1-day publication lag. Measured on the 3,190 barcodes the tool ships:

| Chain | Share of displayed prices that may have changed, worst moment in the week |
|---|---|
| Save-On-Foods | **36.68%** |
| Metro | **28.39%** |
| Walmart | **9.48%** |

For the day after a refresh those figures are 5.32%, 4.17% and 1.51%. **The interface states
the worst one, not the average and not the pooled figure** (§1.3e). In plain words, for the
disclosure line: *prices are 1–8 days old; at the end of that window as many as one in three
may have changed.*

**2. Absence staleness — unbounded by any schedule, and the interface must show the date
rather than a promise.** §1.3b: Walmart was absent from the dataset for 49 consecutive days
in 2025 and 26 more in 2026. No refresh cadence touches this. Therefore:

> **Corrected in §2.** The rule below is right, but the reasoning behind it named the wrong
> chain. Chain-level absence — a whole chain vanishing for weeks — is Walmart's problem.
> What the 7-day rule mostly catches is **product-level catalogue rotation**, an individual
> line not listed this week, and there **Metro** is the worst by a wide margin: 67.42% of
> its offers comparable against 85.19% and 85.25%. On the extract date no chain was absent
> at all, so every exclusion the tool currently makes is a product, not a chain. These are
> two different failure modes and I had conflated them.


- Every price carries **its own observed date**, not the refresh date. These are different
  fields, and conflating them would be the publication-lag error from CLAUDE.md repeated
  inside our own product.
- A chain whose latest observation is **more than 7 days behind the extract's own maximum
  date** is shown as **"no recent price"** — never as absent, never silently dropped from
  the comparison (brief §3.2). A 7-day threshold catches all four multi-day absence episodes
  observed since 2025 and none of the single days. Measured against the shipped extract it
  excludes 1,256 offers, 651 of them Metro's (§2).
- The extract's metadata records, per chain, the latest observed date and how many days it is
  behind, so the interface renders this from data rather than from a rule compiled into the
  page.

**3. A coverage floor, because a chain can be present and nearly empty.** Metro's basket
bottomed out at 1 product against a median of 1,633 (§1.3b). Twelve such days across three
chains in twenty months — rare, but a refresh landing on one would publish a nearly-empty
comparison under a fresh date. **A chain contributing under half its trailing-median basket
coverage is treated as absent for that refresh**, and if the whole extract is under floor,
the refresh does not deploy.

### What would make me change this

Stated now, with numbers, so it is a check rather than a judgement call later:

- **If publication becomes irregular enough that Thursday's file is late in more than 1 week
  in 4**, weekly stops being defensible — a missed Thursday makes the tool 15 days stale, and
  §1.3e puts Save-On-Foods past 50% wrong at 14 days. The daily probe measures exactly this
  at negligible cost, and the answer becomes daily polling with a full pull on first sight of
  a new file.
- **If the Thursday concentration decays below roughly 60%** at Metro or Save-On-Foods, the
  day-alignment argument weakens and the schedule should be re-derived. It is currently 92.50%
  and 89.40%, and rising, so this is a tripwire rather than an expectation.
- **If Walmart's absences recur**, its comparisons may need withdrawing rather than
  labelling. 85 missing days in 598 is tolerable with a clear "no recent price"; a chain
  absent half the time is not one the tool can honestly compare.

### Carried forward, unchanged

The brief's non-goal stands and nothing in Section 2 onward may erode it: **no ads, no
ad-network scripts, no third-party trackers.** The licence request to the maintainer stated
this project was non-commercial with no ads, and permission was granted on that basis. This
is deferred pending a written answer from the maintainer, not declined, and that agreement
would be its own decision made separately from this brief. If basic usage numbers are wanted,
a cookieless, privacy-respecting counter and nothing more.

---

## What §1 changed about the plan

1. **The extract needs a per-chain freshness block**, not just prices — latest observed date
   and days-behind, per chain. Section 2 should add it to 2.1's field list.
2. **History depth (brief 2.2) has an answer now.** Median hold is 8–10 days and the cycle is
   weekly, so "is today's price unusual" needs weeks, not months. Four to six weeks of
   per-barcode history covers about four flyer cycles and keeps the extract small. Galleria's
   39-day median would have argued for more, and Galleria is out of scope.
3. **Two numbers were wrong and are withdrawn**, both mine, both caught by the standing
   controls: R1's k-day staleness measure (understated 6.5×, §1.3c), and an R3 statement that
   crashed identically on both runs and compared byte-identical — caught by `verify_twice.py`,
   which asserts completion before it compares bytes. Second incident of that class.


---
---

# §2 — The data extract

*Computed under build `2026-08-28T17:48:35Z` — models
`d1f90ee`/`f6d7345`/`6d01e90`/`01ff1a1`/`b584c32`/`b2f47b3`/`bfc7be8`, snapshot
`20260822T134045Z`, extract date 2026-08-21. Verified twice with `scripts/verify_twice.py`,
byte-identical, and the check includes an md5 of each written JSON file so the files are
covered and not just the printed results.*

Query: [E1_tool_extract.sql](../analysis/phase4/E1_tool_extract.sql). Output:
[`tool/data/`](../tool/data/).

## The design rule this section was built on

An interface can only be as honest as the data it is handed. Each of the four constraints is
therefore enforced in the extract, not left to the page to remember:

| Constraint | How the extract enforces it |
|---|---|
| No pooled staleness | No pooled figure is *computed anywhere in the file*. `meta.json` carries a per-chain curve and nothing else, so the page has no pooled number to display |
| Absence is a property of the comparison | Every product carries a `comparison` object naming the chains compared, the chains excluded with reason and date, and the sentence the interface is licensed to print. "Cheapest" unqualified is not one of the available sentences |
| Per-chain date and staleness are first-class | `observed_date`, `days_behind`, `is_recent`, `staleness_pct`, `staleness_horizon_days` and `staleness_exceeds_measured` are stored per offer. The page is not given the parts to compute a comparison the extract has not licensed |
| Basis never crosses | Every offer carries `price_basis`; only offers on the product's majority basis are marked `comparable`, and the rest carry the reason |

## What shipped

| | |
|---|---|
| Comparison basket | **3,190** barcodes |
| **Products in the extract** | **2,921** |
| Omitted, no observation in 200 days | **269** — delisted or dormant, no price to show |
| Offers (barcode × chain) | 6,093 |
| History spells, 42-day window | 13,260 |
| Rows excluded before the extract | 197 ambiguous, of 1,105,033 in scope. 0 orphan, 0 unparseable, 0 non-positive |

**The 269 are disclosed in `meta.json`, not dropped quietly.** The dashboard already had to
fix one silent contradiction between two basket counts (3,190 against 3,477); shipping 2,921
products under a published figure of 3,190 would have been the same mistake with different
numbers.

## 2.1–2.4 against the brief

**2.1 — per barcode per chain: price, basis, min quantity, date observed, on-sale flag.**
Present, plus the freshness and staleness fields constraint 3 requires. Excluded counts are
in `meta.json`.

**2.2 — short recent price history.** 42 days, six flyer cycles, from the 8–10 day median
hold in §1.2. Exported as **runs of constant price rather than one point per day**: the same
information at a fraction of the size, and gaps stay visible because a spell covers only the
days actually observed (honesty rule 1). The "is this actually a sale" signal from Phase 2
appears per offer as `prior_14d`: days observed, low, high, and **days already spent at this
exact price**. It is a count of days, never a verdict — the findings forbid "retailer X
inflates prices before sales", and a per-product day-count does not say that.

**2.3 — size it.** It ships as static JSON with no backend, comfortably:

| File | Raw | Gzipped |
|---|---|---|
| `products.json` | 3.24 MB | **178.6 KB** |
| `history.json` | 1.60 MB | **75.1 KB** |
| `meta.json` | 2.0 KB | 1.0 KB |
| **Total** | 4.84 MB | **254.7 KB** |

**No history depth had to be cut.** History is a separate file, so §3 can defer loading it
until a product is opened and the first paint costs 179 KB. The one cost worth naming is
parse time: 3.24 MB of JSON is real work on a mid-range phone, and §5.5's phone-width check
should measure it rather than assume it.

**2.4 — basis never crosses.** Enforced, and currently binding on nothing: **all 6,093
offers are `each`**, so `excluded_basis_mismatch` is 0 at every chain. The rule stays,
because a per-weight price appearing later would otherwise be compared silently, but I would
rather record that it is presently vacuous than let the zero read as a passed test.

## The result that matters most, and it is not a good one

**The tool can offer a real comparison for 61% of what it carries.**

| Chains with a price from the last 7 days | Products | Share |
|---|---|---|
| 3 | 464 | 15.88% |
| 2 | 1,316 | 45.05% |
| **1 — nothing to compare** | **813** | **27.83%** |
| **0 — nothing to show** | **328** | **11.23%** |

1,780 of 2,921 products (60.93%) have two or more chains with a recent price. Against the
published basket of 3,190 it is 55.80%. **For nearly two products in five, the honest answer
is "I cannot compare this"** — and that is what the extract makes the page say, rather than
letting it compare whatever it happens to have.

This is the entire reason constraint 2 exists. Without it the tool would compare one chain
against a price from May and call the winner.

### The chain most often missing is Metro, not Walmart

I expected Walmart, and said so. Walmart has by far the worst chain-level absence record —
85 missing days since 2025-01-01 including a 49-day run (§1.3b). At **product** level it is
not the problem:

| Chain | Offers | Comparable | Excluded: no recent price | Share comparable |
|---|---|---|---|---|
| **Metro** | 1,998 | 1,347 | **651** | **67.42%** |
| Walmart | 1,864 | 1,588 | 276 | 85.19% |
| Save-On-Foods | 2,231 | 1,902 | 329 | 85.25% |

These are different failure modes and I had conflated them. Chain-level absence is the whole
chain vanishing from the extract for weeks. What the 7-day rule mostly catches is
**product-level rotation** — an individual line not listed this week — and Metro rotates its
listed catalogue harder than the other two. On the extract date no chain was absent at all;
every one of these 1,256 exclusions is a product, not a chain.

The constraint is right and the reasoning behind it was right. The chain I named was wrong.

## A defect the first run shipped, caught before it went anywhere

The first build handed **every offer a staleness figure**, including offers 200 days old, by
mapping any age above 14 days onto the 14-day measurement. That is presenting an unmeasured
quantity as a measured one — 14 days is simply the longest horizon §1.3e measured, and how
wrong a 200-day-old price is has never been computed.

**1,137 of 6,093 offers (18.66%) were in that state.** They now carry
`staleness_pct: null`, `staleness_horizon_days: null` and
`staleness_exceeds_measured: true`, and §3 must render that as "older than 14 days — how
far it may have moved has not been measured", never as a number.

A second, smaller one: the `size` field was `units_raw`, which at some chains is the product
name with the size glued to the end — `"marvel spidey and his amazing friends170g"`. It now
comes from the parsed quantity and is **null where the parse failed**, which is 114 of 2,921
products. A missing size is better than a wrong one.

## What §2 hands to §3

- `comparison.claim` — the sentence the interface prints. Three forms only: nothing to
  compare, only one chain has a recent price, or cheapest of the *n* named chains.
- `comparison.unavailable` — every excluded chain with its last observed date, its age and
  its reason. Brief §3.2 requires these to be shown, not dropped.
- `offers[].staleness_*` — per chain, measured or explicitly not measured.
- `meta.chains[].staleness` — the per-chain curve for the standing disclosure. There is no
  pooled figure to reach for.

---


---

# §3 — The interface

*Same build and extract as §2. The page is [`tool/index.html`](../tool/index.html), one
static file, no framework and no external request. Verified by
[`scripts/test_tool_render.js`](../scripts/test_tool_render.js), which renders **all 2,921
products** through the page's own card functions — pulled out of `index.html` rather than
copied, so the test cannot drift from what ships — and asserts the honesty rules on the
rendered output.*

## Built unavailable-first, because that is where 39% of it lives

The three result states were written in this order: nothing to compare, then one chain, then
the comparison. That ordering was the point — a tool whose failure states are an afterthought
is a bad tool for 1,141 of its 2,921 products.

**State A — nothing recent anywhere (328 products, 11.23%).** Red rule, and the heading is
the finding, not an apology:

> **Nothing to compare. No chain has a price for this from the last 7 days.**
> This is not a statement that the product is unavailable, and it is certainly not a
> statement about which chain is cheaper. It means the data has nothing recent enough to
> answer with. The last prices I did see are below.

The stale prices still appear, each with its date and its warning. Brief §3.2 forbids
dropping a chain silently; it does not require pretending the old price never existed.

**State B — exactly one chain (813 products, 27.83%).** Amber rule, and the copy exists to
kill one specific misreading:

> **Only Save-On-Foods has a price from the last 7 days.**
> **There is nothing to compare it with.** This does not mean Save-On-Foods is cheapest — it
> means the other chain has no recent price here, so no comparison exists to win.

A single price with a green tick beside it reads as a verdict. This is the state most likely
to mislead, and it is 2.5× more common than the state where nothing shows at all.

**State C — two or three chains (1,780 products, 60.93%).** The heading is
`comparison.claim`, taken verbatim from the extract:

> Cheapest of the 3 chains with a price from the last 7 days: Metro, Save-On-Foods and Walmart.

Cheapest first, each with its date, its basis, its own chain's measured staleness and its
14-day context. Chains that did not qualify appear below a dashed rule under **"Not compared
— last seen"**, struck through and greyed, with the reason and the date.

## Staleness renders as a warning, never as an absence

The 1,137 offers past the longest measured horizon get a bordered red block, not a dash:

> ⚠ **178 days old.** How far this price may have moved since has **not been measured** —
> the longest span I checked is 14 days. Treat it as unknown, not as current.

Everything inside the measured range gets the chain's own figure and the age that goes with
it — *"Captured on the extract date. Measured: 5.32% of Save-On-Foods prices differ a day
after capture."* Per chain, always. There is no pooled number in the extract to print, so
there is none on the page.

The render test asserts both halves: every `staleness_exceeds_measured` offer produces the
words "not been measured" **and** its age in days, and no offer beyond the horizon carries a
percentage.

## The landing state, before anyone searches and misses

Shown above the search box, on first load:

- **2,921 products, all national brands.** *Store brands cannot be compared* and are not
  here at all — President's Choice against Selection is not a comparison this tool can make.
- **3 chains: Metro, Save-On-Foods, Walmart.** In-store pickup prices for one neighbourhood
  in Toronto — not national, not provincial, not delivery.
- **60.9% of them can actually be compared today**, with a four-segment bar breaking that
  into 464 at three chains, 1,316 at two, 813 at only one, 328 with nothing recent — the
  last two labelled *nothing to compare*.
- Prices are from 2026-08-21, refreshed weekly, and **at Save-On-Foods, the chain that moves
  most, 36.68% of prices change over a week** — the worst chain named rather than an average
  taken.

A user should be able to see the shape of the thing before searching for something it does
not have. The empty-search result says the same in miniature rather than a bare "no results".

Underneath everything, fixed to the bottom of the viewport and not behind a link:
*Toronto pickup prices, one neighbourhood · national brands only, no store brands · data to
2026-08-21 · no basket, no store ranking · The underlying data was sourced from
ProjectHammer.org.*

## What the interface deliberately cannot do

**No basket, no total, no store ranking** (brief §3.4). Nothing on the page sums across
products or counts wins per chain. The word "cheapest" appears only inside a sentence naming
the chains it applies to and the product it applies to.

**Six weeks of history, on request.** A step chart per chain, drawn from the spells in
`history.json`, loaded only when asked for so it costs nothing on first paint. Gaps in the
line are days with no observation, and the caption says so — a flat line would be a
forward-fill drawn as a fact.

## Two copy defects the render test caught

Both were in the extract, not the page, which is the right place for them to have been:

1. **The claim printed a raw vendor code.** *"Cheapest of the 2 chains …: SaveOnFoods and
   Walmart."* `SaveOnFoods` is a database key, not a shop name.
2. **Three chains joined as "A and B and C".**

Both are fixed at source: a `chain_label` macro in the extract, carried into every offer,
every unavailable entry, `meta.chains`, and `history.json`. **The page no longer keeps its
own name map** — it reads the label from the data, so there is one mapping rather than two
that can disagree. The test now fails if any raw vendor code reaches the reader, or if a
claim joins names with a repeated "and".

## Size, measured over HTTP

| Asset | Raw | Gzipped |
|---|---|---|
| `index.html` | 21.1 KB | 7.2 KB |
| `data/meta.json` | 2.3 KB | 1.1 KB |
| `data/products.json` | 3,499.0 KB | 180.9 KB |
| `data/history.json` | 1,764.9 KB | 76.5 KB |
| **First paint** (history deferred) | | **189.2 KB** |
| Total if everything is fetched | 5,287.4 KB | 265.7 KB |

All four assets return 200 over HTTP and every JSON parses. Layout is single-column with a
560px breakpoint; **that is a CSS assertion, not a measurement, and §5.5's phone-width check
still has to make it a measurement** — along with the parse cost of 3.5 MB of JSON on a
mid-range phone, which is the one number in this section I do not have.

---

*The underlying data was sourced from ProjectHammer.org.*
