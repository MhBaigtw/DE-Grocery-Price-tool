-- Q3.8: the pairwise price comparison, and whether the answer is STABLE.
--
-- The question is not "which store is cheapest". It is whether any answer holds across
-- categories, dates and basket subsets, or whether it depends on what you buy. "It
-- depends, and here is what on" is the stronger result and the more likely one.
--
-- EVERY NUMBER HERE IS "ON IDENTICAL NATIONAL-BRAND PRODUCTS". §3.5 established that the
-- UPC-matched basket contains 1 private-label product out of 8,448, structurally, because
-- a store brand has one seller and therefore no cross-vendor barcode. The blind spot is
-- 15.05% of observed rows and 22.64% of price-weighted shelf exposure at these vendors.
-- No sentence below may be read as "vendor A is cheaper" without that qualifier.
--
-- SCOPE: the three non-Galleria pairs. §3.1 measured Galleria's pairs at 5-8% basket
-- overlap against 48-65% for these, and §3.7 showed that is a genuinely disjoint
-- catalogue rather than a coverage failure. Galleria is reported there, not ranked here.
--
-- INTRANSITIVITY IS TESTED, NOT NOTED. Pairwise comparisons run on different GTIN sets,
-- so A<B and B<C need not imply A<C. Rather than flag that as a design caveat, results 6
-- and 7 measure it: every pair is recomputed on the THREE-WAY COMMON intersection and the
-- two orderings are compared. If they agree, the caveat is theoretical. If they disagree,
-- that disagreement is the finding.
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

CREATE OR REPLACE TEMP TABLE obs AS
SELECT m.gtin14, m.vendor, s.observed_date AS d, s.price_basis AS basis,
       -- determinism-ok: min() over (gtin, vendor, date, basis), which Phase 0 B6 proves
       -- is not unique. min() is a total order and takes the lowest price a shopper could
       -- have paid that day -- the consistent reading for a price comparison.
       min(s.unit_price) AS px,
       min(cat(sp.product_name)) AS category
       -- determinism-ok: category is a pure function of product_name, and all products
       -- sharing a gtin at one vendor share the name in practice; min() makes the pick
       -- total either way.
FROM stg_price s
JOIN int_upc_match m ON m.product_key = s.product_key
JOIN stg_product sp ON sp.product_key = s.product_key
WHERE m.is_reliable_only
  AND m.vendor IN ('Metro','SaveOnFoods','Walmart')
  AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
  AND s.unit_price IS NOT NULL AND s.unit_price > 0
  AND s.observed_date >= DATE '2024-06-11'
GROUP BY 1,2,3,4;

-- The 90+ co-observed-day basket, restricted to these three vendors.
CREATE OR REPLACE TEMP TABLE g90 AS
SELECT gtin14 FROM (SELECT gtin14, count(DISTINCT d) AS co_days
                    FROM (SELECT gtin14, d FROM obs GROUP BY 1,2
                          HAVING count(DISTINCT vendor) >= 2)
                    GROUP BY 1)
WHERE co_days >= 90;

-- Per-GTIN, per-date price ratios for each ordered pair, on matching basis.
CREATE OR REPLACE TEMP TABLE ratios AS
SELECT a.vendor AS va, b.vendor AS vb, a.gtin14, a.d, a.basis, a.category,
       a.px AS px_a, b.px AS px_b, a.px / b.px AS ratio
FROM obs a
JOIN obs b ON b.gtin14 = a.gtin14 AND b.d = a.d AND b.basis = a.basis AND b.vendor > a.vendor
WHERE a.gtin14 IN (SELECT gtin14 FROM g90);

-- ============================ 1. THE HEADLINE, WITH n =============================

-- 1. Per pair: the central tendency, and how often each side is cheaper. A ratio below
--    1.00 means the FIRST-named vendor is cheaper on identical national-brand products.
SELECT va || ' / ' || vb                                              AS pair,
       count(*)                                                       AS n_gtin_days,
       count(DISTINCT gtin14)                                         AS n_gtins,
       count(DISTINCT d)                                              AS n_dates,
       round(median(ratio), 4)                                        AS median_ratio,
       round(exp(avg(ln(ratio))), 4)                                  AS geomean_ratio,
       round(100.0*count(*) FILTER (WHERE ratio < 0.99)/count(*), 2)  AS pct_first_cheaper,
       round(100.0*count(*) FILTER (WHERE ratio > 1.01)/count(*), 2)  AS pct_second_cheaper,
       round(100.0*count(*) FILTER (WHERE ratio BETWEEN 0.99 AND 1.01)/count(*), 2) AS pct_within_1pct
FROM ratios GROUP BY 1 ORDER BY pair;

-- ============================ 2. STABILITY ACROSS DATES ===========================

-- 2. Per pair per date, then the distribution of those daily medians. A stable answer has
--    a tight distribution that does not cross 1.00; an unstable one straddles it.
WITH daily AS (
  SELECT va, vb, d, count(*) AS n, median(ratio) AS r
  FROM ratios GROUP BY 1,2,3 HAVING count(*) >= 30)
SELECT va || ' / ' || vb                                   AS pair,
       count(*)                                            AS n_dates,
       round(median(r), 4)                                 AS median_of_daily_medians,
       round(quantile_cont(r, 0.10), 4)                    AS p10,
       round(quantile_cont(r, 0.90), 4)                    AS p90,
       round(100.0*count(*) FILTER (WHERE r < 1.0)/count(*), 2) AS pct_dates_first_cheaper
FROM daily GROUP BY 1 ORDER BY pair;

-- ============================ 3. STABILITY ACROSS CATEGORIES ======================

-- 3. Does the answer hold category by category, or does it flip?
SELECT va || ' / ' || vb                                   AS pair, category,
       count(*)                                            AS n_gtin_days,
       count(DISTINCT gtin14)                              AS n_gtins,
       round(median(ratio), 4)                             AS median_ratio,
       CASE WHEN median(ratio) < 1 THEN min(va) ELSE min(vb) END AS cheaper_side
       -- determinism-ok: va and vb are constant within the (va, vb) group by
       -- construction, so min() returns that constant value and cannot vary.
FROM ratios GROUP BY va, vb, category HAVING count(*) >= 200
ORDER BY pair, category;

-- ============================ 4. STABILITY ACROSS BASKET SUBSETS ==================

-- 4. Price tertiles: does the answer depend on whether you buy cheap or expensive items?
WITH t AS (
  SELECT *, ntile(3) OVER (PARTITION BY va, vb ORDER BY px_b, gtin14, d) AS tertile
  -- determinism-ok: ORDER BY (px_b, gtin14, d) is a total order -- (gtin14, d) is unique
  -- within a pair by the construction of `ratios`, so no tie survives.
  FROM ratios)
SELECT va || ' / ' || vb                                   AS pair,
       tertile,
       count(*)                                            AS n,
       round(median(px_b), 2)                              AS median_price_of_second,
       round(median(ratio), 4)                             AS median_ratio,
       CASE WHEN median(ratio) < 1 THEN min(va) ELSE min(vb) END AS cheaper_side
       -- determinism-ok: constant within the group, as above.
FROM t GROUP BY va, vb, tertile ORDER BY pair, tertile;

-- 5. Per-GTIN consistency: for how many products is one vendor cheaper on essentially
--    every co-observed day? If the answer is product-specific rather than vendor-wide,
--    that is the "it depends" result in its sharpest form.
WITH per_gtin AS (
  SELECT va, vb, gtin14, count(*) AS days,
         100.0*count(*) FILTER (WHERE ratio < 0.99)/count(*) AS pct_a_cheaper
  FROM ratios GROUP BY 1,2,3 HAVING count(*) >= 30)
SELECT va || ' / ' || vb                                             AS pair,
       count(*)                                                      AS n_gtins,
       count(*) FILTER (WHERE pct_a_cheaper >= 90)                   AS first_cheaper_90pct_of_days,
       count(*) FILTER (WHERE pct_a_cheaper <= 10)                   AS second_cheaper_90pct_of_days,
       count(*) FILTER (WHERE pct_a_cheaper BETWEEN 10 AND 90)       AS mixed,
       round(100.0*count(*) FILTER (WHERE pct_a_cheaper BETWEEN 10 AND 90)/count(*), 2) AS pct_mixed
FROM per_gtin GROUP BY 1 ORDER BY pair;

-- ============================ 5. INTRANSITIVITY, MEASURED =========================

-- The three-way common set: GTIN-days where ALL THREE vendors have a usable price on the
-- same basis. Every pair recomputed on this identical set removes the "different GTIN
-- sets" source of intransitivity, leaving only the statistic's own.
CREATE OR REPLACE TEMP TABLE common3 AS
SELECT gtin14, d, basis FROM obs
WHERE gtin14 IN (SELECT gtin14 FROM g90)
GROUP BY 1,2,3 HAVING count(DISTINCT vendor) = 3;

-- 6. Each pair, on its OWN intersection vs on the COMMON three-way set. If the orderings
--    differ, the pairwise design is producing an intransitive answer and that is a result.
SELECT r.va || ' / ' || r.vb                                          AS pair,
       count(*) FILTER (WHERE c.gtin14 IS NULL)                       AS n_own_only,
       round(median(r.ratio), 4)                                      AS median_own_intersection,
       count(*) FILTER (WHERE c.gtin14 IS NOT NULL)                   AS n_common,
       round(median(r.ratio) FILTER (WHERE c.gtin14 IS NOT NULL), 4)  AS median_common_set
FROM ratios r
LEFT JOIN common3 c ON c.gtin14 = r.gtin14 AND c.d = r.d AND c.basis = r.basis
GROUP BY 1 ORDER BY pair;

-- 7. THE TRANSITIVITY IDENTITY, on the common set. If the three medians were mutually
--    consistent, median(M/S) * median(S/W) would equal median(M/W). The deviation from
--    1.000 is the intransitivity the median statistic itself introduces, with the GTIN-set
--    difference already removed by using the common set.
WITH m AS (
  SELECT r.va, r.vb, median(r.ratio) AS med
  FROM ratios r JOIN common3 c ON c.gtin14 = r.gtin14 AND c.d = r.d AND c.basis = r.basis
  GROUP BY 1,2)
SELECT round((SELECT med FROM m WHERE va='Metro' AND vb='SaveOnFoods'), 4)   AS metro_over_saveon,
       round((SELECT med FROM m WHERE va='SaveOnFoods' AND vb='Walmart'), 4) AS saveon_over_walmart,
       round((SELECT med FROM m WHERE va='Metro' AND vb='Walmart'), 4)       AS metro_over_walmart,
       round((SELECT med FROM m WHERE va='Metro' AND vb='SaveOnFoods')
           * (SELECT med FROM m WHERE va='SaveOnFoods' AND vb='Walmart'), 4) AS implied_metro_over_walmart,
       round(((SELECT med FROM m WHERE va='Metro' AND vb='SaveOnFoods')
            * (SELECT med FROM m WHERE va='SaveOnFoods' AND vb='Walmart'))
           / (SELECT med FROM m WHERE va='Metro' AND vb='Walmart'), 4)       AS transitivity_residual;

-- 8. Size of the common set, so results 6 and 7 carry their n.
SELECT count(*) AS gtin_day_basis_cells, count(DISTINCT gtin14) AS gtins,
       count(DISTINCT d) AS dates FROM common3;

-- ============================ 6. THE TIE CASE IN RESULT 2 =========================

-- 9. Result 2 counts a date as "first cheaper" only where its median ratio is below 1.0, so
--    "the second vendor was cheaper on 100% of dates" silently assumes no date sits at
--    exactly 1.0. Added 2026-09-12, after the claims sweep found that assumption unexamined
--    behind the writeup's headline "100% of 711". Same daily medians, same n >= 30 filter,
--    every date put in exactly one of three bins, plus the closest any date came to 1.0.
WITH daily AS (
  SELECT va, vb, d, count(*) AS n, median(ratio) AS r
  FROM ratios GROUP BY 1,2,3 HAVING count(*) >= 30)
SELECT va || ' / ' || vb                                   AS pair,
       count(*)                                            AS n_dates,
       count(*) FILTER (WHERE r < 1.0)                     AS dates_first_cheaper,
       count(*) FILTER (WHERE r = 1.0)                     AS dates_exactly_1,
       count(*) FILTER (WHERE r > 1.0)                     AS dates_second_cheaper,
       round(min(r), 4)                                    AS min_daily_median,
       round(max(r), 4)                                    AS max_daily_median
FROM daily GROUP BY 1 ORDER BY pair;
