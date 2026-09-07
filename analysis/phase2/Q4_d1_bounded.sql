-- Q4: D1, bounded. The 2025-26 composition check that was never done.
--
-- D1 IS NOT A HEADLINE FINDING AND NOTHING HERE VERIFIES OR REFUTES A COMPANY'S CLAIM.
-- The brief's reasoning, restated so it can be argued with rather than merely cited:
--
--   Products with stable listings are disproportionately products with stable prices.
--   Measuring a price freeze only on continuously-listed products therefore asks whether
--   prices held among the products least likely to move -- and answers yes almost by
--   construction.
--
--   Worse, the survivorship runs ONE DIRECTION. A product whose price changed during the
--   window and was then delisted is invisible; a product whose price held and stayed
--   listed is fully visible. Every mechanism that removes a product from the sample is
--   correlated with the outcome being measured, and all of them flatter the retailer.
--
--   This is a SELECTION-versus-OUTCOME problem, not a sample-quality problem. It is not
--   fixed by improving the sample's composition, because a better-composed sample of
--   survivors is still a sample of survivors. That is why 4.2 forbids a per-vendor
--   compliance rate: the number would be wrong in a knowable direction and there is no
--   correction to apply.
--
-- What this query DOES produce: the composition check Phase 0 never ran on the 2025-26
-- window, and a direct measurement of the survivorship gap so its size is stated rather
-- than asserted.
SET threads = 2;

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

-- The 2025-26 window, the only one still standing (Phase 0 D1; 2024-25 is a NO-GO).
CREATE OR REPLACE TEMP TABLE win AS
SELECT s.product_key AS k, s.observed_date AS d,
       -- determinism-ok: min() over (key, date). Phase 0 B6 proves this is not unique;
       -- min() is a total order and takes the lowest price charged that day, the same
       -- convention used throughout Section 3.
       min(s.unit_price) AS px
FROM stg_price s
WHERE s.product_key IS NOT NULL
  AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
  AND s.unit_price IS NOT NULL AND s.price_basis = 'each'
  AND s.observed_date BETWEEN DATE '2025-11-01' AND DATE '2026-02-05'
GROUP BY 1,2;

CREATE OR REPLACE TEMP TABLE prof AS
SELECT w.k, kk.vendor, kk.category, kk.brand_class, kk.total_qty,
       count(*)                          AS days_present,
       min(w.d)                          AS first_seen,
       max(w.d)                          AS last_seen,
       min(w.px)                         AS px_min,
       max(w.px)                         AS px_max,
       median(w.px)                      AS px_med,
       count(DISTINCT w.px)              AS distinct_prices
FROM win w
JOIN (SELECT product_key AS k, vendor, cat(product_name) AS category, brand_class, total_qty
      FROM stg_product) kk ON kk.k = w.k
GROUP BY 1,2,3,4,5;

-- Window length in observed days, per vendor, as the denominator for "continuous".
CREATE OR REPLACE TEMP TABLE vdays AS
SELECT p.vendor, count(DISTINCT w.d) AS vendor_days
FROM win w JOIN prof p ON p.k = w.k GROUP BY 1;

-- ============================ 1. THE SURVIVORSHIP GAP, MEASURED ===================

-- 1. How many products are present for the whole window vs part of it, per vendor?
--    "Continuously listed" is >=90% of the vendor's own observed days in the window.
SELECT p.vendor, v.vendor_days,
       count(*)                                                          AS products_seen,
       count(*) FILTER (WHERE p.days_present >= 0.90*v.vendor_days)      AS continuously_listed,
       round(100.0*count(*) FILTER (WHERE p.days_present >= 0.90*v.vendor_days)/count(*), 2) AS pct_continuous,
       count(*) FILTER (WHERE p.days_present < 0.50*v.vendor_days)       AS present_under_half
FROM prof p JOIN vdays v ON v.vendor = p.vendor
GROUP BY 1,2 ORDER BY pct_continuous DESC, p.vendor;

-- 2. THE MECHANISM, stated as a number: do continuously-listed products have more stable
--    prices than products that left the window? If yes, the selection IS the outcome, and
--    no compliance rate computed on survivors can be trusted.
SELECT CASE WHEN p.days_present >= 0.90*v.vendor_days THEN 'a. continuously listed'
            WHEN p.days_present >= 0.50*v.vendor_days THEN 'b. partial'
            ELSE 'c. brief' END                                          AS listing_stability,
       count(*)                                                          AS products,
       round(median(p.distinct_prices), 1)                               AS median_distinct_prices,
       round(100.0*count(*) FILTER (WHERE p.distinct_prices = 1)/count(*), 2) AS pct_never_changed_price,
       round(median(100.0*(p.px_max - p.px_min)/nullif(p.px_min,0)), 2)  AS median_pct_price_range
FROM prof p JOIN vdays v ON v.vendor = p.vendor
GROUP BY 1 ORDER BY 1;

-- 3. The same, per vendor, so the effect is not one vendor's artefact.
SELECT p.vendor,
       round(100.0*count(*) FILTER (WHERE p.distinct_prices = 1
                                      AND p.days_present >= 0.90*v.vendor_days)
             / nullif(count(*) FILTER (WHERE p.days_present >= 0.90*v.vendor_days), 0), 2) AS pct_flat_among_continuous,
       round(100.0*count(*) FILTER (WHERE p.distinct_prices = 1
                                      AND p.days_present < 0.50*v.vendor_days)
             / nullif(count(*) FILTER (WHERE p.days_present < 0.50*v.vendor_days), 0), 2)  AS pct_flat_among_brief
FROM prof p JOIN vdays v ON v.vendor = p.vendor
GROUP BY 1 ORDER BY p.vendor;

-- ============================ 2. THE 2025-26 COMPOSITION CHECK ====================
-- Phase 0 characterised D1's 2024-25 Metro slice (474 SKUs, a frozen-and-packaged cut)
-- and never ran the equivalent on 2025-26. This is that check.

-- 4. Category composition of the continuously-listed slice vs the vendor's full window
--    catalogue.
SELECT p.vendor, p.category,
       count(*)                                                          AS products_in_window,
       count(*) FILTER (WHERE p.days_present >= 0.90*v.vendor_days)      AS continuously_listed,
       round(100.0*count(*) FILTER (WHERE p.days_present >= 0.90*v.vendor_days)
             / nullif(sum(count(*) FILTER (WHERE p.days_present >= 0.90*v.vendor_days))
                      OVER (PARTITION BY p.vendor), 0), 2)               AS pct_of_continuous,
       round(100.0*count(*) / sum(count(*)) OVER (PARTITION BY p.vendor), 2) AS pct_of_window
FROM prof p JOIN vdays v ON v.vendor = p.vendor
WHERE p.vendor IN ('Metro','Loblaws','NoFrills','SaveOnFoods')
GROUP BY 1,2 ORDER BY p.vendor, p.category;

-- 5. Brand-class composition of the same slice -- Metro's claim is scoped to "all private
--    label and national brand grocery products", so this is the axis its own wording
--    names.
SELECT p.vendor, p.brand_class,
       count(*) FILTER (WHERE p.days_present >= 0.90*v.vendor_days)      AS continuously_listed,
       count(*)                                                          AS products_in_window,
       round(100.0*count(*) FILTER (WHERE p.days_present >= 0.90*v.vendor_days)
             / nullif(count(*), 0), 2)                                   AS pct_of_class_continuous
FROM prof p JOIN vdays v ON v.vendor = p.vendor
WHERE p.vendor = 'Metro'
GROUP BY 1,2 ORDER BY continuously_listed DESC, p.brand_class;

-- 6. Price level of the surviving slice vs the window catalogue -- the axis D4's basket
--    turned out to be skewed on.
SELECT p.vendor,
       round(median(p.px_med) FILTER (WHERE p.days_present >= 0.90*v.vendor_days), 2) AS median_px_continuous,
       round(median(p.px_med), 2)                                                     AS median_px_all_window,
       round(median(p.total_qty) FILTER (WHERE p.days_present >= 0.90*v.vendor_days), 0) AS median_size_continuous,
       round(median(p.total_qty), 0)                                                  AS median_size_all_window
FROM prof p JOIN vdays v ON v.vendor = p.vendor
WHERE p.vendor IN ('Metro','Loblaws','NoFrills','SaveOnFoods')
GROUP BY 1 ORDER BY p.vendor;

-- ============================ 3. WHAT A COMPLIANCE RATE WOULD HAVE SAID ===========

-- 7. Computed ONLY to show how far wrong it would be, and reported as the two numbers
--    together so neither can be quoted alone. 4.2 forbids publishing this per vendor as a
--    finding; showing the gap between the survivor rate and the all-products rate is the
--    argument FOR that prohibition, not a violation of it.
SELECT p.vendor,
       count(*) FILTER (WHERE p.days_present >= 0.90*v.vendor_days)      AS n_survivors,
       round(100.0*count(*) FILTER (WHERE p.distinct_prices = 1
                                      AND p.days_present >= 0.90*v.vendor_days)
             / nullif(count(*) FILTER (WHERE p.days_present >= 0.90*v.vendor_days), 0), 2) AS pct_flat_SURVIVORS_ONLY,
       count(*)                                                          AS n_all_window,
       round(100.0*count(*) FILTER (WHERE p.distinct_prices = 1)/count(*), 2) AS pct_flat_ALL_WINDOW
FROM prof p JOIN vdays v ON v.vendor = p.vendor
GROUP BY 1 ORDER BY p.vendor;

-- 8. Window shape: how much of the window does each vendor actually cover? A vendor
--    missing a chunk of the window cannot support a freeze claim about it at all.
SELECT p.vendor, v.vendor_days,
       min(p.first_seen) AS first_date, max(p.last_seen) AS last_date,
       count(DISTINCT p.k) AS products
FROM prof p JOIN vdays v ON v.vendor = p.vendor
GROUP BY 1,2 ORDER BY v.vendor_days DESC, p.vendor;
