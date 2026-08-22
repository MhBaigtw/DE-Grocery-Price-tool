-- C3: price movement per (vendor, sku).
-- How many distinct prices were ever observed, and what fraction of products NEVER
-- changed price across their entire observed history?
-- If that fraction is very high, several time-series analyses are dead.
--
-- Restricted to the full-catalogue era (>= 2024-06-11, per A2b) and to products with
-- a non-blank sku observed on at least 30 distinct days -- a product seen 3 times
-- cannot meaningfully be called "never changed".
SET threads = 4;

CREATE OR REPLACE TEMP TABLE series AS
SELECT p.vendor, p.sku,
       count(DISTINCT try_cast(substr(r.nowtime,1,10) AS DATE)) AS days_observed,
       count(DISTINCT r.current_price)                          AS distinct_prices,
       min(try_cast(r.current_price AS DOUBLE))                 AS min_price,
       max(try_cast(r.current_price AS DOUBLE))                 AS max_price
FROM raw r JOIN product p ON p.id = r.product_id
WHERE try_cast(substr(r.nowtime,1,10) AS DATE) >= DATE '2024-06-11'
  AND p.sku IS NOT NULL AND trim(p.sku) <> ''
  AND r.current_price IS NOT NULL AND trim(r.current_price) <> ''
GROUP BY 1,2
HAVING count(DISTINCT try_cast(substr(r.nowtime,1,10) AS DATE)) >= 30;

-- 1. Headline: fraction that never moved, per vendor.
SELECT vendor,
       count(*)                                                     AS sku_series,
       round(avg(days_observed),0)                                  AS mean_days_observed,
       count(*) FILTER (WHERE distinct_prices = 1)                  AS never_changed,
       round(100.0*count(*) FILTER (WHERE distinct_prices=1)/count(*),2) AS pct_never_changed,
       round(avg(distinct_prices),2)                                AS mean_distinct_prices,
       round(median(distinct_prices),1)                             AS median_distinct_prices,
       count(*) FILTER (WHERE distinct_prices >= 5)                 AS with_5plus_prices
FROM series GROUP BY vendor ORDER BY pct_never_changed DESC;

-- 2. Overall, one line.
SELECT count(*) AS all_series,
       count(*) FILTER (WHERE distinct_prices=1) AS never_changed,
       round(100.0*count(*) FILTER (WHERE distinct_prices=1)/count(*),2) AS pct_never_changed,
       count(*) FILTER (WHERE distinct_prices>=2) AS moved_at_least_once,
       count(*) FILTER (WHERE distinct_prices>=5) AS moved_4plus_times
FROM series;

-- 3. Distribution of distinct-price counts.
SELECT CASE WHEN distinct_prices=1 THEN 'a. 1 (flat)'
            WHEN distinct_prices=2 THEN 'b. 2'
            WHEN distinct_prices<=4 THEN 'c. 3-4'
            WHEN distinct_prices<=9 THEN 'd. 5-9'
            WHEN distinct_prices<=19 THEN 'e. 10-19'
            ELSE 'f. 20+' END AS distinct_price_bucket,
       count(*) AS sku_series,
       round(100.0*count(*)/sum(count(*)) OVER (),2) AS pct
FROM series GROUP BY 1 ORDER BY 1;
