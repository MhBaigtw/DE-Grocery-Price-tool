# Project Hammer — ergonomics feedback from a downstream consumer

**From:** a downstream analysis project consuming the published dataset.
**Last updated:** 2026-09-08. Items 1–9 were written 2026-08-22; items 10–11 are new.

**Based on two snapshots:**

| | Snapshot 1 | Snapshot 2 |
|---|---|---|
| id | `20260822T134045Z` | `20260824T132829Z` |
| downloaded | 2026-08-22 | 2026-08-24 |
| covers | 2024-02-28 → 2026-08-21 | 2024-02-28 → 2026-08-23 |
| `raw` rows | 71,809,333 | 72,022,652 |
| `product` rows | 187,028 | 187,070 |
| sha256 (SQLite) | `2da260be76b3e441…` | `5307d80f30d250f5…` |

The underlying data was sourced from ProjectHammer.org.

This is **not a wishlist**. Every item below is friction we actually hit while auditing
the data, with the cost it imposed and the smallest change that would remove it. Items
are ranked by impact on a downstream consumer. Correctness bugs are reported separately
in our findings document; this list is specifically about *ergonomics* — things that are
not wrong, but are expensive to consume.

Where we disagree with our own suggestion, we say so.

---

## 1. Make `current_price` a scalar, and move multibuy offers to their own column

**Friction.** `current_price` is not always a price. It also carries multibuy offers
(`2/$7.00`) and per-weight rates (`1.99/100g`), plus some rows with raw HTML and embedded
newlines. **1,303,020 rows (1.81%) do not parse as a number.**

| Shape | Rows |
|---|---|
| Multibuy `N/$X.XX` | 679,923 |
| Per-weight `X.XX/100g` | 360,365 |
| **Cents-form `NNN$`** (e.g. `329$` for $3.29) | **~48,000** |
| Other (embedded newlines) | remainder of 262,732 |

**A fourth shape, isolated after a second snapshot.** `current_price` sometimes holds the
price in **cents with a trailing dollar sign** — `329$` for $3.29, `1400$` for $14.00.
It is **Loblaws only** (zero rows at every other vendor), affects `old_price` too (6,488
rows), and has run continuously since **2025-10-22** at a steady ~175 rows/day — so it
survived at least one post-processing rework. Snapshot-to-snapshot it is stable, not
spreading: 47,992 rows on 2026-08-22, 48,342 on 2026-08-24, the growth being only the two
new dates.

It is recoverable by dividing by 100, and we will parse it. We mention it because a
consumer who does *not* notice gets a silent 100× error rather than a missing value, which
is worse than the multibuy case — `329$` looks like a plausible price for a case of wine.

Concentration is the problem, not the headline percentage:

| Vendor | Non-scalar rows | % of that vendor's rows |
|---|---|---|
| Metro | 623,001 | **7.59%** |
| Save-On-Foods | 458,511 | **6.46%** |
| T&T | 77,351 | 1.43% |

**What it cost us.** This is the single most dangerous thing we found, because it fails
*silently and asymmetrically*. `CAST(current_price AS DOUBLE)` returns NULL — no error,
no warning — so a naive pipeline quietly drops 7.6% of Metro and 6.5% of Save-On-Foods.
Those are two of the three vendors whose UPCs come directly from the vendor, i.e. exactly
the ones any trustworthy cross-vendor comparison depends on. A consumer would silently
lose their best data and never know.

The obvious workaround is worse than the bug: stripping `2/$7.00` to `7.00` yields
**double** the true unit price of $3.50, producing numbers that are wrong by 2× while
looking entirely plausible.

**Smallest fix.** Keep `current_price` strictly numeric (the per-unit price, `3.50` in
the example) and add two nullable columns: `offer_qty` (`2`) and `offer_total` (`7.00`).
Anyone who does not care about multibuy ignores them and is still correct; anyone who
does gets the offer without parsing strings.

If that is too invasive, the cheap version is a single `price_is_scalar` boolean, or even
just a documented note that this happens and how often. Silence is the costly part.

---

## 2. Fix the Walmart field misalignment: product name is landing in `units`, price text in `brand`

**Friction.** Three distinct problems in one field:

- **`units` is literally the string `error`** for **409 products** across Walmart,
  No Frills, Voila and Loblaws. An error token was written into a data field.
- **Walmart's `units` frequently contains the product name, not the size.** We first
  read this as stray marketing copy, but `concatted` — whose format is
  `vendor~product_name@units^brand` — shows it is **field misalignment in the Walmart
  extractor**: the units slot holds a verbatim copy of the product name, and the brand
  slot sometimes holds price text with embedded newlines. For example:
  `Walmart~SkinnyPop Skinnypack Gluten Free Popcorn@SkinnyPop Skinnypack Gluten Free Popcorn^$5.57
current price $5.57
$5.16/100g`.
  This single cause explains both the 51.38% unit parse rate and part of the 32.48%
  blank-brand rate.
- **257 products contain a non-breaking space (U+00A0)** inside `units` (Metro 235,
  Walmart 22).

**What it cost us.** A deliberately simple unit parser reaches 99%+ on five vendors but
only **51.38% on Walmart** — and the gap is almost entirely marketing copy, not parser
weakness. Our parse rate across all vendors is 88.12% of products that have a units
string; Walmart alone accounts for most of the shortfall.

The non-breaking space deserves special mention because it is genuinely nasty: it is
visually identical to a space, and `\s` in most regex engines does **not** match it. So
`2<nbsp>l` silently fails to parse while `2 l` succeeds, with no visible difference in any
console or spreadsheet. We only found it by hex-dumping values that "obviously should have
parsed."

**Smallest fix.** Three cheap, independent wins: (a) write NULL instead of `error`;
(b) `.replace(' ', ' ')` on extraction; (c) for Walmart, treat the size field as
absent rather than filling it with the nearest available attribute string. (c) is the
biggest win and probably the most work; (a) and (b) are close to free.

---

## 3. Your documentation says `product.id` changes daily. In this snapshot it never does.

**This is a documentation defect, and we are listing it separately from the feature
request in §4 because the two need different fixes: §4 is "please add a guarantee", this
is "please correct a statement that is currently false."**

**Friction.** The column documentation states, for both `product.id` and
`raw.product_id`:

> *"This ID changes every day and is not a stable unique identifier!"*

We measured the opposite, on every axis we could test:

| Test | Result |
|---|---|
| `(vendor, sku)` series observed on 30+ days carrying exactly one `product_id` | **100%**, all 8 vendors |
| Sample of 20 products observed 441–756 days each | **1 distinct id each** |
| `product.id` = `vendor \|\| sku` for products with a non-blank sku | **161,300 of 161,300** |
| Blank-sku series (hashed ids) carrying one id | **100%** (7,339 series) |
| Distinct `(vendor, sku)` keys vs `product` rows | 161,300 vs 161,300 — **zero collisions** |

The id is not opaque and it is not rotating: it is a deterministic concatenation of two
columns you already publish. Where sku extraction failed, it falls back to a hash of
`concatted` — and those are stable too. Both shapes are present across the entire date
range, so this is a fallback rule, not a scheme that changed at some point.

**What it cost us.** This was the single most expensive item in our audit — not to
compute, but to *believe*. Disproving a documented guarantee is much more work than
verifying one: we had to test id stability three separate ways, then work out the
underlying composition rule to explain *why* it was stable, before we could trust the
result enough to act on it. Meanwhile we had already designed our product-identity layer
defensively around an instability that does not exist.

We still cannot fully close it, and this is the part only you can answer: **we have one
snapshot.** We can prove ids are stable *within* a published file. We cannot prove they
are stable *across* publications, because that requires two files and we have one. That
is precisely the guarantee the documentation is talking about, and precisely the one we
cannot test from outside.

**Why this is worse than a harmless stale note.** A consumer who reads the warning does
defensive work they did not need. A consumer who *checks* the data sees ids that are
obviously stable, concludes the warning is stale, and starts depending on them — which
may be wrong in exactly the way the warning intended to prevent. **The documentation being
wrong in the safe direction still produces unsafe behaviour**, because it trains people to
disregard it.

And it is about to matter much more: you have announced that `raw.product_id` becomes a
number. Consumers who quietly started trusting the visibly-stable id will break, and the
warning that should have protected them is the one they learned to ignore.

**Smallest fix.** One of these two sentences, whichever is true:

- *"`product.id` is `vendor||sku` where a SKU could be extracted, and is stable across
  publications."* — or —
- *"`product.id` is stable within a published file but is not guaranteed stable between
  publications."*

Either resolves it. The current text is the only option that is actively misleading.

---

## 4. Ship an explicit `product_key` column

**This is the feature request that follows from §3.** §3 asks you to correct a false
statement; this asks for something that does not exist yet. They are separable — you could
do §3 alone and we would be most of the way there.

**Friction.** Even granting everything in §3, downstream consumers currently have to
*derive* product identity by concatenating `vendor` and `sku` themselves, and to handle
the blank-sku fallback themselves. Everyone doing this independently will do it slightly
differently — different case handling, different treatment of the 25,728 blank-sku rows
(13.8% of the catalogue), different decisions about whether `Loblaws20064552_EA` and
`Loblaws 20064552_EA` are the same thing.

**What it cost us.** Less than §3 — the derivation is easy once you know the rule. The
cost is not difficulty, it is *divergence*: two analyses of your dataset that reach
different numbers because they keyed products differently are worse for the project's
credibility than either being slightly wrong on its own.

**Smallest fix.** One column on `product`, populated for every row, stable across
publications, with a documented definition. `vendor||sku` where a SKU exists and the
existing `concatted` hash otherwise would do — that is what `id` already is today, so this
may be closer to a rename plus a guarantee than to new work.

**This matters more now, not less.** With `raw.product_id` becoming a number, a separate
and explicitly-guaranteed key is what lets that change be a non-event for consumers
instead of a breaking one. Our own identity layer is derived and owned on our side
precisely so that an upstream id type change stays an ingest-layer detail — but we should
not have to have made that call blind.

**Where we disagree with ourselves:** if you only ever do one of §3 or §4, do §3. A
correct sentence about what exists beats a new column with the old warning still attached.

---

## 5. Fix or document the ~878K price rows that join to nothing

**Friction.** 878,559 `raw` rows (**1.22%**) have a `product_id` with no matching
`product.id`. They are prices with no vendor, no name, no sku, no UPC.

| Apparent vendor (from the id prefix) | Unjoined rows | Distinct ids | Days affected |
|---|---|---|---|
| Metro | **637,508** | 6,906 | 884 of 887 |
| Walmart | 56,125 | 1,742 | 795 |
| Galleria | 46,254 | 145 | 881 |
| Loblaws | 43,270 | 302 | 731 |
| No Frills | 32,413 | 222 | 732 |
| T&T | 23,726 | 217 | 778 |
| Voila | 21,120 | 102 | 832 |
| Save-On-Foods | 18,064 | 966 | 671 |

**What it cost us.** Every join in our audit needed an explicit accounting of what it
dropped and why, and every percentage needed a stated denominator, because "the number of
price rows" and "the number of price rows we can attribute to a vendor" differ by 1.22%.
Metro losing 637K rows across 884 of 887 days is a persistent structural gap, not an
occasional glitch.

**We have since diagnosed the cause, and it is more specific than "missing rows".**
Three quarters of it is a **`product_id` scheme migration that was applied to the
catalogue but not retroactively to history.**

Metro's current `product.id` values are opaque base64 (`YRnfY16EEimWdPCI1S5mVw==`). The
orphaned rows carry two earlier forms:

| Generation | Example | Distinct ids | Orphan rows | Share |
|---|---|---|---|---|
| `vendor~name@units^brand` | `Metro~Old Cheddar Cheese Slices@200 g^Cracker Barrel` | 8,604 | **670,189** | **76.3%** |
| `vendor` + `sku` | `Metro062020000064` | 1,992 | 208,293 | 23.7% |
| malformed URL slugs | `Loblawshoney-bunches-of-oat-honey-roasted-cere` | 21 | 67 | 0.01% |

The fingerprint is unmistakable: **8.41% of rows before 2024-10-01 are orphaned, against
0.357% after** — a 24× step at the boundary your documentation already flags as the
Sept 30 2024 change.

**These are not junk rows.** 878,554 of 878,559 parse to a price, the median is $5.89,
and the multibuy median is $3.50. They are ordinary grocery prices whose catalogue entry
is no longer reachable.

**And they are not recoverable downstream.** We tried both obvious routes, because the id
forms are so legible: splitting `vendor||sku` and matching `(vendor, sku)` against
`product`, and matching the `vendor~name@units^brand` id against `product.concatted`.
**Both return exactly zero matches.** The skus and concatted strings are not in the
current catalogue under any key.

**Smallest fix, in the order we would value it:**

1. **Publish a mapping from retired `product_id` values to current ones.** One two-column
   table would erase 74% of this problem permanently, for us and for every other consumer.
   This is by far the highest-value item in this document per unit of your effort.
2. **Or document that `raw` is not referentially complete**, so consumers use a LEFT JOIN
   with an explicit orphan count rather than an INNER JOIN that silently shrinks their
   data. Cheap, and it converts a silent 1.22% loss into a visible one.
3. **Separately**, the 21 truncated URL-slug ids (mostly Loblaws, 2026-02-01) look like a
   field-truncation bug in that day's extract, unrelated to the migration.

**One note in your favour:** because `product` holds only the currently-listed catalogue,
some of this is unavoidable — a delisted product's price history has to point somewhere.
The 0.357% background rate after 2024-10-01 is that, and it seems reasonable. The 8.41%
before it is the migration, and that part is fixable.

---

## 6. The documented small-basket end date is a month off

**Friction.** The docs say the small-basket period ran **Feb 28 – Jul 10/11 2024**. The
data says the regime change is **2024-06-10/11**:

| Date | Rows, all vendors | × previous day |
|---|---|---|
| 2024-06-09 | 1,226 | 1.02 |
| **2024-06-10** | **8,703** | **7.10** |
| **2024-06-11** | **87,735** | **10.08** |
| 2024-07-10 | 51,680 | 0.87 |
| 2024-07-11 | 44,161 | 0.85 |

July 10/11 shows a mild dip, not a transition.

**What it cost us.** We nearly discarded a month of perfectly good full-catalogue data.
Anyone computing a product-count or breadth metric and trusting the documented date will
either wrongly exclude 2024-06-11 → 2024-07-10, or wrongly treat it as small-basket.

**Smallest fix.** Change the date in the docs to 2024-06-10/11.

---

## 7. Normalise UPCs to a fixed width, or say that they are not normalised

**Friction.** UPC values appear at 4, 5, 6, 8, 10, 11, 12, 13 and 14 digits. The 11-digit
values (14,901 products) are almost always UPC-A with the leading zero stripped, so
joining on the raw string splits products that are genuinely the same.

**What it cost us.** Normalising to GTIN-14 (strip non-digits, left-pad to 14) **rescued
5,050 GTINs** that a raw-string join would have split. That is a large correction to the
number our project depends on most, and a consumer who did not think to check would
simply have had a quietly smaller, quietly wrong answer.

A second, subtler trap: the 4–5 digit values are **not junk** — they are PLU produce codes
(`4312` Eddoes, `40174` Granny Smith Apples, `46640` Tomato On The Vine), and PLU is a
real cross-vendor standard. A consumer who filters "short UPCs" as garbage silently
discards fresh-produce matching; one who leaves them in gets valid produce matches mixed
into a packaged-goods identifier space. Both are defensible; neither is signposted.

**Smallest fix.** Either store UPCs zero-padded to 14 digits, or add one line to the docs:
"UPC values are stored as extracted and are not width-normalised; 4–5 digit values are PLU
produce codes, not UPCs." The documentation fix alone removes most of the risk.

---

## 8. Duplicate rows have roughly doubled, and increasingly disagree on price

**Friction.** The docs estimate ~6,500 affected products/day as of Nov 2024. We confirm
that almost exactly — **6,529** — and find it has since roughly doubled.

| Month | Mean duplicated products/day | Duplicates with *conflicting* price |
|---|---|---|
| 2024-11 | 6,529 | 619 |
| 2025-11 | 13,014 | 4,827 |
| 2026-07 | **14,189** | **9,025** |

Worst single case: one Metro product appearing **1,062 times in one day**.

**What it cost us.** The count itself is manageable and well documented — the growth in
*conflicting-price* duplicates is the real cost. Those cannot be resolved with `DISTINCT`,
because the duplicate rows disagree about the price, so every consumer must invent their
own tie-break rule. Different consumers will invent different rules and get different
answers from the same file.

**Smallest fix.** In preference order: (1) deduplicate before publishing; (2) add a
`listing_context` column (category / advertised slot) so duplicates are explainable rather
than mysterious; (3) failing both, publish the recommended tie-break rule so that
consumers at least converge on the same wrong-or-right answer.

**Where we disagree with ourselves:** option (1) is not obviously correct. The duplicates
carry real information — that a product was listed in several places, sometimes at
different prices — and collapsing them upstream destroys that. We would rather have (2)
than (1), even though (1) is less work for you.

---

## 9. Smaller items, batched

These are each cheap and none is individually urgent.

| Item | Evidence | Suggested fix |
|---|---|---|
| `nowtime` is a string, not a date | All 71.8M rows; also 8 rows with a NULL `nowtime` carrying a real price | Store as DATE; drop or fix the 8 dateless rows |
| `hammer-lastupdated.txt` is human-formatted | `2026-08-21 21:26:00.11 (Eastern Time)` needs custom parsing and has an ambiguous DST offset | Publish ISO 8601 with an explicit offset, e.g. `2026-08-21T21:26:00.11-04:00` |
| `price_per_unit` has non-unit denominators | `100356g` (17,293 rows), plus `100kg`, `100lb.`, `100l`, `100lt`, `100ea`, `100un.` | Validate the denominator against a small allow-list at extraction |
| `old_price` sometimes ≤ `current_price` | Galleria 1,372 rows (2.52% of its old_prices) | Only populate `old_price` when it exceeds `current_price` |
| Sale signalling is inconsistent across vendors | Metro, Save-On-Foods, T&T and Galleria never write a sale word into `other`; Loblaws has 730,582 sale rows (22.72%) with no `old_price` because they are multibuy | A normalised `on_sale` boolean would let consumers stop reverse-engineering eight different conventions |
| No published schema or changelog | We built our own expected-schema file and a check to detect the announced `product_id` type change | A tiny `schema.json` next to the download, bumped when the shape changes |

---

---

## Status as of our latest snapshot — please ignore anything you have already fixed

You mentioned you are working through post-processing changes, so this section says
**what we can and cannot see**, to save you re-reading items that are already done.

**Our newest data is the 2026-08-23 extract, downloaded 2026-08-24. As of today
(2026-09-08) that is 16 days old.** Anything fixed in the last two weeks is invisible to
us, and this table should be read as "still present as of 2026-08-23", never as "still
broken today".

| Item | Verified against the 2026-08-23 extract | Status |
|---|---|---|
| **1** — non-scalar `current_price` | cents-form 48,342 rows; `Now$NNN` 12,476; multibuy 680,161 | **still present** |
| **2** — Walmart field misalignment | 7,057 Walmart products (18.61%) have the product name in `concatted`'s units slot; unit parse rate 51.42% | **still present**, marginally wider than the 6,898 / 18.19% we first reported |
| **3** — `product.id` documentation | documentation, not data — we cannot verify from a snapshot | unknown |
| **4** — explicit `product_key` | no such column present | not present |
| **5** — orphan `raw` rows | 880,787 rows still join to nothing | **still present** |
| **6** — small-basket end date | documentation — cannot verify from a snapshot | unknown |
| **7** — UPC width | unchanged | **still present** |
| **8** — duplicate rows | unchanged | **still present** |
| **E12** — `old_price` holding the literal string `was` | 870,720 rows | **still present** |

**None of this is a complaint about pace.** It is a status list so you can skip what is
done. If you tell us an item is fixed we will pull a fresh snapshot and confirm rather
than asking you again.

---

## 10. Galleria's catalogue barely overlaps the other vendors' — worth documenting

**Not a defect. A property of the data that a consumer will misread as one.**

Anyone building a cross-vendor comparison will reasonably assume the eight vendors are
broadly comparable catalogues with different prices. For Galleria that is not true, and
the gap is large enough to change what an analysis can do.

| Vendor | Products | **% with a usable GTIN** | GTINs carried | **% of those GTINs carried by ≥1 other reliable-tier vendor** |
|---|---|---|---|---|
| Save-On-Foods | 16,158 | 95.20% | 15,382 | **46.63%** |
| **Galleria** | 10,697 | **86.23%** | 9,201 | **11.13%** |
| Metro | 26,311 | 73.78% | 19,413 | **41.69%** |
| Walmart | 37,914 | 28.86% | 10,932 | **54.00%** |

**Galleria has the second-best barcode coverage of the four vendors whose UPCs come
directly from the vendor — better than Metro's — and yet nine in ten of its barcoded
products are carried by none of the others.** The next lowest overlap is 41.69%, so this
is a four-fold gap and not a gradient.

**Why this matters to a consumer.** We spent real time checking whether we had a matching
bug, because 11% looked like a pipeline failure. It is not: Galleria is a Korean grocery
banner and a substantially distinct product range is exactly what one should expect. The
data is right and our expectation was wrong.

**Smallest fix: one sentence in the documentation** — something like *"vendors differ
substantially in catalogue composition; Galleria in particular carries a largely distinct
product range, so cross-vendor matches involving it will be sparse."* That would have
saved us the investigation, and it will save it for everyone after us.

**We are not asking you to change any data here.** This is the cheapest item in this
document and it is purely documentation.

---

## 11. Document that UPC matching is structurally blind to private label

**Also not a defect — a limit of the UPC fields that every consumer will rediscover
independently.**

A cross-vendor basket built on UPC/GTIN can only contain products carrying the same
barcode at two or more vendors. Private label cannot: President's Choice is Loblaws',
Selection is Metro's, Great Value is Walmart's. A store brand has one seller by
definition, so it has no cross-vendor barcode, so it can never appear in such a basket.

We built the reliable-tier basket (GTINs at 2+ vendors whose UPCs come from the vendor
directly) and measured what it contains:

| Measure | Value |
|---|---|
| Products in the basket | 8,448 |
| **Private-label products in the basket** | **1** |
| Private-label products in the catalogue | 16,106 |

And the size of what that removes, at the vendors involved:

| Vendor | % of price rows that are private label | **% of price-weighted shelf exposure** |
|---|---|---|
| **Metro** | 19.01% | **30.60%** |
| Save-On-Foods | 22.76% | 28.78% |
| Walmart | 1.63% | 1.42% |
| **Pooled** | **15.05%** | **22.64%** |

*("Price-weighted exposure" is the sum of observed unit prices across price rows. It is
deliberately not called spend — the dataset carries no quantities sold, and we are not
going to imply one.)*

**So any UPC-matched cross-vendor price comparison built on this dataset is blind to
roughly 22.6% of price-weighted shelf exposure, and about 30% at Metro** — and it is blind
to exactly the segment where banner-versus-banner price competition is sharpest.

This is not a criticism of the UPC fields, which are doing their job. It is a limit that
is invisible until you measure it, and every consumer who builds a basket will hit it.

**Smallest fix: a line in the documentation** noting that UPC-based cross-vendor matching
excludes private label by construction, so comparisons built on it are national-brand
comparisons.

**Where we would push back on ourselves:** the obvious remedy — matching on product
description instead of barcode — is one we considered and rejected for our own use, because
it has an accuracy problem we could not bound. We are not asking you to build it. We are
asking for the sentence that stops the next consumer assuming their basket is
representative.

## 12. The Save-On-Foods location: the methodology page and the data disagree

*Added 2026-09-12.*

**The methodology page says:** *"Prices are gathered daily and cover the North York area of
Toronto, except for Save on Foods (that one is a location in Calgary)."*

**What the data shows.** Save-On-Foods product URLs carry a store id (`/rsid/NNNN/`), so the
location can be read from the data itself. Across the whole history:

| Store id | URL path | Products | First seen | Last seen | Store |
|---|---|---|---|---|---|
| **2210** | `/sm/pickup/` | **15,766 (97%)** | 2024-09-28 | 2026-09-10 | Westsyde, Kamloops, BC |
| 6634 | `/sm/pickup/` | 2 | 2024-09-28 | 2024-11-13 | Heritage, Calgary, AB |
| 1982 | `/sm/planning/` | 451 | 2024-09-28 | 2026-09-10 | Not identified by us |

**We do not think the page is simply wrong.** The evidence fits a changed configuration
better: a Calgary store (6634) does appear, early, and stops in November 2024, while the
Kamloops store carries almost everything since. A pickup store that was changed once, with
the page written before or around the change, would produce exactly this pattern. You will
know which it was; we cannot tell from the outside.

Store 1982 we could not place. Its 451 products are all distinct from store 2210's, sit under
`/sm/planning/` rather than `/sm/pickup/`, and are mostly bakery, confectionery and seasonal
items. It was in use alongside 2210 for the whole period.

**Why it matters to a consumer.** We read the page, took "North York" as the scope for every
chain but did not register the Save-On-Foods exception, and compared Save-On-Foods with
Toronto chains as if they were in the same area. That mistake is ours, not yours — but a
consumer who reads the page carefully would still conclude Calgary, and a Calgary/Kamloops
difference matters to anyone comparing regions.

**Smallest fix:** update that sentence to name the store actually configured, or say that
the Save-On-Foods location has changed over time. If store 1982 is intentional, a line on
what it represents would help.

**One question, if you have a moment:** could you confirm the North York location used for
the other seven chains — a postal code or store would do? Their URLs carry no store id, so
it is the one part of the scope we cannot verify from the data.

---

## What is already good, and worth not losing

Stated because feedback documents skew negative, and because these are properties we
built on:

- **The join is documented and the SQLite file is indexed on `raw.product_id`.** Loading
  71.8M rows into an analysis engine took under two minutes.
- **The UPC reliability tiering is published and honest.** Being told plainly which
  vendors are fuzzy-matched, and that they may contain errors, is *more* useful than a
  higher-coverage UPC column with no provenance. We built our headline number on that
  tiering and could not have done so without it. It is the single most valuable piece of
  documentation you publish.
- **`old_price` exists at all.** It gives 566,564 identifiable sale events, of which
  279,599 have a full 14 days of continuous prior daily history. That is a large, genuine
  sample for questions about sale behaviour, and it is the strongest thing in the dataset.
- **Daily coverage is good.** 887 distinct dates over a 906-day span, and only 271 missing
  vendor-days in total across 8 vendors. The one large outage (2025-08-11 → 2025-08-29,
  19 days, all vendors) is visible and unambiguous rather than partial and misleading.

---

## Ranking, and the reasoning

| Rank | Item | Consumer cost if unfixed | Effort to fix | Why this rank |
|---|---|---|---|---|
| 1 | Scalar `current_price` (§1) | **Silent 2× price errors, or silent loss of 7.6% of your best vendor** | Medium | Only item here that produces confidently wrong numbers rather than missing ones |
| 2 | **Walmart field misalignment (§2)** | **Two fields corrupted at once: `units` unusable for half of Walmart, `brand` partly filled with price text** | Medium | Live data corruption, still being written daily. One root cause explains two separate symptoms, so one fix retires two findings |
| 3 | `product.id` doc contradiction (§3) | Consumers over-engineer around a non-problem, or learn to ignore your warnings right before a breaking change | **One sentence** | Best effort-to-value ratio here — but it is a stale sentence, not corrupted data. A wrong description costs less than wrong values |
| 4 | Stable product key (§4) | Every consumer re-derives identity defensively | Low | The guarantee itself, once §3 says what is true today |
| 5 | **Orphan rows (§5)** | **1.22% of all price rows, 7.2% of Metro's, unjoinable — and 74% of it is one retired id scheme** | **Low: a two-column mapping table** | Re-ranked after diagnosis. We first read this as "some rows are missing"; it is a **non-retroactive primary-key migration**, and a published old-id → new-id mapping would erase three quarters of it in one shot. Highest value per unit of your effort in this document |
| 6 | Small-basket date (§6) | A month of good data wrongly discarded | **Trivial** | Pure documentation error, near-zero cost |
| 7 | UPC width + PLU (§7) | Cross-vendor matches silently split | Low | Affects the number most consumers care about most |
| 8 | Duplicates (§8) | Consumers invent divergent tie-breaks | Medium | Real, but already documented and expected |
| 9 | Batched smaller items (§9) | Friction, not error | Low each | Individually minor; collectively a nice afternoon |
| **10** | **UPC blind to private label (§11)** | Every consumer builds a basket believing it is representative; it silently omits ~22.6% of price-weighted shelf exposure and ~30% at Metro | **One sentence** | New. Ranked low only because it costs you nothing and changes no data — but it is the item most likely to produce a confidently wrong *published* number by someone downstream, and that argues for doing it early despite the rank |
| **11** | **Galleria catalogue disjointness (§10)** | A consumer reads 11% cross-vendor overlap as their own matching bug and goes looking for it, as we did | **One sentence** | New. Purely documentation, and the cheapest item in this document |

**On the two new items (§10, §11), added 2026-09-08.** Both are documentation-only and
both sit at the bottom of the ranking, which understates §11. Its cost is not to us — we
have already measured the blind spot and can caveat around it — but to the next consumer
who publishes a "which supermarket is cheapest" number without knowing that private label
is structurally absent from it. One sentence from you prevents a class of wrong public
claims. If the ranking were by *risk of someone else being wrong in public* rather than by
cost to us, §11 would be third.

**§5 was re-ranked after we diagnosed it.** Its position is unchanged but its reasoning
is not: the effort estimate moved from "Low (doc) / High (fix)" to genuinely low, because
the fix turns out to be a mapping table rather than backfilling 878K rows. If you only act
on one thing below the top three, this is the one.

**On the top three.** §1 and §2 are both *live corruption* — every extract you publish
from here on carries them. §3 is a sentence that is out of date. Ranking a documentation
fix above a data-corruption fix would be optimising for our reading convenience over your
data's correctness, so §2 sits above §3 even though §3 is a hundred times cheaper to fix.

**Why §2 moved up.** We initially filed the Walmart `units` problem as "marketing copy in
a size field" and ranked it seventh. Reading `concatted` showed that was the wrong
diagnosis: it is a **field-assignment bug**, and it accounts for both the 51.38% unit
parse rate *and* part of the 32.48% blank-brand rate. Two symptoms we had been treating as
unrelated turned out to be one cause, which raises both its impact and the value of fixing
it. That is also why it is worth your time over the cheaper items: it is the only entry
where one change retires two findings.

If only two things change, we would pick **§1** and **§2** — the two that are actively
corrupting values. **§3** is the one to do anyway, because it costs a sentence.

---

*Every number in this document is reproducible from committed SQL against the snapshot
identified at the top. Happy to share the queries, the full findings document, or to
re-run any of this against a newer snapshot on request.*
