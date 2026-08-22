-- B6: duplicate magnitude -- rows per (product_id, date).
-- Upstream estimated ~6,500 products per day affected as of Nov 2024. Test that, and
-- show how it has moved over time.
--
-- Note: `min(price) <> max(price)` is used instead of `count(DISTINCT price)` -- it
-- answers the same question (do the duplicate rows disagree on price?) at a small
-- fraction of the memory, which matters at 71M rows.
SET threads = 4;

CREATE OR REPLACE TEMP TABLE dup AS
SELECT try_cast(substr(r.nowtime,1,10) AS DATE) AS d,
       p.vendor,
       r.product_id,
       count(*)                                          AS n_rows,
       (min(r.current_price) <> max(r.current_price))     AS price_conflict
FROM raw r JOIN product p ON p.id=r.product_id
WHERE try_cast(substr(r.nowtime,1,10) AS DATE) IS NOT NULL
GROUP BY 1,2,3;

-- 1. Monthly duplicate magnitude.
SELECT date_trunc('month', d) AS month,
       count(DISTINCT d)                                                AS days,
       sum(CASE WHEN n_rows>1 THEN 1 ELSE 0 END)                        AS dup_product_days,
       round(sum(CASE WHEN n_rows>1 THEN 1 ELSE 0 END)*1.0/count(DISTINCT d),0)
                                                                        AS mean_dup_products_per_day,
       sum(n_rows-1)                                                    AS surplus_rows,
       round(100.0*sum(CASE WHEN n_rows>1 THEN 1 ELSE 0 END)/count(*),2) AS pct_product_days_duplicated,
       sum(CASE WHEN price_conflict THEN 1 ELSE 0 END)                  AS dup_with_conflicting_price
FROM dup GROUP BY 1 ORDER BY 1;

-- 2. Per vendor, full-catalogue era only.
SELECT vendor,
       count(DISTINCT d) AS days,
       round(sum(CASE WHEN n_rows>1 THEN 1 ELSE 0 END)*1.0/count(DISTINCT d),0) AS mean_dup_products_per_day,
       max(n_rows) AS worst_single_product_day_rows,
       sum(CASE WHEN price_conflict THEN 1 ELSE 0 END) AS product_days_with_conflicting_price
FROM dup WHERE d >= DATE '2024-06-11'
GROUP BY vendor ORDER BY mean_dup_products_per_day DESC;
