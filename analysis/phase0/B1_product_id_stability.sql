-- B1: confirm (or refute) the instability of product.id.
-- Locked decision #5 and the upstream docs both say product.id / raw.product_id
-- "changes every day and is not a stable unique identifier".
-- Test: for a product identified by (vendor, sku), how many distinct product_id values
-- does it take across its observed life, and over how many days? A truly daily-rotating
-- id would give distinct_ids ~= distinct_days.
CREATE OR REPLACE TEMP VIEW obs AS
SELECT try_cast(substr(r.nowtime,1,10) AS DATE) AS d,
       p.vendor, p.sku, p.product_name, r.product_id
FROM raw r JOIN product p ON p.id = r.product_id
WHERE try_cast(substr(r.nowtime,1,10) AS DATE) IS NOT NULL
  AND p.sku IS NOT NULL AND trim(p.sku) <> '';

-- 1. Population-level: ratio of distinct ids to distinct days, per vendor.
--    ratio ~1.0 => id rotates daily. ratio ~0 => id is stable.
SELECT vendor,
       count(*)                                   AS sku_series,
       round(avg(distinct_days),1)                AS avg_days_observed,
       round(avg(distinct_ids),2)                 AS avg_distinct_product_ids,
       round(avg(distinct_ids*1.0/distinct_days),4) AS avg_ids_per_day_ratio,
       count(*) FILTER (WHERE distinct_ids = 1)   AS series_with_exactly_one_id,
       round(100.0*count(*) FILTER (WHERE distinct_ids = 1)/count(*),2) AS pct_single_id
FROM (SELECT vendor, sku, count(DISTINCT d) AS distinct_days,
             count(DISTINCT product_id) AS distinct_ids
      FROM obs GROUP BY 1,2 HAVING count(DISTINCT d) >= 30)
GROUP BY vendor ORDER BY vendor;

-- 2. The 20-product sample the brief asks for: 20 long-lived SKUs, showing how many
--    distinct product_id values each carried.
SELECT vendor, sku, any_value(product_name) AS product_name,
       count(DISTINCT d) AS days_observed,
       count(DISTINCT product_id) AS distinct_product_ids,
       min(d) AS first_day, max(d) AS last_day
FROM obs
GROUP BY vendor, sku
HAVING count(DISTINCT d) >= 400
ORDER BY hash(vendor||sku)
LIMIT 20;
