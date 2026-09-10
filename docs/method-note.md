# Method note — how I know the numbers are trustworthy

*Companion to [the writeup](writeup.md). This is the part I would read first if someone
else had written it.*

The writeup argues that measurement choices moved the answer more than the supermarkets
did. That argument is only worth anything if my own measurements are sound. This note is
the evidence, including **four times I caught myself being wrong**.

Every check below is a committed script that can be run against the repository.

---

## The controls

| Control | What it enforces | Shown to fail when it should |
|---|---|---|
| [`check_schema.py`](../scripts/check_schema.py) | The upstream schema matches a committed contract; ingest fails loudly rather than casting or inferring | 6 of 6 cases |
| [`check_determinism.py`](../scripts/check_determinism.py) | No SQL construct can return a different answer on the same data without a written, checkable justification | 8 of 8 cases |
| [`verify_twice.py`](../scripts/verify_twice.py) | Every published number is computed twice and both runs **succeeded** and agree | 5 of 5 cases |
| [`check_layering.py`](../scripts/check_layering.py) | An upstream row id cannot leak into the analysis layer | shown to fail |
| [`check_model_parity.py`](../scripts/check_model_parity.py) | Two build paths cannot silently disagree about what a model means | shown to fail |
| [`verify_reproducible.py`](../scripts/verify_reproducible.py) | The materialised data matches its own definition, column by column | 22 of 22 columns |
| dbt test suite | 40 contract tests, on both snapshots | 23 of 23 injected violations caught |

"Shown to fail when it should" is the load-bearing column. **A check that has never failed
has not been tested**, so each one has a companion that deliberately breaks it and asserts
it complains.

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

### 3. Two runs that crashed identically and passed a byte-comparison

My reproducibility check was `diff run1 run2`. That check has a hole: **two runs that fail
the same way produce identical output and compare as agreement.**

This is not hypothetical. During the basket analysis, a query failed on both runs with the
same error, produced byte-identical output, and a `diff` reported success.
[`verify_twice.py`](../scripts/verify_twice.py) — written one working session earlier —
caught it, because it asserts successful completion and matching row counts *before* it
compares bytes.

The test for that checker includes a probe engineered to crash identically on both runs,
asserting the checker still refuses. A plain `diff` passes that probe.

*[findings §2.8](phase-2-findings.md)*

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
| unparseable | 28 | Too few to test |

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
