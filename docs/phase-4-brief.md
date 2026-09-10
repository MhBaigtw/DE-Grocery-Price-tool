# Phase 4 — The tool

A public web tool that answers one question: **for this specific product, which of these
stores is cheapest right now?**

This is the comparison the findings support. It is an identical-barcode comparison at
multiple chains on the same date, which survived every robustness check in Phase 2. It is
**not** the basket claim, which the findings forbid.

Read `CLAUDE.md`, `docs/phase-2-findings.md` (especially "what must never be said") and
`docs/writeup.md` first.

---

## What the tool is, stated honestly

- Around 3,477 barcodes, national brands only
- Metro, Save-On-Foods and Walmart (Galleria's catalogue barely overlaps — see §3.7)
- In-store pickup prices for one Toronto neighbourhood
- As of the most recent refresh, with the date shown on screen

**Store brands cannot appear.** No shared barcode, so President's Choice against Selection
is not a comparison this tool can make. That limit goes in the interface, not in an
about page — a user who doesn't understand it will draw a false conclusion from a true
number.

---

## Section 1 — Measure the refresh cadence first

Do not pick a schedule. Derive it.

1.1 Day-of-week distribution of price changes, per chain, across the full history. If
    changes cluster on one weekday, that is the flyer cycle and it sets the schedule.

1.2 How long a price typically holds, per chain — median and p90 duration between
    changes. This tells you how stale a given refresh interval leaves the tool.

1.3 Publication lag over all snapshots held: the gap between the scrape date and when the
    file became available. The maintainer has warned this will become irregular, so
    report the distribution, not a single figure.

1.4 From those three, recommend a refresh schedule and state what staleness it implies in
    the worst case. That worst case belongs in the interface.

Report before building anything.

---

## Section 2 — The data extract

2.1 Export, per barcode, per chain: current price, price basis, min quantity, the date
    observed, and whether the row was on sale. Ambiguous and orphan rows are excluded per
    the standing rules, and the excluded count is reported in the extract's metadata.

2.2 Include a short recent price history per barcode — enough to show whether today's
    price is unusual, and no more. This is where the "is this actually a sale" logic from
    2A can appear as a per-product signal rather than an aggregate claim.

2.3 Size the extract. It should be small enough to ship as static JSON with no backend. If
    it isn't, cut history depth before cutting products.

2.4 Every price in the extract carries its `price_basis`. A per-weight price and an
    each-price must never be compared in the interface.

---

## Section 3 — The interface

3.1 Search by product name or brand. Results show the product, then the price at each
    chain that stocks it, cheapest first, with the observed date.

3.2 **Only chains that stocked that barcode on the same date are compared.** If one chain
    has no recent observation, it shows as "no recent price" — never as absent, and never
    silently dropped from the comparison.

3.3 On-screen, always visible, not behind a link:
    - the data date and how stale it may be
    - Toronto pickup prices, one neighbourhood
    - national brands only, store brands cannot be compared
    - the attribution: "The underlying data was sourced from ProjectHammer.org"

3.4 **No basket, no total, no "cheapest store" verdict.** The tool answers per-product and
    stops. Anything that sums across products reintroduces the claim the findings forbid.

3.5 Link to the writeup from the tool. A user who wants to know why it works this way
    should be one click from the answer.

---

## Section 4 — Refresh automation

4.1 Scheduled job on the cadence from Section 1: fetch the newest upstream snapshot,
    verify schema, rebuild the models, regenerate the extract, deploy.

4.2 **The schema check is a gate, not a log line.** If `raw.product_id` has changed type
    or any column has moved, the refresh stops and the site keeps serving the last good
    extract rather than deploying something unverified.

4.3 The determinism and reconciliation checks run in the pipeline. A refresh that fails
    any check does not deploy.

4.4 Keep the snapshot archive accruing per `docs/retention-design.md`. The mirror is
    independently valuable and the tool is not a reason to stop it.

4.5 Alert on failure in a way you will actually notice. A silent refresh failure means the
    site serves stale prices with a fresh-looking date.

---

## Section 5 — Deployment

5.1 Static host, no backend. The extract is JSON, the interface is client-side.

5.2 Deployed on the owner's own domain, on a subdomain or path of its own so it is
    clearly a distinct project rather than something bolted onto an existing page.

5.3 Deploy from CI so the refresh is one pipeline, not a manual step. A refresh that
    fails any check leaves the previous deploy in place.

5.4 The tool must stand on its own for a visitor arriving from an external link, with no
    prior context: what it does, what it covers, what it cannot answer, and the data
    date, all visible without scrolling or clicking through.

5.5 Verify the deployed site over HTTP the way the dashboard was verified: every asset
    loads, every JSON parses, the stated date matches the extract's actual date. Verify
    on a phone-width viewport as well — a price lookup is a phone tool, and a comparison
    table that breaks at 380px is broken.

5.6 The repository links the deployed tool, and the tool links the writeup. A reader who
    lands on either should be able to reach the other in one click.

---

## Exit criteria

- Refresh cadence measured and justified, not assumed.
- Extract ships as static JSON with every qualifier attached to every price.
- Interface answers per-product only, with the four disclosures always visible.
- Refresh runs on schedule, gates on schema and checks, and fails without deploying.
- Deployed and verified live.

## Non-goals

No basket. No store ranking. No store-brand comparison. No user accounts.

No ads, ad-network scripts, or third-party trackers in this phase. This is deferred, not
declined: the original licence request to the dataset maintainer stated the project was
non-commercial with no ads, so permission was granted on that basis. Nothing of that kind
ships unless the maintainer agrees in writing first, and that agreement would be its own
decision, made separately from this brief.

If basic usage numbers are wanted, use a privacy-respecting, cookieless analytics option
and nothing more. That is a measurement tool, not monetisation, and it avoids dragging a
consent banner onto a page whose whole argument is about being straight with the reader.
