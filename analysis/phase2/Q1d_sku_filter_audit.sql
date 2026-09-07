-- Q1.5: the `vendor_sku` filter as a fourth exclusion class, and the 576,200 / 566,564
-- reconciliation.
--
-- WHERE THE FILTER CAME FROM. Phase 0's F5 partitioned literally by `(vendor, sku)`:
--
--     row_number() OVER (PARTITION BY vendor, sku ORDER BY d)
--
-- A blank sku under that partition collapses every blank-sku product at a vendor into one
-- price series, so F5 HAD to write `WHERE p.sku IS NOT NULL AND trim(p.sku) <> ''`. The
-- filter was not a judgement about which products deserve to be measured; it was a
-- consequence of the key.
--
-- P2_3 then inherited it verbatim, with the stated reason "definitions are held identical
-- to F5 so the comparison is like-for-like". But P2_3 keys on `product_key`, and Phase 1
-- §4.1 built the `concatted` fallback specifically so that the 25,728 blank-sku products
-- (13.76% of the catalogue) WOULD have a key. So the filter now removes exactly the
-- population the owned key was designed to cover, for a reason that no longer exists.
--
-- That makes it a fourth exclusion class, undeclared and unaudited. This query audits it
-- on the same terms as the other three: how much, is it a random slice, and should it
-- stay -- judged on current grounds, not inherited ones.
SET threads = 4;

CREATE OR REPLACE TEMP MACRO cat(nm) AS
  CASE
    WHEN regexp_matches(lower(nm), '(bread|bagel|bun|tortilla|pita)')                 THEN 'a. bread & bakery'
    WHEN regexp_matches(lower(nm), '(milk|cream|yogur|yoghur|cheese|butter|margarine)') THEN 'b. dairy'
    WHEN regexp_matches(lower(nm), 'egg')                                              THEN 'c. eggs'
    WHEN regexp_matches(lower(nm), '(apple|banana|orange|potato|onion|carrot|tomato|lettuce|berry|berries|grape|pepper|broccoli|cucumber)') THEN 'd. produce'
    WHEN regexp_matches(lower(nm), '(chicken|beef|pork|turkey|bacon|ham|sausage|fish|salmon|tuna|shrimp)') THEN 'e. meat & fish'
    WHEN regexp_matches(lower(nm), '(rice|pasta|flour|sugar|cereal|oat|noodle)')       THEN 'f. pantry staples'
    WHEN regexp_matches(lower(nm), '(juice|coffee|tea|soda|water|cola|drink)')         THEN 'g. beverages'
    ELSE 'h. other' END;

-- Daily grain, carrying BOTH filter flags so all four populations come from one build and
-- the 2x2 is exact rather than four separately-filtered runs that might not line up.
CREATE OR REPLACE TEMP TABLE daily AS
SELECT s.product_key                                  AS k,
       s.observed_date                                AS d,
       max(CASE WHEN s.old_offer_type <> 'blank' THEN 1 ELSE 0 END) AS on_sale,
       max(CASE WHEN s.old_unit_price IS NOT NULL THEN 1 ELSE 0 END) AS old_has_value,
       max(CASE WHEN s.offer_type = 'multibuy' THEN 1 ELSE 0 END)   AS multibuy
FROM stg_price s
WHERE s.product_key IS NOT NULL
GROUP BY 1,2;

CREATE OR REPLACE TEMP TABLE keyed AS
SELECT sp.product_key AS k, sp.vendor, sp.product_key_basis,
       cat(sp.product_name) AS category, sp.brand_class
FROM stg_product sp;

-- determinism-ok: gaps-and-islands over `daily`, which is GROUP BY (key, date) and
-- therefore holds exactly one row per key per date, so ORDER BY the date is a TOTAL
-- order within the partition.
CREATE OR REPLACE TEMP TABLE runs_all AS
SELECT *, row_number() OVER (PARTITION BY k ORDER BY d)
        - row_number() OVER (PARTITION BY k, on_sale ORDER BY d) AS grp
FROM daily;

-- Events under NO date floor.
CREATE OR REPLACE TEMP TABLE ev_all AS
SELECT k, min(d) AS sale_start, count(*) AS run_days,
       max(old_has_value) AS old_has_value, max(multibuy) AS multibuy
FROM runs_all WHERE on_sale = 1 GROUP BY k, grp;

-- Events under the 2024-06-11 floor. Recomputed from scratch rather than filtered from
-- the above, because the floor TRUNCATES an event that spans it rather than removing it,
-- and a filtered-after-the-fact count would get that wrong.
-- determinism-ok: same gaps-and-islands over the same (key, date) grain, one row per
-- key per date, so ORDER BY the date is a total order.
CREATE OR REPLACE TEMP TABLE runs_dated AS
SELECT *, row_number() OVER (PARTITION BY k ORDER BY d)
        - row_number() OVER (PARTITION BY k, on_sale ORDER BY d) AS grp
FROM daily WHERE d >= DATE '2024-06-11';

CREATE OR REPLACE TEMP TABLE ev_dated AS
SELECT k, min(d) AS sale_start, count(*) AS run_days,
       max(old_has_value) AS old_has_value, max(multibuy) AS multibuy
FROM runs_dated WHERE on_sale = 1 GROUP BY k, grp;

-- ============================ THE RECONCILIATION ==================================

-- 1. THE 2x2, line by line. Q1b reported 576,200; P2_3 reports 566,564. Every cell here
--    is counted, none is derived by subtraction.
SELECT 'A. all keys, all dates          (Q1b)' AS population, count(*) AS events FROM ev_all
UNION ALL
SELECT 'B. all keys, date >= 2024-06-11', count(*) FROM ev_dated
UNION ALL
SELECT 'C. vendor_sku only, all dates', count(*) FROM ev_all e
  JOIN keyed kk USING (k) WHERE kk.product_key_basis = 'vendor_sku'
UNION ALL
SELECT 'D. vendor_sku only, date floor  (P2_3)', count(*) FROM ev_dated e
  JOIN keyed kk USING (k) WHERE kk.product_key_basis = 'vendor_sku';

-- 2. The same four numbers decomposed into the two effects and their interaction, so the
--    9,636 difference is accounted for rather than asserted.
WITH n AS (
  SELECT (SELECT count(*) FROM ev_all)                                          AS a,
         (SELECT count(*) FROM ev_dated)                                        AS b,
         (SELECT count(*) FROM ev_all e JOIN keyed kk USING (k)
           WHERE kk.product_key_basis = 'vendor_sku')                           AS c,
         (SELECT count(*) FROM ev_dated e JOIN keyed kk USING (k)
           WHERE kk.product_key_basis = 'vendor_sku')                           AS d
)
SELECT a AS start_576200, d AS end_566564, a - d AS total_difference,
       a - b AS lost_to_date_floor_all_keys,
       a - c AS lost_to_sku_filter_all_dates,
       (a - b) + (a - c) - (a - d) AS overlap_lost_to_both
FROM n;

-- 3. Which blank-sku events does the sku filter remove, per vendor and year?
SELECT kk.vendor, year(e.sale_start) AS yr,
       count(*) FILTER (WHERE kk.product_key_basis = 'vendor_concatted') AS events_removed,
       count(*) FILTER (WHERE kk.product_key_basis = 'vendor_sku')       AS events_kept,
       round(100.0 * count(*) FILTER (WHERE kk.product_key_basis = 'vendor_concatted')
             / count(*), 3)                                              AS pct_removed
FROM ev_dated e JOIN keyed kk USING (k)
GROUP BY 1,2 ORDER BY vendor, yr;

-- 4. Per vendor overall, with the product counts behind it.
SELECT kk.vendor,
       count(*) FILTER (WHERE kk.product_key_basis = 'vendor_concatted') AS events_removed,
       count(*)                                                          AS events_total,
       round(100.0 * count(*) FILTER (WHERE kk.product_key_basis = 'vendor_concatted')
             / count(*), 3)                                              AS pct_removed,
       count(DISTINCT kk.k) FILTER (WHERE kk.product_key_basis = 'vendor_concatted') AS blank_sku_products
FROM ev_dated e JOIN keyed kk USING (k)
GROUP BY 1 ORDER BY pct_removed DESC, vendor;

-- ============================ IS IT A RANDOM SLICE? ===============================

-- 5. Promotion character of the removed events vs the kept ones. Same three axes the
--    other classes were judged on.
SELECT kk.product_key_basis                                              AS basis,
       count(*)                                                          AS events,
       round(median(e.run_days), 1)                                      AS median_run_days,
       count(*) FILTER (WHERE e.old_has_value = 1)                       AS with_old_price_value,
       round(100.0*count(*) FILTER (WHERE e.old_has_value = 1)/count(*), 2) AS pct_with_value,
       count(*) FILTER (WHERE e.multibuy = 1)                            AS multibuy_events,
       round(100.0*count(*) FILTER (WHERE e.multibuy = 1)/count(*), 3)   AS pct_multibuy
FROM ev_dated e JOIN keyed kk USING (k)
GROUP BY 1 ORDER BY 1;

-- 6. Category mix of removed vs kept events.
SELECT kk.category,
       count(*) FILTER (WHERE kk.product_key_basis = 'vendor_concatted') AS removed,
       round(100.0*count(*) FILTER (WHERE kk.product_key_basis = 'vendor_concatted')
             / nullif(sum(count(*) FILTER (WHERE kk.product_key_basis = 'vendor_concatted')) OVER (), 0), 2) AS pct_removed,
       count(*) FILTER (WHERE kk.product_key_basis = 'vendor_sku')       AS kept,
       round(100.0*count(*) FILTER (WHERE kk.product_key_basis = 'vendor_sku')
             / nullif(sum(count(*) FILTER (WHERE kk.product_key_basis = 'vendor_sku')) OVER (), 0), 2) AS pct_kept
FROM ev_dated e JOIN keyed kk USING (k)
GROUP BY 1 ORDER BY category;

-- 7. Brand-class mix of removed vs kept events.
SELECT kk.brand_class,
       count(*) FILTER (WHERE kk.product_key_basis = 'vendor_concatted') AS removed,
       round(100.0*count(*) FILTER (WHERE kk.product_key_basis = 'vendor_concatted')
             / nullif(sum(count(*) FILTER (WHERE kk.product_key_basis = 'vendor_concatted')) OVER (), 0), 2) AS pct_removed,
       count(*) FILTER (WHERE kk.product_key_basis = 'vendor_sku')       AS kept,
       round(100.0*count(*) FILTER (WHERE kk.product_key_basis = 'vendor_sku')
             / nullif(sum(count(*) FILTER (WHERE kk.product_key_basis = 'vendor_sku')) OVER (), 0), 2) AS pct_kept
FROM ev_dated e JOIN keyed kk USING (k)
GROUP BY 1 ORDER BY brand_class;

-- 8. The evaluable cohort: does admitting blank-sku products change the number D2 is
--    actually built on (14 days of continuous pre-window history)?
CREATE OR REPLACE TEMP TABLE pre AS
SELECT k, d, count(*) OVER w AS pre_days
FROM daily WHERE d >= DATE '2024-06-11'
WINDOW w AS (PARTITION BY k ORDER BY d
             RANGE BETWEEN INTERVAL 14 DAY PRECEDING AND INTERVAL 1 DAY PRECEDING);

SELECT kk.product_key_basis AS basis,
       count(*)             AS evaluable_events
FROM ev_dated e
JOIN pre p    ON p.k  = e.k AND p.d = e.sale_start AND p.pre_days = 14
JOIN keyed kk ON kk.k = e.k
GROUP BY 1 ORDER BY 1;
