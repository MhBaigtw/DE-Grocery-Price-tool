-- P1.3: THE key test of Section 1. For products present in both snapshots, does
-- (vendor, sku) refer to the same product?
--
-- Phase 0 showed product.id = vendor||sku is stable WITHIN a snapshot, and flagged that
-- as tautological: the table cannot represent an inconsistency, because id is unique and
-- derived from the key. This is the first test that is not circular -- two independently
-- published files, compared on the key we are proposing to own.
--
-- If (vendor, sku) is stable here, Section 4's surrogate key is straightforward.
-- If it is not, Section 4 changes shape entirely.
ATTACH IF NOT EXISTS 'hammer2.duckdb' AS s2 (READ_ONLY);
SET threads = 4;

CREATE OR REPLACE TEMP MACRO norm(x) AS
  lower(regexp_replace(trim(coalesce(x,'')), '\s+', ' ', 'g'));

CREATE OR REPLACE TEMP TABLE k1 AS
SELECT vendor, sku, norm(product_name) AS name, norm(units) AS units, norm(brand) AS brand,
       norm(upc) AS upc, id
FROM product WHERE sku IS NOT NULL AND trim(sku) <> '';

CREATE OR REPLACE TEMP TABLE k2 AS
SELECT vendor, sku, norm(product_name) AS name, norm(units) AS units, norm(brand) AS brand,
       norm(upc) AS upc, id
FROM s2.product WHERE sku IS NOT NULL AND trim(sku) <> '';

-- 1. Key population: how many keys are shared, added, dropped.
SELECT (SELECT count(*) FROM k1)                                          AS keys_snapshot1,
       (SELECT count(*) FROM k2)                                          AS keys_snapshot2,
       (SELECT count(*) FROM k1 JOIN k2 USING (vendor, sku))              AS keys_in_both,
       (SELECT count(*) FROM k2 WHERE NOT EXISTS
          (SELECT 1 FROM k1 WHERE k1.vendor=k2.vendor AND k1.sku=k2.sku)) AS keys_added_in_snap2,
       (SELECT count(*) FROM k1 WHERE NOT EXISTS
          (SELECT 1 FROM k2 WHERE k2.vendor=k1.vendor AND k2.sku=k1.sku)) AS keys_dropped_in_snap2;

-- 2. THE HEADLINE: disagreement rate per vendor, for keys present in both.
SELECT a.vendor,
       count(*)                                                    AS shared_keys,
       count(*) FILTER (WHERE a.name  <> b.name)                   AS name_changed,
       count(*) FILTER (WHERE a.units <> b.units)                  AS units_changed,
       count(*) FILTER (WHERE a.brand <> b.brand)                  AS brand_changed,
       count(*) FILTER (WHERE a.upc   <> b.upc)                    AS upc_changed,
       count(*) FILTER (WHERE a.name<>b.name OR a.units<>b.units
                          OR a.brand<>b.brand OR a.upc<>b.upc)     AS any_disagreement,
       round(100.0*count(*) FILTER (WHERE a.name<>b.name OR a.units<>b.units
                          OR a.brand<>b.brand OR a.upc<>b.upc)/count(*),4) AS pct_disagree
FROM k1 a JOIN k2 b USING (vendor, sku)
GROUP BY a.vendor ORDER BY pct_disagree DESC;

-- 3. Overall, one line -- the number Section 4 depends on.
SELECT count(*) AS shared_keys,
       count(*) FILTER (WHERE a.name<>b.name OR a.units<>b.units
                          OR a.brand<>b.brand OR a.upc<>b.upc) AS disagreeing_keys,
       round(100.0*count(*) FILTER (WHERE a.name<>b.name OR a.units<>b.units
                          OR a.brand<>b.brand OR a.upc<>b.upc)/count(*),4) AS pct_disagree,
       count(*) FILTER (WHERE a.id <> b.id)                     AS product_id_changed
FROM k1 a JOIN k2 b USING (vendor, sku);

-- 4. Every disagreement, shown so the KIND of change is visible (not just the rate).
SELECT a.vendor, a.sku,
       CASE WHEN a.name<>b.name THEN 'name ' ELSE '' END ||
       CASE WHEN a.units<>b.units THEN 'units ' ELSE '' END ||
       CASE WHEN a.brand<>b.brand THEN 'brand ' ELSE '' END ||
       CASE WHEN a.upc<>b.upc THEN 'upc ' ELSE '' END           AS fields_changed,
       a.name AS name_snap1, b.name AS name_snap2,
       a.units AS units_snap1, b.units AS units_snap2,
       a.upc AS upc_snap1, b.upc AS upc_snap2
FROM k1 a JOIN k2 b USING (vendor, sku)
WHERE a.name<>b.name OR a.units<>b.units OR a.brand<>b.brand OR a.upc<>b.upc
ORDER BY a.vendor, a.sku LIMIT 40;

-- 5. Direction of the UPC churn. Blank -> populated is ENRICHMENT and is harmless.
--    Populated -> DIFFERENT populated is INSTABILITY and breaks cross-vendor matching
--    reproducibility. These must not be reported as one number.
SELECT a.vendor,
       count(*) FILTER (WHERE a.upc <> b.upc)                                   AS upc_changed,
       count(*) FILTER (WHERE a.upc = '' AND b.upc <> '')                       AS blank_to_populated,
       count(*) FILTER (WHERE a.upc <> '' AND b.upc = '')                       AS populated_to_blank,
       count(*) FILTER (WHERE a.upc <> '' AND b.upc <> '' AND a.upc <> b.upc)   AS VALUE_CHANGED,
       round(100.0*count(*) FILTER (WHERE a.upc <> '' AND b.upc <> '' AND a.upc <> b.upc)
             / nullif(count(*) FILTER (WHERE a.upc <> ''),0), 3)                AS pct_of_populated_upcs_changed
FROM k1 a JOIN k2 b USING (vendor, sku)
GROUP BY a.vendor ORDER BY upc_changed DESC;

-- 6. Does the churn touch the RELIABLE-tier set that D4's basket depends on?
SELECT CASE WHEN a.vendor IN ('Metro','Galleria','SaveOnFoods','Walmart')
            THEN 'reliable_tier' ELSE 'fuzzy_tier' END                          AS tier,
       count(*)                                                                 AS shared_keys,
       count(*) FILTER (WHERE a.upc <> '' AND b.upc <> '' AND a.upc <> b.upc)   AS upc_value_changed,
       count(*) FILTER (WHERE a.upc = '' AND b.upc <> '')                       AS upc_gained
FROM k1 a JOIN k2 b USING (vendor, sku)
GROUP BY 1;

-- 7. Are the "value changed" UPCs genuinely different products, or the same GTIN with
--    different zero-padding? Phase 0 B4 already normalises to GTIN-14 for exactly this
--    reason; applying the same rule here separates real instability from formatting.
CREATE OR REPLACE TEMP MACRO digits(x) AS regexp_replace(coalesce(x,''),'[^0-9]','','g');
CREATE OR REPLACE TEMP MACRO gtin14(x) AS lpad(digits(x),14,'0');

SELECT a.vendor,
       count(*)                                                        AS upc_value_changed_raw,
       count(*) FILTER (WHERE gtin14(a.upc) = gtin14(b.upc))           AS same_after_gtin14_normalisation,
       count(*) FILTER (WHERE gtin14(a.upc) <> gtin14(b.upc))          AS GENUINELY_DIFFERENT,
       round(100.0*count(*) FILTER (WHERE gtin14(a.upc) <> gtin14(b.upc))
             / nullif(count(*) FILTER (WHERE a.upc <> ''),0), 4)       AS pct_of_populated_genuinely_unstable
FROM k1 a JOIN k2 b USING (vendor, sku)
WHERE a.upc <> '' AND b.upc <> '' AND a.upc <> b.upc
GROUP BY a.vendor ORDER BY 4 DESC;

-- 8. The genuinely-different ones, for inspection.
SELECT a.vendor, a.sku, a.name, a.upc AS upc_snap1, b.upc AS upc_snap2
FROM k1 a JOIN k2 b USING (vendor, sku)
WHERE a.upc <> '' AND b.upc <> '' AND gtin14(a.upc) <> gtin14(b.upc)
ORDER BY a.vendor, a.sku LIMIT 15;
