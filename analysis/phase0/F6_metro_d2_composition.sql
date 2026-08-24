-- F6: does D2's Metro slice carry the same selection skew F2 found in D1's 474?
--
-- The concern is well founded: Metro's D2-evaluable rate is 21.22% (23,472 of 110,604),
-- and the gate is the SAME mechanism F2 proved distorts D1 -- "did this SKU appear on
-- every one of 14 consecutive days". Products that survive a continuous-presence filter
-- are products with stable listings, and F2 showed those skew frozen-and-packaged.
--
-- Compares brand and category composition of Metro's evaluable events against ALL Metro
-- events. Category is the same crude keyword probe used in F2/D4 -- indicative only;
-- the dataset has no category column.
SET threads = 4;

CREATE OR REPLACE TEMP TABLE mdaily AS
SELECT p.sku, try_cast(substr(r.nowtime,1,10) AS DATE) AS d,
       max(CASE WHEN r.old_price IS NOT NULL AND trim(r.old_price)<>'' THEN 1 ELSE 0 END) AS on_sale
FROM raw r JOIN product p ON p.id = r.product_id
WHERE p.vendor='Metro' AND p.sku IS NOT NULL AND trim(p.sku)<>''
  AND try_cast(substr(r.nowtime,1,10) AS DATE) >= DATE '2024-06-11'
GROUP BY 1,2;

CREATE OR REPLACE TEMP TABLE mev AS
SELECT sku, d AS sale_start
FROM (SELECT sku, d, on_sale, lag(on_sale) OVER (PARTITION BY sku ORDER BY d) AS prev FROM mdaily)
WHERE on_sale=1 AND coalesce(prev,0)=0;

-- Pre-window presence via a RANGE window frame (one pass) rather than a correlated
-- subquery per event -- see the performance note in F5.
CREATE OR REPLACE TEMP TABLE mpre AS
SELECT sku, d, count(*) OVER (PARTITION BY sku ORDER BY d
         RANGE BETWEEN INTERVAL 14 DAY PRECEDING AND INTERVAL 1 DAY PRECEDING) AS pre_days
FROM mdaily;

CREATE OR REPLACE TEMP TABLE mscored AS
SELECT e.sku, e.sale_start, coalesce(pr.pre_days,0) AS pre_days
FROM mev e LEFT JOIN mpre pr ON pr.sku=e.sku AND pr.d=e.sale_start;

CREATE OR REPLACE TEMP TABLE mtagged AS
SELECT s.sku, s.sale_start,
       CASE WHEN s.pre_days = 14 THEN 'evaluable' ELSE 'not_evaluable' END AS grp,
       upper(trim(coalesce(p.brand,'(blank)'))) AS brand_u,
       CASE
         WHEN regexp_matches(lower(p.product_name),'(bread|bagel|bun|tortilla|pita|croissant)') THEN 'a. bread & bakery'
         WHEN regexp_matches(lower(p.product_name),'(milk|cream|yogur|yoghur|cheese|butter|margarine)') THEN 'b. dairy'
         WHEN regexp_matches(lower(p.product_name),'egg') THEN 'c. eggs'
         WHEN regexp_matches(lower(p.product_name),'(apple|banana|orange|potato|onion|carrot|tomato|lettuce|berry|berries|grape|pepper|broccoli|cucumber|salad)') THEN 'd. produce'
         WHEN regexp_matches(lower(p.product_name),'(chicken|beef|pork|turkey|bacon|ham|sausage|fish|salmon|tuna|shrimp)') THEN 'e. meat & fish'
         WHEN regexp_matches(lower(p.product_name),'(rice|pasta|flour|sugar|cereal|oat|noodle|soup|sauce)') THEN 'f. pantry staples'
         WHEN regexp_matches(lower(p.product_name),'(juice|coffee|tea|soda|water|cola|drink|beverage)') THEN 'g. beverages'
         WHEN regexp_matches(lower(p.product_name),'(frozen|pizza|ice cream)') THEN 'h. frozen'
         ELSE 'i. other' END AS cat
FROM mscored s
JOIN product p ON p.vendor='Metro' AND p.sku = s.sku;

-- 1. Cohort sizes (must reconcile with D2: Metro 110,604 events, 23,472 evaluable).
SELECT grp, count(*) AS events FROM mtagged GROUP BY grp ORDER BY grp;

-- 2. Category composition, evaluable vs all.
SELECT cat,
       count(*) FILTER (WHERE grp='evaluable')                                        AS evaluable,
       count(*)                                                                       AS all_events,
       round(100.0*count(*) FILTER (WHERE grp='evaluable')
             / sum(count(*) FILTER (WHERE grp='evaluable')) OVER (),2)                AS pct_of_evaluable,
       round(100.0*count(*) / sum(count(*)) OVER (),2)                                AS pct_of_all,
       round( (100.0*count(*) FILTER (WHERE grp='evaluable')
               / sum(count(*) FILTER (WHERE grp='evaluable')) OVER ())
            / nullif(100.0*count(*) / sum(count(*)) OVER (),0), 2)                    AS skew_ratio
FROM mtagged GROUP BY cat ORDER BY cat;

-- 3. Brand composition, top brands by presence in the evaluable set.
SELECT brand_u AS brand,
       count(*) FILTER (WHERE grp='evaluable')                                        AS evaluable,
       count(*)                                                                       AS all_events,
       round(100.0*count(*) FILTER (WHERE grp='evaluable')/nullif(count(*),0),1)      AS retention_pct,
       round(100.0*count(*) FILTER (WHERE grp='evaluable')
             / sum(count(*) FILTER (WHERE grp='evaluable')) OVER (),2)                AS pct_of_evaluable,
       round(100.0*count(*) / sum(count(*)) OVER (),2)                                AS pct_of_all
FROM mtagged GROUP BY brand_u
HAVING count(*) >= 300
ORDER BY evaluable DESC LIMIT 20;
