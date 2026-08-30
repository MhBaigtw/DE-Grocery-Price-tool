# Phase 2 — Findings

Phase 1 built representation. Phase 2 produces the two findings the project rests on.

**Scope:** D2 (sale honesty) and D4 (basket comparison). D1 is demoted — see Section 4.
No dashboard, no writeup, no automation. Those are Phase 3 and Phase 4.

Read `CLAUDE.md` first. Two rules matter most here: exclusions are reported, never
silent; and every published number carries its build stamp.

---

## Section 1 — Exclusion accounting and bias audit

**Do this before computing any finding.** Phase 0's F1 got the D2 bias question wrong by
testing the wrong axis, and the correct test changed the answer categorically. That
mistake is cheap now and expensive after a number is published.

Three exclusion classes are now in force: ambiguous prices (46,884 rows), orphan
NULL-key rows (878,559 rows), and unparsed prices (33 rows).

1.1 A single exclusion ledger. For D2 and D4 separately: every row and event removed,
    by class, by vendor, by year. One table, published in the findings doc, quoted in
    any writeup.

1.2 **Bias audit per exclusion class.** For each class, the question is never "how many"
    but "are the removed rows a random slice of what remains". Test on the axes that
    could plausibly move the finding:

    - **Time.** Orphans are 8.412% before 2024-10-01 and 0.357% after, concentrated in
      Metro. D2 spans the whole history, so its early period is materially thinner for
      one vendor and its late period is not. Quantify: per vendor, per year, the share
      of D2 events lost. State whether any vendor-year loses enough to distort a trend.
    - **Promotion type.** The multibuy exclusion was categorical, not partial, and the
      excluded events were ~8pp deeper. That is fixed, but the same test must be run
      against the remaining classes: are ambiguous or orphan rows disproportionately
      sale rows, deep-discount rows, or one promotion type?
    - **Category and brand.** Ambiguous prices are 22.5% produce. Does any exclusion
      class concentrate in a category D4's basket depends on?

    Report each as "random slice" or "distinct type", with the number behind it. Where
    an exclusion is biased, the finding it touches carries that caveat in its headline,
    not in a footnote.

1.3 Determinism. Every number destined for the findings doc is computed twice and
    compared. Any non-deterministic aggregate over a group not proven unique is a defect,
    not a style choice — replace it with an explicit deterministic tiebreak. Add a lint
    check for this pattern; three separate incidents is a class, not a coincidence.

---

## Section 2 — D2, sale honesty

Two independent findings. The second does not depend on `old_price`'s value, only its
presence, so Loblaws' 9.2% event-level value loss doesn't touch it.

### 2A — Pre-sale price inflation

The question: when a retailer advertises a struck-out "regular" price, was that price
actually being charged beforehand?

`old_price` is the retailer's claim about the regular price. The `current_price` history
is what was actually charged. The gap between them is the finding.

2A.1 For each sale event with a usable `old_price` value and 14 days of continuous
     pre-window history, compare the claimed regular price against the observed price
     level in the pre-window. Define the comparison statistic explicitly and justify it
     — modal observed price, median, and last-observed-before-sale will disagree, and
     which one you pick is an argument, not a detail. Report sensitivity across at least
     two of them.

2A.2 Compare only within matching `price_basis`. An each-price and a per-weight price are
     not comparable without size. Multibuy compares on derived `unit_price` with
     `min_qty` stated.

2A.3 Report per vendor: the share of events where the claimed regular exceeds the
     observed pre-window level, the magnitude distribution, and n. State Loblaws'
     under-sampling (39,274 of 43,253 events usable) in the result, not beneath it.

2A.4 Consider and report the innocent explanations before concluding anything: a genuine
     price increase followed by a sale, a manufacturer list price, a product returning
     from a long absence. Quantify what fraction of flagged events each could account for.

### 2B — Sale frequency

2B.1 Per product, the share of observed days carrying a sale flag. Per vendor, the
     distribution.

2B.2 A product on sale most of the time does not have a sale price, it has a price.
     Report the share of products above thresholds (50%, 75%, 90% of days), per vendor,
     and the categories they concentrate in.

2B.3 This uses the flag only, so it is unaffected by the `was`-string loss. Say so.

---

## Section 3 — D4, basket comparison

Restricted to the reliable-tier UPC set: 5,222 GTINs at 2+ reliable vendors, 3,477 with
90+ shared days.

3.1 **The availability problem is the whole problem.** Vendors do not stock the same
    products on the same days, so summing a fixed basket per vendor compares different
    baskets and produces a meaningless number. Use pairwise comparison on the
    intersection of GTINs available at both vendors on that date, and report n for every
    comparison. If n varies materially across pairs, say so.

3.2 Match `price_basis` within every comparison. Exclude ambiguous prices per rule; report
    the count dropped per comparison.

3.3 The interesting question is not "which store is cheapest" but **whether the answer is
    stable**. Test whether any vendor is consistently cheaper across baskets, categories
    and dates, or whether it depends on what you buy. "It depends, and here is what it
    depends on" is a stronger and more honest result than a ranking, and it is the more
    likely one.

3.4 Report the basket's composition against the full catalogue, the way D1's 474 were
    characterized. 3,477 GTINs that survived a co-observation filter are not a random
    sample of groceries, and readers will assume they are unless told otherwise.

---

## Section 4 — D1, bounded secondary

D1 is **not a headline finding** and no result from it names a company's claim as
verified or refuted.

The reason, stated in the findings doc in a form someone can argue with: products with
stable listings are disproportionately products with stable prices, so measuring a price
freeze only on continuously-listed products asks whether prices held among the products
least likely to move. Worse, a product whose price changed during the window and then
left the catalogue is invisible, so the survivorship runs one direction and flatters the
retailer. This is a selection-versus-outcome problem and is not fixed by improving the
sample's composition.

4.1 If run at all, run it as "among continuously-listed products, X" with the survivorship
    direction stated in the same sentence. Report the 2025-26 composition check that was
    never done.

4.2 Do not publish a per-vendor freeze compliance rate. The data does not support it.

---

## Section 5 — Findings document

5.1 `docs/phase-2-findings.md`. Every number carries its build stamp. Every percentage
    carries its n. Every exclusion states its count and its bias verdict.

5.2 For each finding, a short "what would change this conclusion" section. What sample,
    what upstream fix, what additional snapshot would move it.

5.3 Update `docs/upstream-feedback.md` with anything new. Jacob is mid-rework; findings
    that arrive late arrive useless.

## Exit criteria

- The exclusion ledger and bias audit are complete and every exclusion has a verdict.
- 2A and 2B produce numbers with stated n, sensitivity, and innocent explanations
  quantified.
- D4 produces a pairwise comparison with availability handled explicitly and basket
  composition characterized.
- D1 is either bounded per Section 4 or dropped, with the reasoning written down.
- Every published number computed twice, identically.

## Non-goals

No dashboard. No writeup. No Airflow. No fuzzy cross-vendor matching.
