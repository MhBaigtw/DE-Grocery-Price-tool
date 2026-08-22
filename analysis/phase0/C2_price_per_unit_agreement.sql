-- C2: does `price_per_unit` agree with current_price / parsed_quantity?
-- CLAUDE.md already flags price_per_unit as untrustworthy; this measures by how much.
-- Restricted to rows where BOTH sides are computable:
--   - units parses to a canonical quantity (C1 parser, same definitions)
--   - price_per_unit parses to (amount, per-quantity, unit class) and the class MATCHES
--     the product's unit class (comparing $/100g against a count is meaningless)
-- Disagreement = relative difference > 1%.
SET threads = 4;

CREATE OR REPLACE TEMP MACRO u_norm(x) AS
  regexp_replace(lower(trim(translate(coalesce(x,''), chr(160)||chr(8201)||chr(8239), '   '))), '\s+', ' ', 'g');
CREATE OR REPLACE TEMP MACRO u_mult(x) AS coalesce(
  try_cast(regexp_extract(u_norm(x), '^([0-9]+) ?[x*] ?[0-9]', 1) AS DOUBLE),
  try_cast(regexp_extract(u_norm(x), '[x*] ?([0-9]+)$', 1) AS DOUBLE), 1.0);
CREATE OR REPLACE TEMP MACRO u_qty(x) AS try_cast(regexp_extract(u_norm(x),
  '([0-9]+(?:\.[0-9]+)?) ?(kilogram|kilograms|kg|gram|grams|g|pound|pounds|lbs|lb|ounce|ounces|oz|litre|litres|liter|liters|millilitre|millilitres|milliliter|milliliters|ml|l|fl ?oz|count|ct|pack|packs|pk|piece|pieces|pc|each|ea|un|units|unit)\b',1) AS DOUBLE);
CREATE OR REPLACE TEMP MACRO u_tok(x) AS regexp_extract(u_norm(x),
  '[0-9](?: )?(kilogram|kilograms|kg|gram|grams|g|pound|pounds|lbs|lb|ounce|ounces|oz|litre|litres|liter|liters|millilitre|millilitres|milliliter|milliliters|ml|l|fl ?oz|count|ct|pack|packs|pk|piece|pieces|pc|each|ea|un|units|unit)\b',1);
CREATE OR REPLACE TEMP MACRO cls(tok) AS
  CASE WHEN tok IN ('kilogram','kilograms','kg','gram','grams','g','pound','pounds','lbs','lb','ounce','ounces','oz') THEN 'mass_g'
       WHEN tok IN ('litre','litres','liter','liters','millilitre','millilitres','milliliter','milliliters','ml','l','fl oz','floz') THEN 'volume_ml'
       WHEN tok IN ('count','ct','pack','packs','pk','piece','pieces','pc','each','ea','un','un.','units','unit','item') THEN 'count'
       ELSE NULL END;
CREATE OR REPLACE TEMP MACRO fac(tok) AS
  CASE tok WHEN 'kg' THEN 1000 WHEN 'kilogram' THEN 1000 WHEN 'kilograms' THEN 1000
           WHEN 'lb' THEN 453.592 WHEN 'lbs' THEN 453.592 WHEN 'pound' THEN 453.592 WHEN 'pounds' THEN 453.592
           WHEN 'oz' THEN 28.3495 WHEN 'ounce' THEN 28.3495 WHEN 'ounces' THEN 28.3495
           WHEN 'l' THEN 1000 WHEN 'litre' THEN 1000 WHEN 'litres' THEN 1000 WHEN 'liter' THEN 1000 WHEN 'liters' THEN 1000
           WHEN 'fl oz' THEN 29.5735 WHEN 'floz' THEN 29.5735 ELSE 1 END;

-- price_per_unit: "$2.00/100g" -> amount 2.00, per 100, token g
CREATE OR REPLACE TEMP MACRO ppu_amt(x) AS
  try_cast(regexp_extract(u_norm(x), '([0-9]+(?:\.[0-9]+)?)\s*/', 1) AS DOUBLE);
CREATE OR REPLACE TEMP MACRO ppu_qty(x) AS
  coalesce(try_cast(regexp_extract(u_norm(x), '/\s*([0-9]+(?:\.[0-9]+)?)', 1) AS DOUBLE), 1.0);
CREATE OR REPLACE TEMP MACRO ppu_tok(x) AS
  replace(regexp_extract(u_norm(x), '/\s*[0-9]*\.?[0-9]*\s*([a-z.]+)\s*$', 1), '.', '');

CREATE OR REPLACE TEMP TABLE cmp AS
SELECT p.vendor,
       cls(u_tok(p.units))                                        AS prod_class,
       u_qty(p.units) * fac(u_tok(p.units)) * u_mult(p.units)     AS prod_canon_qty,
       try_cast(r.current_price AS DOUBLE)                        AS price,
       cls(ppu_tok(r.price_per_unit))                             AS ppu_class,
       ppu_amt(r.price_per_unit)                                  AS ppu_amount,
       ppu_qty(r.price_per_unit) * fac(ppu_tok(r.price_per_unit)) AS ppu_canon_qty
FROM raw r JOIN product p ON p.id = r.product_id
WHERE r.price_per_unit IS NOT NULL AND trim(r.price_per_unit) <> ''
  AND p.units IS NOT NULL AND trim(p.units) <> '';

CREATE OR REPLACE TEMP TABLE evaluable AS
SELECT *,
       price / nullif(prod_canon_qty,0)      AS derived_unit_price,
       ppu_amount / nullif(ppu_canon_qty,0)  AS stated_unit_price
FROM cmp
WHERE prod_class IS NOT NULL AND ppu_class IS NOT NULL
  AND prod_class = ppu_class
  AND prod_canon_qty > 0 AND ppu_canon_qty > 0
  AND price IS NOT NULL AND ppu_amount IS NOT NULL;

-- 1. Denominators first: how much of the data is even evaluable?
SELECT (SELECT count(*) FROM raw)        AS all_raw_rows,
       (SELECT count(*) FROM cmp)        AS rows_with_ppu_and_units,
       (SELECT count(*) FROM evaluable)  AS rows_evaluable,
       round(100.0*(SELECT count(*) FROM evaluable)/(SELECT count(*) FROM raw),2) AS pct_of_raw_evaluable;

-- 2. Disagreement rate per vendor.
SELECT vendor,
       count(*)                                                                       AS evaluable_rows,
       count(*) FILTER (WHERE abs(derived_unit_price-stated_unit_price)
                              > 0.01*abs(stated_unit_price))                          AS disagree_gt_1pct,
       round(100.0*count(*) FILTER (WHERE abs(derived_unit_price-stated_unit_price)
                              > 0.01*abs(stated_unit_price))/count(*),2)              AS pct_disagree_gt_1pct,
       round(100.0*count(*) FILTER (WHERE abs(derived_unit_price-stated_unit_price)
                              > 0.10*abs(stated_unit_price))/count(*),2)              AS pct_disagree_gt_10pct,
       round(median(abs(derived_unit_price-stated_unit_price)/nullif(abs(stated_unit_price),0))*100,2)
                                                                                      AS median_abs_pct_diff
FROM evaluable GROUP BY vendor ORDER BY pct_disagree_gt_1pct DESC;

-- 3. Vendors with NO usable price_per_unit at all (excluded above, named here).
SELECT p.vendor, count(*) AS price_rows,
       count(*) FILTER (WHERE r.price_per_unit IS NULL OR trim(r.price_per_unit)='') AS blank_ppu_rows,
       round(100.0*count(*) FILTER (WHERE r.price_per_unit IS NULL OR trim(r.price_per_unit)='')/count(*),2) AS pct_blank
FROM raw r JOIN product p ON p.id=r.product_id
GROUP BY p.vendor ORDER BY pct_blank DESC;
