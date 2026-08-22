-- B3: UPC coverage -- fraction of products with a non-blank upc, per vendor.
-- Reported two ways, because they answer different questions:
--   (a) by distinct product: how much of the catalogue is identifiable
--   (b) by price observation: how much of the actual time series is identifiable
-- Tier labels follow CLAUDE.md's Known Contamination section.
CREATE OR REPLACE TEMP MACRO blank(x) AS (x IS NULL OR trim(x)='');
CREATE OR REPLACE TEMP MACRO tier(v) AS
  CASE WHEN v IN ('Metro','Galleria','SaveOnFoods') THEN '1_vendor_direct'
       WHEN v = 'Walmart'                            THEN '2_matched_walmart_source'
       ELSE '3_fuzzy_matched' END;

-- (a) catalogue coverage
SELECT tier(vendor) AS upc_tier, vendor,
       count(*) AS products,
       count(*) FILTER (WHERE NOT blank(upc)) AS products_with_upc,
       round(100.0*count(*) FILTER (WHERE NOT blank(upc))/count(*),2) AS pct_with_upc
FROM product GROUP BY 1,2 ORDER BY 1,2;

-- (b) time-series coverage
SELECT tier(p.vendor) AS upc_tier, p.vendor,
       count(*) AS price_rows,
       count(*) FILTER (WHERE NOT blank(p.upc)) AS price_rows_with_upc,
       round(100.0*count(*) FILTER (WHERE NOT blank(p.upc))/count(*),2) AS pct_rows_with_upc
FROM raw r JOIN product p ON p.id=r.product_id
GROUP BY 1,2 ORDER BY 1,2;

-- (c) UPC format sanity: length distribution. A real UPC-A is 12 digits, EAN-13 is 13.
SELECT length(trim(upc)) AS upc_len, count(*) AS products,
       count(DISTINCT vendor) AS vendors,
       string_agg(DISTINCT vendor, ',') AS vendor_list
FROM product WHERE NOT blank(upc)
GROUP BY 1 ORDER BY products DESC;
