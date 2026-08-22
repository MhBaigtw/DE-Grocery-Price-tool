-- D3: shrinkflation -- (vendor,sku) pairs whose parsed unit size changes over time,
-- holding or raising price across the change.
--
-- EXPECTED RESULT: ZERO, and the reason is structural, not empirical.
-- product.id = vendor||sku (B1b) and product.id is unique, so the product table can
-- physically hold only ONE units string per (vendor,sku) -- see B2b. There is no
-- history of unit size. If upstream ever revises a product's size, it overwrites.
-- This query establishes that directly rather than asserting it.
SET threads = 4;

-- 1. Direct test: does any (vendor,sku) carry more than one units string?
SELECT count(*) AS vendor_sku_with_multiple_unit_strings
FROM (SELECT vendor, sku FROM product
      WHERE sku IS NOT NULL AND trim(sku)<>''
      GROUP BY 1,2 HAVING count(DISTINCT coalesce(units,'')) > 1);

-- 2. Fallback avenue A: same vendor + same product_name, DIFFERENT units and different
--    sku. This is a relisting, and is the only shrinkflation signal available.
--    It cannot distinguish shrinkflation from "vendor also stocks a second size".
CREATE OR REPLACE TEMP MACRO u_norm(x) AS
  regexp_replace(lower(trim(translate(coalesce(x,''), chr(160)||chr(8201)||chr(8239),'   '))),'\s+',' ','g');
CREATE OR REPLACE TEMP MACRO u_qty(x) AS try_cast(regexp_extract(u_norm(x),
  '([0-9]+(?:\.[0-9]+)?) ?(kilogram|kg|gram|g|pound|pounds|lbs|lb|ounce|ounces|oz|litre|litres|liter|liters|millilitre|milliliter|ml|l|count|ct|pack|pk|piece|pc|each|ea|un|unit)\b',1) AS DOUBLE);
CREATE OR REPLACE TEMP MACRO u_tok(x) AS regexp_extract(u_norm(x),
  '[0-9](?: )?(kilogram|kg|gram|g|pound|pounds|lbs|lb|ounce|ounces|oz|litre|litres|liter|liters|millilitre|milliliter|ml|l|count|ct|pack|pk|piece|pc|each|ea|un|unit)\b',1);
CREATE OR REPLACE TEMP MACRO fac(t) AS CASE t
  WHEN 'kg' THEN 1000 WHEN 'kilogram' THEN 1000 WHEN 'lb' THEN 453.592 WHEN 'lbs' THEN 453.592
  WHEN 'pound' THEN 453.592 WHEN 'pounds' THEN 453.592 WHEN 'oz' THEN 28.3495
  WHEN 'ounce' THEN 28.3495 WHEN 'ounces' THEN 28.3495 WHEN 'l' THEN 1000
  WHEN 'litre' THEN 1000 WHEN 'litres' THEN 1000 WHEN 'liter' THEN 1000 WHEN 'liters' THEN 1000 ELSE 1 END;

CREATE OR REPLACE TEMP TABLE sized AS
SELECT vendor, sku, product_name, units,
       lower(trim(product_name)) AS n_name,
       u_qty(units)*fac(u_tok(units)) AS canon_qty,
       CASE WHEN u_tok(units) IN ('kg','kilogram','g','gram','lb','lbs','pound','pounds','oz','ounce','ounces') THEN 'mass'
            WHEN u_tok(units) IN ('l','litre','litres','liter','liters','ml','millilitre','milliliter') THEN 'vol'
            ELSE 'other' END AS cls
FROM product
WHERE sku IS NOT NULL AND trim(sku)<>'' AND units IS NOT NULL AND trim(units)<>'';

SELECT count(*) AS name_groups_with_multiple_sizes,
       sum(n_skus) AS skus_involved
FROM (SELECT vendor, n_name, cls, count(DISTINCT sku) AS n_skus
      FROM sized WHERE cls <> 'other' AND canon_qty IS NOT NULL
      GROUP BY 1,2,3
      HAVING count(DISTINCT canon_qty) > 1 AND count(DISTINCT sku) > 1);

-- 3. Sample for eyeballing: are these genuine size changes or just two shelf sizes?
SELECT vendor, n_name AS product_name, cls,
       count(DISTINCT sku) AS skus,
       string_agg(DISTINCT units, ' | ') AS unit_strings,
       string_agg(DISTINCT cast(canon_qty AS VARCHAR), ' | ') AS canonical_sizes
FROM sized WHERE cls <> 'other' AND canon_qty IS NOT NULL
GROUP BY 1,2,3
HAVING count(DISTINCT canon_qty) > 1 AND count(DISTINCT sku) > 1
ORDER BY hash(vendor||n_name) LIMIT 20;
