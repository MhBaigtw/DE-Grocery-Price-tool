-- E8 (bug, HIGH severity): `current_price` is not always a scalar price.
-- It sometimes holds a MULTIBUY offer ("2/$7.00") or a PER-WEIGHT rate ("1.99/100g").
-- Consequences:
--   * try_cast(current_price AS DOUBLE) silently yields NULL -> rows vanish from any
--     naive numeric analysis, with no error.
--   * Stripping to the trailing number is WORSE than dropping: "2/$7.00" means $3.50
--     each, not $7.00.
-- The damage is concentrated in Metro and Save-On-Foods -- two of the three
-- vendor-direct-UPC vendors, i.e. exactly the ones B4 relies on.
SET threads = 4;

-- 1. Magnitude overall and per vendor.
SELECT p.vendor,
       count(*)                                                          AS price_rows,
       count(*) FILTER (WHERE try_cast(r.current_price AS DOUBLE) IS NULL
                          AND trim(r.current_price) <> '')               AS non_scalar_rows,
       round(100.0*count(*) FILTER (WHERE try_cast(r.current_price AS DOUBLE) IS NULL
                          AND trim(r.current_price) <> '')/count(*),2)   AS pct_non_scalar,
       count(*) FILTER (WHERE regexp_matches(r.current_price, '^[0-9]+/\$'))     AS multibuy_form,
       count(*) FILTER (WHERE regexp_matches(r.current_price, '/[0-9]*[a-z]+$')) AS per_weight_form
FROM raw r JOIN product p ON p.id = r.product_id
GROUP BY p.vendor ORDER BY pct_non_scalar DESC;

-- 2. The distinct shapes, so a future parser knows what it must handle.
SELECT CASE
         WHEN regexp_matches(current_price, '^[0-9]+/\$[0-9]')      THEN 'multibuy  N/$X.XX'
         WHEN regexp_matches(current_price, '^[0-9.]+/[0-9]*[a-z]+$') THEN 'per-weight X.XX/100g'
         ELSE 'other' END AS shape,
       count(*) AS rows,
       min(current_price) AS example_min, max(current_price) AS example_max
FROM raw
WHERE try_cast(current_price AS DOUBLE) IS NULL AND trim(current_price) <> ''
GROUP BY 1 ORDER BY rows DESC;

-- 3. Does it move over time? (Is this a recent regression or always present?)
SELECT date_trunc('month', try_cast(substr(nowtime,1,10) AS DATE)) AS month,
       count(*) FILTER (WHERE try_cast(current_price AS DOUBLE) IS NULL
                          AND trim(current_price) <> '') AS non_scalar_rows,
       round(100.0*count(*) FILTER (WHERE try_cast(current_price AS DOUBLE) IS NULL
                          AND trim(current_price) <> '')/count(*),2) AS pct
FROM raw WHERE try_cast(substr(nowtime,1,10) AS DATE) IS NOT NULL
GROUP BY 1 ORDER BY 1;
