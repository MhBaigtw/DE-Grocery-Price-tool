# Phase 3 — Publication

Phase 2 produced the results. Phase 3 makes them readable by someone who will never open
the repo.

**Scope:** a written piece, and a small dashboard that supports it. Not a product.

Read `CLAUDE.md` and `docs/phase-2-findings.md` first. The "what must never be said"
section is binding on everything in this phase.

---

## Section 1 — The argument

Before writing anything, settle what the piece argues. Draft it as one paragraph in
`docs/phase-3-thesis.md` and stop for review.

The material supports this shape:

> Grocery price transparency is harder than it looks, and the gap is not where people
> assume. Most apparent pre-sale price inflation is explained by prices retailers
> actually charged. Cross-retailer promotion comparison is undefined, because the sale
> flag means different things at different retailers. And UPC-based comparison —
> the method every price comparison tool uses — is structurally blind to private label,
> which is roughly 23% of shelf exposure and the segment where retailers compete
> hardest. The one clean comparison that survives says Walmart is cheaper on identical
> national-brand products on 100% of observed dates, while 85% of individual products
> have no consistent cheaper vendor. The aggregate answer and the shopper's answer
> disagree, and both are true.

Argue with that shape if the evidence supports a better one. Do not soften it into "we
looked at grocery prices". The negative results are the contribution.

Constraints on the argument:

1.1 Every headline claim carries its qualifier **in the sentence**, not in a footnote or
    a methodology section. "On identical national-brand products" and "within-vendor
    only" are part of the claim, not caveats on it.

1.2 R1 is a bracket. Never a point estimate, in either direction.

1.3 No accusation the data does not support. The promotional-cadence result is about
    cadence, not honesty, and the piece must not be readable as "retailers lie".

1.4 The five withdrawals appear in the piece, not just the repo. What you looked for and
    could not support is the most credible part of the writeup and the part that will
    distinguish it from every other grocery price post.

---

## Section 2 — The written piece

2.1 Format: markdown in the repo, so it lives with its evidence and is versioned with it.
    A copy can be posted elsewhere later.

2.2 Structure — a suggestion, not a mandate:
    - What people assume grocery price data can tell them
    - What it actually can, with the three results
    - What it structurally cannot, with private label as the centrepiece
    - The one clean comparison, with its qualifier
    - What would need to change to answer the question properly

2.3 Every number in the piece traces to a query in the repo. Link them. A reader who
    doubts a figure should be one click from the SQL that produced it.

2.4 Length: whatever the argument needs and no more. This is not a report; padding it
    with methodology will bury the results.

2.5 State the data vintage prominently. The newest snapshot is 2026-08-23 and the
    maintainer is actively fixing defects, so several findings describe a moment in time.
    Say so where a reader will see it, not only in an appendix.

---

## Section 3 — The dashboard

The dashboard exists to make the argument tangible. It is not a shopping tool and must
not be mistakable for one.

3.1 Static site, no backend, pre-aggregated data. Deployment target is a static host.

3.2 Minimum content, in priority order:
    - The national-brand pairwise comparison over time, with n shown per date
    - The private-label blind spot, visualized: what share of the catalogue the basket
      can and cannot see
    - Per-vendor sale frequency, within-vendor only, with the cross-vendor comparison
      explicitly marked as unavailable and why
    - The exclusion ledger, browsable

3.3 **Do not build a basket price lookup.** A shopper typing a list and getting "Walmart
    is cheapest" is precisely the claim the findings forbid. If a lookup exists at all,
    it must be scoped to national-brand products with the private-label gap stated on
    the same screen — and the honest default is not to build it in this phase.

3.4 Attribution — "The underlying data was sourced from ProjectHammer.org" — visible on
    every page, per the maintainer's requirement.

3.5 Every chart states its n and its qualifier on the chart, not in a caption below it.

---

## Section 4 — Repository presentation

4.1 The README links the writeup first, the dashboard second, the findings docs third.
    A visitor arriving from projecthammer.org should reach the argument in one click.

4.2 Verify the reproduce-from-scratch instructions actually work from a clean checkout.
    Have them followed literally rather than checked by inspection.

## Exit criteria

- The thesis paragraph is agreed before the piece is written.
- The piece is published in the repo, every number traceable, every qualifier inline.
- The dashboard is deployed, attributed, with n and qualifiers on every chart.
- The README routes a cold visitor to the argument.

## Non-goals

No basket lookup tool. No Airflow. No new analysis — if Phase 3 wants a number that
does not exist, that is a Phase 4 question, not a reason to compute it while writing.
