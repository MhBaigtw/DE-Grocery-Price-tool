# Phase 3 §1 — The argument

**Status: draft for review. Nothing else in Phase 3 starts until this is agreed.**

Source of every figure: `docs/phase-2-findings.md`, consolidated record. Build
`2026-08-28T17:48:35Z`, snapshot `20260822T134045Z`, data through 2026-08-23.

---

## The thesis paragraph

> Ask which supermarket is cheaper and you assume the hard part is getting the prices.
> It is not. Across four independent attempts to measure Canadian grocery prices from a
> public dataset of 71.8 million observations, **the answer moved more when we changed a
> defensible methodological choice than it did between retailers.** How you define a
> "sale" reverses the ranking of which chain promotes most — Save-On-Foods is first by one
> definition and fifth by another, so we withdrew that comparison rather than pick.
> Which statistic you use for "the price before the sale" moves apparent pre-sale
> inflation across a sixfold range, from 3.4% to 21.3% of events, and most of that gap is
> retailers genuinely raising a price and then discounting it. How you build the sample
> moves a price-freeze compliance rate by up to 13 points, in a direction that changes by
> retailer, which is why we publish no such rate. And matching products by barcode — the
> only way to compare identical goods across chains — is structurally blind to store
> brands, because a store brand has one seller and therefore no shared barcode. That blind
> spot is 22.6% of price-weighted shelf presence, 30.6% at Metro, and it is precisely where
> the chains compete hardest. **One comparison survived every check we could think to run:
> on identical national-brand products stocked by both stores on the same day, Walmart was
> cheaper than Metro on 100% of 711 observed dates and cheaper than Save-On-Foods on 100%
> of 606.** It is stable, transitive, and it does not answer the question people ask —
> because for roughly half the individual products in that comparison, and 85% of those
> between Metro and Save-On-Foods, neither store is reliably cheaper. The aggregate answer
> and the shopper's answer disagree, and both are correct. That gap, not the price data, is
> the thing worth understanding.

---

## Why this instead of the brief's shape

The brief's sketch and this draft agree on the material and on the tone. I am proposing a
different **load-bearing claim**, and one factual correction that the sketch would have
carried into print.

### The correction, first

> The sketch says: *"Walmart is cheaper on identical national-brand products on 100% of
> observed dates, while 85% of individual products have no consistent cheaper vendor."*

**Those two figures are from different comparisons and should not be joined.** The 84.61%
is **Metro vs Save-On-Foods**. On the two Walmart pairs the mixed share is **50.96%** and
**49.55%** — and 795 of 1,664 Metro/Walmart GTINs *do* have Walmart consistently cheaper on
90%+ of days. Attaching "85%" to the Walmart claim overstates the incoherence of the one
result that survived, in a piece whose credibility rests on not overstating.

The draft above says "roughly half the individual products in that comparison, and 85% of
those between Metro and Save-On-Foods". Same point, correctly attributed.

### The argument

The sketch's claim is *"transparency is harder than it looks, and the gap is not where
people assume."* That is true and it is a mood. It does not say where the gap **is**, so
the four negative results arrive as a list of difficulties rather than as evidence for
anything.

The evidence supports something sharper: **the measurement choices dominated the
retailers.** That is not a framing I imposed on the results — it is the one thing all four
withdrawals have in common, and each was discovered independently while trying to do
something else:

| Choice | Range it moved the answer | Where |
|---|---|---|
| Definition of "on sale" | Ranking **reverses**: Save-On-Foods 1st of 8 under `old_price` presence, 5th under promotional text; Loblaws 4th and 1st | W1, §2.7 |
| Comparison statistic for the pre-sale price | **6.3×** — 3.39% to 21.27% of the same 228,608 events | R1, §2.6 |
| Sample construction (survivors vs all) | Up to **13.3 pp**, direction varying by retailer | W4, §4.2 |
| Product-matching method | Excludes **22.64%** of price-weighted shelf presence entirely | R3, §3.5 |

Against those, the largest *retailer* effect we measured is Walmart's ~17.9% price
advantage over Save-On-Foods on national brands. **Three of the four methodological
choices move the answer by more than that**, and the fourth removes a quarter of the shelf
from view. That is the finding, and I do not think a grocery-price piece usually makes it.

It also earns the constructive half rather than asserting it. If choices dominate, then a
result that is **invariant** to those choices is worth something — and R3 is: stable across
100% of dates, across 7–8 of 8 categories, transitive to within 0.59% when recomputed on a
common basket. The piece can say "here is the one number that survived, and here is exactly
how narrow it is", which is stronger than "we looked at grocery prices and it was hard".

### What I am not claiming

- **Not that the data is bad.** It is unusually good and the maintainer is actively
  improving it. The choices are ours, not defects in his dataset.
- **Not that measurement is futile.** One comparison survived; the piece ends on it.
- **Not that retailers are dishonest.** Constraint 1.3. The pre-sale result is a bracket
  whose gap is mostly explained by ordinary repricing, and the paragraph says so.

---

## What this commits the piece to

1. **R1 appears only as a bracket** — "3.4% to 21.3%" — with the reason the bounds are
   built to err in opposite directions. Never a point. *(Constraint 1.2.)*
2. **Every headline claim carries its qualifier in the sentence.** The draft does this:
   *"on identical national-brand products stocked by both stores on the same day"* is
   inside the Walmart claim, not after it. *(Constraint 1.1.)*
3. **All four withdrawals appear in the argument itself**, as the evidence for the thesis
   rather than as an appendix of failures. *(Constraint 1.4.)* W5 is a Phase 1 carry-forward
   and belongs in the piece's method note, not the thesis.
4. **"Price-weighted shelf presence" never becomes "market share" or "spend."** The dataset
   has no quantities sold. The paragraph uses "shelf presence"; the piece must define it
   once, plainly, at first use.
5. **The data vintage is stated where a reader sees it** — data through 2026-08-23, and
   several findings describe defects the maintainer may already have fixed. *(2.5.)*

## What would make me withdraw this thesis

- **If the "choices dominate" framing cannot be made concrete in three sentences** for a
  general reader, it is too abstract to lead with and the brief's shape is safer. The
  four-row table above is the test: if the piece needs more than that to land the claim,
  fall back.
- **If a reader's honest summary is "so none of it means anything."** That is a
  misreading the thesis invites and the piece must actively close it. The Walmart result is
  the closer, and if it cannot carry that weight the argument is wrong.

## One thing the thesis deliberately omits

The most interesting *methodological* result in Phase 2 — that two runs of the same query
crashing identically pass a byte-comparison, or that a vendor-controlled comparison
overturned a pooled one three separate times — is not in the paragraph. It is a story about
doing analysis, not about grocery prices, and it belongs in the piece's method section if
anywhere. **Leading with it would make the piece about us.**
