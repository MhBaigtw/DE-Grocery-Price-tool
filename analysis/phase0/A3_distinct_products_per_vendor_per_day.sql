-- A3: distinct products per vendor per day.
-- "Distinct product" here = distinct product_id within the day. product_id is not a
-- stable identity across days (locked decision #5) but within a single day's extract
-- it does identify a listing, so it is the right unit for a per-day breadth count.
-- Compare with A2's row count: rows > distinct products means duplicate listings (B6).
CREATE OR REPLACE TEMP VIEW obs AS
SELECT try_cast(substr(r.nowtime,1,10) AS DATE) AS d, p.vendor, r.product_id
FROM raw r JOIN product p ON p.id = r.product_id
WHERE try_cast(substr(r.nowtime,1,10) AS DATE) IS NOT NULL;

-- Monthly mean of distinct-products-per-day, per vendor, post-transition and pre.
SELECT date_trunc('month', d) AS month, vendor,
       count(DISTINCT d) AS days_present,
       round(avg(n_products),0) AS mean_distinct_products_per_day,
       min(n_products) AS min_day, max(n_products) AS max_day
FROM (SELECT d, vendor, count(DISTINCT product_id) AS n_products
      FROM obs GROUP BY 1,2)
GROUP BY 1,2 ORDER BY 1,2;
