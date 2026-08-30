-- P2.6: sku-reuse RISK MEASUREMENT. Explicitly not a deliverable, and nothing is built
-- on it (per instruction).
--
-- The concern: Section 4's owned key rests on (vendor, sku) being a stable identity.
-- P1.3 verified that across two snapshots two days apart. It cannot rule out a slower
-- failure -- a vendor retiring a SKU and later REUSING the same string for a different
-- product. If that happens, one key silently spans two products and every price series
-- built on it is a splice of two unrelated things.
--
-- Heuristic: for (vendor, sku) keys with an observation gap > 30 days, does the price
-- level or the product description shift discontinuously on resumption? A large jump in
-- both is consistent with reuse. It is also consistent with a genuine repricing after a
-- delisting, so this measures RISK, not incidence -- the number below is an upper bound
-- on how much reuse there could be, not an estimate of how much there is.
SET threads = 4;

-- daily price level per key, using the parsed unit price.
--
-- Keyed on the OWNED product_key (md5, proved collision-free in P3.5). The original
-- 64-bit hash workaround had one collision, and a merged key is actively dangerous here:
-- two products sharing a key produce an artificial gap followed by an artificial price
-- discontinuity -- precisely the pattern this heuristic counts. Re-run under md5; the
-- delta is reported in section 5.5.
CREATE OR REPLACE TEMP TABLE d AS
SELECT s.product_key AS k, s.observed_date AS d, avg(s.unit_price) AS px
FROM stg_price s JOIN product p ON p.id = s.product_id
WHERE p.sku IS NOT NULL AND trim(p.sku) <> ''
  AND s.observed_date >= DATE '2024-06-11'
  AND s.unit_price IS NOT NULL
  AND s.price_basis = 'each'          -- compare like with like; per-weight is a different scale
GROUP BY 1,2;

-- gaps longer than 30 days between consecutive observations of the same key
CREATE OR REPLACE TEMP TABLE gaps AS
SELECT k, d AS resume_date, px AS px_after,
       lag(d)  OVER w AS last_seen,
       lag(px) OVER w AS px_before,
       date_diff('day', lag(d) OVER w, d) AS gap_days
FROM d WINDOW w AS (PARTITION BY k ORDER BY d);

CREATE OR REPLACE TEMP TABLE longgaps AS
SELECT *, abs(px_after - px_before) / nullif(px_before, 0) AS rel_move
FROM gaps WHERE gap_days > 30 AND px_before IS NOT NULL AND px_before > 0;

-- 1. How many keys have a >30-day gap at all, and how do prices behave on resumption?
SELECT count(*)                                              AS gap_events,
       count(DISTINCT k)                                      AS distinct_keys_with_gap,
       round(median(gap_days),0)                              AS median_gap_days,
       round(median(rel_move)*100,2)                          AS median_pct_price_move,
       count(*) FILTER (WHERE rel_move > 0.50)                AS move_gt_50pct,
       count(*) FILTER (WHERE rel_move > 2.00)                AS move_gt_200pct,
       round(100.0*count(*) FILTER (WHERE rel_move > 0.50)/count(*),2) AS pct_gt_50
FROM longgaps;

-- 2. Baseline for comparison: price moves across a NORMAL (<= 7 day) gap. If the
--    long-gap distribution looks like this one, gaps are not suspicious at all.
SELECT count(*) AS short_gap_events,
       round(median(abs(px_after-px_before)/nullif(px_before,0))*100,2) AS median_pct_move,
       round(100.0*count(*) FILTER (WHERE abs(px_after-px_before)/nullif(px_before,0) > 0.50)
             /count(*),2)                                               AS pct_gt_50
FROM gaps WHERE gap_days BETWEEN 1 AND 7 AND px_before IS NOT NULL AND px_before > 0;

-- 3. Per vendor (key strings rejoined here, where the row count is small).
CREATE OR REPLACE TEMP TABLE keymap AS
-- determinism-ok: grouped by product_key, which determines vendor 1:1 by construction
-- (P3.5: md5 over vendor||chr(31)||sku, proved collision-free on both snapshots).
SELECT product_key AS k, any_value(vendor) AS vendor, any_value(sku) AS sku,
       any_value(product_name) AS product_name, any_value(units_raw) AS units
FROM stg_product GROUP BY 1;

SELECT m.vendor, count(*) AS gap_events,
       round(median(g.gap_days),0) AS median_gap_days,
       round(median(g.rel_move)*100,2) AS median_pct_move,
       count(*) FILTER (WHERE g.rel_move > 2.00) AS move_gt_200pct
FROM longgaps g JOIN keymap m USING (k)
GROUP BY m.vendor ORDER BY gap_events DESC;

-- 4. The sample: biggest discontinuities, with the product name on each side so a human
--    can judge whether it looks like the same product.
SELECT m.vendor, m.sku, g.last_seen, g.resume_date, g.gap_days,
       round(g.px_before,2) AS px_before, round(g.px_after,2) AS px_after,
       round(g.rel_move*100,0) AS pct_move,
       m.product_name, m.units
FROM longgaps g JOIN keymap m USING (k)
WHERE g.rel_move > 2.00
ORDER BY g.rel_move DESC LIMIT 20;
