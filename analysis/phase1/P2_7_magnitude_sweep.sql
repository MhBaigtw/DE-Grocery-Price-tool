-- P2.7 (brief item 2.5): CORRECTNESS sweep, not coverage.
--
-- Coverage says 100.00% of rows produced a number. It says nothing about whether the
-- number is right. The four cents-form variants were found by looking twice -- reading a
-- shape census, spotting 'a$N', asking what it was. That method does not scale and does
-- not generalise: it finds the defects someone thought to look for.
--
-- This is the method that finds the fifth variant without looking. A magnitude error in a
-- price parser has a signature: within one product's own history, the price jumps by
-- exactly a power of ten and back. Real prices do not do that. So: within each stable
-- (vendor, sku), compare ADJACENT observations and flag ratios near 100x, 0.01x, 10x and
-- 0.1x.
--
-- The sweep is agnostic about cause. It will flag a genuine unit-size change or a
-- clearance as readily as a parse bug, so a hit is a lead, not a verdict -- but a parse
-- bug CANNOT hide from it, which is the point.
--
-- Keyed on the OWNED product_key (md5, proved collision-free in P3.5). This query
-- originally used a 64-bit hash workaround that had ONE collision in 161,300 keys -- and
-- a merged key is not a harmless rounding error HERE: it interleaves two different
-- products' price series under one key, manufacturing exactly the large adjacent-day
-- ratio this sweep is built to detect. Re-run under the md5 key; the delta is reported
-- in section 5.5.
SET threads = 4;

CREATE OR REPLACE TEMP TABLE keymap AS
SELECT product_key AS k, any_value(vendor) AS vendor, any_value(sku) AS sku,
       any_value(product_name) AS product_name, any_value(units_raw) AS units
FROM stg_product GROUP BY 1;

-- one price per key per day, per basis (comparing 'each' against 'per_100g' is meaningless)
CREATE OR REPLACE TEMP TABLE d AS
SELECT s.product_key AS k, s.price_basis, s.observed_date AS dt,
       avg(s.unit_price)          AS px,
       any_value(s.normalization) AS norm,
       any_value(s.offer_type)    AS otype
FROM stg_price s JOIN product p ON p.id = s.product_id
WHERE p.sku IS NOT NULL AND trim(p.sku) <> ''
  AND s.unit_price IS NOT NULL AND s.unit_price > 0
  AND s.observed_date >= DATE '2024-06-11'
GROUP BY 1,2,3;

-- adjacent observations of the same key+basis
CREATE OR REPLACE TEMP TABLE adj AS
SELECT k, price_basis, dt, px, norm, otype,
       lag(px)   OVER w AS prev_px,
       lag(dt)   OVER w AS prev_dt,
       lag(norm) OVER w AS prev_norm,
       px / nullif(lag(px) OVER w, 0) AS ratio
FROM d WINDOW w AS (PARTITION BY k, price_basis ORDER BY dt);

-- Only the flagged rows are materialised, and only the columns the report needs.
-- Keeping SELECT * over 58M adjacent pairs exhausted the 5.2 GB spill budget.
CREATE OR REPLACE TEMP TABLE flagged AS
SELECT k, price_basis, dt, prev_dt, px, prev_px, ratio, norm, prev_norm, otype,
       CASE
         WHEN ratio BETWEEN  95.0  AND 105.0  THEN 'x100'
         WHEN ratio BETWEEN   0.0095 AND 0.0105 THEN 'x0.01'
         WHEN ratio BETWEEN   9.5  AND  10.5  THEN 'x10'
         WHEN ratio BETWEEN   0.095 AND 0.105 THEN 'x0.1'
         ELSE NULL END AS magnitude_flag
FROM adj
WHERE prev_px IS NOT NULL AND date_diff('day', prev_dt, dt) <= 3
  AND (ratio BETWEEN 95.0 AND 105.0 OR ratio BETWEEN 0.0095 AND 0.0105
    OR ratio BETWEEN 9.5 AND 10.5 OR ratio BETWEEN 0.095 AND 0.105);

-- denominator kept separately so percentages still carry their n
CREATE OR REPLACE TEMP TABLE denom AS
SELECT count(*) AS pairs_examined FROM adj
WHERE prev_px IS NOT NULL AND date_diff('day', prev_dt, dt) <= 3;

-- 1. HEADLINE: how many adjacent-day moves look like a power-of-ten error?
SELECT (SELECT pairs_examined FROM denom)                    AS adjacent_pairs_examined,
       count(*)                                              AS flagged,
       round(100.0*count(*)/(SELECT pairs_examined FROM denom),6) AS pct_flagged,
       count(*) FILTER (WHERE magnitude_flag = 'x100')       AS x100,
       count(*) FILTER (WHERE magnitude_flag = 'x0.01')      AS x0_01,
       count(*) FILTER (WHERE magnitude_flag = 'x10')        AS x10,
       count(*) FILTER (WHERE magnitude_flag = 'x0.1')       AS x0_1
FROM flagged;

-- 2. Per vendor.
SELECT m.vendor,
       count(*)                                              AS flagged,
       count(*) FILTER (WHERE f.magnitude_flag='x100')       AS x100,
       count(*) FILTER (WHERE f.magnitude_flag='x0.01')      AS x0_01,
       count(*) FILTER (WHERE f.magnitude_flag='x10')        AS x10,
       count(*) FILTER (WHERE f.magnitude_flag='x0.1')       AS x0_1,
       count(*) FILTER (WHERE (f.norm='none') <> (f.prev_norm='none')) AS one_side_repaired
FROM flagged f JOIN keymap m USING (k)
GROUP BY m.vendor ORDER BY flagged DESC;

-- 3. THE DIAGNOSTIC THAT MATTERS: does either side of a flagged pair carry a
--    normalization? If a x100 jump sits between a repaired row and an unrepaired one,
--    the repair rule is firing inconsistently -- i.e. a parse bug, not a price move.
SELECT magnitude_flag,
       count(*)                                                        AS pairs,
       count(*) FILTER (WHERE norm='none' AND prev_norm='none')        AS neither_repaired,
       count(*) FILTER (WHERE norm<>'none' AND prev_norm<>'none')      AS both_repaired,
       count(*) FILTER (WHERE (norm='none') <> (prev_norm='none'))     AS ONE_SIDE_REPAIRED
FROM flagged
GROUP BY 1 ORDER BY pairs DESC;

-- 4. Sample for inspection, biased toward the dangerous case (one side repaired).
SELECT m.vendor, m.sku, f.magnitude_flag, f.prev_dt, f.dt,
       round(f.prev_px,4) AS px_before, round(f.px,4) AS px_after, round(f.ratio,2) AS ratio,
       f.prev_norm, f.norm, f.otype, m.product_name, m.units
FROM flagged f JOIN keymap m USING (k)
ORDER BY ((f.norm='none') <> (f.prev_norm='none')) DESC, f.magnitude_flag, hash(f.k)
LIMIT 25;
