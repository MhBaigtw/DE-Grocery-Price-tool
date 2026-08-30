-- E6 (bug): degenerate UPC values that would create false cross-vendor matches.
--   (a) all-zero UPCs of plausible length (excluded from B4 by the '^0+$' filter)
--   (b) a single UPC attached to many DIFFERENT product names at one vendor
-- NOTE on operators: DuckDB's `~` is regexp_full_match, NOT a partial match. The
-- '^0+$' test is fully anchored so `!~` is correct there; unanchored keyword searches
-- must use regexp_matches() instead (this bit D4 before it was fixed).
CREATE OR REPLACE TEMP MACRO digits(x) AS regexp_replace(coalesce(x,''),'[^0-9]','','g');

-- (a) all-zero UPCs
SELECT count(*) AS allzero_product_rows,
       count(DISTINCT vendor) AS vendors,
       string_agg(DISTINCT vendor, ',' ORDER BY vendor) AS vendor_list
FROM product
WHERE length(digits(upc)) BETWEEN 11 AND 14 AND digits(upc) ~ '^0+$';

-- (b) one UPC, many distinct product names at the SAME vendor
SELECT vendor, upc, count(DISTINCT product_name) AS distinct_names, count(*) AS product_rows,
       string_agg(DISTINCT product_name, ' | ' ORDER BY product_name) AS names
FROM product
WHERE length(digits(upc)) BETWEEN 11 AND 14 AND NOT digits(upc) ~ '^0+$'
GROUP BY vendor, upc
HAVING count(DISTINCT product_name) >= 4
ORDER BY distinct_names DESC LIMIT 12;
