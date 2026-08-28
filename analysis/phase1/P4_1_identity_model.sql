-- P4.1 / P4.2: the owned key and the cross-vendor identity model, verified.
--
-- 4.1 asks for a surrogate key derived by us, covering the blank-sku 13.8%, with
--     `raw.product_id` absent below staging.
-- 4.2 asks for the reliable-group UPC set materialised as a first-class model with a tier
--     on every match, lower tiers kept and flagged rather than deleted.
--
-- This confirms both against Phase 0's numbers rather than asserting them.
SET threads = 4;

-- 1. Owned key coverage: every product has one, including the blank-sku population.
SELECT count(*)                                                      AS products,
       count(product_key)                                            AS with_owned_key,
       count(*) - count(product_key)                                 AS missing_key,
       count(DISTINCT product_key)                                   AS distinct_keys,
       count(*) FILTER (WHERE product_key_basis = 'vendor_sku')       AS keyed_on_sku,
       count(*) FILTER (WHERE product_key_basis = 'vendor_concatted') AS keyed_on_concatted
FROM stg_product;

-- 2. The tier census. Every product appears; nothing is filtered.
SELECT match_tier,
       count(*)                                                      AS products,
       count(DISTINCT gtin14)                                        AS distinct_gtins,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2)            AS pct_of_products,
       string_agg(DISTINCT vendor, ',' ORDER BY vendor)              AS vendors
FROM int_upc_match
GROUP BY match_tier ORDER BY products DESC;

-- 3. RECONCILE AGAINST PHASE 0 B4. The reliable-only GTIN count must be 5,222 -- if the
--    model disagrees with the finding it was built from, one of them is wrong.
SELECT count(DISTINCT gtin14) FILTER (WHERE is_reliable_only)         AS reliable_only_gtins,
       5222                                                           AS phase0_b4_expected,
       count(DISTINCT gtin14) FILTER (WHERE is_reliable_only) - 5222   AS difference
FROM int_upc_match;

-- 4. Cross-vendor overlap by vendor count, reconciling B4's breakdown.
WITH g AS (
  SELECT gtin14, any_value(n_vendors_on_gtin) AS nv,
         any_value(n_fuzzy_vendors_on_gtin) AS nf
  FROM int_upc_match WHERE gtin14 IS NOT NULL GROUP BY gtin14)
SELECT nv AS vendors_on_gtin, count(*) AS gtins,
       count(*) FILTER (WHERE nf = 0)  AS reliable_only,
       count(*) FILTER (WHERE nf = nv) AS fuzzy_only,
       count(*) FILTER (WHERE nf > 0 AND nf < nv) AS mixed
FROM g GROUP BY nv ORDER BY nv;

-- 5. The weakest-participant rule, made visible: GTINs carried by a reliable vendor AND a
--    fuzzy one are tiered `fuzzy`, not `vendor_upc`. This is the rule that stops one
--    reliable vendor laundering a fuzzy match into a headline number.
SELECT match_tier, vendor_upc_tier AS this_vendors_own_tier,
       count(*) AS products
FROM int_upc_match
WHERE match_tier IN ('vendor_upc', 'matched_upc', 'fuzzy')
GROUP BY 1, 2 ORDER BY 1, products DESC;

-- 6. PLU-style short codes: kept and tiered, not silently dropped or silently mixed in.
SELECT count(*)                              AS plu_short_products,
       count(DISTINCT vendor)                AS vendors,
       string_agg(DISTINCT vendor, ',')      AS vendor_list
FROM int_upc_match WHERE match_tier = 'plu_short';

-- 7. Reconcile B4d's co-observation figure: of the reliable-only GTINs, how many are
--    priced at 2+ reliable vendors on 90+ shared days? Phase 0 said 3,477. Joining on
--    the OWNED key, not product_id -- this is the first downstream use of it.
SET threads = 4;
CREATE OR REPLACE TEMP TABLE codays AS
SELECT m.gtin14, s.observed_date AS d, count(DISTINCT m.vendor) AS nv
FROM stg_price s
JOIN int_upc_match m ON m.product_key = s.product_key
WHERE m.is_reliable_only
  AND s.observed_date >= DATE '2024-06-11'
GROUP BY 1, 2;

SELECT count(DISTINCT gtin14) FILTER (WHERE shared >= 90)   AS gtins_90plus_shared_days,
       3477                                                  AS phase0_b4d_expected,
       count(DISTINCT gtin14) FILTER (WHERE shared >= 90) - 3477 AS difference,
       count(DISTINCT gtin14) FILTER (WHERE shared >= 365)  AS gtins_365plus
FROM (SELECT gtin14, count(*) FILTER (WHERE nv >= 2) AS shared FROM codays GROUP BY 1);
