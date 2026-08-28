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

**Almost nothing changes, and what changes is metadata.** The 71.8M-row price series
appears append-only (§1.4: 12 altered rows out of 71,809,333). So retaining full archives
to detect size changes is retaining ~906 MB to observe ~14 field changes.

*"Appears" is doing real work in that sentence — the evidence is 12 rows over one 2-day
window. Tier 2a below turns it into something checked weekly rather than assumed.*

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

### Tier 2a — the rewrite detector

The paragraph above contains a load-bearing word: **"Prices are append-only"**. That is
not a fact about the dataset. It is an inference from **12 changed rows across 2 dates**,
observed across a **single pair of publications 2 days apart** (§1.4). And the maintainer
has since told us he is **reworking post-processing** — the exact activity that would
rewrite history if anything does.

Two things follow. First, omitting prices from the delta is the right call *and* it is the
thing that would make a rewrite invisible to us. Second, `CLAUDE.md` honesty rule 4 —
every published number is reproducible — silently assumes append-only. An assumption that
carries a published-numbers guarantee, rests on 12 rows, and sits directly downstream of
announced upstream change should be **monitored, not assumed**.

The cheap way to monitor it is not to raise the archive cadence. It is to carry a
fingerprint of the price series in the delta that already ships weekly.

**Construction.** One row per `observed_date`, using the fingerprint from
`P1_4_snapshot_diff.sql` unchanged, so a delta-to-delta comparison and a full snapshot
diff produce numbers that mean the same thing:

| Column | Meaning |
|---|---|
| `observed_date` | the scrape day (from `nowtime`), never the snapshot date |
| `n_rows` | rows upstream published for that day |
| `price_checksum` | order-independent sum of hashes over `current_price`, `old_price`, `price_per_unit` |
| `identity_checksum` | the same, plus `product_id` and `other` |

**Two checksums, and the second is not padding.** The one rewrite we have ever observed
changed `product_id` **at an unchanged price** (§1.4: rows swapping between
`LGwlbuu+EVyHYv7vaNRU2Q==` and `Walmart6XQS4BK8VMKL`). A price-only checksum — the obvious
thing to build, and what "a price checksum" literally asks for — **would have been blind to
the only real event in the record.** Carrying both costs 8 bytes per date and separates
"our published numbers moved" from "upstream re-keyed something".

**Cost, measured on the real 889-date history rather than estimated:**

| Measure | Value |
|---|---|
| Rows (one per observed date, 2024-02-28 → 2026-08-23) | **889** |
| Price rows fingerprinted | 72,022,644 |
| **Parquet + zstd** | **16.77 KiB** |
| CSV, uncompressed | 58.2 KiB |
| **Per date** | **19.3 bytes** |
| Growth | ~7 KB/year |

**16.77 KiB against an 8.09 MB delta — 0.2%.** The full-history fingerprint ships in every
weekly delta; there is no reason to send only the recent tail, because a rewrite of a
year-old date is precisely the case that matters and precisely the one a tail would miss.

| Cadence | Delta | + detector | Change |
|---|---|---|---|
| Weekly | 420 MB/yr | 421 MB/yr | **+0.9 MB/yr** |

**What it does and does not do.** It detects that a date changed; it does not say what
changed — `P1_4b_rewritten_rows.sql` is the diagnostic, and it needs two full archives, so
a detector hit is a reason to **pull an off-cycle archive**, which is the response this is
designed to trigger. It cannot see a rewrite of a date that upstream also removed and
re-added at an identical checksum, which is not a failure mode worth engineering against.

**What this changes about the append-only claim.** It stops being an assumption and
becomes a **monitored property**, at 0.2% of the delta and no change to archive cadence.
If it never fires, §1.4's conclusion is confirmed weekly instead of once. If it fires, we
find out in a week rather than at the next quarterly archive — or never.

*Source: `P5_7_rewrite_detector_size.sql`. Sizes measured, not estimated.*


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
   The rewrite detector is inside the weekly delta and adds 0.9 MB/year, so it does not
   change this decision; it only makes the append-only assumption the cadence rests on
   observable.
2. **Does a delta ever supersede an archive?** Proposed: no. Deltas are additive evidence;
   an archive is never deleted because a delta covers the same period.
3. **Where deltas live.** Proposed: `data/deltas/<utc-stamp>.parquet`, gitignored like
   snapshots, with the same manifest discipline (sha256 + timestamps).

## What this does NOT do

It does not make shrinkflation detectable retroactively. The first size change this scheme
can observe is one that happens **after the second delta is taken**. Phase 0's NO-GO on D3
stands for all historical data; this only starts the clock.
