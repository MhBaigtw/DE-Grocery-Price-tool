-- Q2B: D2 finding two -- how often is a product on sale?
--
-- WHY THIS IS INDEPENDENT OF 2A. It uses `old_price` as a FLAG only, never as a value.
-- Phase 1 §2.7 established that 869,495 rows carry the literal string `was` in `old_price`
-- -- 33.18% of Loblaws sale rows -- so the struck-out VALUE is missing for a large,
-- vendor-specific slice. Those rows still carry a sale signal, so a frequency measure is
-- unaffected by them while a depth measure is not. §2.7 measured Loblaws' event-level
-- exposure at 9.20% for value-dependent analysis and ZERO for flag-only analysis.
--
-- This is the finding that survives the `was` loss intact, and that is the point of
-- running two independent D2 findings rather than one.
--
-- SCOPE, per the Section 1 bias audit: headline is 2025-01-01 .. 2026-08-21. 2024 is
-- reported separately because two exclusion classes concentrate there.
--
-- EXCLUSIONS (honesty rules 3, 6, and §1.5): ambiguous excluded, orphan excluded by
-- construction, vendor_concatted reported as a separate tier.
SET threads = 4;

CREATE OR REPLACE TEMP MACRO cat(nm) AS
  CASE
    WHEN regexp_matches(lower(nm), '(bread|bagel|bun|tortilla|pita)')                 THEN 'a. bread & bakery'
    WHEN regexp_matches(lower(nm), '(milk|cream|yogur|yoghur|cheese|butter|margarine)') THEN 'b. dairy'
    WHEN regexp_matches(lower(nm), 'egg')                                              THEN 'c. eggs'
    WHEN regexp_matches(lower(nm), '(apple|banana|orange|potato|onion|carrot|tomato|lettuce|berry|berries|grape|pepper|broccoli|cucumber)') THEN 'd. produce'
    WHEN regexp_matches(lower(nm), '(chicken|beef|pork|turkey|bacon|ham|sausage|fish|salmon|tuna|shrimp)') THEN 'e. meat & fish'
    WHEN regexp_matches(lower(nm), '(rice|pasta|flour|sugar|cereal|oat|noodle)')       THEN 'f. pantry staples'
    WHEN regexp_matches(lower(nm), '(juice|coffee|tea|soda|water|cola|drink)')         THEN 'g. beverages'
    ELSE 'h. other' END;

-- One row per product per OBSERVED day. A day the product was not observed is NOT a day
-- it was off sale -- honesty rule 1. The denominator is days OBSERVED, never days elapsed,
-- and that distinction is the whole reason this measure is defensible on a dataset with a
-- 19-day dataset-wide blackout and 271 missing vendor-days (Phase 0 E9).
CREATE OR REPLACE TEMP TABLE pd AS
SELECT s.product_key                                                     AS k,
       s.observed_date                                                   AS d,
       max(CASE WHEN s.old_offer_type <> 'blank' THEN 1 ELSE 0 END)      AS on_sale
FROM stg_price s
WHERE s.product_key IS NOT NULL
  AND s.parse_confidence <> 'ambiguous'
  AND s.offer_type <> 'unparsed'
  AND s.observed_date >= DATE '2025-01-01'
GROUP BY 1,2;

CREATE OR REPLACE TEMP TABLE prod AS
SELECT p.k,
       count(*)                                  AS days_observed,
       sum(p.on_sale)                            AS days_on_sale,
       100.0 * sum(p.on_sale) / count(*)         AS pct_days_on_sale,
       kk.vendor, kk.product_key_basis, kk.category, kk.brand_class
FROM pd p
JOIN (SELECT product_key AS k, vendor, product_key_basis,
             cat(product_name) AS category, brand_class FROM stg_product) kk
     ON kk.k = p.k
GROUP BY p.k, kk.vendor, kk.product_key_basis, kk.category, kk.brand_class;

-- A coverage floor: a product seen 3 days cannot have a meaningful "share of days on
-- sale". 90 days is the same bar Phase 0 B4d used for co-observation.
CREATE OR REPLACE TEMP TABLE prod90 AS
SELECT * FROM prod WHERE days_observed >= 90;

-- ============================ 2B.1  THE DISTRIBUTION ==============================

-- 1. Cohort accounting, honesty rule 7.
SELECT 'a. products observed at all in 2025-2026'   AS step, count(*) AS products FROM prod
UNION ALL SELECT 'b. + observed on 90+ days',        count(*) FROM prod90
UNION ALL SELECT 'c. + vendor_sku tier (headline)',  count(*) FROM prod90
  WHERE product_key_basis = 'vendor_sku';

-- 2. Identity-tier split, per §1.5 -- reported, not dropped.
SELECT product_key_basis AS tier, count(*) AS products,
       round(median(pct_days_on_sale), 2) AS median_pct_days_on_sale
FROM prod90 GROUP BY 1 ORDER BY 1;

-- 3. HEADLINE: per vendor, the distribution of "share of observed days on sale".
SELECT vendor,
       count(*)                                            AS n_products,
       round(median(days_observed), 0)                     AS median_days_observed,
       round(median(pct_days_on_sale), 2)                  AS median_pct_on_sale,
       round(quantile_cont(pct_days_on_sale, 0.75), 2)     AS p75,
       round(quantile_cont(pct_days_on_sale, 0.90), 2)     AS p90,
       round(avg(pct_days_on_sale), 2)                     AS mean_pct_on_sale
FROM prod90 WHERE product_key_basis = 'vendor_sku'
GROUP BY 1 ORDER BY median_pct_on_sale DESC, vendor;

-- ============================ 2B.2  "ALWAYS ON SALE" ==============================
-- A product on sale most of the time does not have a sale price. It has a price.

-- 4. Share of products above each threshold, per vendor, with n.
SELECT vendor,
       count(*)                                                        AS n_products,
       count(*) FILTER (WHERE pct_days_on_sale >= 50)                  AS ge_50pct,
       round(100.0*count(*) FILTER (WHERE pct_days_on_sale >= 50)/count(*), 2) AS pct_ge_50,
       count(*) FILTER (WHERE pct_days_on_sale >= 75)                  AS ge_75pct,
       round(100.0*count(*) FILTER (WHERE pct_days_on_sale >= 75)/count(*), 2) AS pct_ge_75,
       count(*) FILTER (WHERE pct_days_on_sale >= 90)                  AS ge_90pct,
       round(100.0*count(*) FILTER (WHERE pct_days_on_sale >= 90)/count(*), 2) AS pct_ge_90
FROM prod90 WHERE product_key_basis = 'vendor_sku'
GROUP BY 1 ORDER BY pct_ge_50 DESC, vendor;

-- 5. Which categories do the always-on-sale products concentrate in? Compared against the
--    category mix of the whole cohort, so "produce is 20% of them" is readable against
--    produce's share of everything.
SELECT category,
       count(*)                                                        AS all_products,
       round(100.0*count(*)/sum(count(*)) OVER (), 2)                  AS pct_of_all,
       count(*) FILTER (WHERE pct_days_on_sale >= 50)                  AS ge_50pct,
       round(100.0*count(*) FILTER (WHERE pct_days_on_sale >= 50)
             / nullif(sum(count(*) FILTER (WHERE pct_days_on_sale >= 50)) OVER (), 0), 2) AS pct_of_ge50,
       round( (100.0*count(*) FILTER (WHERE pct_days_on_sale >= 50)
              / nullif(sum(count(*) FILTER (WHERE pct_days_on_sale >= 50)) OVER (), 0))
            / nullif(100.0*count(*)/sum(count(*)) OVER (), 0), 2)      AS concentration_ratio
FROM prod90 WHERE product_key_basis = 'vendor_sku'
GROUP BY 1 ORDER BY category;

-- 6. And by brand class -- private label vs national brand promotional intensity.
SELECT brand_class,
       count(*)                                                        AS n_products,
       round(median(pct_days_on_sale), 2)                              AS median_pct_on_sale,
       round(100.0*count(*) FILTER (WHERE pct_days_on_sale >= 50)/count(*), 2) AS pct_ge_50
FROM prod90 WHERE product_key_basis = 'vendor_sku'
GROUP BY 1 ORDER BY n_products DESC, brand_class;

-- 7. The extreme tail, per vendor: products on sale on EVERY observed day. If a vendor
--    has many of these, its "sale" flag is not marking a promotion at all.
SELECT vendor,
       count(*) FILTER (WHERE pct_days_on_sale = 100)                  AS always_on_sale,
       count(*)                                                        AS n_products,
       round(100.0*count(*) FILTER (WHERE pct_days_on_sale = 100)/count(*), 3) AS pct_always,
       round(median(days_observed) FILTER (WHERE pct_days_on_sale = 100), 0)   AS median_days_obs
FROM prod90 WHERE product_key_basis = 'vendor_sku'
GROUP BY 1 ORDER BY pct_always DESC, vendor;

-- ============================ 2B.3  THE `was` LOSS DOES NOT TOUCH THIS =============

-- 8. Stated as a number, not asserted: how many of the sale-days counted above rest on a
--    row whose old_price has NO usable value? If this is large and the finding is
--    unaffected, that is the demonstration that flag-only analysis survives the loss.
SELECT sp.vendor,
       count(*)                                                        AS sale_rows,
       count(*) FILTER (WHERE s.old_unit_price IS NULL)                AS sale_rows_no_value,
       round(100.0*count(*) FILTER (WHERE s.old_unit_price IS NULL)/count(*), 2) AS pct_flag_only
FROM stg_price s JOIN stg_product sp USING (product_key)
WHERE s.product_key IS NOT NULL
  AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
  AND s.observed_date >= DATE '2025-01-01'
  AND s.old_offer_type <> 'blank'
GROUP BY 1 ORDER BY pct_flag_only DESC, sp.vendor;

-- ============================ 2024, SEPARATELY CAVEATED ===========================

-- 9. The same headline over 2024 alone, never pooled with the above. Reported so the
--    difference is visible, and caveated because two exclusion classes concentrate here.
CREATE OR REPLACE TEMP TABLE pd24 AS
SELECT s.product_key AS k, s.observed_date AS d,
       max(CASE WHEN s.old_offer_type <> 'blank' THEN 1 ELSE 0 END) AS on_sale
FROM stg_price s
WHERE s.product_key IS NOT NULL
  AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
  AND s.observed_date >= DATE '2024-06-11' AND s.observed_date < DATE '2025-01-01'
GROUP BY 1,2;

SELECT kk.vendor, count(*) AS n_products,
       round(median(100.0*x.days_on_sale/x.days_observed), 2) AS median_pct_on_sale_2024,
       round(100.0*count(*) FILTER (WHERE 100.0*x.days_on_sale/x.days_observed >= 50)
             / count(*), 2)                                   AS pct_ge_50_2024
FROM (SELECT k, count(*) AS days_observed, sum(on_sale) AS days_on_sale
      FROM pd24 GROUP BY 1 HAVING count(*) >= 90) x
JOIN (SELECT product_key AS k, vendor, product_key_basis FROM stg_product) kk ON kk.k = x.k
WHERE kk.product_key_basis = 'vendor_sku'
GROUP BY 1 ORDER BY median_pct_on_sale_2024 DESC, kk.vendor;
