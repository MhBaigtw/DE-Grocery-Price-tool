-- E7 (bugs): assorted field-level defects found while working sections A-D.
-- Each block is a separate reproducing query with its own magnitude.
SET threads = 4;
CREATE OR REPLACE TEMP MACRO blank(x) AS (x IS NULL OR trim(x)='');

-- (1) `units` literally containing the string 'error'
SELECT 'units_is_error' AS defect, count(*) AS products, count(DISTINCT vendor) AS vendors,
       string_agg(DISTINCT vendor,',' ORDER BY vendor) AS vendor_list
FROM product WHERE lower(trim(units)) = 'error';

-- (2) non-breaking space (U+00A0) inside `units` -- invisible, breaks naive \s parsing
SELECT 'nbsp_in_units' AS defect, count(*) AS products,
       count(DISTINCT vendor) AS vendors, string_agg(DISTINCT vendor,',' ORDER BY vendor) AS vendor_list
FROM product WHERE contains(units, chr(160));

-- (3) price_per_unit denominators that are not a sane basis
SELECT 'bad_ppu_denominator' AS defect,
       lower(regexp_extract(price_per_unit, '/\s*(.+)$', 1)) AS denominator,
       count(*) AS rows
FROM raw
WHERE NOT blank(price_per_unit)
  AND lower(regexp_extract(price_per_unit,'/\s*(.+)$',1)) IN
      ('100356g','100kg','100lb.','100l','100lt','100ea','100un.','')
GROUP BY 1,2 ORDER BY rows DESC;

-- (4) current_price that will not cast to a number, or is <= 0
SELECT 'unparseable_or_nonpositive_price' AS defect,
       count(*) FILTER (WHERE try_cast(current_price AS DOUBLE) IS NULL AND NOT blank(current_price)) AS unparseable,
       count(*) FILTER (WHERE try_cast(current_price AS DOUBLE) <= 0)                                 AS nonpositive,
       count(*) FILTER (WHERE blank(current_price))                                                   AS blank_price
FROM raw;

-- (5) old_price present but NOT greater than current_price -- a "sale" that isn't
SELECT 'oldprice_not_above_current' AS defect, p.vendor,
       count(*) AS rows_with_old_price,
       count(*) FILTER (WHERE try_cast(r.old_price AS DOUBLE) <= try_cast(r.current_price AS DOUBLE)) AS old_le_current,
       round(100.0*count(*) FILTER (WHERE try_cast(r.old_price AS DOUBLE) <= try_cast(r.current_price AS DOUBLE))
             /count(*),2) AS pct
FROM raw r JOIN product p ON p.id=r.product_id
WHERE NOT blank(r.old_price)
GROUP BY 1,2 ORDER BY pct DESC;

-- (6) rows flagged Out of Stock that still carry a price
SELECT 'out_of_stock_with_price' AS defect,
       count(*) AS oos_rows,
       count(*) FILTER (WHERE try_cast(current_price AS DOUBLE) > 0) AS oos_rows_with_positive_price
FROM raw WHERE lower(other) LIKE '%out of stock%';
