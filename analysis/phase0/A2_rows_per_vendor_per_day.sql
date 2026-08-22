-- A2: rows per vendor per day across the whole history.
-- Vendor comes from product.vendor via the documented join. The 878,559 rows that do
-- not join (see E2, 1.22% of raw) have no vendor and are EXCLUDED here; they are
-- reported separately rather than silently dropped.
--
-- This statement emits the full per-vendor-per-day series (used for the chart).
-- Written to CSV by the runner; the summary statements below are what gets quoted.
CREATE OR REPLACE TEMP VIEW obs AS
SELECT try_cast(substr(r.nowtime,1,10) AS DATE) AS d,
       p.vendor                                 AS vendor,
       r.product_id,
       p.sku,
       p.upc
FROM raw r
JOIN product p ON p.id = r.product_id
WHERE try_cast(substr(r.nowtime,1,10) AS DATE) IS NOT NULL;

-- 1. Monthly mean rows/day per vendor: the shape of the series, small enough to read.
SELECT date_trunc('month', d) AS month,
       vendor,
       count(DISTINCT d)                            AS days_present,
       round(count(*) * 1.0 / count(DISTINCT d), 0) AS mean_rows_per_present_day
FROM obs
GROUP BY 1,2
ORDER BY 1,2;
