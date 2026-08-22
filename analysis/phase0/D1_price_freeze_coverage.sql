-- D1: price-freeze verification (Nov 1 - Feb 5), coverage feasibility.
-- Two freeze windows fall inside the data: 2024-11-01..2025-02-05 and
-- 2025-11-01..2026-02-05. Metro is the vendor that made the public claim.
-- Question: how many products have >=90% daily coverage across the FULL window, and
-- how many have zero gaps? Honesty rule #1: a missing day is not an unchanged price,
-- so a freeze cannot be verified on a product whose history is full of holes.
SET threads = 4;

CREATE OR REPLACE TEMP TABLE win AS
SELECT * FROM (VALUES
  ('2024-25', DATE '2024-11-01', DATE '2025-02-05'),
  ('2025-26', DATE '2025-11-01', DATE '2026-02-05')
) t(window_label, d0, d1);

CREATE OR REPLACE TEMP TABLE cov AS
SELECT w.window_label,
       date_diff('day', w.d0, w.d1) + 1                                  AS window_days,
       p.vendor, p.sku,
       count(DISTINCT try_cast(substr(r.nowtime,1,10) AS DATE))          AS days_present,
       count(DISTINCT r.current_price)                                   AS distinct_prices
FROM raw r
JOIN product p ON p.id = r.product_id
JOIN win w ON try_cast(substr(r.nowtime,1,10) AS DATE) BETWEEN w.d0 AND w.d1
WHERE p.sku IS NOT NULL AND trim(p.sku) <> ''
  AND r.current_price IS NOT NULL AND trim(r.current_price) <> ''
GROUP BY 1,2,3,4;

-- 1. Coverage feasibility per window per vendor.
SELECT window_label, vendor,
       any_value(window_days)                                            AS window_days,
       count(*)                                                          AS skus_seen_at_all,
       count(*) FILTER (WHERE days_present >= 0.90*window_days)           AS skus_90pct_coverage,
       count(*) FILTER (WHERE days_present  = window_days)                AS skus_zero_gaps,
       round(100.0*count(*) FILTER (WHERE days_present >= 0.90*window_days)/count(*),2) AS pct_90pct,
       round(100.0*count(*) FILTER (WHERE days_present  = window_days)/count(*),2)      AS pct_zero_gaps
FROM cov GROUP BY window_label, vendor ORDER BY window_label, vendor;

-- 2. Of the well-covered SKUs, how many actually held price for the whole window?
--    (This is the finding itself, but only computable where coverage supports it.)
SELECT window_label, vendor,
       count(*) FILTER (WHERE days_present >= 0.90*window_days)                          AS well_covered_skus,
       count(*) FILTER (WHERE days_present >= 0.90*window_days AND distinct_prices = 1)  AS held_price_flat,
       round(100.0*count(*) FILTER (WHERE days_present >= 0.90*window_days AND distinct_prices=1)
             / nullif(count(*) FILTER (WHERE days_present >= 0.90*window_days),0),2)     AS pct_flat_among_well_covered
FROM cov GROUP BY window_label, vendor ORDER BY window_label, vendor;
