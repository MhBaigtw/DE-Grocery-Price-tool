-- P5.5: did the retired 64-bit hash contaminate any key-level number in Sections 2 and 3?
--
-- Sections 2 and 3 ran two key-level heuristics on `hash(vendor || '|' || sku)`, a
-- workaround for a DuckDB 1.5.5 statistics bug on VARCHAR sku columns. Section 3.5 later
-- proved that workaround had ONE collision in 161,300 keys and replaced it with the owned
-- md5 key. The D2 counts were restated there. These two were not:
--
--   * findings 2.5 -- the magnitude sweep. A merged key interleaves two products' price
--     series under one identity, which MANUFACTURES the large adjacent-day ratio the
--     sweep exists to detect. This is the worst possible place for a merged key.
--   * findings 2.6 -- the sku-reuse heuristic (3.25% vs 0.41%, 663 events > 200%). A
--     merged key produces an artificial gap followed by an artificial price
--     discontinuity, which is precisely the pattern this heuristic counts.
--
-- METHOD. Both keyings are computed in ONE run from ONE base table, so the delta is
-- measured rather than compared across two runs that might differ for other reasons.
-- The hash-level price is re-derived from the same sums and counts, so the only thing
-- that changes between the two arms is which rows share an identity.
--
-- The collision, for the record (result 0 below):
--   SaveOnFoods / 00014100283522  Goldfish Mega Bites Crackers, Cheddar Jalapeno, 167 g
--   SaveOnFoods / 00064100283022  Nutri-Grain Bars, Raspberry, 8 Each
-- Two unrelated SaveOnFoods products at similar grocery price points.
SET threads = 4;

-- 0. The collision itself, named rather than asserted.
SELECT hash(vendor || '|' || sku)                       AS hash64,
       count(*)                                         AS md5_keys_sharing_it,
       string_agg(vendor || ' / ' || sku || ' / ' || coalesce(product_name, ''), ' || '
                  ORDER BY vendor, sku) AS members
FROM stg_product
WHERE product_key_basis = 'vendor_sku'
GROUP BY 1 HAVING count(*) > 1;

-- 0b. CONTROL: joining stg_product on the owned key must select the same price rows the
--     original queries selected by joining `product` on product_id. If these differ the
--     delta below is measuring a changed population, not a changed key.
SELECT
  (SELECT count(*) FROM stg_price s JOIN product p ON p.id = s.product_id
    WHERE p.sku IS NOT NULL AND trim(p.sku) <> ''
      AND s.observed_date >= DATE '2024-06-11' AND s.unit_price IS NOT NULL) AS via_product_id,
  (SELECT count(*) FROM stg_price s JOIN stg_product sp USING (product_key)
    WHERE sp.product_key_basis = 'vendor_sku'
      AND s.observed_date >= DATE '2024-06-11' AND s.unit_price IS NOT NULL) AS via_product_key;

-- ---------------------------------------------------------------------------------
-- Base: one row per (md5 key, hash key, basis, date), carrying SUM and COUNT so the
-- hash-level average can be re-derived exactly rather than averaged from averages.
-- ---------------------------------------------------------------------------------
CREATE OR REPLACE TEMP TABLE base AS
SELECT sp.product_key                       AS k_md5,
       hash(sp.vendor || '|' || sp.sku)     AS k_hash,
       s.price_basis                        AS basis,
       s.observed_date                      AS dt,
       sum(s.unit_price)                    AS sx,
       count(*)                             AS n
FROM stg_price s JOIN stg_product sp USING (product_key)
WHERE sp.product_key_basis = 'vendor_sku'
  AND s.observed_date >= DATE '2024-06-11'
  AND s.unit_price IS NOT NULL
GROUP BY 1,2,3,4;

-- ============================ PART A -- findings 2.6, sku reuse ====================
-- 'each' basis only, per the original query.
CREATE OR REPLACE TEMP TABLE a_md5 AS
  SELECT k_md5 AS k, dt, sx/n AS px FROM base WHERE basis = 'each';
CREATE OR REPLACE TEMP TABLE a_hash AS
  SELECT k_hash AS k, dt, sum(sx)/sum(n) AS px FROM base WHERE basis = 'each' GROUP BY 1,2;

CREATE OR REPLACE TEMP TABLE ag_md5 AS
SELECT k, dt AS resume_date, px AS px_after, lag(dt) OVER w AS last_seen,
       lag(px) OVER w AS px_before, date_diff('day', lag(dt) OVER w, dt) AS gap_days
FROM a_md5 WINDOW w AS (PARTITION BY k ORDER BY dt);
CREATE OR REPLACE TEMP TABLE ag_hash AS
SELECT k, dt AS resume_date, px AS px_after, lag(dt) OVER w AS last_seen,
       lag(px) OVER w AS px_before, date_diff('day', lag(dt) OVER w, dt) AS gap_days
FROM a_hash WINDOW w AS (PARTITION BY k ORDER BY dt);

-- A1. Long-gap headline, both keyings side by side.
SELECT 'md5 (owned key)' AS keying, count(*) AS gap_events, count(DISTINCT k) AS distinct_keys_with_gap,
       round(median(gap_days),0) AS median_gap_days,
       round(median(abs(px_after-px_before)/nullif(px_before,0))*100,2) AS median_pct_move,
       count(*) FILTER (WHERE abs(px_after-px_before)/nullif(px_before,0) > 0.50) AS move_gt_50pct,
       count(*) FILTER (WHERE abs(px_after-px_before)/nullif(px_before,0) > 2.00) AS move_gt_200pct,
       round(100.0*count(*) FILTER (WHERE abs(px_after-px_before)/nullif(px_before,0) > 0.50)/count(*),4) AS pct_gt_50
FROM ag_md5 WHERE gap_days > 30 AND px_before IS NOT NULL AND px_before > 0
UNION ALL
SELECT 'hash64 (retired)', count(*), count(DISTINCT k),
       round(median(gap_days),0),
       round(median(abs(px_after-px_before)/nullif(px_before,0))*100,2),
       count(*) FILTER (WHERE abs(px_after-px_before)/nullif(px_before,0) > 0.50),
       count(*) FILTER (WHERE abs(px_after-px_before)/nullif(px_before,0) > 2.00),
       round(100.0*count(*) FILTER (WHERE abs(px_after-px_before)/nullif(px_before,0) > 0.50)/count(*),4)
FROM ag_hash WHERE gap_days > 30 AND px_before IS NOT NULL AND px_before > 0;

-- A2. The 1-7 day baseline, both keyings.
SELECT 'md5 (owned key)' AS keying, count(*) AS short_gap_events,
       round(median(abs(px_after-px_before)/nullif(px_before,0))*100,2) AS median_pct_move,
       round(100.0*count(*) FILTER (WHERE abs(px_after-px_before)/nullif(px_before,0) > 0.50)/count(*),4) AS pct_gt_50
FROM ag_md5 WHERE gap_days BETWEEN 1 AND 7 AND px_before IS NOT NULL AND px_before > 0
UNION ALL
SELECT 'hash64 (retired)', count(*),
       round(median(abs(px_after-px_before)/nullif(px_before,0))*100,2),
       round(100.0*count(*) FILTER (WHERE abs(px_after-px_before)/nullif(px_before,0) > 0.50)/count(*),4)
FROM ag_hash WHERE gap_days BETWEEN 1 AND 7 AND px_before IS NOT NULL AND px_before > 0;

-- A3. Per vendor, owned key -- the table that replaces findings 2.6's per-vendor table.
SELECT sp.vendor, count(*) AS gap_events,
       round(median(g.gap_days),0) AS median_gap_days,
       round(median(abs(g.px_after-g.px_before)/nullif(g.px_before,0))*100,2) AS median_pct_move,
       count(*) FILTER (WHERE abs(g.px_after-g.px_before)/nullif(g.px_before,0) > 2.00) AS move_gt_200pct
FROM ag_md5 g JOIN stg_product sp ON sp.product_key = g.k
WHERE g.gap_days > 30 AND g.px_before IS NOT NULL AND g.px_before > 0
GROUP BY 1 ORDER BY gap_events DESC;

-- ============================ PART B -- findings 2.5, magnitude sweep ==============
CREATE OR REPLACE TEMP TABLE b_md5 AS
  SELECT k_md5 AS k, basis, dt, sx/n AS px FROM base WHERE sx/n > 0;
CREATE OR REPLACE TEMP TABLE b_hash AS
  SELECT k_hash AS k, basis, dt, sum(sx)/sum(n) AS px FROM base GROUP BY 1,2,3 HAVING sum(sx)/sum(n) > 0;

CREATE OR REPLACE TEMP TABLE f_md5 AS
SELECT k, dt, prev_dt, px, prev_px, ratio,
       CASE WHEN ratio BETWEEN 95.0 AND 105.0 THEN 'x100'
            WHEN ratio BETWEEN 0.0095 AND 0.0105 THEN 'x0.01'
            WHEN ratio BETWEEN 9.5 AND 10.5 THEN 'x10'
            WHEN ratio BETWEEN 0.095 AND 0.105 THEN 'x0.1' END AS magnitude_flag
FROM (SELECT k, basis, dt, px, lag(px) OVER w AS prev_px, lag(dt) OVER w AS prev_dt,
             px / nullif(lag(px) OVER w, 0) AS ratio
      FROM b_md5 WINDOW w AS (PARTITION BY k, basis ORDER BY dt))
WHERE prev_px IS NOT NULL AND date_diff('day', prev_dt, dt) <= 3
  AND (ratio BETWEEN 95.0 AND 105.0 OR ratio BETWEEN 0.0095 AND 0.0105
    OR ratio BETWEEN 9.5 AND 10.5 OR ratio BETWEEN 0.095 AND 0.105);

CREATE OR REPLACE TEMP TABLE f_hash AS
SELECT k, dt, prev_dt, px, prev_px, ratio,
       CASE WHEN ratio BETWEEN 95.0 AND 105.0 THEN 'x100'
            WHEN ratio BETWEEN 0.0095 AND 0.0105 THEN 'x0.01'
            WHEN ratio BETWEEN 9.5 AND 10.5 THEN 'x10'
            WHEN ratio BETWEEN 0.095 AND 0.105 THEN 'x0.1' END AS magnitude_flag
FROM (SELECT k, basis, dt, px, lag(px) OVER w AS prev_px, lag(dt) OVER w AS prev_dt,
             px / nullif(lag(px) OVER w, 0) AS ratio
      FROM b_hash WINDOW w AS (PARTITION BY k, basis ORDER BY dt))
WHERE prev_px IS NOT NULL AND date_diff('day', prev_dt, dt) <= 3
  AND (ratio BETWEEN 95.0 AND 105.0 OR ratio BETWEEN 0.0095 AND 0.0105
    OR ratio BETWEEN 9.5 AND 10.5 OR ratio BETWEEN 0.095 AND 0.105);

-- B1. Flagged pairs, both keyings. This is the POST-fix sweep (residual 1,825 in 2.5).
SELECT 'md5 (owned key)' AS keying, count(*) AS flagged,
       count(*) FILTER (WHERE magnitude_flag='x100')  AS x100,
       count(*) FILTER (WHERE magnitude_flag='x0.01') AS x0_01,
       count(*) FILTER (WHERE magnitude_flag='x10')   AS x10,
       count(*) FILTER (WHERE magnitude_flag='x0.1')  AS x0_1
FROM f_md5
UNION ALL
SELECT 'hash64 (retired)', count(*),
       count(*) FILTER (WHERE magnitude_flag='x100'),
       count(*) FILTER (WHERE magnitude_flag='x0.01'),
       count(*) FILTER (WHERE magnitude_flag='x10'),
       count(*) FILTER (WHERE magnitude_flag='x0.1')
FROM f_hash;

-- B2. Per-vendor flagged counts under the owned key. Vendor is resolved through the
--     owned key, not through product_id.
SELECT sp.vendor, count(*) AS flagged
FROM f_md5 f JOIN stg_product sp ON sp.product_key = f.k
GROUP BY 1 ORDER BY flagged DESC;

-- B3. THE DIRECT TEST: is anything attributable to the collision itself? Under the hash
--     keying the two merged products share one series; under md5 they do not.
SELECT 'flagged pairs on the colliding bucket, hash64 keying' AS what, count(*) AS n
FROM f_hash WHERE k = 918118051070506723
UNION ALL
SELECT 'long-gap events on the colliding bucket, hash64 keying', count(*)
FROM ag_hash WHERE k = 918118051070506723 AND gap_days > 30 AND px_before IS NOT NULL AND px_before > 0
UNION ALL
SELECT 'long-gap events on the two md5 keys, md5 keying', count(*)
FROM ag_md5 WHERE k IN (SELECT product_key FROM stg_product
                        WHERE product_key_basis='vendor_sku'
                          AND hash(vendor || '|' || sku) = 918118051070506723)
  AND gap_days > 30 AND px_before IS NOT NULL AND px_before > 0;
