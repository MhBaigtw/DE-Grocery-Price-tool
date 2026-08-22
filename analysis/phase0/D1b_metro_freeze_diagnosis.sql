-- D1b: why is Metro's freeze-window coverage so poor? Distinguish two causes:
--   (a) the vendor is missing on many days in the window (extract failures), vs
--   (b) the vendor is present but its SKU set churns, so no single SKU spans the window.
-- These have different implications: (a) is a data gap, (b) means Metro relists products.
SET threads = 4;
CREATE OR REPLACE TEMP TABLE win AS SELECT * FROM (VALUES
  ('2024-25', DATE '2024-11-01', DATE '2025-02-05'),
  ('2025-26', DATE '2025-11-01', DATE '2026-02-05')) t(window_label,d0,d1);

-- 1. Vendor-days present in each window (cause a).
SELECT w.window_label, p.vendor,
       date_diff('day',w.d0,w.d1)+1                                    AS window_days,
       count(DISTINCT try_cast(substr(r.nowtime,1,10) AS DATE))        AS vendor_days_present
FROM raw r JOIN product p ON p.id=r.product_id
JOIN win w ON try_cast(substr(r.nowtime,1,10) AS DATE) BETWEEN w.d0 AND w.d1
GROUP BY 1,2,3 ORDER BY 1,2;

-- 2. SKU churn (cause b): distribution of per-SKU days-present for Metro.
SELECT w.window_label,
       CASE WHEN dp >= 90 THEN 'a. 90-97 days'
            WHEN dp >= 60 THEN 'b. 60-89'
            WHEN dp >= 30 THEN 'c. 30-59'
            WHEN dp >= 10 THEN 'd. 10-29'
            ELSE 'e. 1-9' END AS days_present_bucket,
       count(*) AS metro_skus
FROM (SELECT w.window_label AS wl, p.sku,
             count(DISTINCT try_cast(substr(r.nowtime,1,10) AS DATE)) AS dp
      FROM raw r JOIN product p ON p.id=r.product_id
      JOIN win w ON try_cast(substr(r.nowtime,1,10) AS DATE) BETWEEN w.d0 AND w.d1
      WHERE p.vendor='Metro' AND p.sku IS NOT NULL AND trim(p.sku)<>''
      GROUP BY 1,2) s
JOIN win w ON w.window_label = s.wl
GROUP BY 1,2 ORDER BY 1,2;
