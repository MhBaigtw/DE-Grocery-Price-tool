# The hard part of comparing grocery prices isn't getting the prices

*How four measurement choices moved the answer more than the supermarkets did — and the one comparison that survived.*

<sub>71.8M price observations, 8 Canadian chains, Feb 2024 – 23 Aug 2026. In-store pickup, one Toronto neighbourhood. Data: [Project Hammer](https://projecthammer.org). Full provenance at the end.</sub>

---

## Which supermarket is cheaper?

It sounds like a data problem. Get the prices, put them side by side, add them up. The
prices exist — 71.8 million of them, published openly, updated daily.

I spent a long time on that question. **The prices were never the hard part.** What kept
changing the answer was my own choices about how to measure — and they changed it by more
than the supermarkets differed from each other.

---

## Four times a choice moved the answer more than the retailers did

### 1. How you define "on sale" scrambles which chain looks most promotional

There are two reasonable ways to tell whether a product is on sale. Either the retailer
publishes a struck-out "was" price, or its listing carries promotional text — `SALE`,
`Rollback`, `2 for $7`.

Rank all eight chains by how often their products are on sale, and the two definitions
barely agree at all:

| Chain | By struck-out price | Rank | By promotional text | Rank |
|---|---|---|---|---|
| Save-On-Foods | 32.4% | **1** | 8.6% | **5** |
| Metro | 29.0% | 2 | 0.0% | 7= |
| Voila | 19.1% | 3 | 19.4% | 2 |
| Loblaws | 17.8% | **4** | 24.1% | **1** |
| No Frills | 14.1% | 5 | 14.1% | 4 |
| Walmart | 12.2% | 6 | 17.1% | 3 |
| T&T | 6.2% | 7 | 0.9% | 6 |
| Galleria | 0.8% | 8 | 0.0% | 7= |

**Rank correlation between the two orderings: 0.196** — statistically indistinguishable
from no relationship. The chain that looks most promotional under one definition is fifth
under the other; the one that looks fourth is first.

The two mechanisms agree almost perfectly at some chains and barely at all at others. Where
a product has a struck-out price, promotional text confirms it on **99.5%** of rows at No
Frills — and **21.5%** at Save-On-Foods. At Metro the check is impossible: the promotional
text field is empty on all 6,003,385 of its rows.

So "which chain promotes most?" has no stable answer. **I withdrew that comparison rather
than pick a definition and publish the ranking it produced.** I am not showing the reversal
because one ordering is right — I am showing it because neither is.

*Not a claim about any retailer's behaviour. A claim about the word "sale".*
→ [`Q2d_flag_semantics.sql`](../analysis/phase2/Q2d_flag_semantics.sql) · [findings §2.7](phase-2-findings.md)

### 2. Which "before" price you pick moves apparent pre-sale inflation sixfold

When a retailer strikes out a regular price, was that price actually being charged?

To answer it you need "the price before the sale" — and that is not one number. Take the
same **228,608 sale events** and the same fortnight of prior prices:

| "The price before the sale" means… | Share of sales where the struck-out price is higher |
|---|---|
| the most commonly charged price | **21.3%** |
| the median price | 20.6% |
| the price the day before | 4.4% |
| **any** price actually charged in those 14 days | **3.4%** |

**Between 3.4% and 21.3%.** Same events, same data, sixfold range.

The bounds are built to fail in opposite directions and neither is "the truth". The low
bound clears a retailer that charged the higher price on even one of fourteen days. The
high bound flags a retailer that genuinely raised its price and then ran a sale — ordinary
retail, not deception.

And that turns out to be most of the gap: **at the five largest chains, 77% to 95% of
flagged sales are explained by the retailer having actually charged that price during the
window.** A price rise followed by a discount is not a fabricated "regular" price.

**I found no evidence that any retailer lies about its regular prices.** The honest
statement is the bracket, and the bracket is mostly ordinary repricing.

> **Where 228,608 comes from.** It is a deliberately narrow slice of the 575,036 sale
> events in the data. Requiring fourteen consecutive days of prior prices leaves 279,962;
> requiring the struck-out price to carry a usable *number* rather than just a flag leaves
> 275,779; restricting to the stronger of two product-identity methods leaves 275,240; and
> restricting to 2025–26 — because an earlier data gap makes 2024 unreliable for one chain
> — leaves **228,608**. A different figure, 279,596, appears in the detailed findings: that
> counts events with a usable *current* price and does not require the struck-out price to
> be a number at all. Narrower cohort, different question.

→ [`Q2a_presale_inflation.sql`](../analysis/phase2/Q2a_presale_inflation.sql) · [findings §2A, §2.6](phase-2-findings.md)

### 3. How you build the sample moves a price-freeze rate by up to 13 points

Metro publicly committed to a price freeze from 1 November to 5 February. Testing it means
picking which products count — and the obvious choice is products listed continuously
through the window.

That choice is not neutral. Compare the "share of products whose price never changed"
computed on continuously-listed products against all products in the window:

| Chain | Survivors only | All products | Gap |
|---|---|---|---|
| Walmart | 46.1% | 59.4% | **13.3 pts** |
| Metro | 20.8% | 30.0% | 9.3 pts |
| Galleria | 82.9% | 82.1% | −0.7 pts |

The gap swings from −0.7 to 13.3 points **and changes direction by chain**, so there is no
correction to apply. A number that moves that far on a sample-construction choice is not a
compliance rate.

**I publish no price-freeze compliance figure for Metro or anyone else, and this piece does
not say whether any chain honoured a freeze.** I could not measure it, so I did not.

*(A separate problem: "price never changed" isn't freeze compliance anyway. A price that
**fell** hasn't violated a freeze.)*

→ [`Q4_d1_bounded.sql`](../analysis/phase2/Q4_d1_bounded.sql) · [findings §4](phase-2-findings.md)

### 4. Matching products by barcode makes a quarter of the shelf invisible

To compare prices across chains you need the *same product* in both. The only reliable way
is the barcode.

**A store brand has one seller.** President's Choice is Loblaws'. Selection is Metro's.
Great Value is Walmart's. A store brand therefore has no barcode shared with a competitor,
so it can never appear in a barcode-matched comparison — not because of a data gap, but by
construction.

My matched basket covers **3,477 distinct barcodes, which is 8,448 product listings** —
each barcode is stocked by two to four chains, and each chain's listing counts once.
**Exactly one of those 8,448 listings is a store brand.** The catalogue contains 16,106
store-brand products.

How much that removes:

| Chain | Share of price-weighted shelf presence that is store brand |
|---|---|
| **Metro** | **30.6%** |
| Save-On-Foods | 28.8% |
| Pooled | **22.6%** |

*"Price-weighted shelf presence" means the sum of observed prices across listings. This
dataset records no quantities sold, so it is not spend and not market share — it is how much
of the observed shelf, weighted by price, sits in store brands.*

**So every barcode-matched grocery comparison — including mine — is blind to roughly a
quarter of the shelf, and it is the quarter where the chains compete hardest on price.**
Store brands are the retailer's own margin lever; that is the point of them.

This is not fixable with better matching or more data. The products genuinely do not exist
at two chains.

→ [`Q3b_basket_blindspot.sql`](../analysis/phase2/Q3b_basket_blindspot.sql) · [findings §3.5](phase-2-findings.md)

---

## What survived

One comparison came through every check I could think to run.

> **On identical national-brand products stocked by both stores on the same day, Walmart
> was cheaper than Metro on 100% of 711 observed dates, and cheaper than Save-On-Foods on
> 100% of 606.** Typical gaps: about 12.6% against Metro, about 17.9% against Save-On-Foods.
> Metro was cheaper than Save-On-Foods on 91.7% of dates, by about 5.3%.

The qualifier is part of the claim, not a footnote on it. *Identical national-brand
products. Stocked by both. Same day.*

It survived the things that broke everything else:

- **Not one date in 711 goes the other way.** Not an average that hides variation.
- **Holds in every category** — all eight, for both Walmart comparisons.
- **The three comparisons are consistent with each other.** Recomputed on only the products
  all three chains stocked on the same day, no figure moves more than 0.5%, and chaining
  Metro→Save-On-Foods→Walmart lands within **0.6%** of the direct Metro→Walmart measure.
  Comparisons built this way are not guaranteed to agree. These do.

### Why this is not "so none of it means anything"

That reading is available and it is wrong, so let me close it directly.

**A result that survives its own measurement choices is a different kind of object from one
that hasn't been tested.** The promotion ranking scrambled when I changed the definition of
a sale. The pre-sale figure moved sixfold when I changed the comparison price. The freeze
rate moved 13 points when I changed the sample. **The Walmart comparison did none of that**
— I varied the statistic, the basket, the dates and the categories, and it held.

The difference between those two kinds of result is the whole point, and it is only visible
if you go looking. **Most published grocery price comparisons never run that check at all**
— they pick one definition, compute one number, and publish it. A number produced that way
is not wrong on purpose; it is simply untested, and a reader has no way to tell it apart
from one that has been tried and held.

So the conclusion is not "nothing is knowable". It is narrower and more useful: **some
grocery price claims are robust and some are artefacts of how they were computed, and you
can only tell which is which by trying to break them.**

### And it still doesn't answer the shopper's question

The Walmart result is an aggregate. Shoppers buy specific products.

- For **about half** the individual products in the Walmart comparisons, neither chain is
  reliably cheaper across the days both stock it.
- Between Metro and Save-On-Foods that rises to **85%**.
- The advantage depends on price level. Walmart's edge is largest on cheap items (**17%**
  against Metro) and smallest on expensive ones (**8%**). Metro's edge over Save-On-Foods
  is **zero** on the cheapest third of the basket and 9.7% on the dearest.

**The aggregate answer and the shopper's answer disagree, and both are correct.** "Walmart
is cheaper on national brands" is true of the basket and unreliable for the specific thing
in your hand. And since the comparison excludes store brands entirely, it is silent on
roughly a quarter of what is actually on the shelf.

→ [`Q3c_pairwise_stability.sql`](../analysis/phase2/Q3c_pairwise_stability.sql) · [findings §3.8](phase-2-findings.md)

---

## One more thing the data said, which I did not expect

Galleria — a Korean grocery chain — barely overlaps the others. Only **11.1%** of its
barcoded products are carried by any other chain whose barcodes I could trust, against
41.7% to 54.0% for the rest.

I assumed I had a matching bug and went looking for it. There isn't one. Of the four chains
whose barcodes come straight from the retailer rather than being guessed by text-matching,
**Galleria has the second-best barcode coverage** — better than Metro's. Its catalogue is
simply different, which for a specialist grocer is exactly what you would expect.

**A "which supermarket is cheapest" comparison cannot include it in any meaningful way** —
and that is a fact about Canadian grocery retail, not a defect in the data.

→ [`Q3b_basket_blindspot.sql`](../analysis/phase2/Q3b_basket_blindspot.sql) · [findings §3.7](phase-2-findings.md)

---

## What would have to change to answer the question properly

- **A product identity that isn't the barcode.** Comparing a store brand against a national
  brand means matching on what a product *is* — size, category, contents — not on a code
  that store brands cannot share. That is a different and harder problem, with its own
  accuracy question, and I did not attempt it.
- **A shared definition of "on sale."** Until the field means the same thing at every
  chain, cross-retailer promotion comparisons are not defined. One published sentence from
  each retailer would fix it.
- **Quantities.** Every "share of the shelf" figure here is weighted by price because the
  data has no units sold. Without those, no honest basket weighting is possible.
- **Wider geography.** One Toronto neighbourhood, pickup prices.

---

## Where these numbers come from

Every figure traces to a committed query:

| Claim | Query |
|---|---|
| Sale-definition scramble | [`Q2d_flag_semantics.sql`](../analysis/phase2/Q2d_flag_semantics.sql) |
| 3.4%–21.3% bracket | [`Q2a_presale_inflation.sql`](../analysis/phase2/Q2a_presale_inflation.sql) |
| Freeze-rate sensitivity | [`Q4_d1_bounded.sql`](../analysis/phase2/Q4_d1_bounded.sql) |
| Store-brand blind spot, Galleria | [`Q3b_basket_blindspot.sql`](../analysis/phase2/Q3b_basket_blindspot.sql) |
| Walmart comparison, stability, consistency | [`Q3c_pairwise_stability.sql`](../analysis/phase2/Q3c_pairwise_stability.sql) |
| What was excluded and whether it was biased | [`Q1_exclusion_ledger.sql`](../analysis/phase2/Q1_exclusion_ledger.sql), [`Q1b_bias_controls.sql`](../analysis/phase2/Q1b_bias_controls.sql) |

Full results, with every denominator and every withdrawal:
**[docs/phase-2-findings.md](phase-2-findings.md)**.

**How I know the numbers are trustworthy — and the mistakes I caught in my own work:**
**[docs/method-note.md](method-note.md)**. It is short, and it is the part I would read
first if someone else had written this.

---

## Data, scope and licence

**The data.** The [Project Hammer](https://projecthammer.org) public dataset: 71.8 million
price observations from eight Canadian grocery chains, February 2024 to 23 August 2026.
**The underlying data was sourced from ProjectHammer.org.**

**The scope.** These are *in-store pickup prices for one neighbourhood in Toronto*. Nothing
here is a national, provincial or "Canadian" price. The comparison basket also excludes the
expensive end of the catalogue — its 95th-percentile price is $13.99 against $20.04 for the
catalogue as a whole — so it describes ordinary mid-market groceries and nothing above that.

**The vintage.** My newest snapshot is 23 August 2026. The dataset's maintainer is actively
fixing several of the defects described here, so parts of this piece describe a moment in
time rather than a permanent state. Anything he fixed after that date is invisible to me.

**The licence.** The analysis code and documentation are MIT licensed. The dataset is not
mine, is not redistributed in this repository, and carries its own attribution requirement,
which is the line above.
