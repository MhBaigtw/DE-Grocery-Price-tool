-- C1: unit string parseability.
-- A deliberately SIMPLE parser to canonical (quantity, unit) in grams / millilitres /
-- count. Simple is the point: it is the parser a real pipeline would start from, and
-- the tail it fails on is the finding. The tail is shown, not dropped (honesty rule #4).
--
-- Handled forms:
--   "500g", "1.36kg", "2 l", "675 g", "250 millilitre"     -> single quantity+unit
--   "6x93.0ml", "93ML*6", "4 x 100 g"                      -> multipack, quantity multiplied
--   "12un", "1ea", "6 count"                                -> count
--   "4 per pack", "2 per tray", "1 bunch"                    -> count (N-per-X form)
-- Conversions: kg->g x1000, lb->g x453.592, oz->g x28.3495, l->ml x1000, floz->ml x29.5735.

-- NOTE: DuckDB's \s does not match U+00A0 (non-breaking space), and 257 products
-- carry one inside `units` (Metro 235, Walmart 22) -- see E5. Those are translated to
-- a plain space FIRST, otherwise strings like '2<nbsp>l' silently fail to parse.
CREATE OR REPLACE TEMP MACRO u_norm(x) AS
  regexp_replace(
    lower(trim(translate(coalesce(x,''), chr(160) || chr(8201) || chr(8239), '   '))),
    '\s+', ' ', 'g');

-- multipack: leading "N x" or trailing "* N"
CREATE OR REPLACE TEMP MACRO u_mult(x) AS coalesce(
  try_cast(regexp_extract(u_norm(x), '^([0-9]+) ?[x*] ?[0-9]', 1) AS DOUBLE),
  try_cast(regexp_extract(u_norm(x), '[x*] ?([0-9]+)$', 1) AS DOUBLE),
  1.0);

-- the quantity attached to the unit token
CREATE OR REPLACE TEMP MACRO u_qty(x) AS
  try_cast(regexp_extract(u_norm(x),
    '([0-9]+(?:\.[0-9]+)?) ?(kilogram|kilograms|kg|gram|grams|g|pound|pounds|lbs|lb|ounce|ounces|oz|litre|litres|liter|liters|millilitre|millilitres|milliliter|milliliters|ml|l|fl ?oz|count|ct|pack|packs|pk|piece|pieces|pc|each|ea|un|units|unit)\b', 1)
  AS DOUBLE);

CREATE OR REPLACE TEMP MACRO u_tok(x) AS
  regexp_extract(u_norm(x),
    '[0-9](?: )?(kilogram|kilograms|kg|gram|grams|g|pound|pounds|lbs|lb|ounce|ounces|oz|litre|litres|liter|liters|millilitre|millilitres|milliliter|milliliters|ml|l|fl ?oz|count|ct|pack|packs|pk|piece|pieces|pc|each|ea|un|units|unit)\b', 1);

-- "N per pack" / "N per tray" / "N bunch": a count with a container word.
CREATE OR REPLACE TEMP MACRO u_perpack(x) AS
  try_cast(regexp_extract(u_norm(x), '^([0-9]+) (?:per )?(?:pack|tray|bunch|bag|box|case)$', 1) AS DOUBLE);

CREATE OR REPLACE TEMP MACRO u_class(x) AS
  CASE
    WHEN u_tok(x) IN ('kilogram','kilograms','kg','gram','grams','g','pound','pounds','lbs','lb','ounce','ounces','oz') THEN 'mass_g'
    WHEN u_tok(x) IN ('litre','litres','liter','liters','millilitre','millilitres','milliliter','milliliters','ml','l','fl oz','floz') THEN 'volume_ml'
    WHEN u_tok(x) IN ('count','ct','pack','packs','pk','piece','pieces','pc','each','ea','un','units','unit') THEN 'count'
    WHEN u_perpack(x) IS NOT NULL THEN 'count'
    ELSE NULL END;

CREATE OR REPLACE TEMP MACRO u_factor(x) AS
  CASE u_tok(x)
    WHEN 'kg' THEN 1000 WHEN 'kilogram' THEN 1000 WHEN 'kilograms' THEN 1000
    WHEN 'lb' THEN 453.592 WHEN 'lbs' THEN 453.592 WHEN 'pound' THEN 453.592 WHEN 'pounds' THEN 453.592
    WHEN 'oz' THEN 28.3495 WHEN 'ounce' THEN 28.3495 WHEN 'ounces' THEN 28.3495
    WHEN 'l' THEN 1000 WHEN 'litre' THEN 1000 WHEN 'litres' THEN 1000 WHEN 'liter' THEN 1000 WHEN 'liters' THEN 1000
    WHEN 'fl oz' THEN 29.5735 WHEN 'floz' THEN 29.5735
    ELSE 1 END;

CREATE OR REPLACE TEMP MACRO u_canon(x) AS
  coalesce(u_qty(x) * u_factor(x) * u_mult(x), u_perpack(x));

-- Also handle bare-count forms with no unit token: "4 per pack", "6 pack" already
-- covered; "4" alone is treated as unparseable (ambiguous).
CREATE OR REPLACE TEMP VIEW parsed AS
SELECT vendor, units,
       u_class(units)  AS unit_class,
       u_canon(units)  AS canonical_qty
FROM product
WHERE units IS NOT NULL AND trim(units) <> '';

-- 1. Parse rate per vendor (denominator = products with a non-blank units string).
SELECT vendor,
       count(*)                                                      AS products_with_units,
       count(*) FILTER (WHERE unit_class IS NOT NULL AND canonical_qty IS NOT NULL) AS parsed_ok,
       round(100.0*count(*) FILTER (WHERE unit_class IS NOT NULL AND canonical_qty IS NOT NULL)/count(*),2) AS pct_parsed,
       count(*) FILTER (WHERE unit_class='mass_g')    AS as_mass,
       count(*) FILTER (WHERE unit_class='volume_ml') AS as_volume,
       count(*) FILTER (WHERE unit_class='count')     AS as_count
FROM parsed GROUP BY vendor ORDER BY pct_parsed;

-- 2. Overall, with the blank-units population stated explicitly.
SELECT (SELECT count(*) FROM product)                                       AS all_products,
       (SELECT count(*) FROM product WHERE units IS NULL OR trim(units)='') AS blank_units,
       (SELECT count(*) FROM parsed)                                        AS with_units,
       (SELECT count(*) FROM parsed WHERE unit_class IS NOT NULL AND canonical_qty IS NOT NULL) AS parsed_ok,
       round(100.0*(SELECT count(*) FROM parsed WHERE unit_class IS NOT NULL AND canonical_qty IS NOT NULL)
             /(SELECT count(*) FROM parsed),2)                              AS pct_of_with_units,
       round(100.0*(SELECT count(*) FROM parsed WHERE unit_class IS NOT NULL AND canonical_qty IS NOT NULL)
             /(SELECT count(*) FROM product),2)                             AS pct_of_all_products;

-- 3. The 30 most common UNPARSEABLE strings, with counts. Not dropped silently.
SELECT units, count(*) AS products, count(DISTINCT vendor) AS vendors,
       string_agg(DISTINCT vendor, ',') AS vendor_list
FROM parsed WHERE unit_class IS NULL OR canonical_qty IS NULL
GROUP BY units ORDER BY products DESC LIMIT 30;
