# Snapshot retention design

**Status: proposed, for a decision before Phase 2.** Nothing here is built yet.

## The problem this solves

Phase 0 D3 established that **shrinkflation is undetectable from a single snapshot**:
`product.id = vendor||sku` is unique, so the `product` table can hold only one `units`
value per SKU. A size change overwrites. The only way to recover unit-size history is to
**compare snapshots taken apart in time**.

Phase 1 §1.3 then measured what actually moves between publications, and the answer
reshapes the retention question:

| Field | Change over 2 days, 161,290 shared keys |
|---|---|
| `product_name` | 388 |
| `units` | **14** |
| `brand` | 541 |
| `upc` | 11,263 *(10,318 of them blank → populated)* |

**Almost nothing changes, and what changes is metadata.** The 71.8M-row price series is
append-only (§1.4: 12 altered rows out of 71,809,333). So retaining full archives to
detect size changes is retaining ~906 MB to observe ~14 field changes.

## The mistake in the current approach

`fetch_snapshot.py` stores both full distributions — **1.38 GB per snapshot**. At that
size the cadence question answers itself badly:

| Cadence | Per year | Feasible on a 476 GB laptop at ~13 GB free? |
|---|---|---|
| Weekly | 72 GB | no |
| Monthly | 17 GB | no |
| Quarterly | 5.5 GB | barely, and only for one year |

That table is what drove the earlier "should this go to cloud?" question. **It is the wrong
table**, because it prices the wrong artifact.

## The two-tier scheme

### Tier 1 — full archives, low cadence, for the public mirror

Unchanged from today: both distributions, sha256, download timestamp, immutable.

- **Purpose:** the mirroring CLAUDE.md commits to, and the ability to rebuild any
  historical analysis from scratch.
- **Cadence: quarterly**, plus one before any known upstream schema change.
- **Cost: 1.38 GB each, ~5.5 GB/year.**

### Tier 2 — slim metadata delta, high cadence, for change detection

One row per product, carrying only the fields that define identity and size, plus the
observation window. **Measured, not estimated**, against the real 187,028-row catalogue:

| Format | Size |
|---|---|
| **Parquet + zstd** | **8.09 MB** |
| CSV + gzip | 9.48 MB |
| *(full SQLite archive, for contrast)* | *906.24 MB* |

**8.09 MB — 170× smaller than the archive it replaces for this purpose.**

Columns: `product_key`, `vendor`, `sku`, `product_name`, `brand`, `upc`, `units`,
`first_seen`, `last_seen`, `days_observed`.

`product_key` is the owned key from §3.5 (md5, proved collision-free across both
snapshots), so deltas join to each other and to `stg_product` without depending on
`raw.product_id` — which upstream has announced will change type.

**What it deliberately omits:** the price series. Prices are append-only, so a delta of
them is just the new days, which the next full archive carries anyway. Including them
would restore most of the 906 MB and defeat the point.

#### What cadence becomes affordable

| Cadence | Slim deltas/year | Size/year | Plus quarterly archives | **Total/year** |
|---|---|---|---|---|
| **Daily** | 365 | 2.9 GB | 5.5 GB | **8.4 GB** |
| **Weekly** | 52 | 0.42 GB | 5.5 GB | **5.9 GB** |
| **Monthly** | 12 | 0.10 GB | 5.5 GB | **5.6 GB** |

**Weekly slim deltas cost 420 MB a year.** Even daily is 2.9 GB — less than one full
archive every two days would cost in a week.

The binding constraint stops being the deltas and becomes the quarterly archives, which is
the correct place for it: those exist for mirroring and reproducibility, not for change
detection.

**Recommended: weekly slim deltas, quarterly full archives.** Weekly is well inside the
timescale of a package-size change, and 52 observations a year is enough to date a change
to within a week — far better than the current zero.

## What this does to the cloud decision

**It removes the urgency.** At 5.9 GB/year total, local storage is viable for years,
especially after the 2.55 GB reclaimed by compacting `hammer.duckdb`.

Cloud remains attractive for one reason that is not about capacity: CLAUDE.md records that
the maintainer **encourages redistribution**, so a public bucket of Tier-1 archives is the
mirroring the project already committed to. That is a publishing decision, not a storage
one, and it should be made on its own merits.

**Recommendation: stay local for Tier 2 (the deltas), and treat Tier 1 as a publishing
question for whenever the project goes public.** Revisit if the archive cadence rises above
quarterly.

## What still needs deciding

1. **Cadence sign-off.** Weekly deltas, quarterly archives — or different numbers.
2. **Does a delta ever supersede an archive?** Proposed: no. Deltas are additive evidence;
   an archive is never deleted because a delta covers the same period.
3. **Where deltas live.** Proposed: `data/deltas/<utc-stamp>.parquet`, gitignored like
   snapshots, with the same manifest discipline (sha256 + timestamps).

## What this does NOT do

It does not make shrinkflation detectable retroactively. The first size change this scheme
can observe is one that happens **after the second delta is taken**. Phase 0's NO-GO on D3
stands for all historical data; this only starts the clock.
