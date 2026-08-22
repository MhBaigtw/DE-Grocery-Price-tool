-- B4b: how much does GTIN-14 normalisation change B4? Shows that joining on the raw
-- upc string would have understated cross-vendor overlap (leading-zero variants).
CREATE OR REPLACE TEMP MACRO digits(x) AS regexp_replace(coalesce(x,''), '[^0-9]', '', 'g');
CREATE OR REPLACE TEMP MACRO gtin14(x) AS lpad(digits(x), 14, '0');
CREATE OR REPLACE TEMP MACRO tier(v)   AS
  CASE WHEN v IN ('Metro','Galleria','SaveOnFoods','Walmart') THEN 'reliable' ELSE 'fuzzy' END;

-- RAW string join (no normalisation)
WITH raw_join AS (
  SELECT trim(upc) AS k, vendor, tier(vendor) AS t FROM product
  WHERE upc IS NOT NULL AND trim(upc) <> '' GROUP BY 1,2,3
), raw_agg AS (
  SELECT k, count(DISTINCT vendor) nv, count(DISTINCT vendor) FILTER (WHERE t='fuzzy') nf
  FROM raw_join GROUP BY k
),
norm_join AS (
  SELECT gtin14(upc) AS k, vendor, tier(vendor) AS t FROM product
  WHERE length(digits(upc)) BETWEEN 11 AND 14 AND digits(upc) !~ '^0+$' GROUP BY 1,2,3
), norm_agg AS (
  SELECT k, count(DISTINCT vendor) nv, count(DISTINCT vendor) FILTER (WHERE t='fuzzy') nf
  FROM norm_join GROUP BY k
)
SELECT 'raw_string_join' AS method,
       (SELECT count(*) FROM raw_agg)                                  AS distinct_keys,
       (SELECT count(*) FROM raw_agg WHERE nv>=2)                      AS at_2plus,
       (SELECT count(*) FROM raw_agg WHERE nv>=2 AND nf=0)             AS at_2plus_reliable_only
UNION ALL
SELECT 'gtin14_normalised',
       (SELECT count(*) FROM norm_agg),
       (SELECT count(*) FROM norm_agg WHERE nv>=2),
       (SELECT count(*) FROM norm_agg WHERE nv>=2 AND nf=0);
