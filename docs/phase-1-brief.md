# Phase 1 — Representation

**No findings in this phase.** Phase 1 builds the two things every surviving analysis
depends on: a price you can compute with, and a product identity you own. D2 and D4 are
not touched. D1 is not touched.

Read `CLAUDE.md` first. Every rule in it applies. Work section by section, report, wait.

## Why this phase exists

Phase 0 established that both surviving findings are blocked on representation, not on
analysis:

- 5,726 sale events (6,421 under the stricter rule) are excluded from D2 solely because
  `current_price` is non-scalar. That exclusion is **categorical, not partial**: multibuy
  prices can never survive a numeric cast, so 100% of Metro's "n for $X" offers (925
  events) are absent. The excluded events are also ~8pp deeper at the median.
- D4's basket rests on 3,477 GTINs whose prices come disproportionately from Metro and
  Save-On-Foods, the two vendors with the highest non-scalar rates.
- Product identity is currently borrowed from upstream, and upstream has announced a
  breaking type change to the column it's borrowed from.

Building either finding before this phase means rebuilding it after.

---

## Section 1 — Second snapshot

Everything Phase 0 concluded about identity rests on **one snapshot**. That is the single
largest unverified assumption in the project.

1.1 Acquire a second snapshot, at least several days separated from the first. Record
    provenance per the G1 rule: download timestamp, sha256, `hammer-lastupdated.txt`
    value, max `nowtime`, and the resulting publication lag.

1.2 Run `check_schema.py` against it. Report the result. If `raw.product_id` has already
    changed type, stop and report before doing anything else.

1.3 **Cross-snapshot identity test.** For products present in both snapshots, does
    `(vendor, sku)` refer to the same product? Compare `product_name`, `brand` and
    `units` across snapshots for the same key. Report the disagreement rate per vendor.

    Phase 0 showed `product.id = vendor||sku` is stable *within* a snapshot, which is
    tautological. This is the first real test of the claim, and the answer determines
    whether Section 4 is straightforward or hard.

1.4 Diff the two snapshots: rows added, rows removed, rows whose price changed. Report
    whether upstream data is append-only or whether history gets rewritten. If history is
    rewritten between snapshots, say so loudly — it changes what "the archive" means.

---

## Section 2 — Price representation

Build one model that turns the raw price text into something computable, for every row,
with no silent losses.

2.1 Inventory the shapes. Enumerate the distinct forms `current_price` and `old_price`
    take, with counts, per vendor. Include the scalar case. Show the 40 most common
    non-scalar patterns verbatim.

2.2 Design the target model. Every price row resolves to:

    - `offer_type` — scalar | multibuy | per_weight | unparsed
    - `unit_price` — the price of one unit, derived where derivable
      (`2/$7.00` → 3.50; `$4.99/100g` → basis-dependent, see below)
    - `min_qty` — 1 for scalar, n for multibuy
    - `price_basis` — each | per_100g | per_lb | per_kg
    - `raw_price_text` — always retained, never discarded
    - `parse_confidence` — and an explicit `unparsed` verdict where nothing was derived

    Rules:
    - **Never drop a row for being unparseable.** It gets `offer_type = 'unparsed'` and
      keeps its raw text. The unparsed set must remain countable and inspectable.
    - **Never strip a multibuy to its scalar.** `2/$7.00` → 7.00 doubles the true price
      and would corrupt every downstream number.
    - A per-weight price is a real price. It is not comparable to an each-price without
      a size, which is what `price_basis` exists to record.

2.3 Reconcile against Phase 0. After parsing, re-run the D2 exclusion count. Report the
    new number of sale events lost to non-scalar prices, per vendor, against the prior
    5,726 / 6,421. State how many of Metro's 925 multibuy events are recovered.

    Update the D2 caveat in `phase-0-findings.md` to reflect the post-parse state. The
    current wording implies a permanent scope limit; it is a pre-parse limit.

2.4 `price_per_unit` cross-check. Phase 0 flagged it as untrustworthy. Now that units and
    prices both parse, quantify: where both are computable, how often does the upstream
    field agree with ours? Where it disagrees, spot-check ten cases and say which side is
    right. This is upstream feedback material.

---

## Section 3 — Unit representation

3.1 Canonical parse of `units` → (quantity, unit, pack_count). Handle `2 x 500 mL`.
    Report parse rate per vendor.

3.2 Walmart's 51% parse rate is already diagnosed as field misalignment rather than bad
    formatting. Determine whether the correct value is recoverable from `concatted`, and
    if so, whether recovering it is worth the complexity. Recommend, don't decide alone —
    a vendor-specific repair rule is a maintenance liability and should be argued for
    explicitly.

3.3 Junk-value handling. `Out of stock` in the brand field, `error` in units, and the
    451 unclassifiable brand values need an explicit verdict. **Junk does not default to
    a real category.** Add `unclassifiable` rather than letting unknown brands fall
    through to "national brand", which biases private-label share downward.

---

## Section 4 — Product identity

4.1 Own key. Define a surrogate key derived by us, not borrowed from upstream, covering
    the blank-sku 13.8% as well. Document the derivation. Downstream models reference
    only this key — `raw.product_id` must not appear below the staging layer, so the
    announced type change is an ingest-layer event and nothing more.

4.2 Cross-vendor identity. Materialize the reliable-group UPC set from Phase 0 (5,222
    GTINs at 2+ reliable vendors, 3,477 with 90+ shared days) as a first-class model with
    the tier on every match: `vendor_upc` | `matched_upc` | `fuzzy` | `unmatched`.

    Lower tiers are kept and flagged, never deleted. Headline numbers filter to the top
    tier at query time, not by dropping rows at load time.

4.3 Do **not** attempt fuzzy cross-vendor matching in this phase. It is a Phase 2
    decision with its own accuracy question, and B5's 26/30 eyeball is not a basis for
    shipping it.

---

## Section 5 — Contracts and tests

5.1 dbt tests on the staging and intermediate models: uniqueness on the owned key,
    not-null on every field the downstream depends on, accepted values on `offer_type`,
    `price_basis` and match tier, and a relationship test between the price model and the
    product model.

5.2 A reconciliation test: row count in equals row count out at every layer, with any
    deliberate reduction named and asserted. Silent row loss is the failure mode this
    catches.

5.3 Each test must be shown to fail when it should. A test that has never failed has not
    been tested — same standard as the schema check's control case.

5.4 Report test counts as counts, never as a phase pass rate.

---

## Exit criteria

Phase 1 is done when:

- Two snapshots are archived with provenance, and cross-snapshot identity stability is
  measured with a number, per vendor.
- Every price row in both snapshots has an `offer_type` and either a `unit_price` or an
  explicit `unparsed` verdict. The unparsed set is counted and its shapes listed.
- The post-parse D2 exclusion count is reported against the pre-parse 5,726 / 6,421.
- An owned product key exists, `raw.product_id` appears nowhere below staging, and the
  cross-vendor tier model is materialized.
- All tests pass and each has been demonstrated to fail when it should.
- `docs/FILES.md` is current and `check_manifest.py` passes.

## Non-goals

No findings. No dashboard. No fuzzy cross-vendor matching. No Airflow. No decision on
D1's viability — that is Phase 2, and it is a methodology question, not a data question.
