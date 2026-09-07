-- Q3.1: the D4 comparison design, and how much of the basket survives it.
--
-- THE AVAILABILITY PROBLEM IS THE FINDING'S SHAPE, NOT A PREPROCESSING STEP. This query
-- produces no price comparison. It decides the design, justifies it, and measures whether
-- the design has anything to work with -- because if the intersections are thin, that is
-- the result, and it has to be said before a price number exists rather than discovered
-- as a caveat afterwards.
--
-- ================================ THE DESIGN ======================================
--
-- REJECTED: a fixed basket summed per vendor. Vendors do not stock the same products on
-- the same days, so a fixed basket forces one of two errors. Either you drop every date
-- on which any basket member is missing anywhere -- which is an availability filter
-- masquerading as a price measure and collapses the sample -- or you carry the last known
-- price forward, which honesty rule 1 forbids outright. A missing day is not an unchanged
-- price.
--
-- REJECTED: an all-vendors-at-once intersection. The reliable tier is four vendors
-- (Metro, Galleria, Save-On-Foods, Walmart), so a four-way intersection is the ceiling,
-- and it is the product of four availability constraints. Phase 0 B4 already found no
-- GTIN reaches five vendors without a fuzzy participant. Result 4 below measures the
-- four-way case rather than assuming it is empty.
--
-- CHOSEN: PAIRWISE, PER DATE, ON THE INTERSECTION.
--   For each ordered vendor pair (A, B) and each date d, take the GTINs where BOTH
--   vendors have a usable price on d in a MATCHING price_basis, and compare within that
--   set. n is reported for every (pair, date).
--
--   Why pairwise: it preserves n. Every vendor pair keeps its own comparable set instead
--   of all pairs being cut down to whatever all four vendors happen to stock.
--   Why per date: pooling across dates lets one vendor's cheap week be compared against
--   another's expensive week. Holding the date fixed removes that.
--   The cost, stated: pairwise comparisons need not be transitive. If A<B and B<C it does
--   not follow that A<C, because each comparison runs on a different GTIN set. That is a
--   real limitation and it is why 3.3 asks whether the answer is STABLE rather than
--   asking for a ranking.
--
-- EXCLUSIONS (honesty rules 3, 6, and §1.5), all counted in result 2:
--   ambiguous prices, orphan NULL-key rows, unparsed rows, and non-matching price_basis.
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

-- The reliable-tier basket: 2+ vendors, every one of them reliable (Phase 0 B4 = 5,222).
CREATE OR REPLACE TEMP TABLE basket AS
SELECT m.product_key, m.gtin14, m.vendor
FROM int_upc_match m WHERE m.is_reliable_only;

-- Usable observations on the basket, with every exclusion applied and countable.
CREATE OR REPLACE TEMP TABLE obs AS
SELECT b.gtin14, b.vendor, s.observed_date AS d, s.price_basis AS basis,
       -- determinism-ok: min() over (gtin, vendor, date, basis). Phase 0 B6 proves a
       -- product can appear many times in one day with conflicting prices, so this group
       -- is NOT unique; min() is a total order and takes the lowest price a shopper could
       -- have paid that day, which is the consistent reading for a price comparison.
       min(s.unit_price) AS px
FROM stg_price s JOIN basket b ON b.product_key = s.product_key
WHERE s.product_key IS NOT NULL
  AND s.parse_confidence <> 'ambiguous'
  AND s.offer_type <> 'unparsed'
  AND s.unit_price IS NOT NULL
  AND s.observed_date >= DATE '2024-06-11'
GROUP BY 1,2,3,4;

-- ============================ 1. THE BASKET, AND 3,477 ============================

-- 1. Reconstruct Phase 0 B4/B4d so the population is the published one, not a new one.
CREATE OR REPLACE TEMP TABLE coobs AS
SELECT gtin14, count(DISTINCT d) AS co_days
FROM (SELECT gtin14, d FROM obs GROUP BY 1,2 HAVING count(DISTINCT vendor) >= 2)
GROUP BY 1;

SELECT (SELECT count(DISTINCT gtin14) FROM basket)                        AS reliable_only_gtins,
       (SELECT count(*) FROM coobs)                                       AS gtins_ever_co_observed,
       (SELECT count(*) FROM coobs WHERE co_days >= 90)                   AS gtins_90plus_co_days,
       (SELECT count(*) FROM coobs WHERE co_days >= 365)                  AS gtins_365plus_co_days;

-- 2. THE EXCLUSION COUNT for D4, per honesty rule 7 -- what the design drops before any
--    comparison happens.
SELECT count(*)                                                           AS basket_price_rows,
       count(*) FILTER (WHERE s.parse_confidence = 'ambiguous')            AS dropped_ambiguous,
       count(*) FILTER (WHERE s.offer_type = 'unparsed')                   AS dropped_unparsed,
       count(*) FILTER (WHERE s.unit_price IS NULL)                        AS dropped_no_unit_price,
       count(*) FILTER (WHERE s.observed_date < DATE '2024-06-11')         AS dropped_pre_full_catalogue
FROM stg_price s JOIN basket b ON b.product_key = s.product_key;

-- ============================ 2. PAIRWISE SURVIVAL ================================

CREATE OR REPLACE TEMP TABLE g90 AS
SELECT gtin14 FROM coobs WHERE co_days >= 90;

-- Every (pair, date) intersection, on matching basis. This is the unit the design runs on.
CREATE OR REPLACE TEMP TABLE pair_day AS
SELECT a.vendor AS va, b.vendor AS vb, a.d, a.basis,
       count(*)                    AS n_gtins,
       median(a.px / nullif(b.px, 0)) AS median_ratio
FROM obs a
JOIN obs b ON b.gtin14 = a.gtin14 AND b.d = a.d AND b.basis = a.basis
          AND b.vendor > a.vendor
WHERE a.gtin14 IN (SELECT gtin14 FROM g90)
GROUP BY 1,2,3,4;

-- 3. THE SURVIVAL TABLE: for each vendor pair, how many of the 3,477 ever appear
--    together, how big is a typical day's intersection, and on how many dates is the
--    intersection large enough to mean anything?
SELECT va || ' vs ' || vb                                          AS pair,
       count(DISTINCT d)                                           AS dates_with_any_overlap,
       round(median(n_gtins), 0)                                   AS median_gtins_per_date,
       max(n_gtins)                                                AS max_gtins_per_date,
       count(*) FILTER (WHERE n_gtins >= 30)                       AS date_basis_cells_n_ge_30,
       count(*) FILTER (WHERE n_gtins >= 100)                      AS date_basis_cells_n_ge_100
FROM pair_day
GROUP BY 1 ORDER BY median_gtins_per_date DESC, pair;

-- 4. How many distinct GTINs from the 3,477 does each pair ever share, and what share of
--    3,477 is that? This is the "what fraction survives" number.
SELECT a.vendor || ' vs ' || b.vendor                              AS pair,
       count(DISTINCT a.gtin14)                                    AS gtins_shared_ever,
       round(100.0 * count(DISTINCT a.gtin14)
             / (SELECT count(*) FROM g90), 2)                      AS pct_of_3477
FROM obs a
JOIN obs b ON b.gtin14 = a.gtin14 AND b.d = a.d AND b.basis = a.basis
          AND b.vendor > a.vendor
WHERE a.gtin14 IN (SELECT gtin14 FROM g90)
GROUP BY 1 ORDER BY gtins_shared_ever DESC, pair;

-- 5. THE FOUR-WAY CASE, measured rather than assumed: on how many dates do ALL FOUR
--    reliable vendors carry the same GTIN, and how many GTINs is that?
SELECT count(*)                                    AS gtin_date_cells_all_four,
       count(DISTINCT gtin14)                      AS distinct_gtins,
       count(DISTINCT d)                           AS distinct_dates
FROM (SELECT gtin14, d FROM obs
      WHERE gtin14 IN (SELECT gtin14 FROM g90)
      GROUP BY 1,2 HAVING count(DISTINCT vendor) = 4);

-- 6. Distribution of intersection sizes, so "thin" is a shape rather than an adjective.
SELECT CASE WHEN n_gtins = 1 THEN 'a. 1 GTIN'
            WHEN n_gtins < 10 THEN 'b. 2-9'
            WHEN n_gtins < 30 THEN 'c. 10-29'
            WHEN n_gtins < 100 THEN 'd. 30-99'
            ELSE 'e. 100+' END                     AS intersection_size,
       count(*)                                    AS pair_date_basis_cells,
       round(100.0*count(*)/sum(count(*)) OVER (), 2) AS pct
FROM pair_day GROUP BY 1 ORDER BY 1;

-- 7. Which vendors are even in the reliable tier, and how much basket presence does each
--    have? A pair can only be as thick as its thinner side.
SELECT vendor,
       count(DISTINCT gtin14)                      AS gtins_in_basket,
       count(DISTINCT d)                           AS dates_present,
       count(*)                                    AS observations
FROM obs WHERE gtin14 IN (SELECT gtin14 FROM g90)
GROUP BY 1 ORDER BY gtins_in_basket DESC, vendor;

-- ============================ 3.4  BASKET COMPOSITION =============================

-- 8. What the 3,477 actually are, against the full catalogue. Readers assume a basket is
--    a random sample of groceries unless told otherwise; D1's 474 were characterised the
--    same way and turned out to be a frozen-and-packaged slice.
SELECT cat(sp.product_name)                                        AS category,
       count(DISTINCT sp.product_key) FILTER (WHERE m.gtin14 IN (SELECT gtin14 FROM g90)) AS basket_products,
       count(DISTINCT sp.product_key)                              AS catalogue_products,
       round(100.0 * count(DISTINCT sp.product_key) FILTER (WHERE m.gtin14 IN (SELECT gtin14 FROM g90))
             / nullif(sum(count(DISTINCT sp.product_key) FILTER (WHERE m.gtin14 IN (SELECT gtin14 FROM g90))) OVER (), 0), 2) AS pct_basket,
       round(100.0 * count(DISTINCT sp.product_key)
             / sum(count(DISTINCT sp.product_key)) OVER (), 2)     AS pct_catalogue
FROM stg_product sp LEFT JOIN int_upc_match m ON m.product_key = sp.product_key
GROUP BY 1 ORDER BY category;

-- 9. Brand-class composition of the basket, same purpose.
SELECT sp.brand_class,
       count(DISTINCT sp.product_key) FILTER (WHERE m.gtin14 IN (SELECT gtin14 FROM g90)) AS basket_products,
       count(DISTINCT sp.product_key)                              AS catalogue_products
FROM stg_product sp LEFT JOIN int_upc_match m ON m.product_key = sp.product_key
GROUP BY 1 ORDER BY basket_products DESC, sp.brand_class;
