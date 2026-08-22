-- A2c: anomalously low volume days ("partial extracts").
-- These are more dangerous than missing days: the vendor IS present, so a naive
-- coverage check counts the day as good, but most of the catalogue is absent.
-- Rule: a day is a partial extract if the vendor's distinct-product count is below
-- 50% of that vendor's trailing-28-day median. Threshold is a judgement call, stated
-- here so it can be changed; counts at 25% and 10% are given for sensitivity.
-- Restricted to the full-catalogue era (>= 2024-06-11, see A2b).
CREATE OR REPLACE TEMP VIEW obs AS
SELECT try_cast(substr(r.nowtime,1,10) AS DATE) AS d, p.vendor, r.product_id
FROM raw r JOIN product p ON p.id = r.product_id
WHERE try_cast(substr(r.nowtime,1,10) AS DATE) >= DATE '2024-06-11';

CREATE OR REPLACE TEMP VIEW vd AS
SELECT vendor, d, count(DISTINCT product_id) AS n FROM obs GROUP BY 1,2;

CREATE OR REPLACE TEMP VIEW scored AS
SELECT vendor, d, n,
       median(n) OVER (PARTITION BY vendor ORDER BY d
                       ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING) AS trailing_median
FROM vd;

SELECT vendor,
       count(*)                                                     AS present_days,
       count(*) FILTER (WHERE n < 0.50*trailing_median)             AS days_below_50pct,
       count(*) FILTER (WHERE n < 0.25*trailing_median)             AS days_below_25pct,
       count(*) FILTER (WHERE n < 0.10*trailing_median)             AS days_below_10pct,
       round(100.0*count(*) FILTER (WHERE n < 0.50*trailing_median)/count(*),2) AS pct_days_below_50pct
FROM scored WHERE trailing_median IS NOT NULL
GROUP BY vendor ORDER BY days_below_50pct DESC;
