-- D2: sale honesty -- was the price raised just before the sale?
-- Two numbers, and their intersection is the real sample size:
--   (a) distinct sale EVENTS: a transition where old_price goes absent -> present
--       for a (vendor,sku). Consecutive sale days are one event, not many.
--   (b) of those, how many have >=14 days of CONTINUOUS pre-sale daily history
--       immediately before the event. "Continuous" means a row on every one of the
--       14 calendar days -- honesty rule #1, a missing day is not an unchanged price.
-- Vendors whose old_price is effectively unpopulated (Galleria, 0.92%) will show a
-- tiny sample; that is the finding, not a bug.
SET threads = 4;

CREATE OR REPLACE TEMP TABLE daily AS
SELECT p.vendor, p.sku,
       try_cast(substr(r.nowtime,1,10) AS DATE)                     AS d,
       max(CASE WHEN r.old_price IS NOT NULL AND trim(r.old_price)<>'' THEN 1 ELSE 0 END) AS on_sale
FROM raw r JOIN product p ON p.id = r.product_id
WHERE p.sku IS NOT NULL AND trim(p.sku) <> ''
  AND try_cast(substr(r.nowtime,1,10) AS DATE) >= DATE '2024-06-11'
GROUP BY 1,2,3;

-- sale event = first day of a run of on_sale=1, where the previous OBSERVED day was not on sale
CREATE OR REPLACE TEMP TABLE events AS
SELECT vendor, sku, d AS sale_start
FROM (SELECT vendor, sku, d, on_sale,
             lag(on_sale) OVER (PARTITION BY vendor, sku ORDER BY d) AS prev_on_sale
      FROM daily)
WHERE on_sale = 1 AND coalesce(prev_on_sale,0) = 0;

-- continuous pre-sale history: rows present on each of the 14 calendar days before start
CREATE OR REPLACE TEMP TABLE evaluable AS
SELECT e.vendor, e.sku, e.sale_start,
       (SELECT count(*) FROM daily x
         WHERE x.vendor=e.vendor AND x.sku=e.sku
           AND x.d BETWEEN e.sale_start - INTERVAL 14 DAY AND e.sale_start - INTERVAL 1 DAY) AS pre_days_present
FROM events e;

-- 1. Per vendor: events, and events with a full 14-day continuous run before them.
SELECT vendor,
       count(*)                                                        AS sale_events,
       count(*) FILTER (WHERE pre_days_present = 14)                   AS events_with_14d_continuous_history,
       round(100.0*count(*) FILTER (WHERE pre_days_present=14)/count(*),2) AS pct_evaluable,
       count(*) FILTER (WHERE pre_days_present >= 10)                  AS events_with_10plus_days,
       count(DISTINCT sku)                                             AS distinct_skus_with_any_sale
FROM evaluable GROUP BY vendor ORDER BY events_with_14d_continuous_history DESC;

-- 2. Overall intersection -- the real sample size for D2.
SELECT count(*) AS all_sale_events,
       count(*) FILTER (WHERE pre_days_present=14) AS evaluable_events,
       round(100.0*count(*) FILTER (WHERE pre_days_present=14)/count(*),2) AS pct
FROM evaluable;
