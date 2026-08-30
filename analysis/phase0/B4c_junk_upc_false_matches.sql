-- B4c: decompose the B4b difference. Two opposing effects:
--   (+) zero-padding merges 11-digit and 12-digit forms of the SAME product
--   (-) excluding <11-digit values removes SPURIOUS matches on junk codes
-- Both are corrections. This shows the size of each so the headline number is auditable.
CREATE OR REPLACE TEMP MACRO digits(x) AS regexp_replace(coalesce(x,''), '[^0-9]', '', 'g');
CREATE OR REPLACE TEMP MACRO gtin14(x) AS lpad(digits(x), 14, '0');
CREATE OR REPLACE TEMP MACRO tier(v)   AS
  CASE WHEN v IN ('Metro','Galleria','SaveOnFoods','Walmart') THEN 'reliable' ELSE 'fuzzy' END;

-- 1. Cross-vendor matches that exist ONLY because of short (<11 digit) codes.
WITH short_keys AS (
  SELECT trim(upc) AS k, vendor, tier(vendor) t FROM product
  WHERE upc IS NOT NULL AND trim(upc)<>'' AND length(digits(upc)) < 11 GROUP BY 1,2,3
)
SELECT count(*) AS junk_keys_at_2plus_vendors,
       count(*) FILTER (WHERE nf=0) AS junk_keys_reliable_only,
       sum(nv) AS vendor_memberships
FROM (SELECT k, count(DISTINCT vendor) nv, count(DISTINCT vendor) FILTER (WHERE t='fuzzy') nf
      FROM short_keys GROUP BY k HAVING count(DISTINCT vendor)>=2);

-- 2. Show the worst offenders: short codes shared across many vendors.
SELECT trim(upc) AS junk_upc, length(digits(upc)) AS n_digits,
       count(DISTINCT vendor) AS vendors,
       string_agg(DISTINCT vendor, ',') AS vendor_list,
       count(*) AS product_rows,
       min(product_name) AS example_name
FROM product
WHERE upc IS NOT NULL AND trim(upc)<>'' AND length(digits(upc)) < 11
GROUP BY 1,2 HAVING count(DISTINCT vendor)>=2
ORDER BY vendors DESC, product_rows DESC LIMIT 15;

-- 3. Gain from zero-padding: GTINs where 2+ vendors matched only after normalisation.
WITH n AS (
  SELECT gtin14(upc) g, trim(upc) k, vendor FROM product
  WHERE length(digits(upc)) BETWEEN 11 AND 14 AND digits(upc) !~ '^0+$' GROUP BY 1,2,3
)
SELECT count(*) AS gtins_rescued_by_zero_padding
FROM (SELECT g FROM n GROUP BY g
      HAVING count(DISTINCT vendor)>=2 AND count(DISTINCT k)>1);
