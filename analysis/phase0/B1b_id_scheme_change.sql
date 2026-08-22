-- B1b: why does B1 contradict the upstream "id changes every day" warning?
-- Hypothesis: upstream changed the id SCHEME. The old scheme is an opaque base64-ish
-- hash; the current scheme is literally vendor||sku. Test both the timeline and the
-- composition rule.
CREATE OR REPLACE TEMP VIEW obs AS
SELECT try_cast(substr(r.nowtime,1,10) AS DATE) AS d, r.product_id, p.vendor, p.sku
FROM raw r JOIN product p ON p.id = r.product_id
WHERE try_cast(substr(r.nowtime,1,10) AS DATE) IS NOT NULL;

-- 1. When is each id shape observed?
SELECT CASE WHEN product_id LIKE '%=' THEN 'base64ish_hash' ELSE 'vendor_prefixed' END AS id_shape,
       count(*) AS rows, min(d) AS first_day, max(d) AS last_day, count(DISTINCT d) AS days
FROM obs GROUP BY 1;

-- 2. Does product.id == vendor || sku for the vendor-prefixed shape?
--    (vendor spelling in the id differs from product.vendor for two vendors.)
SELECT vendor,
       count(*) AS product_rows,
       count(*) FILTER (WHERE id = replace(replace(vendor,'&',''),' ','') || sku) AS id_equals_vendor_sku,
       count(*) FILTER (WHERE id LIKE '%=')                                       AS id_is_base64ish,
       count(*) FILTER (WHERE sku IS NULL OR trim(sku)='')                        AS blank_sku
FROM product GROUP BY vendor ORDER BY vendor;

-- 3. The population B1 excluded: products with a BLANK sku. Are their ids stable?
--    These have no (vendor,sku) key, so stability must be judged on `concatted`.
SELECT count(*) AS blank_sku_series,
       round(avg(distinct_ids),3) AS avg_distinct_ids,
       count(*) FILTER (WHERE distinct_ids=1) AS series_with_one_id,
       round(100.0*count(*) FILTER (WHERE distinct_ids=1)/count(*),2) AS pct_single_id
FROM (
  SELECT p.concatted, count(DISTINCT r.product_id) AS distinct_ids
  FROM raw r JOIN product p ON p.id=r.product_id
  WHERE (p.sku IS NULL OR trim(p.sku)='')
  GROUP BY 1 HAVING count(DISTINCT try_cast(substr(r.nowtime,1,10) AS DATE)) >= 30
);
