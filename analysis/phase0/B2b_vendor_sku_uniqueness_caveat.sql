-- B2b: why B2's "0% unstable" is tautological, and what the real test is.
-- Because product.id = vendor||sku for every non-blank-sku row, the product table can
-- physically hold only ONE row per (vendor,sku). So "does (vendor,sku) map to one name"
-- is true by construction, not by evidence. This query establishes that.
-- The real question -- does upstream ever RE-DESCRIBE a sku (new name/unit size) --
-- has to be asked of the base64-id rows, which are the ones that escape that constraint.

-- 1. Is (vendor,sku) unique in product? (If yes, B2 proves nothing.)
SELECT count(*) AS product_rows_with_sku,
       count(DISTINCT vendor || '\u0000' || sku) AS distinct_vendor_sku,
       count(*) - count(DISTINCT vendor || '\u0000' || sku) AS surplus_rows
FROM product WHERE sku IS NOT NULL AND trim(sku) <> '';

-- 2. Do any (vendor,sku) pairs appear on more than one product row (via a base64 id)?
--    These are the genuine re-descriptions and the only place a name/unit change shows.
SELECT vendor, sku, count(*) AS product_rows,
       count(DISTINCT lower(trim(product_name))) AS distinct_names,
       count(DISTINCT lower(trim(coalesce(units,'')))) AS distinct_units,
       string_agg(DISTINCT product_name, ' || ') AS names,
       string_agg(DISTINCT coalesce(units,'(blank)'), ' || ') AS unit_values
FROM product WHERE sku IS NOT NULL AND trim(sku) <> ''
GROUP BY vendor, sku HAVING count(*) > 1
ORDER BY product_rows DESC LIMIT 25;

-- 3. The `concatted` key bundles vendor+name+unit+brand. How many distinct concatted
--    values share one (vendor,sku)? That is the honest measure of re-description.
SELECT vendor,
       count(*) AS vendor_sku_keys,
       count(*) FILTER (WHERE n_concat > 1) AS keys_with_multiple_descriptions,
       round(100.0*count(*) FILTER (WHERE n_concat>1)/count(*),3) AS pct
FROM (SELECT vendor, sku, count(DISTINCT concatted) AS n_concat
      FROM product WHERE sku IS NOT NULL AND trim(sku)<>'' GROUP BY 1,2)
GROUP BY vendor ORDER BY vendor;
