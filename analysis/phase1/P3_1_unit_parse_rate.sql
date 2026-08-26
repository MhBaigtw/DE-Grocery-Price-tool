-- P3.1: unit parse rate per vendor, against the canonical (quantity, unit, pack_count)
-- model in stg_product.
--
-- Phase 0 C1 measured 88.12% with an ad-hoc parser. This measures the committed one, and
-- separates the two populations that a single percentage hides: products with NO units
-- text at all (nothing to parse) versus products whose units text failed to parse
-- (something to fix).
SET threads = 4;

-- 1. Headline, per vendor. Denominators stated separately so "88%" is never ambiguous
--    about what it is a percentage OF.
SELECT vendor,
       count(*)                                                          AS products,
       count(*) FILTER (WHERE units_raw IS NULL OR trim(units_raw) = '') AS no_units_text,
       count(*) FILTER (WHERE units_raw IS NOT NULL AND trim(units_raw) <> '') AS has_units_text,
       count(*) FILTER (WHERE unit_qty IS NOT NULL)                      AS parsed,
       round(100.0 * count(*) FILTER (WHERE unit_qty IS NOT NULL)
             / nullif(count(*) FILTER (WHERE units_raw IS NOT NULL AND trim(units_raw) <> ''), 0), 2)
                                                                          AS pct_of_text_parsed,
       round(100.0 * count(*) FILTER (WHERE unit_qty IS NOT NULL) / count(*), 2)
                                                                          AS pct_of_all_parsed
FROM stg_product
GROUP BY vendor ORDER BY pct_of_text_parsed;

-- 2. Overall, one line.
SELECT count(*)                                                           AS all_products,
       count(*) FILTER (WHERE units_raw IS NULL OR trim(units_raw) = '')  AS no_units_text,
       count(*) FILTER (WHERE unit_qty IS NOT NULL)                       AS parsed,
       round(100.0 * count(*) FILTER (WHERE unit_qty IS NOT NULL)
             / nullif(count(*) FILTER (WHERE units_raw IS NOT NULL AND trim(units_raw) <> ''), 0), 2)
                                                                           AS pct_of_text_parsed
FROM stg_product;

-- 3. Unit-of-measure and pack distribution -- is the parser producing sensible shapes?
SELECT unit_uom,
       count(*)                                       AS products,
       count(*) FILTER (WHERE pack_count > 1)         AS multipacks,
       round(median(unit_qty), 1)                     AS median_item_qty,
       round(median(total_qty), 1)                    AS median_total_qty,
       max(pack_count)                                AS max_pack
FROM stg_product WHERE unit_qty IS NOT NULL
GROUP BY unit_uom ORDER BY products DESC;

-- 4. Parse confidence per vendor.
SELECT vendor,
       count(*) FILTER (WHERE unit_parse_confidence = 'exact')    AS exact,
       count(*) FILTER (WHERE unit_parse_confidence = 'derived')  AS derived_multipack,
       count(*) FILTER (WHERE unit_parse_confidence = 'inferred') AS inferred_count,
       count(*) FILTER (WHERE unit_parse_confidence = 'none')     AS none
FROM stg_product GROUP BY vendor ORDER BY vendor;

-- 5. The unparsed tail, with counts. Not dropped, not hidden.
SELECT units_raw, count(*) AS products,
       string_agg(DISTINCT vendor, ',') AS vendors
FROM stg_product
WHERE units_raw IS NOT NULL AND trim(units_raw) <> '' AND unit_qty IS NULL
GROUP BY units_raw ORDER BY products DESC LIMIT 25;
