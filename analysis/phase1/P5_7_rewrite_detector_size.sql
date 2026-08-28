-- P5.7: size and shape of the rewrite detector proposed in docs/retention-design.md.
--
-- WHY A DETECTOR IS NEEDED AT ALL. Findings 1.4 concluded upstream is "append-only in
-- practice". That conclusion rests on 12 changed rows across 2 dates, observed over a
-- 2-day window between two publications -- and the maintainer has since announced he is
-- reworking post-processing. An append-only archive is therefore a PROPERTY WE SHOULD
-- MONITOR, not an assumption we may rely on. Honesty rule 4 ("every published number is
-- reproducible") quietly depends on it.
--
-- WHAT IT COSTS. One row per observed_date, carried in the weekly slim delta. This
-- measures that table rather than estimating it -- the retention document's existing
-- sizes are measured and this one should match that standard.
--
-- The fingerprint construction is the one findings 1.4 already used and validated
-- (P1_4_snapshot_diff.sql), so a delta and a full snapshot diff produce comparable
-- numbers rather than two similar-looking things that cannot be joined.
SET threads = 4;

-- Two checksums, deliberately. See the retention document for why one is not enough:
--   price_checksum    -- what breaks a published number if it is rewritten
--   identity_checksum -- includes product_id, which is the ONLY thing that actually
--                        moved in the one rewrite ever observed (findings 1.4: the 12
--                        rows were re-keyed at an UNCHANGED price). A price-only
--                        checksum would have been blind to it.
CREATE OR REPLACE TEMP TABLE fingerprint AS
SELECT try_cast(substr(nowtime, 1, 10) AS DATE)                       AS observed_date,
       count(*)                                                       AS n_rows,
       sum(hash(coalesce(current_price, '') || '|' ||
                coalesce(old_price, '')     || '|' ||
                coalesce(price_per_unit, '')))::HUGEINT                AS price_checksum,
       sum(hash(coalesce(product_id, '')    || '|' ||
                coalesce(current_price, '') || '|' ||
                coalesce(old_price, '')     || '|' ||
                coalesce(price_per_unit, '')|| '|' ||
                coalesce(other, '')))::HUGEINT                         AS identity_checksum
FROM raw
WHERE try_cast(substr(nowtime, 1, 10) AS DATE) IS NOT NULL
GROUP BY 1;

-- 1. Shape: how many rows does the detector carry, and over what span?
SELECT count(*)          AS detector_rows,
       min(observed_date) AS first_date,
       max(observed_date) AS last_date,
       sum(n_rows)        AS price_rows_covered
FROM fingerprint;

-- 2. Size on disk, measured. Written to the spill dir, read back, then the bytes counted.
COPY (SELECT * FROM fingerprint ORDER BY observed_date)
  TO '.duckdb_spill/rewrite_detector.parquet' (FORMAT PARQUET, COMPRESSION ZSTD);
COPY (SELECT * FROM fingerprint ORDER BY observed_date)
  TO '.duckdb_spill/rewrite_detector.csv' (FORMAT CSV, HEADER);

SELECT 'parquet+zstd' AS format,
       (SELECT count(*) FROM fingerprint) AS rows,
       round(sum(total_compressed_size) / 1024.0, 2) AS kib
FROM parquet_metadata('.duckdb_spill/rewrite_detector.parquet');

-- 3. Per-row cost, so the projection to future years is arithmetic rather than a guess.
SELECT round(1024.0 * (SELECT sum(total_compressed_size)/1024.0
                       FROM parquet_metadata('.duckdb_spill/rewrite_detector.parquet'))
             / (SELECT count(*) FROM fingerprint), 1)               AS bytes_per_date,
       (SELECT count(*) FROM fingerprint)                            AS dates_today,
       365                                                           AS dates_added_per_year;
