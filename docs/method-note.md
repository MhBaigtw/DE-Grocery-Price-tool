# Method note — how I know the numbers are trustworthy

*Companion to [the writeup](writeup.md). This is the part I would read first if someone
else had written it.*

The writeup argues that measurement choices moved the answer more than the supermarkets
did. That argument is only worth anything if my own measurements are sound. This note is
the evidence — starting with **the largest error in the project, which none of my checks
caught**, and then four times I did catch myself, one of which happened twice.

Every check below is a committed script that can be run against the repository.

---

## The biggest failure: every check verified consistency, and none verified what the data was of

**Every check in this project verified internal consistency. None of them verified what the
data was of.** The largest error in the project was an unverified scope assumption, locked in
at Phase 0 and never tested.

The schema contract, the determinism lint, the compute-twice check, the reproducibility
checksums, forty dbt contracts and the deploy gate all proved that the pipeline did what it
said to the data it was given. Not one of them asked where the prices came from. That answer
was assumed on day one and written into the project's locked decisions as "in-store pickup
prices for one Toronto neighbourhood".

**For one chain it was false.** Save-On-Foods has no stores in Ontario. In this dataset, 97%
of its products are priced at a store in Kamloops, British Columbia. So I published two
comparisons — Walmart about 17.9% cheaper than Save-On-Foods, Metro about 5.3% cheaper —
that were really comparisons between two cities, and I built them into a public tool that
told visitors it was showing Toronto prices.

**Every check passed the whole time**, because every check was about consistency, and a
pipeline that is consistent over the wrong scope is still consistent. The evidence was in the
data from the start: Save-On-Foods' product links carry the store's id. Nothing looked at it,
because nothing was pointed at it.

It was found by someone asking a plain question — *which neighbourhood?* — and nothing else.

**What I did about it:** took the tool offline before fixing anything; withdrew every
comparison involving Save-On-Foods (W6 in the findings); rebuilt the tool as Metro against
Walmart, the only pair priced in the same area; and corrected the locked decision in place,
with a note saying it was wrong from Phase 0.

**What I have not done** is claim a new check that would have caught it. A control verifies
what it is pointed at. The honest lesson is that none of mine were pointed at provenance, and
the controls below — which all worked — should be read with that in mind.

*[findings §9](phase-4-findings.md) · [W6](phase-2-findings.md) · [CLAUDE.md decision 3](../CLAUDE.md)*

---

## The controls

| Control | What it enforces | Shown to fail when it should |
|---|---|---|
| [`check_schema.py`](../scripts/check_schema.py) | The upstream schema matches a committed contract; ingest fails loudly rather than casting or inferring | 6 of 6 cases |
| [`check_determinism.py`](../scripts/check_determinism.py) | No SQL construct can return a different answer on the same data without a written, checkable justification | 8 of 8 cases |
| [`verify_twice.py`](../scripts/verify_twice.py) | Every published number is computed twice and both runs **succeeded** and agree | 5 of 5 cases |
| [`check_claims.py`](../scripts/check_claims.py) | Every figure in the writeup, the README and this note is listed in [`CLAIMS.md`](CLAIMS.md) against a committed source | 7 of 7 cases |
| [`check_layering.py`](../scripts/check_layering.py) | An upstream row id cannot leak into the analysis layer | shown to fail |
| [`check_model_parity.py`](../scripts/check_model_parity.py) | Two build paths cannot silently disagree about what a model means | shown to fail |
| [`verify_reproducible.py`](../scripts/verify_reproducible.py) | The materialised data matches its own definition, column by column | 22 of 22 columns |
| dbt test suite | 40 contract tests, on both snapshots | 23 of 23 injected violations caught |

"Shown to fail when it should" is the load-bearing column. **A check that has never failed
has not been tested**, so each one has a companion that deliberately breaks it and asserts
it complains.

**The last row arrived late, and a reviewer found the gap before any check did.** The rule
that every published figure has a committed query was written down from the start and
enforced by nothing. The writeup carried a rank correlation of 0.196 that no committed query
produced — computed, it turned out, over two chains whose promotional text is not rare but
absent. The project owner found it by reading the draft. No control fired.

The response was a sweep and a check. The sweep traced every figure in the three published
documents as they stood at commit `66ecb20`: **197 figure occurrences, and 1 with no
committed source** — the 97% of Save-On-Foods products at the Kamloops store, above, which
came from queries deleted after they ran. `R6_save_on_foods_store_ids.sql` now regenerates it
(15,766 of 16,258). Of the rest, 105,540 was already recorded as provenance-lost and stays
that way; 614 and the determinism lint's 44 (16 plus 28) trace to committed scripts but
describe an earlier state of them, and are marked historical. `CLAIMS.md` records, entry by
entry, whether the number was confirmed against its source's output for the sweep or traced
through the findings document that quotes it.

`check_claims.py` now fails if a figure in those documents has no entry, if an entry names a
file that is not committed, or if an entry no longer matches its sentence. **It is narrower
than it sounds.** It proves a source exists, not that the source produces the number; that is
still a person. It sees digits only, so a figure written as a word passes unseen.

**It covers three documents, not the repository.** "197 figures checked" means the writeup,
the README and this note, and nothing else. The four findings documents and
`upstream-feedback.md` are not checked at all, and they carry far more figures than the
checked surface: the same extractor counts 6,613 figure occurrences in those five against
197 in these three. That count is the extractor's, tuned on the three checked documents and
not reviewed against the other five, so read it as an order of magnitude. The Phase 3 thesis
is not checked either. The findings documents are where most numbers were first computed; a
figure in them can still lack a committed source, and no sweep has looked.

---

## Four times I caught myself

These are in the repository in full. They are here because a reader deciding whether to
believe the writeup should see the failure rate, not just the controls.

### 1. A pooled comparison overturned by controlling for one variable — three separate times

Orphaned price rows looked **1.70× richer in sale rows** than the rows I kept. That would
have been a real bias in the sale analysis.

It was a composition artefact. 72.6% of those rows are Metro's, and Metro runs more
promotions than average. Recomputed *within* each chain the enrichment is **1.22×**, and
the direction is not even consistent — four chains enriched, three depleted, one neutral.

**The same confound caught me twice more** in the same audit, on multibuy share and on
brand mix. An apparent 11× multibuy enrichment was entirely Metro; within Metro it is
1.77×.

It is the same error I had already made once before, on a different question. Knowing
about it did not prevent it — running the control did.

*[findings §1.2, §1.4](phase-2-findings.md)*

### 2. A published figure that changed between runs of the same query

One published figure moved by **614** across three runs — same data, same
build, same query. The cause was `any_value()` over a group that was not unique: it picks
an arbitrary row, and "arbitrary" is not "stable".

Fixing it exposed a second instance immediately. The fix partitioned by `(product, date)`,
which is *also* not unique on this dataset — one product can appear many times in a single
day's scrape with conflicting prices — so rows migrated between categories between runs.

That was the third instance of one defect class, so I stopped fixing instances and wrote
[`check_determinism.py`](../scripts/check_determinism.py), which flags the pattern
repository-wide. It found **44** constructs. 16 were made deterministic for
free — **one of those was a real latent defect** nobody had noticed — and the other 28 now
carry a written justification a reviewer can check.

*[findings §1.3](phase-2-findings.md)*

### 3. Two runs that crashed identically and passed a byte-comparison — twice

My reproducibility check was `diff run1 run2`. That check has a hole: **two runs that fail
the same way produce identical output and compare as agreement.**

This is not hypothetical. During the basket analysis, a query failed on both runs with the
same error, produced byte-identical output, and a `diff` reported success.
[`verify_twice.py`](../scripts/verify_twice.py) — written one working session earlier —
caught it, because it asserts successful completion and matching row counts *before* it
compares bytes.

The test for that checker includes a probe engineered to crash identically on both runs,
asserting the checker still refuses. A plain `diff` passes that probe.

**It happened again.** Measuring refresh cadence, a query with `GROUP BY 1,2,3` — where
position 3 was an aggregate — failed on both runs with the same binder error and produced
byte-identical output for the second time. `verify_twice.py` refused it again, for the same
reason.

**Two occurrences means this is not a rare accident.** A deterministic bug fails
deterministically; that is what "deterministic" means. Any comparison that treats matching
output as agreement will call a reproducible crash a reproducible result, and **a plain
`diff` would have shipped both of these**. The order of the assertions is the whole
mechanism: exit status first, failure markers second, row counts third, bytes last. Compare
bytes first and the check is worse than nothing, because it produces a pass.

*[findings §2.8](phase-2-findings.md); the repeat in [Phase 4 §1](phase-4-findings.md), "What §1 changed about the plan"*

### 4. A published number whose origin can no longer be established

One published figure — a row count of 105,540 — matches no state I can reconstruct. Not the current value, not the value under any committed version of the code.

I could not explain it, and I did not invent an explanation. It is recorded as
**provenance lost, permanently**, so nobody reopens the search. In response, every findings
section now carries the build fingerprint it was computed under, which makes the next such
discrepancy a lookup instead of an investigation.

**That rule fixes the problem forward, not backward.** Numbers published before it existed
have no such record and never will.

*[earlier findings §5.8](phase-1-findings.md)*

---

## What I excluded, and whether it was biased

Excluding rows is unavoidable. Excluding them *without checking whether they resemble what
remains* is how an exclusion becomes a finding. Of 71,809,333 price observations:

| Class | Rows | Verdict |
|---|---|---|
| kept | 70,883,862 (98.71%) | — |
| **no product record** | **878,559 (1.22%)** | **Biased on time.** Removes 26.8% of Metro's 2024 sale events against 0.4% of its 2025 events |
| ambiguous price | 46,884 (0.07%) | Distinct in kind, immaterial in effect |
| unparseable | 28 *(of 33; the other 5 are also orphans, counted above)* | Too few to test |

The time bias is why **every headline result in the writeup is scoped to 2025–2026**, with
2024 reported separately. The exclusion was not merely large; it was concentrated in one
chain in one year, which is the kind that moves a trend line.

I also found a **fourth exclusion nobody had declared** — a filter carried over from earlier
work whose original justification had disappeared. It removed 8,797 sale events, eight
times more than the documented filter beside it, and was biased on every axis I tested. It
was also worth 0.19% of the final sample. Both halves are true and I report both.

*[findings §1.1, §1.5](phase-2-findings.md)*

---

## What this note does not claim

- **Not that the analysis is error-free.** Four errors are described above, and those are
  the ones I found.
- **Not that the dataset is flawed.** It is unusually good. Every defect in the writeup is
  mine, or is a documented upstream quirk the maintainer is actively working through.
- **Not that the controls are complete.** They cover the failure modes that have actually
  bitten me. Nothing here rules out one that has not yet.

---

*The underlying data was sourced from ProjectHammer.org.*
