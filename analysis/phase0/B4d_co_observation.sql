-- B4d: a shared UPC is only useful if the vendors observed it on the SAME DAYS.
-- B4 counts GTINs that appear at 2+ reliable vendors anywhere in history. This asks
-- the stricter question D4 actually needs: on how many days is the GTIN priced at 2+
-- reliable vendors simultaneously? A pair with zero overlapping days is uncomparable.
CREATE OR REPLACE TEMP MACRO digits(x) AS regexp_replace(coalesce(x,''), '[^0-9]', '', 'g');
CREATE OR REPLACE TEMP MACRO gtin14(x) AS lpad(digits(x), 14, '0');

CREATE OR REPLACE TEMP VIEW rel_obs AS
SELECT gtin14(p.upc) AS gtin, p.vendor,
       try_cast(substr(r.nowtime,1,10) AS DATE) AS d
FROM raw r JOIN product p ON p.id = r.product_id
WHERE p.vendor IN ('Metro','Galleria','SaveOnFoods','Walmart')
  AND length(digits(p.upc)) BETWEEN 11 AND 14
  AND digits(p.upc) !~ '^0+$'
  AND try_cast(substr(r.nowtime,1,10) AS DATE) >= DATE '2024-06-11';

-- GTINs that are reliable-only (no fuzzy vendor carries them), per B4.
CREATE OR REPLACE TEMP VIEW reliable_only_gtins AS
SELECT gtin14(upc) AS gtin FROM product
WHERE length(digits(upc)) BETWEEN 11 AND 14 AND digits(upc) !~ '^0+$'
GROUP BY 1
HAVING count(DISTINCT vendor) >= 2
   AND count(DISTINCT vendor) FILTER (WHERE vendor NOT IN ('Metro','Galleria','SaveOnFoods','Walmart')) = 0;

-- Days on which a GTIN is priced at 2+ reliable vendors at once.
CREATE OR REPLACE TEMP VIEW codays AS
SELECT o.gtin, o.d, count(DISTINCT o.vendor) AS vendors_that_day
FROM rel_obs o JOIN reliable_only_gtins g ON g.gtin = o.gtin
GROUP BY 1,2;

SELECT
  (SELECT count(*) FROM reliable_only_gtins)                                   AS b4_reliable_only_gtins,
  count(DISTINCT gtin) FILTER (WHERE vendors_that_day >= 2)                    AS gtins_with_any_coobserved_day,
  count(DISTINCT gtin) FILTER (WHERE vendors_that_day >= 2)
    * 100.0 / (SELECT count(*) FROM reliable_only_gtins)                       AS pct_coobserved
FROM codays;

-- Distribution of co-observed day counts: how deep is the usable history?
WITH per_g AS (
  SELECT gtin, count(*) FILTER (WHERE vendors_that_day>=2) AS codays
  FROM codays GROUP BY gtin
)
SELECT CASE WHEN codays = 0            THEN 'a. 0 days (never comparable)'
            WHEN codays < 30           THEN 'b. 1-29 days'
            WHEN codays < 90           THEN 'c. 30-89 days'
            WHEN codays < 180          THEN 'd. 90-179 days'
            WHEN codays < 365          THEN 'e. 180-364 days'
            ELSE                            'f. 365+ days' END AS coobserved_days_bucket,
       count(*) AS gtins
FROM per_g GROUP BY 1 ORDER BY 1;
