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
**Notes:** Two statements in it are contradicted by the data and are flagged in `docs/phase-0-findings.md` §2.1 and §2.2 — the small-basket end date (Jul 10/11 vs the actual 2024-06-11) and the claim that `product.id` changes daily. Neither was silently worked around. Its "File manifest (mandatory)" section is what requires this file, and requires `scripts/check_manifest.py` to pass before any phase is reported complete. Its "Upstream volatility" section is what requires `config/expected_schema.json` and `scripts/check_schema.py`.

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

### analysis/phase1/
**Purpose:** Numbered queries behind every Phase 1 number, same rule as `analysis/phase0/`: no figure exists without a committed query that regenerates it.
**Breaks if removed:** Every number in `docs/phase-1-findings.md` becomes unverifiable.
**Depends on:** `hammer.duckdb` and `hammer2.duckdb` (both gitignored, rebuilt via `scripts/load_snapshot.py`). Queries that span snapshots `ATTACH` the second database.
**Notes:** `P1_4b` carries a method note explaining why it uses a multiset diff rather than a join — that is a correction to a real mistake and is left visible on purpose. Cross-snapshot queries assume `hammer2.duckdb` sits in the repo root; rebuild it with `python scripts/load_snapshot.py 20260824T132829Z --db hammer2.duckdb`.

### models/
**Purpose:** The representation layer. `price_parse_macros.sql` holds the price-parsing macros; `stg_price.sql` is the staging model that turns raw price text into a computable unit price for every row.
**Breaks if removed:** Every downstream number reverts to `CAST(current_price AS DOUBLE)`, which silently drops 1.8% of rows concentrated in Metro and Save-On-Foods, and reads `329$` as $329.00 instead of $3.29.
**Depends on:** `raw` and `product` in a loaded snapshot. Built by `scripts/build_models.py`.
**Notes:** `offer_type` and `normalization` are deliberately separate columns — the first describes the commercial offer, the second the encoding repair — so "how many single-unit offers are there?" stays answerable without knowing every quirk. Per-weight prices are rescaled to per-100g/per-100ml for comparability, with the vendor's stated denominator preserved in `price_basis_stated`. Written as a single SELECT so it drops into dbt unchanged when Section 5 needs the test framework.

### scripts/build_models.py
**Purpose:** Materialises the models into a snapshot's DuckDB. Separate from `run_query.py` because it needs write access, and that one is deliberately read-only.
**Breaks if removed:** `stg_price` cannot be built, and nothing downstream has a price to compute with.
**Depends on:** `models/`, a loaded snapshot database.
**Notes:** Asserts row count in == row count out and refuses to continue on a mismatch — silent row loss is the failure mode this catches. Defaults to a view; `--materialize table` trades ~2.1 GB of disk for query speed, which is what the current build uses because the regex parse over 71.8M rows made every downstream query cost minutes.

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
**Notes:** Refuses to overwrite an existing snapshot directory and `chmod 0o444`s each archive after download — immutability enforced by the filesystem, not by good intentions. It captures `hammer-lastupdated.txt` *alongside* the download because staleness is only meaningful relative to when the copy was pulled. Archives total ~1.4 GB.

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
**Notes:** Deliberately separate from the Section E bug list. E is "this is wrong"; F is "this is not wrong but it is expensive to consume". Mixing them would bury the correctness bugs. It carries the required attribution wording, includes a "what is already good" section so the feedback is not purely negative, and states one point where we disagree with our own suggestion (§7: deduplicating upstream would destroy real information, so we prefer a `listing_context` column even though it is more work for the maintainer).

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
