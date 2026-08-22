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

**Phase 0 — data reconnaissance. Complete.** Nothing is built yet: no pipeline, no dbt
models, no schema design. Phase 0 answered questions about the data and produced a
go/no-go verdict on each proposed analysis.

- [docs/phase-0-findings.md](docs/phase-0-findings.md) — the deliverable. Start with §1
  (the headline number), §2 (bad news), and §8 (what the data can and cannot support).
- [docs/upstream-feedback.md](docs/upstream-feedback.md) — ergonomics feedback for the
  dataset maintainer, written to be sent as-is.

## Layout

```
CLAUDE.md                       project rules: locked decisions, honesty rules
README.md                       this file
config/
  expected_schema.json          asserted column names + types of raw and product
docs/
  phase-0-brief.md              the Phase 0 assignment
  phase-0-findings.md           the Phase 0 deliverable
  upstream-feedback.md          ergonomics feedback for the maintainer
  FILES.md                      file manifest (what each file is for)
analysis/phase0/                one .sql per finding; every number traces to one of these
scripts/
  fetch_snapshot.py             download a snapshot + record sha256/timestamps
  load_snapshot.py              load a snapshot into DuckDB (read-only over the source)
  run_query.py                  run a saved query against the analysis DB
  check_schema.py               assert the loaded schema matches config/
  test_check_schema.py          prove check_schema.py fails when it should
  check_manifest.py             verify docs/FILES.md matches the repo
data/snapshots/                 downloaded archives (gitignored for size, not licence)
```

## Reproducing Phase 0

```bash
python scripts/fetch_snapshot.py                       # writes data/snapshots/<utc-stamp>/
python scripts/load_snapshot.py --workdir /tmp/hammer  # writes hammer.duckdb (gitignored)
python scripts/check_schema.py                         # MUST pass before any analysis
python scripts/run_query.py analysis/phase0/B4_cross_vendor_upc_overlap.sql --all
```

Queries over the full 71.8M-row table need a memory budget and a spill directory:

```bash
python scripts/run_query.py analysis/phase0/B6_duplicate_rows.sql --all \
  --memory-limit 3GB --temp-dir /tmp/spill
```

Snapshots are immutable: `fetch_snapshot.py` never overwrites one, and archives are stored
read-only. Analysis reads from a snapshot, never from a live download.

## Checks

```bash
python scripts/check_schema.py        # schema drift (catches the announced product_id change)
python scripts/test_check_schema.py   # proves the above actually fails when it should
python scripts/check_manifest.py      # docs/FILES.md vs the repo
```

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
