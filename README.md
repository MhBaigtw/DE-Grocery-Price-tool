# Canadian Grocery Price Analysis

A data-quality and analysis project built on the [Project Hammer](https://projecthammer.org)
dataset — a publicly published time series of Canadian grocery prices scraped from 8 vendor
websites since February 2024.

**The underlying data was sourced from ProjectHammer.org.**

**This is a downstream consumer of a published dataset. It does not scrape any
grocery vendor.**

## Scope, stated up front

The upstream data is the **"in store pickup" price for North York, Toronto** — for seven of the eight chains. **Save-On-Foods is priced at a store in Kamloops, BC**, and is never compared against the Toronto chains.
Nothing here is a national, provincial, or "Canadian" price. Any number that leaves this
repo carries that qualifier.

## Start here

**→ [The writeup](docs/writeup.md)** — the argument, for a reader who will never open this
repo. *The hard part of comparing grocery prices isn't getting the prices.*

**→ [The price tool](https://de-grocery-project.netlify.app)** — what one product costs at
Metro and Walmart, in-store pickup in North York, Toronto, across 3,465 national-brand
barcodes. For 44% of them only one store, or neither, has a recent price, and the tool says so
rather than guessing. Its 3,465 products are slightly fewer than the analysis basket's 3,477
barcodes, and not the same set: the tool compares only Metro and Walmart and does not apply the
analysis's stricter matching rule ([findings §7](docs/phase-4-findings.md) explains why).
**Currently offline** while a scope error is corrected ([findings §9](docs/phase-4-findings.md)).
It deploys from Netlify on every push to `main`, and the build refuses to publish an extract
that fails `scripts/check_extract.py`. Locally: serve the repo over HTTP and open
`tool/index.html`.

**→ [The findings](docs/phase-2-findings.md)** — every number, denominator, exclusion and
withdrawal. Opens with a consolidated record.

**→ [The method note](docs/method-note.md)** — how I know the numbers are trustworthy,
starting with the largest error in the project, which none of the checks caught.

---

## Current status

**Phase 0 — data reconnaissance. Complete.** Questions about the data, and a go/no-go
verdict on each proposed analysis. No findings.

**Phase 1 — representation. Complete.** A computable price and an owned product identity.
100.000% of price rows in both snapshots resolve to a unit price or an explicit `unparsed`
verdict (33 unparsed in each snapshot, of 71.8M / 72.0M rows). An owned product key with **0 collisions** across
both snapshots. 40 dbt tests passing on both, 23 of 23 demonstrated to fail when they
should.

**Phase 2 — findings. Complete.** Three results, six withdrawals, a full exclusion ledger
with a bias verdict on each class. The sixth, W6, withdraws every comparison involving
Save-On-Foods, whose prices come from a store in Kamloops, BC.

**Phase 3 — publication. Complete:** the writeup and the method note. Phase 3 also
published a dashboard, since **retired**: after W6 the analysis has one surviving pairwise
comparison, the writeup carries it, and every chart is a surface where a withdrawn claim can
resurface. It stays in the repository as a record and is never published
([`dashboard/RETIRED.md`](dashboard/RETIRED.md)).

**Phase 4 — the price tool. Live.** Refresh cadence measured rather than assumed (Thursday is
the flyer day at six of eight chains, and a daily refresh beats a correctly-timed weekly one
by under 2 percentage points). Taken offline on 2026-09-12 when Save-On-Foods was found to be
priced in Kamloops, BC, rebuilt as Metro vs Walmart, and put back up after review
([findings](docs/phase-4-findings.md) §9). **Refreshed automatically when upstream publishes**,
not on a clock: a light refresh loads only the two chains the tool reads, runs every gate that
guards the extract on a free GitHub runner, and is proven byte-identical to the full rebuild
(§10). The page states how old its prices are rather than promising when they will update.

### What this project found, and what it did not

**Found, with stated bounds:**

- **Between 3.4% and 21.3%** of 2025–26 sale events advertise a "regular" price not
  supported by the fortnight before the sale — a **bracket, not a point**, with most of the
  gap attributable to ordinary repricing.
- **On identical national-brand products stocked by both chains on the same day**, Walmart
  was cheaper than Metro on 100% of 711 observed dates and in all 8 categories, by about
  12.6%. Both are priced in
  North York, Toronto. For about half of individual products (51%), neither is reliably
  cheaper.
- **One exclusion in the pipeline is biased**, not merely large, which is why every headline
  result is scoped to 2025–26.

**Explicitly NOT found:**

- **No retailer has been shown to lie about prices.**
- **No "cheapest supermarket" claim.** The barcode-matched comparison is blind to store
  brands — about 22.6% of price-weighted shelf presence — which is where the chains compete
  hardest.
- **No cross-chain ranking of promotional frequency.** Computed, then **withdrawn**: the
  sale flag is not semantically equivalent across chains.
- **No price-freeze compliance rate for any retailer.** Not measurable from this data.
- **No comparison between Save-On-Foods and any other chain.** Computed, then **withdrawn**
  (W6): its prices come from a store in Kamloops, BC, and with one store per chain, regional
  pricing cannot be separated from store pricing.
- **Nothing national, and nothing GTA-wide.** North York, Toronto, pickup prices — except Save-On-Foods, which is Kamloops, BC.

## Layout

```
CLAUDE.md                       project rules: locked decisions, honesty rules, handoff rules
AGENTS.md                       entry point for non-Claude agents; points at docs/RESUME.md
README.md                       this file
LICENSE                         MIT, for the code only -- not the data
netlify.toml                    deploy config: gated build, headers, only main publishes
config/
  expected_schema.json          asserted column names + types of raw and product
docs/
  RESUME.md                     how to pick this project up without prior context
  FILES.md                      file manifest (what each file is for)
  CLAIMS.md                     every published figure and the committed source behind it
  phase-0-brief.md ...          one brief per phase, phase-0 to phase-4
  phase-0-findings.md           data reconnaissance
  phase-1-findings.md           representation: parsing and an owned product identity
  phase-2-findings.md           the results, withdrawals W1-W6, what must never be said
  phase-3-thesis.md             the argument the writeup makes
  phase-4-findings.md           refresh cadence, the tool, the scope correction (section 9)
  writeup.md                    the public piece
  method-note.md                how the numbers were checked, and what the checks missed
  retention-design.md           snapshot retention scheme (proposed)
  upstream-feedback.md          feedback for the dataset's maintainer
analysis/phase0/ ... phase4/    one .sql per finding; every number traces to one of these
models/                         the parsing macros and the staging/intermediate models
dbt/                            the dbt project: contracts and tests (dbt test, not dbt run)
tool/                           the price tool: index.html and its generated data/ extract
dashboard/                      RETIRED Phase 3 dashboard, kept as a record, never published
scripts/
  fetch_snapshot.py             download a snapshot + record sha256/timestamps
  load_snapshot.py              load a snapshot into DuckDB (deletes its target DB first)
  build_models.py               materialise the models; asserts rows in == rows out
  compact_db.py                 reclaim dead pages DuckDB does not free on rebuild
  run_query.py                  run a saved query against the analysis DB
  verify_twice.py               run a query twice: both must succeed and agree
  refresh_light.py              the automated refresh: two chains only, every extract gate
  refresh.py                    the full rebuild (manual): keeps archives, proves the light path
  check_light_parity.py         the light extract must equal the full extract, byte for byte
  netlify_changes.sh            skip builds nothing ships from; age limit only on data deploys
  netlify_build.sh              the deploy build: gates first, then assemble _site
  run_dbt_tests.py              run the dbt suite on both snapshots, report counts
  check_schema.py               assert the loaded schema matches config/
  check_layering.py             assert product_id appears nowhere below staging
  check_model_parity.py         assert the two model build paths have not drifted
  check_determinism.py          flag SQL that could return a different answer twice
  check_manifest.py             verify docs/FILES.md matches the repo
  check_claims.py               verify every published figure has a committed source
  check_extract.py              the deploy gate for the tool's extract
  verify_reproducible.py        assert the materialisation is a cache, not an artifact
  verify_deploy.py              check the live site over HTTP, compression included
  measure_phone.js              time the tool on a mid-range phone profile
  serve_gzip.py                 a local server that compresses, like the real host
  test_*.py, test_*.js          prove each check fails when it should
.handoff/                       where the last session stopped -- not a record of what is true
.github/workflows/refresh.yml   daily probe; refreshes only when upstream has published
data/provenance/                what each shipped extract was built from (hash, timestamps)
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
python scripts/check_claims.py         # every figure in the published docs has a committed source
python scripts/test_check_claims.py    # proves the above fails when it should  (7 of 7)
python scripts/test_check_light_parity.py # any difference from the full extract is refused  (7 of 7)
python scripts/test_netlify_changes.py # docs skip the build; data deploys enforce the age limit  (12 of 12)
python scripts/check_layering.py       # product_id must not appear below staging
python scripts/check_model_parity.py   # models/ and dbt/models/ must not have drifted
python scripts/check_determinism.py    # SQL that could return a different answer twice
python scripts/test_check_determinism.py # proves the above fails when it should  (8 of 8)
python scripts/verify_reproducible.py  # the materialisation matches its own definition
python scripts/run_dbt_tests.py        # 40 dbt tests, both snapshots
python scripts/test_dbt_contracts.py   # proves each dbt test fails when it should  (23 of 23)
```

Every one of those numbers is a **count of assertions that exist**, never a pass rate for
a phase (CLAUDE.md honesty rule 8, "pass rates only for tests that exist").

`check_schema.py` exists because upstream has announced that `raw.product_id` will change
from a string to a number. Ingest asserts the schema and **fails loudly** — it never
silently casts, coerces, or infers. When the change lands, `config/expected_schema.json`
is updated deliberately, in its own commit, with a note.

## House rules

`CLAUDE.md` is binding, not advisory. The ones that bite hardest in practice:

- **A missing day is not an unchanged price.** No forward-filling across gaps without an
  explicit, named, documented rule.
- **Publication lag is not a data gap.** The date a price was observed and the date I
  obtained the file containing it are two different fields, and a late upload must never
  be reported as missing scrape data.
- **Every published number is reproducible.** If a figure appears in a document, a
  committed `.sql` file regenerates it.
- **Report the denominator.** Every percentage carries its n.

## Data availability, and what "reproducible" means here

The dataset itself is **not in this repository** — `data/snapshots/` and the DuckDB files
are gitignored, because ~1.4 GB of binary archives is the wrong payload for git history.
Redistribution is permitted and encouraged by the maintainer, so a mirror is possible; it
would go via release assets or object storage rather than the repo, and that decision has
not been made yet.

`scripts/fetch_snapshot.py` downloads a fresh snapshot with provenance (sha256, download
timestamps, upstream `hammer-lastupdated.txt`). Every number in the findings documents
cites the snapshot id and build stamp it was computed under, so a rebuild can be checked
against them — but a *newly downloaded* snapshot is a different snapshot and will not
reproduce them exactly. That is the point of the immutability rule, not a defect.

## Two licences, and they are not the same

Readers conflate these constantly, so they are stated separately and plainly.

### The code: MIT

Everything authored in this repository — the Python scripts, the SQL models and queries,
the dbt project, and the documentation — is **MIT licensed**. See [LICENSE](LICENSE). Use
it, fork it, ship it commercially; keep the copyright notice.

### The data: Project Hammer's, not mine

The grocery price data is **not mine and is not licensed by me**. It belongs to
[Project Hammer](https://projecthammer.org) and is used here as a downstream consumer.

**It is also not in this repository.** `data/snapshots/` and the DuckDB files are
gitignored. Cloning this repo gets you the code and the findings, never the dataset.

The maintainer has confirmed by email that publishing derived analysis and redistributing
the dataset are both permitted, and that redistribution is encouraged. That permission
comes with a required attribution, used here, in the writeup and in the tool:

> The underlying data was sourced from ProjectHammer.org

**What this means in practice:** MIT lets you take the code. It does **not** give you any
right to the data, and it does **not** transfer the attribution obligation away from you —
if you republish numbers derived from Project Hammer, the attribution requirement is yours
to carry, not something the MIT licence on this code discharges.
