-- B2: is (vendor, sku) a stable identity?
-- Test: for each (vendor, sku), how many distinct product_name / units values does it
-- carry across its observed life? A stable key gives exactly one of each.
-- Names are compared case-insensitively with whitespace collapsed, so pure formatting
-- churn is not counted as a change (that would overstate instability).
CREATE OR REPLACE TEMP MACRO norm(x) AS lower(regexp_replace(trim(coalesce(x,'')), '\s+', ' ', 'g'));

CREATE OR REPLACE TEMP VIEW keyed AS
SELECT vendor, sku, norm(product_name) AS n_name, norm(units) AS n_units, id
FROM product
WHERE sku IS NOT NULL AND trim(sku) <> '';

SELECT vendor,
       count(*)                                                        AS distinct_vendor_sku,
       count(*) FILTER (WHERE n_names > 1)                             AS sku_with_multiple_names,
       round(100.0*count(*) FILTER (WHERE n_names>1)/count(*),2)       AS pct_name_unstable,
       count(*) FILTER (WHERE n_units > 1)                             AS sku_with_multiple_units,
       round(100.0*count(*) FILTER (WHERE n_units>1)/count(*),2)       AS pct_units_unstable,
       count(*) FILTER (WHERE n_names>1 OR n_units>1)                  AS sku_unstable_either,
       round(100.0*count(*) FILTER (WHERE n_names>1 OR n_units>1)/count(*),2) AS pct_unstable_either
FROM (SELECT vendor, sku,
             count(DISTINCT n_name)  AS n_names,
             count(DISTINCT n_units) AS n_units
      FROM keyed GROUP BY 1,2)
GROUP BY vendor ORDER BY pct_unstable_either DESC;

-- Overall, one line.
SELECT count(*) AS all_vendor_sku_keys,
       count(*) FILTER (WHERE n_names>1 OR n_units>1) AS unstable_keys,
       round(100.0*count(*) FILTER (WHERE n_names>1 OR n_units>1)/count(*),3) AS pct_unstable
FROM (SELECT vendor, sku, count(DISTINCT n_name) AS n_names, count(DISTINCT n_units) AS n_units
      FROM keyed GROUP BY 1,2);
