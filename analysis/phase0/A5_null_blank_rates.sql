-- A5: null / blank rate per column, per vendor.
-- "Blank" means NULL or empty-after-trim: the CSV/SQLite round-trip produces both and
-- treating '' as populated would overstate coverage.
-- product-level columns (units, brand, upc, sku) are measured over DISTINCT products;
-- raw-level columns (old_price, price_per_unit, other) over price ROWS, because those
-- are per-observation. Denominators are printed for both.
CREATE OR REPLACE TEMP MACRO blank(x) AS (x IS NULL OR trim(x) = '');

-- 1. product-level columns, denominator = distinct product rows per vendor
SELECT vendor,
       count(*) AS product_rows,
       round(100.0*count(*) FILTER (WHERE blank(units))      /count(*),2) AS pct_blank_units,
       round(100.0*count(*) FILTER (WHERE blank(brand))      /count(*),2) AS pct_blank_brand,
       round(100.0*count(*) FILTER (WHERE blank(upc))        /count(*),2) AS pct_blank_upc,
       round(100.0*count(*) FILTER (WHERE blank(sku))        /count(*),2) AS pct_blank_sku,
       round(100.0*count(*) FILTER (WHERE blank(detail_url)) /count(*),2) AS pct_blank_detail_url
FROM product GROUP BY vendor ORDER BY vendor;

-- 2. raw-level columns, denominator = price rows per vendor
SELECT p.vendor,
       count(*) AS price_rows,
       round(100.0*count(*) FILTER (WHERE blank(r.old_price))      /count(*),2) AS pct_blank_old_price,
       round(100.0*count(*) FILTER (WHERE blank(r.price_per_unit)) /count(*),2) AS pct_blank_price_per_unit,
       round(100.0*count(*) FILTER (WHERE blank(r.other))          /count(*),2) AS pct_blank_other,
       round(100.0*count(*) FILTER (WHERE blank(r.current_price))  /count(*),2) AS pct_blank_current_price
FROM raw r JOIN product p ON p.id = r.product_id
GROUP BY p.vendor ORDER BY p.vendor;
