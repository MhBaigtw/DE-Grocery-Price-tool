-- P3.5: prove the owned key is collision-free, across BOTH snapshots.
--
-- The analysis queries in sections 2 and 3 used DuckDB's 64-bit hash() as a workaround for
-- a statistics bug on VARCHAR sku columns. That produced ONE collision in 161,300 keys,
-- which silently merged two distinct products into a single price series and moved the D2
-- event count by 6. A workaround is an acceptable thing to have in a throwaway analysis
-- query; it is not an acceptable thing to have in the owned key.
--
-- The owned key is md5(vendor || chr(31) || sku), or md5(vendor || chr(31) || '#c:' ||
-- concatted) where the sku is blank. This proves zero collisions -- not "few", zero --
-- in each snapshot and in their union.
ATTACH IF NOT EXISTS 'hammer2.duckdb' AS s2 (READ_ONLY);
SET threads = 4;

-- 1. Snapshot 1: distinct key sources vs distinct keys. Equal means no collision.
SELECT 'snapshot_1' AS snapshot,
       count(*)                                                        AS product_rows,
       count(DISTINCT k_source(vendor, sku, concatted))                AS distinct_key_sources,
       count(DISTINCT product_key(vendor, sku, concatted))             AS distinct_keys,
       count(DISTINCT k_source(vendor, sku, concatted))
     - count(DISTINCT product_key(vendor, sku, concatted))             AS COLLISIONS
FROM product
UNION ALL
SELECT 'snapshot_2',
       count(*),
       count(DISTINCT k_source(vendor, sku, concatted)),
       count(DISTINCT product_key(vendor, sku, concatted)),
       count(DISTINCT k_source(vendor, sku, concatted))
     - count(DISTINCT product_key(vendor, sku, concatted))
FROM s2.product;

-- 2. Union of both snapshots -- a key must be collision-free across publications, not
--    merely within one, or a cross-snapshot join reintroduces the problem.
WITH allsrc AS (
  SELECT k_source(vendor, sku, concatted) AS src,
         product_key(vendor, sku, concatted) AS pk FROM product
  UNION
  SELECT k_source(vendor, sku, concatted),
         product_key(vendor, sku, concatted) FROM s2.product
)
SELECT count(DISTINCT src)                       AS distinct_sources_both_snapshots,
       count(DISTINCT pk)                        AS distinct_keys,
       count(DISTINCT src) - count(DISTINCT pk)  AS COLLISIONS
FROM allsrc;

-- 3. The 64-bit workaround hash, for contrast: the same test on the same data.
SELECT count(DISTINCT vendor || chr(31) || coalesce(sku,''))                   AS distinct_sources,
       count(DISTINCT hash(vendor || '|' || sku))                              AS distinct_64bit_hashes,
       count(DISTINCT vendor || chr(31) || coalesce(sku,''))
     - count(DISTINCT hash(vendor || '|' || sku))                              AS collisions_64bit
FROM product WHERE sku IS NOT NULL AND trim(sku) <> '';

-- 4. Key composition: how many products key on sku vs on concatted.
SELECT product_key_basis(sku) AS basis, count(*) AS products,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM product GROUP BY 1 ORDER BY products DESC;

-- 5. Is the key STABLE across snapshots? Same product, same key, both publications.
WITH a AS (SELECT product_key(vendor, sku, concatted) AS pk, vendor, sku FROM product
           WHERE sku IS NOT NULL AND trim(sku) <> ''),
     b AS (SELECT product_key(vendor, sku, concatted) AS pk, vendor, sku FROM s2.product
           WHERE sku IS NOT NULL AND trim(sku) <> '')
SELECT (SELECT count(*) FROM a)                                        AS keys_snap1,
       (SELECT count(*) FROM b)                                        AS keys_snap2,
       (SELECT count(*) FROM a JOIN b USING (pk))                      AS keys_matching_on_owned_key,
       (SELECT count(*) FROM a JOIN b ON a.vendor=b.vendor AND a.sku=b.sku)
                                                                        AS keys_matching_on_vendor_sku,
       (SELECT count(*) FROM a JOIN b USING (pk))
     - (SELECT count(*) FROM a JOIN b ON a.vendor=b.vendor AND a.sku=b.sku)
                                                                        AS DISAGREEMENT;
