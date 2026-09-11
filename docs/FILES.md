# File manifest

Every tracked file in this repo, why it exists, and what breaks without it.
Verified by `scripts/check_manifest.py`, which fails on drift in either direction.

A heading ending in `/` is a **directory entry**: it covers every tracked file beneath
it. Used where files are numerous and uniform in purpose (the Phase 0 query set), so the
manifest documents the *set* rather than restating one line per file.

---

## Reading order

Read these in order to understand the project from scratch:

1. **`CLAUDE.md`** — the rules. Locked decisions and non-negotiable honesty rules. Binding, not advisory. Nothing else makes sense without it.
2. **`README.md`** — what the project is, current status, how to reproduce.
3. **`docs/phase-0-brief.md`** — the Phase 0 assignment, so you can judge whether it was actually answered.
4. **`docs/phase-0-findings.md`** — the deliverable. Start with §1 (the headline number), then §2 (bad news), then §8 (what the data can and cannot support). The middle sections are evidence for those three.
5. **`analysis/phase0/`** — the queries behind every number. Read `B4_cross_vendor_upc_overlap.sql` first; it produces the number the project hinges on.
6. **`docs/phase-1-brief.md`** and **`docs/phase-1-findings.md`** — Phase 1 builds representation (a computable price, an owned product identity). Its §1 is the first non-circular test of product identity, using two snapshots.
7. **`analysis/phase1/`** — the Phase 1 queries. `P1_3_cross_snapshot_identity.sql` is the one that decides whether the owned key is easy or hard.
8. **`docs/upstream-feedback.md`** — the ergonomics report sent to the dataset maintainer. Reads as a summary of what was expensive to consume, so it doubles as an index of the audit's sharpest findings.
9. **`scripts/`** — how a snapshot is fetched, loaded, schema-checked, and queried.
10. **`config/expected_schema.json`** — the schema contract those checks enforce.
11. **`docs/FILES.md`** — this file, last. It is a map, not an introduction.

---

### CLAUDE.md
**Purpose:** Project constitution. Locked decisions (no scraping, snapshot immutability, Toronto-pickup scope, data-range discipline, derived product identity) and seven non-negotiable honesty rules.
**Breaks if removed:** Nothing executable, but the project loses the standard that every other file is written against. Honesty rules #1 (missing day ≠ unchanged price) and #3 (every number has a query) are load-bearing for the whole design.
**Depends on:** Nothing.
**Notes:** Its honesty rules are cited **by name as well as number** throughout the repo, because rules have twice been inserted mid-list and each insertion invalidates every bare "rule N" reference — the second renumbering left stale references in four files before they were caught. Two statements in it are contradicted by the data and are flagged in `docs/phase-0-findings.md` §2.1 and §2.2 — the small-basket end date (Jul 10/11 vs the actual 2024-06-11) and the claim that `product.id` changes daily. Neither was silently worked around. Its "File manifest (mandatory)" section is what requires this file, and requires `scripts/check_manifest.py` to pass before any phase is reported complete. Its "Upstream volatility" section is what requires `config/expected_schema.json` and `scripts/check_schema.py`.

### LICENSE
**Purpose:** MIT licence for the code and documentation in this repository.
**Breaks if removed:** Default copyright applies and nobody may reuse anything here — the state the repo was in before it was published.
**Depends on:** Nothing.
**Notes:** Carries an explicit scope note, because the failure mode is a reader assuming one licence covers everything they can see. It covers **our** code and docs; it does **not** cover the Project Hammer dataset, which is not ours to license, is not redistributed here, and carries its own attribution requirement. README.md states the same split under "Two licences, and they are not the same".

### README.md
**Purpose:** Entry point. What the project is, the Toronto-pickup scope caveat, current status, layout, reproduction commands.
**Breaks if removed:** A newcomer has no orientation and may miss the scope limit, which is the easiest thing in this project to get wrong in public.
**Depends on:** Describes `scripts/`, `analysis/phase0/`, `docs/`.
**Notes:** States the scope limit above the fold deliberately — "not a national price index" is a claim that has to be made early, not in a footnote.

### docs/phase-0-brief.md
**Purpose:** The Phase 0 assignment as written: sections A–E, the deliverable definition, and the instruction to stop afterwards.
**Breaks if removed:** No way to audit whether the findings document answered what was actually asked, or to see which questions were dropped and why.
**Depends on:** `CLAUDE.md`.
**Notes:** Kept verbatim. Where a briefed question turned out to be unanswerable as posed (B2, D3), the findings document says so and explains why rather than quietly substituting a different question.

### docs/phase-0-findings.md
**Purpose:** The Phase 0 deliverable. Provenance, sections A–C numbers, the D1–D4 go/no-go table, the Section E bug list, and a plain-language "what this dataset can and cannot support".
**Breaks if removed:** The entire output of the phase is gone. The queries would survive but the interpretation, the judgement calls, and the go/no-go verdicts would not.
**Depends on:** Every file in `analysis/phase0/`; the snapshot recorded in §0.
**Notes:** Every figure cites the query that produces it. Judgement calls (B5's fuzzy-match eyeball, D3's shrinkflation sample, the PLU exclusion in B4, the 50%-of-median partial-day threshold) are labelled as judgement and show their sample — they are deliberately not dressed up as measurements. §8's "single largest risk" section names E8 as the defect most likely to silently corrupt Phase 1.

### docs/phase-1-brief.md
**Purpose:** The Phase 1 assignment — representation only: a computable price and an owned product identity. Explicitly forbids findings, fuzzy matching, and touching D1/D2/D4.
**Breaks if removed:** Phase 1's scope boundary disappears, and the temptation to compute a finding while the representation is half-built returns. The "no findings" rule is the whole point.
**Depends on:** `docs/phase-0-findings.md` — every section is justified by a Phase 0 number.
**Notes:** Section 1 is deliberately a gate: if cross-snapshot identity were unstable, Section 4 would change shape entirely, so it is answered and reported before anything is built.

### docs/phase-1-findings.md
**Purpose:** What each Phase 1 section measured and decided, so the models are traceable to evidence rather than to judgement.
**Breaks if removed:** The representation models become unexplained — a reader can see *what* was built but not *why* that shape. Section 1's identity-stability numbers are the justification for Section 4's key design.
**Depends on:** `analysis/phase1/`, both snapshots.
**Notes:** Records a methodological error of mine in §1.4 — a join on a non-unique key produced a false "upstream corrupted history" alarm — because the trap is a general hazard on this dataset, not a one-off. §1.5 isolates a defect (the `NNN$` cents-form price) that Phase 0 had lumped into an uncharacterised bucket.

### docs/phase-2-brief.md
**Purpose:** The Phase 2 assignment: the two findings the project rests on (D2 sale honesty, D4 basket comparison), with D1 demoted to a bounded secondary. Section 1 is an exclusion ledger and bias audit that must complete before any finding is computed.
**Breaks if removed:** No way to audit whether Phase 2 answered what was asked, and the ordering constraint — bias audit first, findings second — loses its written justification.
**Depends on:** `docs/phase-1-findings.md`; every section is justified by a Phase 0 or Phase 1 number.
**Notes:** Section 1 is a gate, and it is a gate because of a specific past failure: Phase 0's F1 tested the D2 bias question on the wrong axis and the correct test changed the answer categorically. Section 4's demotion of D1 is a *selection-versus-outcome* argument — products with stable listings are disproportionately products with stable prices — and it explicitly cannot be fixed by improving the sample.

### analysis/phase1/
**Purpose:** Numbered queries behind every Phase 1 number, same rule as `analysis/phase0/`: no figure exists without a committed query that regenerates it.
**Breaks if removed:** Every number in `docs/phase-1-findings.md` becomes unverifiable.
**Depends on:** `hammer.duckdb` and `hammer2.duckdb` (both gitignored, rebuilt via `scripts/load_snapshot.py`). Queries that span snapshots `ATTACH` the second database.
**Notes:** `P1_4b` carries a method note explaining why it uses a multiset diff rather than a join — that is a correction to a real mistake and is left visible on purpose. Cross-snapshot queries assume `hammer2.duckdb` sits in the repo root; rebuild it with `python scripts/load_snapshot.py 20260824T132829Z --db hammer2.duckdb`.

### models/
**Purpose:** The representation layer. `price_parse_macros.sql` holds the price-parsing macros; `stg_price.sql` is the staging model that turns raw price text into a computable unit price for every row.
**Breaks if removed:** Every downstream number reverts to `CAST(current_price AS DOUBLE)`, which silently drops 1.8% of rows concentrated in Metro and Save-On-Foods, and reads `329$` as $329.00 instead of $3.29.
**Depends on:** `raw` and `product` in a loaded snapshot. Built by `scripts/build_models.py`.
**Notes:** Now holds four macro files, two staging models and one intermediate model. `int_upc_match.sql` carries the cross-vendor match tier, and its central rule is that **the tier of a match is the weakest tier of its participants** — a Metro-Loblaws match is `fuzzy`, not `vendor_upc`, because taking the strongest participant would let a reliable vendor launder a fuzzy match into a headline number (8,920 products are demoted this way). `product_key_macros.sql` defines the OWNED product key — md5 over `vendor || chr(31) || sku`, proved collision-free across both snapshots (P3.5). It replaced a 64-bit hash workaround that had one collision in 161,300 keys and silently moved the D2 event count by 6; chr(31) is a delimiter that cannot occur in the data, and md5's ASCII hex output also sidesteps the DuckDB statistics bug that motivated the workaround. `unit_parse_macros.sql` keeps per-item size and pack count in separate columns — `24ea` is `qty=1, pack=24`, not `qty=24, pack=1`, a distinction the P3.4 cross-check caught. `brand_class_macros.sql` enforces the rule that junk never defaults to a real category. Macros are declared in dependency order because DuckDB resolves a macro body at creation time. `offer_type` and `normalization` are deliberately separate columns — the first describes the commercial offer, the second the encoding repair — so "how many single-unit offers are there?" stays answerable without knowing every quirk. Per-weight prices are rescaled to per-100g/per-100ml for comparability, with the vendor's stated denominator preserved in `price_basis_stated`. Written as a single SELECT so it drops into dbt unchanged when Section 5 needs the test framework.

### scripts/build_models.py
**Purpose:** Materialises the models into a snapshot's DuckDB. Separate from `run_query.py` because it needs write access, and that one is deliberately read-only.
**Breaks if removed:** `stg_price` cannot be built, and nothing downstream has a price to compute with.
**Depends on:** `models/`, a loaded snapshot database.
**Notes:** Asserts row count in == row count out and refuses to continue on a mismatch — silent row loss is the failure mode this catches. Defaults to a view; `--materialize table` trades ~2.1 GB of disk for query speed, which is what the current build uses because the regex parse over 71.8M rows made every downstream query cost minutes.

### docs/phase-3-brief.md
**Purpose:** The Phase 3 assignment — turn Phase 2's results into a written piece and a small dashboard for someone who will never open the repo.
**Breaks if removed:** The constraints that keep the writeup honest lose their source: qualifiers in the sentence rather than in footnotes, R1 as a bracket, no accusation the data does not support, and the withdrawals appearing in the piece rather than only in the repo.
**Depends on:** `docs/phase-2-findings.md`, whose "what must never be said" section it declares binding.
**Notes:** §3.3 forbids a basket price lookup outright — a shopper typing a list and getting "Walmart is cheapest" is exactly the claim the findings forbid, so the honest default is not to build it. §1 invites the argument to be replaced if the evidence supports a better one, which is what `phase-3-thesis.md` does.

### docs/phase-3-thesis.md
**Purpose:** The single paragraph the written piece argues, drafted and held for review before any prose is written.
**Breaks if removed:** Phase 3 would start writing without an agreed argument, which is how a piece ends up as a tour of the analysis rather than a claim.
**Depends on:** `docs/phase-2-findings.md` consolidated record; `docs/phase-3-brief.md` §1.
**Notes:** Proposes a **different load-bearing claim** from the brief's sketch — that the methodological choices moved the answer more than the retailers did, evidenced by four independent measurements — and records the case for that substitution rather than making it silently. It also corrects a factual error in the brief's sketch, which joined the 84.61% "no consistent cheaper vendor" figure (Metro vs Save-On-Foods) to the Walmart claim, where the real figure is ~50%. Carries an explicit "what would make me withdraw this thesis" section, because a thesis that cannot be abandoned is not a draft.

### docs/writeup.md
**Purpose:** The Phase 3 written piece — the argument, for a reader who will never open the repo.
**Breaks if removed:** The results stay locked in a 1,900-line findings document that only a technical reader will finish, and the project has no public artefact.
**Depends on:** `docs/phase-2-findings.md` for every figure; `docs/phase-3-thesis.md` for the argument it makes; `analysis/phase2/*.sql`, which it links per claim.
**Notes:** Written against the "what must never be said" list in the findings, which is binding — no "cheapest supermarket" claim, no accusation of dishonesty, no cross-vendor promotion ranking, no freeze-compliance figure, nothing national. Every headline claim carries its qualifier **inside the sentence** rather than in a footnote, because a qualifier a reader can skip is a qualifier that will be skipped. The Walmart section explicitly closes the nihilist reading — a result that survives its own measurement choices is a different object from one that has never been tested — rather than leaving the reader to infer it. Method results are deliberately absent; they live in `method-note.md` so the piece is about grocery prices rather than about us.

### docs/method-note.md
**Purpose:** The companion note evidencing that the writeup's numbers are trustworthy: the seven controls, and four occasions where those controls caught our own errors.
**Breaks if removed:** The writeup's central claim — that measurement choices dominate — loses its own foundation, since a reader has no way to check that *our* measurements were controlled.
**Depends on:** `docs/phase-2-findings.md`, `docs/phase-1-findings.md`, and the check scripts it links.
**Notes:** Deliberately leads with the failures rather than the controls. A reader deciding whether to believe an analysis is better served by its error rate than by its test count, and the four described here — a pooled comparison overturned three separate times by one control, a figure that moved 614 between runs, two runs that crashed identically and passed a byte-comparison, and a number whose provenance is permanently lost — are the strongest evidence in the repository that the rest was checked.

### docs/retention-design.md
**Purpose:** Proposes a two-tier snapshot scheme — full archives at low cadence for the public mirror, plus a slim per-product metadata delta at high cadence for shrinkflation detection. For decision before Phase 2.
**Breaks if removed:** The retention cadence gets decided on the cost of full archives (1.38 GB each), which prices the wrong artifact and makes weekly observation look impossible when it costs 420 MB a year.
**Depends on:** Phase 0 D3 (shrinkflation needs snapshot comparison), Phase 1 §1.3 (what actually changes between publications), §3.5 (the owned key the deltas join on).
**Notes:** The 8.09 MB delta size is measured against the real 187,028-row catalogue, not estimated. Deliberately omits the price series — prices are append-only, so a delta of them would restore most of the 906 MB and defeat the point.

### scripts/compact_db.py
**Purpose:** Rewrites an analysis DuckDB into a fresh file to reclaim dead pages. DuckDB does not reclaim space on `CREATE OR REPLACE TABLE`, and repeated model rebuilds had left `hammer.duckdb` at 5.74 GB with 43% free blocks.
**Breaks if removed:** The database grows without bound across rebuilds. Recovered 2.55 GB on first use.
**Depends on:** An existing analysis database.
**Notes:** Copies table by table straight out of the old file rather than re-running the loader — the loader path extracts a 4.3 GB SQLite intermediate, which needs more free space than a nearly-full disk has. Verifies row counts per table and only deletes the original after the new file is complete, so a failure leaves the original untouched. **It also recreates the parsing macros from `models/*_macros.sql`**, because a table-by-table copy does not carry them: DuckDB persists `CREATE MACRO` in the catalog, but this copies BASE TABLEs only. Losing them is silent until something needs one, and then it misreports itself — `dbt test` fails its on-run-start probe with "Scalar Function with name p_offer_type does not exist", which reads like a dbt problem and is not one.

### dbt/
**Purpose:** The dbt project: a `dbt_project.yml`, a `profiles.yml` with three targets (the snapshot-1 database, the snapshot-2 database, and a throwaway fixture), the staging and intermediate model wrappers, `schema.yml` contracts, and the singular tests under `dbt/tests/`. This is the test framework Phase 1 Section 5 exists to build, and CLAUDE.md's committed modelling layer.
**Breaks if removed:** Every contract the models claim — uniqueness on the owned key, `offer_type` and match-tier domains, the price-to-product relationship, and the row-count reconciliations — reverts to a comment in a SQL file. The failure modes those tests catch (silent row loss, a multibuy stripped to its total, a cents-form read as dollars, junk brand laundered into `national_brand`, a fuzzy match laundered into a headline number) all return to being caught by nobody.
**Depends on:** `dbt-duckdb`, a database built by `scripts/build_models.py`. Tests are run with `dbt test`; `dbt run` is NOT the build path — see the note below.
**Notes:** A **directory entry** — the tests are numerous and uniform in purpose, and the findings document indexes each one by name at the point its guarantee is claimed. Two non-obvious things. **(1) The model bodies here are a second copy of `models/*.sql`, not a shared one.** dbt cannot include a plain `.sql` file and the plain path has no Jinja renderer, so one file cannot serve both; the duplication is stated in `dbt_project.yml` and made safe by `scripts/check_model_parity.py` rather than wished away. **(2) `dbt run` is deliberately not part of the workflow.** `scripts/build_models.py` owns the build, because it is what `verify_reproducible.py` and the `_build_stamp` are written against; running `dbt run` would rebuild the same tables by a second path and put the two out of step. dbt's job here is `dbt test`. The `on-run-start` hook asserts the DuckDB parsing macros are loaded rather than redeclaring them in Jinja — a second macro definition could drift from the one every non-dbt tool uses.

### scripts/check_model_parity.py
**Purpose:** Fails if the model bodies under `models/` and their dbt wrappers under `dbt/models/` have diverged. Normalises away what is *supposed* to differ (comments, `{{ config }}`, and the source references dbt resolves through its graph) and requires the rest to match exactly.
**Breaks if removed:** The duplication between the two build paths becomes unmanaged. A parse rule fixed in one copy and not the other would make every number ambiguous about which definition produced it — the same class of failure as the stale-table incident in `phase-1-findings.md` §3.8, where a build reported success while the data underneath meant something else.
**Depends on:** `models/*.sql`, `dbt/models/**/*.sql`. Standard library only.
**Notes:** Exists because `dbt_project.yml` originally claimed dbt did not own a second copy. It does. Correcting the claim was not enough — the check is what makes it safe. Demonstrated to fail: replacing `p_min_qty(r.current_price)` with a literal `1` in the dbt copy produces exit 1 and a word-level diff naming both files.

### scripts/test_dbt_contracts.py
**Purpose:** Proves every dbt test fails when it should (brief 5.3). Builds a small fixture database whose rows satisfy every contract, then for each test in turn rebuilds it, injects one violation aimed at that test, and requires that test to fail. Includes a control asserting the clean fixture passes every test.
**Breaks if removed:** The test suite becomes an untested assertion — the brief's standard is that a test that has never failed has not been tested, and a suite that failed on everything would otherwise score perfectly.
**Depends on:** `dbt-duckdb`, `models/*.sql` and `models/*macros.sql` (the fixture is built from the same committed SQL the real build uses), the `fixture` target in `dbt/profiles.yml`.
**Notes:** Deliberately does **not** run against the real database. Mutating a 71.8M-row materialisation to test a test would destroy the exact reproducibility property `verify_reproducible.py` exists to guarantee, and rebuilding it costs the better part of an hour. The fixture is built from the committed model SQL rather than from hand-written expected output, so a model gaining a column a test depends on fails loudly here instead of silently skipping the test. `src_rowid` is assigned by `row_number()` because `rowid` is not stable on a `VALUES`-built table. Its first run earned its keep immediately: the control case failed, and the cause was a real defect in the owned key rather than a fixture problem (see `phase-1-findings.md` §5.1).

### scripts/run_dbt_tests.py
**Purpose:** Runs the dbt test suite against both snapshot databases and reports the results as counts.
**Breaks if removed:** `dbt test` still works by hand, but two things it exists to prevent come back. It resolves the database paths to absolute values, and it prints "N of M tests passed" rather than a percentage.
**Depends on:** `dbt-duckdb`, `dbt/`, and a database built by `scripts/build_models.py`.
**Notes:** The absolute-path job is not defensive programming — it is a fix for a real failure. dbt resolves `path:` in `profiles.yml` against the **current working directory**, not against the profile, so the original `../hammer.duckdb` pointed one level above the repo when dbt was run from the repo root; DuckDB created an empty database there and dbt reported a missing-macro catalog error, which looks nothing like the cause. The dangerous half is the other outcome: a suite that passes against an empty database. The counts rule comes from brief 5.4 and CLAUDE.md honesty rule 8 ("report a pass rate only for tests that exist") — the number is scoped to the tests that exist and is never a pass rate for the phase.

### scripts/check_determinism.py
**Purpose:** Flags SQL that can return a different answer on the same data — `any_value`/`first`/`last`/`arg_min`/`arg_max` over a group not proven unique, ranking functions whose `ORDER BY` may not be a total order (or is absent entirely), `LIMIT` without `ORDER BY`, and `string_agg` without `ORDER BY`. Each hazard must either be made deterministic or carry an adjacent `-- determinism-ok: <reason>` annotation.
**Breaks if removed:** The project's only *preventive* control against its most-repeated defect class returns to being detective-only. "Reproducible twice" (honesty rule 4) catches this after the fact and only if someone re-runs; this catches it before the number exists.
**Depends on:** `analysis/`, `models/`, `dbt/`. Standard library only.
**Notes:** Written after the **third** incident of the same class — a 64-bit hash collision moving a D2 count by 6, an `any_value()` moving a published figure by 614 across three runs, and then the fix for that second one partitioning by `(key, date)`, which is not the grain because one product appears many times a day with conflicting prices (Phase 0 B6). The annotation is deliberately a *claim about the data* rather than a suppression: it states why the group is unique or the order total, next to the code, where a reviewer can check it. A ranking function with **no** `ORDER BY` is the one case an annotation cannot silence — no fact about the data can make it deterministic. A justification under three words is rejected, so `determinism-ok: fine` does not pass. It found 44 hazards on first run: 16 were made deterministic for free (`min()` instead of `any_value()` on display columns, `ORDER BY` added to `string_agg`), 28 were justified, and one — `P2_7`'s `any_value` over `(key, basis, date)` — was a real latent defect of exactly the kind that had already bitten twice.

### scripts/test_check_determinism.py
**Purpose:** Proves `check_determinism.py` fails when it should. Eight cases, including two controls asserting the repo is clean before and after.
**Breaks if removed:** The lint becomes an untested assertion — the same standard `test_check_schema.py` and `test_dbt_contracts.py` are held to.
**Depends on:** `scripts/check_determinism.py`.
**Notes:** The case worth reading is `row_number_without_order_by_cannot_be_annotated_away`: it writes a probe carrying a confident-sounding `determinism-ok` annotation and asserts the check **still** fails. An escape hatch that can silence a construct with no correct form is not an escape hatch, it is a hole. The probe file is written into a scanned directory and removed in a `finally`, and the trailing control case would catch it if it were ever left behind.

### docs/phase-2-findings.md
**Purpose:** The Phase 2 deliverable. Section 1 is the exclusion ledger and bias audit, which by design completes *before* any finding is computed.
**Breaks if removed:** The bias verdicts disappear, and with them the reason D2 must be framed the way it is. The ledger is also the only place the three exclusion classes are counted together with their overlaps.
**Depends on:** `analysis/phase2/`, the Phase 1 models, `docs/phase-2-brief.md`.
**Notes:** Opens with a **consolidated record** — the three results with their qualifiers inline, every withdrawal with its reason, the exclusion ledger, the 2A bracket, and a "what must never be said" list. That section is what Phase 3 writes from; the sections beneath it are the evidence. Every section carries a build stamp (honesty rule 5). §1's headline is that one of the three exclusions **is** biased rather than merely large: orphaning removes 26.766% of Metro's 2024 D2 sale events against 0.409% of its 2025 events, which constrains what Section 2 is allowed to plot. It also records a correction to its own method — the pooled "orphans are 1.70× sale-enriched" figure is largely a Metro composition artifact and falls to 1.22× once vendor is controlled for, which is the Phase 0 F1 mistake caught before publication rather than after. §1.3 documents a defect the determinism lint could not catch and running twice did.

### analysis/phase2/
**Purpose:** Numbered queries behind every Phase 2 number, same rule as the earlier phases: no figure exists without a committed query that regenerates it.
**Breaks if removed:** Every number in `docs/phase-2-findings.md` becomes unverifiable.
**Depends on:** `hammer.duckdb` with the Phase 1 models built.
**Notes:** `Q1`/`Q1b` are the exclusion ledger and bias audit, and they run **before** any finding on purpose — Phase 0's F1 asked the bias question on the wrong axis and got a categorically wrong answer, which was cheap only because nothing had been published yet. `Q1b` exists as a separate file because its whole job is the *control* for `Q1`'s headline: the pooled orphan sale-enrichment of 1.70× is largely a Metro composition effect, and only a within-vendor comparison separates the two.

### scripts/verify_twice.py
**Purpose:** Runs a query file twice and verifies the two runs both **succeeded** and agree — exit codes, absence of failure markers, matching result-set counts, matching per-statement row counts, an optional non-empty floor, and only then byte-identity.
**Breaks if removed:** The compute-twice check reverts to `diff run1 run2`, which reports agreement whenever **both runs fail the same way**. Two runs that OOM at the same statement truncate identically and pass a diff.
**Depends on:** `scripts/run_query.py`.
**Notes:** Written after Phase 2 §1.3 recorded the near-miss — paired runs that differed only because one had hit an out-of-memory error under contention. That case was caught because the runs differed; the symmetric case, where both crash identically, was invisible. Order matters: byte-identity is checked **last**, because a crashed pair is a more serious finding than a divergent one and should be reported as such rather than as "not identical". `--expect-statements` pins the result-set count so a query that quietly loses a statement fails rather than being certified reproducible.

### scripts/test_verify_twice.py
**Purpose:** Proves `verify_twice.py` fails when it should. Five cases, including a probe forced to OOM deterministically so both runs truncate to identical output.
**Breaks if removed:** The hardened check becomes an untested assertion, held to a lower standard than `check_schema`, `check_determinism` and the dbt contracts.
**Depends on:** `scripts/verify_twice.py`.
**Notes:** The case worth reading is `both_runs_failing_identically_is_NOT_agreement` — a plain `diff` passes that probe and the checker must not. The non-determinism probe uses 200 rows rather than 3, because `ORDER BY random()` over three values repeats an order often enough to make the test for flakiness itself flaky.

### dashboard/
**Purpose:** The static single-page dashboard and its pre-aggregated JSON. No backend, no build step — open `dashboard/index.html` over HTTP.
**Breaks if removed:** The argument loses its visual half; the exclusion ledger and the store-brand blind spot in particular are far more legible as charts than as prose.
**Depends on:** `analysis/phase3/D1_dashboard_extract.sql`, which writes every file under `dashboard/data/`.
**Notes:** A **directory entry** — `index.html` plus six generated JSON files. Three deliberate constraints. **(1) There is no basket lookup**, and the page says why on the page: a shopper typing a list and getting "Walmart is cheapest" is exactly the claim the findings forbid. **(2) Every chart carries its n and its qualifier on the chart itself**, not in a caption, because a caption is skippable. **(3) The unavailable comparison is a panel, not an omission** — the cross-chain promotion ranking gets its own bordered callout explaining that a struck-out price does not mean the same thing at every chain. The JSON is regenerated by re-running the extract; nothing is hand-edited, so a figure cannot drift from the analysis.

### analysis/phase3/
**Purpose:** The query that produces the dashboard's data. Same rule as the earlier phases: no figure exists without a committed query that regenerates it.
**Breaks if removed:** `dashboard/data/` becomes unreproducible hand-waving.
**Depends on:** `hammer.duckdb` with the Phase 1 models built.
**Notes:** Exports **two basket counts, both labelled** — 3,190 barcodes for the three-chain comparison and 3,477 for the full four-chain basket — because they differ and a dashboard quoting one while the writeup quotes the other would be a silent contradiction. It also emits a `testable` flag on the flag-corroboration export: Metro and Galleria carry no promotional text on any row, so their corroboration rate computes as 0.0, which on a chart would read as "their struck-out prices are never confirmed" — a claim about those chains rather than about a missing field. The flag forces the page to print "cannot be checked" instead. Deliberately exports **no per-product prices**, so nothing here could be joined back into a shopping tool.

### analysis/phase4/
**Purpose:** The five queries behind the refresh-cadence measurement, plus `E1_tool_extract.sql`, which builds the tool's static data extract — day-of-week change distribution, price-hold spells, per-chain coverage and absence, staleness by data age and by refresh day, and the same staleness recomputed on the exact basket the tool ships.
**Breaks if removed:** The refresh schedule reverts to an assumption. The brief's whole demand for Section 1 was that the cadence be derived rather than picked, and these files are the derivation.
**Depends on:** `hammer.duckdb` with the Phase 1 models built; `int_upc_match` for the basket definition in R3/R4/R5.
**Notes:** Two of these carry corrections that are left visible on purpose. **R1 result 5 is withdrawn in place** — it divided by consecutive-observation pairs with a gap of at most k days, which on a near-daily dataset is ~97% one-day pairs, so it re-measured the one-day rate k times and understated 7-day staleness by 6.5×; R3 replaces it with a forward-looking measure and says so in its header. **R3 statement 6 carries a note about crashing identically on both runs** with byte-identical output, which `diff` would have called agreement — the second incident of that class, and the reason `verify_twice.py` asserts successful completion before it compares bytes. R5 rebuilds the 3,190-barcode basket independently rather than importing it, so the findings and the dashboard extract cannot silently drift apart; it exists because the tool's own basket turned out ~1 pp more volatile than the wider reliable set, and the narrower, worse number is the one the interface has to print.

### scripts/check_extract.py
**Purpose:** The deploy gate. The last thing between a rebuilt extract and a live site; exit 1 means nothing deploys and the previous site stays live.
**Breaks if removed:** The Section 2 constraints are enforced when the extract is built, and the render test enforces them on a laptop, but nothing enforces them at deploy time. A thin, stale or dishonest extract would ship under a fresh date.
**Depends on:** `tool/data/*.json`.
**Notes:** Checks **shape and floors, not remembered values**, because a refresh legitimately changes every count and a gate that fails weekly for correct data is a gate someone switches off. Refuses a pooled staleness figure, a staleness curve that falls as data ages (the shape of the withdrawn R1 defect), a figure on an unmeasured age, a cheapest verdict with fewer than two chains, a chain dropped without a reason, a raw vendor code, promotional text in the brand field, and an extract older than 21 days.

### scripts/test_check_extract.py
**Purpose:** Proves `check_extract.py` refuses what it must: each case breaks one promise in the real extract and asserts the gate says no, and names why.
**Breaks if removed:** The deploy gate becomes an untested assertion, which on this project means an unverified one.
**Depends on:** `scripts/check_extract.py`, `tool/data/`.
**Notes:** Includes two cases that must **not** fail: the real extract, and a real brand that merely contains "save" (LIFESAVERS). A check too blunt to pass real data gets disabled, so false positives are tested as seriously as misses.

### scripts/refresh.py
**Purpose:** The weekly refresh (brief section 4): probe upstream, fetch, gate on schema, rebuild, run every standing check, rebuild the extract twice, gate it. It never deploys.
**Breaks if removed:** The cadence derived in findings section 1.4 has nothing to run it, and a refresh becomes a sequence of remembered manual steps.
**Depends on:** every pipeline script it calls; `node` for the render gate.
**Notes:** Runs **locally or on a self-hosted runner, not on hosted CI**. The working set is about 10 GB against about 14 GB of runner disk. `--verify-steps` exists because a dry run printed two commands with wrong flags (`check_model_parity.py` takes no arguments, `run_dbt_tests.py` takes `--target`) and a dry run cannot catch that; it asks each script's own parser instead.

### scripts/verify_deploy.py
**Purpose:** Verifies the **live** site over HTTP: assets load, JSON parses, the extract is within its age limit, the required disclosures are in the served HTML, and no external script, style, frame or image is loaded.
**Breaks if removed:** Every other check runs against the working tree, so a deploy serving a stale or broken extract would pass all of them and still be wrong for every visitor.
**Depends on:** a reachable deployed URL.
**Notes:** Its first run found the attribution and scope disclosures existed only after JavaScript ran and were absent from the served HTML; they are now static. The external-resource check is how the no-trackers non-goal is enforced rather than promised.

### .github/workflows/
**Purpose:** `deploy.yml` gates and deploys the committed extract to GitHub Pages, then verifies the live site; `probe.yml` checks upstream daily and opens or updates an issue when a refresh is due or the served extract is past its limit.
**Breaks if removed:** Deployment becomes manual, and a stopped refresh becomes silent, which is the failure brief 4.5 names.
**Depends on:** `scripts/check_extract.py`, `scripts/test_tool_render.js`, `scripts/test_check_extract.py`, `scripts/verify_deploy.py`, `scripts/refresh.py --probe-only`; GitHub Pages enabled with source "GitHub Actions".
**Notes:** A **directory entry**. CI deliberately does only the light half: the full rebuild does not fit a hosted runner. **Neither workflow has run yet**; both parse and every script they call has been run by hand, which is not the same as the workflow having executed.

### scripts/test_tool_render.js
**Purpose:** Renders every product in the extract through the tool's own card functions and asserts the honesty rules hold on the rendered **output**, not just on the input data.
**Breaks if removed:** The Section 2 constraints are enforced in the extract, but the interface can still betray them at render time — printing a bare "cheapest", showing a 200-day-old price with no warning, dropping a chain that has no recent price, or leaking a raw vendor code. Those are properties of the output and only an output check catches them.
**Depends on:** `tool/index.html`, `tool/data/*.json`, Node.
**Notes:** Pulls the page's script **out of `index.html` itself** rather than keeping a copy, so the test cannot drift from what ships. It has already caught three real defects: a landing state that explained the store-brand limit without using the words brief §3.3 requires, a comparison sentence printing the raw key `SaveOnFoods`, and three chains joined as "A and B and C".

### tool/
**Purpose:** The static price-lookup tool — `index.html` plus the `data/` extract (`meta.json`, `products.json`, `history.json`) generated by `analysis/phase4/E1_tool_extract.sql`.
**Breaks if removed:** The tool has no backend, so these files are the tool's entire data layer. Nothing is computed in the browser.
**Depends on:** `analysis/phase4/E1_tool_extract.sql`, `hammer.duckdb` with the Phase 1 models built.
**Notes:** A **directory entry** — one hand-written HTML file and three generated JSON files. The JSON is never hand-edited, so a figure cannot drift from the analysis. The interface is built **unavailable-first**: the "nothing to compare" and "only one chain" states were written before the comparison state, because 1,141 of 2,921 products land in them, and the one-chain state carries copy whose only job is to stop a lone price reading as a verdict. `staleness_exceeds_measured` renders as a **bordered warning naming the age**, never a dash. The extract is where the tool's honesty is enforced rather than the interface: there is **no pooled staleness figure anywhere in it** (pooling understates Save-On-Foods by over 9 pp), every product carries a `comparison` object naming exactly which chains were compared and which were not with dates and reasons, and per-chain observed date and staleness are stored fields rather than something the page derives. Staleness beyond 14 days is **null with an explicit flag**, not the 14-day figure stretched to fit — 1,137 of 6,093 offers are in that state. 254.7 KB gzipped in total, so history did not have to be shortened.

### docs/RESUME.md
**Purpose:** The orientation procedure for anyone picking the project up without prior context — a new session, a different agent, or a human returning after a break. What to read, in what order, what to verify, what to report, and when to stop.
**Breaks if removed:** Every future session starts by reconstructing the project from whatever it happens to read first, which is how a summary quietly becomes the source of truth instead of the repository.
**Depends on:** `CLAUDE.md`, `docs/FILES.md`, `docs/phase-2-findings.md`, `.handoff/latest_handoff.md`, the phase briefs.
**Notes:** Its load-bearing line is that the **repository wins over any document**, including the handoff note and anything another model said. Step 2 is a list of checks to run rather than trust, and Step 3 requires reporting **anything that contradicts the handoff note** — the contradiction is the point, not the summary.

### AGENTS.md
**Purpose:** Entry point for non-Claude agents (Codex reads it by convention). Points at `docs/RESUME.md`, then the handoff note, then requires a state report before any work.
**Breaks if removed:** An agent that does not read `CLAUDE.md` by convention starts work with no rules and no orientation.
**Depends on:** `docs/RESUME.md`, `CLAUDE.md`, `.handoff/latest_handoff.md`.
**Notes:** Deliberately **does not restate CLAUDE.md's rules** — it names three that arriving agents break most often (counts as counts, volunteer bad news, never work around a wrong instruction) and points at `CLAUDE.md` for the rules themselves. A second copy of a rule drifts from the first, and the copy is always the one someone reads.

### .handoff/
**Purpose:** The session-handoff mechanism. `context_template.md` is the shape of the note, `latest_handoff.md` is the current one, `invoke_codex.sh` hands the project to Codex with the checks that matter run first.
**Breaks if removed:** Work in progress at the end of a session has to be reconstructed from the diff, and the distinction between "blocked on a person" and "not started" is lost — the next agent conflates them.
**Depends on:** `docs/RESUME.md`; `CLAUDE.md`, "Context and handoff", which is the rule the directory implements.
**Notes:** A **directory entry**. The note records **where work stopped, never what is true** — ground truth is `CLAUDE.md`, the findings docs and git history — and it carries an "anything the next agent should distrust" section, which is the reason it is worth reading. `invoke_codex.sh` refuses to run without a note, and warns and asks for confirmation when the tree is dirty or the note is older than the last commit: uncommitted work and a stale note are the two things a handoff actually loses, and neither is visible to the agent picking up.

### docs/phase-4-brief.md
**Purpose:** The Phase 4 assignment — a public per-product price lookup across Metro, Save-On-Foods and Walmart, built on the one comparison the findings support.
**Breaks if removed:** The scope discipline loses its source. The brief is what forbids a basket, a store ranking and a store-brand comparison, and what requires the four disclosures to sit on the screen rather than behind a link.
**Depends on:** `docs/phase-2-findings.md` "what must never be said", which it declares binding; `docs/writeup.md`.
**Notes:** §1 forbids picking a refresh schedule before measuring one, which is why `docs/phase-4-findings.md` exists and why the schedule changed shape once the numbers arrived. Its non-goal on **ads, ad-network scripts and third-party trackers is deferred, not declined**: the licence request to the maintainer stated the project was non-commercial with no ads and permission was granted on that basis, so nothing of that kind ships without a written answer from the maintainer first.

### docs/phase-4-findings.md
**Purpose:** The measured answer to "how often should this refresh, and how stale does that leave it" — day-of-week distribution, price-hold duration, publication lag, coverage and absence, staleness by interval and by refresh day, and the recommendation derived from them.
**Breaks if removed:** Sections 2 through 5 lose their input. The extract's history depth, the interface's staleness disclosure and the refresh automation all cite numbers that exist only here.
**Depends on:** `analysis/phase4/`, re-run with `scripts/verify_twice.py` (logs are gitignored and regenerable).
**Notes:** Carries one build stamp for the whole document, per honesty rule 5. Its central result is not the one expected: a daily refresh beats a correctly-timed weekly one by **under 2 percentage points**, because the Thursday reprice is published after the day it describes and no refresh frequency recovers a blind spot created by publication lag. Records **two withdrawn numbers of its own** in "What §1 changed about the plan", and separates **scheduled staleness** (bounded, 8 days, printable as a number) from **absence staleness** (unbounded — Walmart was missing 49 consecutive days — and disclosable only as a per-chain observed date).

### scripts/check_layering.py
**Purpose:** Enforces that `product_id` appears nowhere below the staging layer — the rule that keeps the announced upstream `raw.product_id` type change an ingest-layer event.
**Breaks if removed:** The rule reverts to discipline. A downstream model could start keying on `product_id`, and the breaking change would then propagate into every mart built on it.
**Depends on:** `models/*.sql` naming convention (`stg_` = staging, `int_`/`mart_` = below).
**Notes:** Strips SQL comments before matching, so documenting the rule does not violate it. Demonstrated to fail: injecting `sp.product_id` into `int_upc_match.sql` produces a non-zero exit naming the file and line.

### scripts/verify_reproducible.py
**Purpose:** Asserts that the materialised `stg_price` is a cache rather than an artifact — every value a pure function of the immutable snapshot plus the committed SQL.
**Breaks if removed:** The 2.1 GB materialisation becomes a thing you have to trust rather than something you can check, and a stale build could diverge from its definition unnoticed.
**Depends on:** `models/`, a built snapshot database.
**Notes:** Attaches the database READ-ONLY and creates its macros in a separate in-memory catalog — a verifier that can modify what it verifies is not a verifier. Compares an order-independent checksum per column, so it catches content drift, not just row counts.

### docs/FILES.md
**Purpose:** This manifest, plus the reading order above.
**Breaks if removed:** `scripts/check_manifest.py` exits 2 and the repo loses its drift check.
**Depends on:** The actual contents of the repo.
**Notes:** Must be updated in the same commit as any file addition or removal, or the manifest check fails.

### analysis/phase0/
**Purpose:** One `.sql` file per finding, named `<section><n>_<slug>.sql`. Every number in `docs/phase-0-findings.md` is regenerated by one of these. This is honesty rule #3 made concrete: no number exists only in a chat message.
**Breaks if removed:** The findings document becomes unverifiable assertion. Nothing in it could be reproduced or challenged.
**Depends on:** `hammer.duckdb`, built by `scripts/load_snapshot.py` from a snapshot; run via `scripts/run_query.py`.
**Notes (the non-obvious parts):**
- **A directory entry, not one heading per query.** ~25 files, uniform in purpose; enumerating them individually would add noise without adding information. The findings document is the index — it cites each query by name at the point its number appears.
- Files are numbered by brief section (`A1`, `B4`, `C2`, `D1`, `E8`). Suffixed letters (`A2b`, `B4c`, `D1b`) are follow-ups that exist because the primary query raised a question: `A2b` because the documented transition date looked wrong, `B2b` because `B2`'s clean result turned out to be tautological, `D1b` to separate "vendor missing" from "vendor present but churning".
- Queries define their filters and thresholds in comments, including the arbitrary-looking ones (the 50%-of-trailing-median partial-day rule, the ≥11-digit GTIN floor, the `>= 2024-06-11` full-catalogue cutoff). Those are judgement calls and are meant to be changeable.
- `B6`, `C2`, `C3`, `D1`, `D2`, `D4` aggregate over all 71.8M rows and need `--memory-limit` and `--temp-dir`. They use `min(x) <> max(x)` in place of `count(DISTINCT x)` where possible — same answer, a fraction of the memory.
- The `F*` files are follow-ups run after the first Phase 0 report, each answering a challenge to a stated conclusion rather than a question from the brief: `F1` (does E8 shrink D2? no — but it costs 2.05% downstream), `F2` (are D1's 474 Metro SKUs representative? no — a frozen/packaged slice), `F3` (can private label be separated from national brand? yes for 4 vendors, never for T&T or Galleria), `F4` (is D3 really "impossible"? only for the 86.2% with a sku). `F4` in particular exists because the original claim was too strong.
- `F4` deliberately does **not** test whether a sku is reissued at a new size. That search is quadratic over 161,300 x 25,728 and short numeric skus collide with digits inside product names, so it was abandoned rather than shipped with a bad signal-to-noise ratio. The limitation is written into the query as a comment so it stays visible.
- `G1_publication_lag.sql` is the one query that reads `_snapshot_provenance` rather than the data alone — it needs to know *when the file was published* to separate publication lag from a scrape gap, and CLAUDE.md requires those never be conflated.
- **DuckDB's `~` is `regexp_full_match`, not a partial match.** Anchored patterns like `'^0+$'` are fine with `~`; unanchored keyword alternations must use `regexp_matches()`. This bit `D4` during the phase and the fix is commented in place.

### scripts/fetch_snapshot.py
**Purpose:** Downloads both dataset distributions into `data/snapshots/<utc-stamp>/`, streaming to disk while hashing, and writes `manifest.json` with the URL, start/finish timestamps, byte size and sha256 of each archive, plus the upstream `hammer-lastupdated.txt` value captured at download time.
**Breaks if removed:** No reproducible way to acquire a snapshot with provenance. Locked decision #2 (snapshot immutability with timestamp and sha256) becomes a manual, forgettable step.
**Depends on:** Network access to `jacobfilipp.com`. Standard library only.
**Notes:** `--help` and `--dry-run` are safe: before argparse was added, the script ignored argv entirely, so any argument — `--help` included — fell through to creating a snapshot directory and opening a network connection. That was found by following the README's reproduce steps literally rather than reading them. Its User-Agent identifies the project by **repository URL**, never by a personal address — a contact point is the courteous thing for an automated fetcher to carry, but an email in a public repo is harvested within days, and a repo URL does not go stale when a person changes address. `REPO_URL` is empty until the remote exists, and the UA then carries no contact at all, which is honester than an invented one. Refuses to overwrite an existing snapshot directory and `chmod 0o444`s each archive after download — immutability enforced by the filesystem, not by good intentions. It captures `hammer-lastupdated.txt` *alongside* the download because staleness is only meaningful relative to when the copy was pulled. Archives total ~1.4 GB.

### scripts/load_snapshot.py
**Purpose:** Extracts the SQLite member from a snapshot and copies `product` and `raw` into a fresh DuckDB file, then writes a `_snapshot_provenance` table into that database.
**Breaks if removed:** No path from a downloaded snapshot to a queryable analysis database; every query in `analysis/phase0/` becomes unrunnable.
**Depends on:** `duckdb` (with its `sqlite` extension), a snapshot produced by `fetch_snapshot.py`.
**Notes:** Loads the **SQLite** distribution, not the CSVs, although both are downloaded because the brief asks for both. SQLite carries declared column types and avoids the BOM and quoting variance the upstream notes warn about for the CSVs. It attaches the source `READ_ONLY` and never writes to the snapshot. `_snapshot_provenance` travels inside the analysis DB so a number can always be traced back to the archive hash that produced it. `--workdir` matters: the extracted SQLite is ~4.3 GB and should not land on a small volume — it is scratch and can be deleted, since the archive is retained.

### scripts/run_query.py
**Purpose:** Runs a saved `.sql` file against the analysis DuckDB read-only and prints the result. Supports multi-statement files, `--all` to print every result set, `--csv` export, and `--memory-limit` / `--temp-dir` for out-of-core aggregations.
**Breaks if removed:** Every query still runs by hand, but the cheap path from "committed SQL file" to "number in a document" disappears — and honesty rule #3 depends on that path staying cheap enough that nobody shortcuts it.
**Depends on:** `duckdb`, `pandas` (via DuckDB's `fetchdf`), `hammer.duckdb`.
**Notes:** Opens the database **read-only**, so no query can mutate the analysis DB; `TEMP` tables still work, which is what the heavier queries use. It has its own semicolon splitter that respects string literals and comments, because DuckDB's Python API takes one statement at a time and the query files are deliberately multi-statement (setup macros, then the reported result). Defaults to `preserve_insertion_order=false` and a spill directory — without those, the 71M-row aggregations die with an allocation failure rather than spilling.

### scripts/check_manifest.py
**Purpose:** Compares `git ls-files` against the `### path` headings in `docs/FILES.md`. Reports files present in the repo but missing from the manifest, manifest entries pointing at nothing, and duplicate entries. Exits non-zero on any drift.
**Breaks if removed:** `docs/FILES.md` silently rots. Undocumented files accumulate and stale entries persist, which is exactly the failure this project's honesty rules are trying to prevent at the documentation layer.
**Depends on:** `git` on PATH, `docs/FILES.md`. No third-party dependencies.
**Notes:** Uses `git ls-files`, so it sees the **index** — a new file must be at least `git add`ed to be checked; untracked files are invisible to it by design, since gitignored artifacts (snapshots, `*.duckdb`) must not need manifest entries. Directory entries (trailing `/`) cover everything beneath them and are considered stale only if nothing tracked lives under them. Headings that contain a space but no `/` are skipped as prose, so ordinary section headings in this file do not get mistaken for paths. Exit codes: 0 clean, 1 drift, 2 usage/environment error.

### docs/upstream-feedback.md
**Purpose:** Section F deliverable — ergonomics feedback for the Project Hammer maintainer, written to be sent as-is. Eight ranked items, each stating the concrete friction hit during the audit, what it cost, and the smallest upstream change that removes it.
**Breaks if removed:** The maintainer asked directly for this and it is a deliverable of the phase. Losing it also loses the ranking rationale — which frictions were expensive versus merely annoying — that will not be obvious from the findings document alone.
**Depends on:** The same queries as `docs/phase-0-findings.md`; every number in it is drawn from that audit.
**Notes:** Carries a dated **status table** recording which earlier items are verified still-present as of the 2026-08-23 extract, so the maintainer can skip anything already fixed — and stating that our newest snapshot is 16 days old, so a recent fix would be invisible to us. Items 10 and 11 (added 2026-09-08) are Phase 2 results: Galleria's catalogue disjointness and the structural private-label blind spot in UPC matching. Deliberately separate from the Section E bug list. E is "this is wrong"; F is "this is not wrong but it is expensive to consume". Mixing them would bury the correctness bugs. It carries the required attribution wording, includes a "what is already good" section so the feedback is not purely negative, and states one point where we disagree with our own suggestion (§7: deduplicating upstream would destroy real information, so we prefer a `listing_context` column even though it is more work for the maintainer).

### config/expected_schema.json
**Purpose:** The schema contract. Records the column names, types and ordinal positions of `raw` and `product` as they are today, including the **current** `VARCHAR` type of `raw.product_id`.
**Breaks if removed:** `scripts/check_schema.py` exits 2 and ingest loses its only guard against a silent upstream schema change.
**Depends on:** A loaded snapshot to have been captured from; consumed by `scripts/check_schema.py`.
**Notes:** Exists because the maintainer has announced that `raw.product_id` will change from string to number. The type recorded here is the current one on purpose — this file is a tripwire, not a wish. When the change lands it is updated **deliberately, in its own commit, with a note**, never as a side effect of making a failing run pass. The `_comment` array at the top of the file says this too, so the warning travels with the file rather than living only here.

### scripts/check_schema.py
**Purpose:** Validates a loaded snapshot against `config/expected_schema.json`. Reports missing columns, unexpected columns, type mismatches, position drift and absent tables. Exits non-zero on any difference.
**Breaks if removed:** An upstream schema change lands silently. The announced `product_id` string→number change would flow into the analysis layer as a type surprise rather than a loud ingest failure.
**Depends on:** `duckdb`, `config/expected_schema.json`, a database built by `load_snapshot.py`.
**Notes:** CLAUDE.md requires ingest to *fail loudly* and never cast, coerce, or infer — so this deliberately has no `--fix` and no auto-update mode. The failure message says what to do (update the expected-schema file in its own commit) rather than offering to do it. Position drift is opt-in via `--strict-position`, because a reordered column is not by itself a correctness problem and defaulting to failure there would train people to ignore the check.

### scripts/test_check_schema.py
**Purpose:** Proves `check_schema.py` actually fails when the schema differs. Six cases, including the announced `product_id` string→number change. Exits non-zero if any case does not behave as expected.
**Breaks if removed:** The schema check becomes an untested assertion. The brief's point stands: a check that has never failed has not been tested.
**Depends on:** `scripts/check_schema.py`, `config/expected_schema.json`, `hammer.duckdb`.
**Notes:** Mutates a **copy of the expected-schema file**, not the database — equivalent to the database having changed in the opposite direction, and it avoids building a corrupted 880 MB DuckDB file for each case. The real database is opened read-only and never touched. Includes a control case asserting the unmodified schema still passes; without it, a checker that failed on everything would score a perfect 5 of 5. This is the only real test suite in the repo, which is why the findings document says "6 of 6" refers to this file alone and is not a pass rate for the phase.

### .gitignore
**Purpose:** Excludes dataset snapshots, DuckDB databases, the DuckDB spill directory, Python bytecode and OS cruft.
**Breaks if removed:** ~1.4 GB of archives and an ~880 MB DuckDB file get committed, and the repo starts redistributing a dataset that is not ours to redistribute.
**Depends on:** Nothing.
**Notes:** `data/snapshots/` is ignored for **size, not licence** — the maintainer has confirmed redistribution is permitted and encouraged, but ~1.4 GB of binary archives is the wrong payload for git history. If we publish a mirror it should go via release assets or object storage, which is a Phase 1+ decision and is flagged as such rather than silently settled here. Provenance is preserved in `docs/phase-0-findings.md` §0 and in each snapshot's `manifest.json`, so a snapshot is identifiable without being stored in git. `.duckdb_spill/` is ignored because heavy queries write multi-GB temp files into it.
