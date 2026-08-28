# Canadian Grocery Price Analysis

A data-quality and analysis project built on the [Project Hammer](https://projecthammer.org)
dataset — a publicly published time series of Canadian grocery prices scraped from 8 vendor
websites since February 2024.

**The underlying data was sourced from ProjectHammer.org.**

**We are a downstream consumer of a published dataset. This project does not scrape any
grocery vendor.**

## Scope, stated up front

The upstream data is the **"in store pickup" price for one neighbourhood in Toronto**.
Nothing here is a national, provincial, or "Canadian" price. Any number that leaves this
repo carries that qualifier.

## Current status

**Phase 0 — data reconnaissance. Complete.** Answered questions about the data and
produced a go/no-go verdict on each proposed analysis. No findings were built.

**Phase 1 — representation. Complete.** Builds the two things every surviving analysis
depends on: a price you can compute with, and a product identity we own. Still no
findings — that is Phase 2.

- Two snapshots archived with provenance; `(vendor, sku)` measured stable across them.
- **100.000%** of price rows in **both** snapshots resolve to a `unit_price` or an
  explicit `unparsed` verdict — 33 unparsed out of 71.8M / 72.0M.
- An owned `product_key` (md5, **0 collisions** across the union of both snapshots),
  with `raw.product_id` appearing nowhere below staging, enforced mechanically.
- **40 dbt tests, passing on both snapshots; 23 of 23 demonstrated to fail when they
  should.** Counts, not a pass rate.

Documents:

- [docs/phase-0-findings.md](docs/phase-0-findings.md) — start with §1 (the headline
  number), §2 (bad news), §8 (what the data can and cannot support).
- [docs/phase-1-findings.md](docs/phase-1-findings.md) — start with §5.1 (a defect the
  test suite found in our own key) and §5.5 (a published figure that turned out stale).
- [docs/upstream-feedback.md](docs/upstream-feedback.md) — ergonomics feedback for the
  dataset maintainer, written to be sent as-is.
- [docs/retention-design.md](docs/retention-design.md) — snapshot retention, proposed,
  for a decision before Phase 2.

## Layout

```
CLAUDE.md                       project rules: locked decisions, honesty rules
README.md                       this file
config/
  expected_schema.json          asserted column names + types of raw and product
docs/
  phase-0-brief.md              the Phase 0 assignment
  phase-0-findings.md           the Phase 0 deliverable
  phase-1-brief.md              the Phase 1 assignment
  phase-1-findings.md           the Phase 1 deliverable
  retention-design.md           snapshot retention scheme (proposed)
  upstream-feedback.md          ergonomics feedback for the maintainer
  FILES.md                      file manifest (what each file is for)
analysis/phase0/                one .sql per finding; every number traces to one of these
analysis/phase1/                same rule, for Phase 1
models/                         the parsing macros and the staging/intermediate models
dbt/                            the dbt project: contracts and tests (dbt test, not dbt run)
scripts/
  fetch_snapshot.py             download a snapshot + record sha256/timestamps
  load_snapshot.py              load a snapshot into DuckDB (read-only over the source)
  build_models.py               materialise the models; asserts rows in == rows out
  compact_db.py                 reclaim dead pages DuckDB does not free on rebuild
  run_query.py                  run a saved query against the analysis DB
  run_dbt_tests.py              run the dbt suite on both snapshots, report counts
  check_schema.py               assert the loaded schema matches config/
  check_layering.py             assert product_id appears nowhere below staging
  check_model_parity.py         assert the two model build paths have not drifted
  check_manifest.py             verify docs/FILES.md matches the repo
  verify_reproducible.py        assert the materialisation is a cache, not an artifact
  test_check_schema.py          prove check_schema.py fails when it should
  test_dbt_contracts.py         prove every dbt test fails when it should
data/snapshots/                 downloaded archives (gitignored for size, not licence)
```

## Reproducing

```bash
python scripts/fetch_snapshot.py                       # writes data/snapshots/<utc-stamp>/
python scripts/load_snapshot.py --workdir /tmp/hammer  # writes hammer.duckdb (gitignored)
python scripts/check_schema.py                         # MUST pass before any analysis
python scripts/run_query.py analysis/phase0/B4_cross_vendor_upc_overlap.sql --all
```

Phase 1 additionally needs the models built, and a second snapshot:

```bash
python scripts/build_models.py --db hammer.duckdb --materialize table

python scripts/load_snapshot.py 20260824T132829Z --db hammer2.duckdb
python scripts/build_models.py --db hammer2.duckdb --materialize table

python scripts/run_dbt_tests.py                        # 40 tests, both snapshots
```

`build_models.py` owns the build, not `dbt run` — `verify_reproducible.py` and the build
stamp are written against it, and a second build path would put the two out of step. dbt's
job here is `dbt test`.

Queries over the full 71.8M-row table need a memory budget and a spill directory:

```bash
python scripts/run_query.py analysis/phase0/B6_duplicate_rows.sql --all \
  --memory-limit 3GB --temp-dir /tmp/spill
```

Snapshots are immutable: `fetch_snapshot.py` never overwrites one, and archives are stored
read-only. Analysis reads from a snapshot, never from a live download.

## Checks

```bash
python scripts/check_schema.py         # schema drift (catches the announced product_id change)
python scripts/test_check_schema.py    # proves the above actually fails when it should  (6 of 6)
python scripts/check_manifest.py       # docs/FILES.md vs the repo
python scripts/check_layering.py       # product_id must not appear below staging
python scripts/check_model_parity.py   # models/ and dbt/models/ must not have drifted
python scripts/verify_reproducible.py  # the materialisation matches its own definition
python scripts/run_dbt_tests.py        # 40 dbt tests, both snapshots
python scripts/test_dbt_contracts.py   # proves each dbt test fails when it should  (23 of 23)
```

Every one of those numbers is a **count of assertions that exist**, never a pass rate for
a phase (CLAUDE.md honesty rule 6).

`check_schema.py` exists because upstream has announced that `raw.product_id` will change
from a string to a number. Ingest asserts the schema and **fails loudly** — it never
silently casts, coerces, or infers. When the change lands, `config/expected_schema.json`
is updated deliberately, in its own commit, with a note.

## House rules

`CLAUDE.md` is binding, not advisory. The ones that bite hardest in practice:

- **A missing day is not an unchanged price.** No forward-filling across gaps without an
  explicit, named, documented rule.
- **Publication lag is not a data gap.** The date a price was observed and the date we
  obtained the file containing it are two different fields, and a late upload must never
  be reported as missing scrape data.
- **Every published number is reproducible.** If a figure appears in a document, a
  committed `.sql` file regenerates it.
- **Report the denominator.** Every percentage carries its n.

## Data licence and attribution

The maintainer has confirmed that publishing derived analysis and redistributing the
dataset are both permitted, and that redistribution is encouraged.

Required attribution, used here and in every writeup and dashboard footer:

> The underlying data was sourced from ProjectHammer.org

Snapshot archives are gitignored because ~1.4 GB of binaries is the wrong payload for git
history, not because redistribution is restricted. Get your own copy from
[jacobfilipp.com/hammer](https://jacobfilipp.com/hammer/), or run `scripts/fetch_snapshot.py`.
