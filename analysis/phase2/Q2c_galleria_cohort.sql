-- Q2.5: characterise Galleria's 2A cohort before its 24.08% is quotable.
--
-- THE PROBLEM. Galleria's residual -- claimed regular exceeds every price observed in the
-- 14-day pre-window -- is 24.08%, the highest of any vendor by 4x. It rests on n = 1,138,
-- the smallest 2A cohort of any vendor. And Galleria's `old_price` coverage is 0.92%
-- (Phase 0 C4), the lowest of any vendor by a wide margin.
--
-- That last fact is the one that matters. 2A requires a claimed regular VALUE, so
-- Galleria's cohort is selected by "whatever populates old_price at all" -- a filter that
-- passes under 1% of its rows. If that 1% is a distinct kind of product, then 24.08% is a
-- statement about that kind of product, not about Galleria.
--
-- This is the same treatment Phase 0 gave D1's 474 Metro SKUs: characterise the surviving
-- slice against the full catalogue, and say what it over- and under-represents.
--
-- SECOND QUESTION, asked because the two populations are suspiciously adjacent: Galleria
-- also owns 26,306 ambiguous bare-integer rows (§3.6) across 90 products. Does the 2A
-- cohort overlap them? If a product's price history is partly ambiguous, its pre-window
-- maximum is computed from the non-ambiguous remainder, which could bias the comparison.
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

-- Galleria's full catalogue, as the comparison baseline.
CREATE OR REPLACE TEMP TABLE gal_cat AS
SELECT product_key AS k, product_name, cat(product_name) AS category,
       units_raw, unit_uom, brand_class, product_key_basis
FROM stg_product WHERE vendor = 'Galleria';

-- Galleria's price rows, with the flags the audit needs.
CREATE OR REPLACE TEMP TABLE gal_rows AS
SELECT s.product_key AS k, s.observed_date AS d, s.price_basis AS basis,
       s.unit_price, s.old_unit_price, s.old_offer_type, s.parse_confidence,
       (s.parse_confidence = 'ambiguous') AS is_ambiguous,
       (s.old_offer_type <> 'blank')      AS is_sale_row,
       (s.old_unit_price IS NOT NULL)     AS has_old_value
FROM stg_price s JOIN gal_cat g ON g.k = s.product_key
WHERE s.observed_date >= DATE '2024-06-11';

-- 1. THE SELECTION FUNNEL: how much of Galleria survives to the 2A cohort, step by step.
SELECT 'a. Galleria products in catalogue'          AS step, count(*) AS n FROM gal_cat
UNION ALL SELECT 'b. products with any price row',   count(DISTINCT k) FROM gal_rows
UNION ALL SELECT 'c. products with any sale flag',   count(DISTINCT k) FROM gal_rows WHERE is_sale_row
UNION ALL SELECT 'd. products with a usable old_price VALUE', count(DISTINCT k)
  FROM gal_rows WHERE has_old_value;

-- 2. Row-level coverage, to put 0.92% on the record for this window.
SELECT count(*)                                        AS price_rows,
       count(*) FILTER (WHERE is_sale_row)             AS sale_flag_rows,
       round(100.0*count(*) FILTER (WHERE is_sale_row)/count(*), 3)   AS pct_sale_flag,
       count(*) FILTER (WHERE has_old_value)           AS rows_with_old_value,
       round(100.0*count(*) FILTER (WHERE has_old_value)/count(*), 3) AS pct_old_value,
       count(*) FILTER (WHERE is_ambiguous)            AS ambiguous_rows,
       round(100.0*count(*) FILTER (WHERE is_ambiguous)/count(*), 3)  AS pct_ambiguous
FROM gal_rows;

-- ============================ COMPOSITION VS THE CATALOGUE ========================
-- The 2A-eligible slice: products that ever carry a usable old_price value.
CREATE OR REPLACE TEMP TABLE gal_eligible AS
SELECT DISTINCT k FROM gal_rows WHERE has_old_value;

-- 3. CATEGORY composition, eligible slice vs full catalogue. Over- and
--    under-representation stated as a ratio, the way D1's 474 were characterised.
SELECT g.category,
       count(*)                                                        AS catalogue_products,
       round(100.0*count(*)/sum(count(*)) OVER (), 2)                  AS pct_catalogue,
       count(*) FILTER (WHERE e.k IS NOT NULL)                         AS eligible_products,
       round(100.0*count(*) FILTER (WHERE e.k IS NOT NULL)
             / nullif(sum(count(*) FILTER (WHERE e.k IS NOT NULL)) OVER (), 0), 2) AS pct_eligible,
       round( (100.0*count(*) FILTER (WHERE e.k IS NOT NULL)
              / nullif(sum(count(*) FILTER (WHERE e.k IS NOT NULL)) OVER (), 0))
            / nullif(100.0*count(*)/sum(count(*)) OVER (), 0), 2)      AS over_representation
FROM gal_cat g LEFT JOIN gal_eligible e ON e.k = g.k
GROUP BY 1 ORDER BY g.category;

-- 4. UNIT TYPE composition -- loose vs packaged is the axis D1's Metro slice turned on.
SELECT coalesce(g.unit_uom, '(unparsed)')                              AS unit_uom,
       count(*)                                                        AS catalogue_products,
       round(100.0*count(*)/sum(count(*)) OVER (), 2)                  AS pct_catalogue,
       count(*) FILTER (WHERE e.k IS NOT NULL)                         AS eligible_products,
       round(100.0*count(*) FILTER (WHERE e.k IS NOT NULL)
             / nullif(sum(count(*) FILTER (WHERE e.k IS NOT NULL)) OVER (), 0), 2) AS pct_eligible
FROM gal_cat g LEFT JOIN gal_eligible e ON e.k = g.k
GROUP BY 1 ORDER BY catalogue_products DESC, unit_uom;

-- 5. The eligible products themselves, named. With n this small the slice can simply be
--    looked at, which is more informative than another ratio.
SELECT g.product_name, g.category, g.units_raw,
       count(*)                                   AS price_rows,
       count(*) FILTER (WHERE r.has_old_value)    AS rows_with_old_value,
       count(*) FILTER (WHERE r.is_ambiguous)     AS ambiguous_rows
FROM gal_rows r JOIN gal_cat g ON g.k = r.k
WHERE r.k IN (SELECT k FROM gal_eligible)
GROUP BY 1,2,3 ORDER BY rows_with_old_value DESC, g.product_name LIMIT 25;

-- 6. How concentrated is the cohort? If a handful of products supply most of the 1,138
--    events, the rate is about those products.
SELECT count(DISTINCT k)                                        AS eligible_products,
       count(*)                                                 AS rows_with_old_value
FROM gal_rows WHERE has_old_value;

-- ============================ THE AMBIGUOUS OVERLAP ================================

-- 7. Do the 2A-eligible products overlap Galleria's ambiguous bare-integer set?
SELECT (SELECT count(DISTINCT k) FROM gal_rows WHERE is_ambiguous)          AS ambiguous_products,
       (SELECT count(*) FROM gal_rows WHERE is_ambiguous)                   AS ambiguous_rows,
       (SELECT count(DISTINCT k) FROM gal_eligible)                         AS eligible_products,
       (SELECT count(*) FROM gal_eligible e
         WHERE EXISTS (SELECT 1 FROM gal_rows r
                        WHERE r.k = e.k AND r.is_ambiguous))                AS OVERLAP_products;

-- 8. If there is overlap, how much of those products' history is ambiguous? An ambiguous
--    row is excluded from the pre-window, so a heavily-ambiguous product has its maximum
--    computed from a thinner set of observations.
SELECT g.product_name,
       count(*)                                                     AS price_rows,
       count(*) FILTER (WHERE r.is_ambiguous)                       AS ambiguous_rows,
       round(100.0*count(*) FILTER (WHERE r.is_ambiguous)/count(*), 2) AS pct_ambiguous,
       count(*) FILTER (WHERE r.has_old_value)                      AS rows_with_old_value
FROM gal_rows r JOIN gal_cat g ON g.k = r.k
WHERE r.k IN (SELECT k FROM gal_eligible)
  AND EXISTS (SELECT 1 FROM gal_rows r2 WHERE r2.k = r.k AND r2.is_ambiguous)
GROUP BY 1 ORDER BY pct_ambiguous DESC, g.product_name LIMIT 20;

-- 9. The decisive number: of Galleria's 2A events, how many belong to a product with ANY
--    ambiguous row? If zero, the two populations are disjoint and 24.08% is unaffected
--    by the ambiguous exclusion.
SELECT count(*)                                                              AS eligible_rows,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM gal_rows r2
                                       WHERE r2.k = r.k AND r2.is_ambiguous)) AS rows_on_ambiguous_products,
       round(100.0*count(*) FILTER (WHERE EXISTS (SELECT 1 FROM gal_rows r2
                                       WHERE r2.k = r.k AND r2.is_ambiguous))/count(*), 3) AS pct
FROM gal_rows r WHERE r.has_old_value;
