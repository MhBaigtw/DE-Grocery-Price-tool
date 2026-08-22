-- F1: does E8 (non-scalar current_price) contaminate D2's sale-event count?
--
-- D2 keys entirely off `old_price` presence and NEVER references current_price, so no
-- event was excluded by E8: the 566,564 / 279,599 counts are complete as stated.
-- The real risk is the opposite one -- those counts OVERSTATE the usable sample,
-- because the actual D2 analysis ("was the price raised before the sale?") requires a
-- numeric price on the sale day AND across the 14-day pre-window. Any event touching a
-- non-scalar price will silently drop out at that point.
--
-- This query measures how many evaluable events would be lost, and to which vendors,
-- so the loss is a known quantity rather than a surprise in Phase 1.
SET threads = 4;

CREATE OR REPLACE TEMP TABLE daily AS
SELECT p.vendor, p.sku,
       try_cast(substr(r.nowtime,1,10) AS DATE) AS d,
       max(CASE WHEN r.old_price IS NOT NULL AND trim(r.old_price)<>'' THEN 1 ELSE 0 END) AS on_sale,
       -- a day is "price-dirty" if ANY row that day has an unparseable current_price
       max(CASE WHEN try_cast(r.current_price AS DOUBLE) IS NULL
                 AND trim(coalesce(r.current_price,'')) <> '' THEN 1 ELSE 0 END) AS dirty_price
FROM raw r JOIN product p ON p.id = r.product_id
WHERE p.sku IS NOT NULL AND trim(p.sku) <> ''
  AND try_cast(substr(r.nowtime,1,10) AS DATE) >= DATE '2024-06-11'
GROUP BY 1,2,3;

CREATE OR REPLACE TEMP TABLE events AS
SELECT vendor, sku, d AS sale_start
FROM (SELECT vendor, sku, d, on_sale,
             lag(on_sale) OVER (PARTITION BY vendor, sku ORDER BY d) AS prev_on_sale
      FROM daily)
WHERE on_sale = 1 AND coalesce(prev_on_sale,0) = 0;

CREATE OR REPLACE TEMP TABLE scored AS
SELECT e.vendor, e.sku, e.sale_start,
       (SELECT count(*) FROM daily x
         WHERE x.vendor=e.vendor AND x.sku=e.sku
           AND x.d BETWEEN e.sale_start - INTERVAL 14 DAY AND e.sale_start - INTERVAL 1 DAY) AS pre_days,
       (SELECT max(x.dirty_price) FROM daily x
         WHERE x.vendor=e.vendor AND x.sku=e.sku AND x.d = e.sale_start)                     AS dirty_on_sale_day,
       (SELECT max(x.dirty_price) FROM daily x
         WHERE x.vendor=e.vendor AND x.sku=e.sku
           AND x.d BETWEEN e.sale_start - INTERVAL 14 DAY AND e.sale_start - INTERVAL 1 DAY) AS dirty_in_prewindow
FROM events e;

-- 1. Headline: nothing was excluded; this is what WOULD be lost downstream.
SELECT
  count(*)                                                         AS all_sale_events,
  count(*) FILTER (WHERE pre_days = 14)                            AS d2_evaluable_events,
  count(*) FILTER (WHERE pre_days = 14
                     AND (coalesce(dirty_on_sale_day,0)=1
                       OR coalesce(dirty_in_prewindow,0)=1))       AS evaluable_but_price_dirty,
  count(*) FILTER (WHERE pre_days = 14
                     AND coalesce(dirty_on_sale_day,0)=0
                     AND coalesce(dirty_in_prewindow,0)=0)         AS evaluable_AND_price_clean,
  round(100.0*count(*) FILTER (WHERE pre_days=14
                     AND (coalesce(dirty_on_sale_day,0)=1
                       OR coalesce(dirty_in_prewindow,0)=1))
        / nullif(count(*) FILTER (WHERE pre_days=14),0),2)         AS pct_of_evaluable_lost
FROM scored;

-- 2. Per vendor -- this is where bias, if any, shows up.
SELECT vendor,
       count(*) FILTER (WHERE pre_days=14)                                   AS d2_evaluable,
       count(*) FILTER (WHERE pre_days=14
                          AND (coalesce(dirty_on_sale_day,0)=1
                            OR coalesce(dirty_in_prewindow,0)=1))            AS lost_to_e8,
       count(*) FILTER (WHERE pre_days=14
                          AND coalesce(dirty_on_sale_day,0)=0
                          AND coalesce(dirty_in_prewindow,0)=0)              AS surviving,
       round(100.0*count(*) FILTER (WHERE pre_days=14
                          AND (coalesce(dirty_on_sale_day,0)=1
                            OR coalesce(dirty_in_prewindow,0)=1))
             / nullif(count(*) FILTER (WHERE pre_days=14),0),2)              AS pct_lost
FROM scored GROUP BY vendor ORDER BY pct_lost DESC;

-- 3. Vendor MIX before vs after, which is the actual test of bias.
WITH ev AS (
  SELECT vendor,
         count(*) FILTER (WHERE pre_days=14) AS before_n,
         count(*) FILTER (WHERE pre_days=14 AND coalesce(dirty_on_sale_day,0)=0
                            AND coalesce(dirty_in_prewindow,0)=0) AS after_n
  FROM scored GROUP BY vendor)
SELECT vendor, before_n, after_n,
       round(100.0*before_n/sum(before_n) OVER (),2) AS pct_of_sample_before,
       round(100.0*after_n /sum(after_n)  OVER (),2) AS pct_of_sample_after,
       round(100.0*after_n /sum(after_n)  OVER ()
           - 100.0*before_n/sum(before_n) OVER (),2) AS share_shift_pp
FROM ev ORDER BY share_shift_pp;
