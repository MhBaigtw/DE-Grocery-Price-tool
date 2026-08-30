-- Q1.1 / Q1.2: the exclusion ledger and the bias audit, for D2 and D4 separately.
--
-- WHY THIS RUNS BEFORE ANY FINDING. Phase 0's F1 asked the D2 bias question on the wrong
-- axis and got a categorically wrong answer. That error was cheap because no number had
-- been published yet. The same error after publication is a retraction.
--
-- THE QUESTION IS NEVER "HOW MANY". It is "are the removed rows a random slice of what
-- remains". A large unbiased exclusion costs precision; a small biased one costs
-- correctness, and only the second one changes how a finding must be framed.
--
-- Three exclusion classes are in force (CLAUDE.md honesty rules 3 and 6):
--   ambiguous   parse_confidence = 'ambiguous'  -- value possibly wrong by 100x
--   orphan      product_key IS NULL             -- no product row, hence no identity
--   unparsed    offer_type = 'unparsed'         -- no derivable price at all
--
-- Orphans are the awkward one: they have no vendor and no category, because both live in
-- `product`. Where a breakdown needs a vendor, orphans are reported on their own row from
-- their id prefix (P5.9 established the prefix is the retired `vendor||sku` / `concatted`
-- id form), never silently dropped and never folded into a vendor's denominator.
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

-- Product-level attributes FIRST, over 187k rows rather than 71.8M. The category macro
-- runs eight regexes; applying it per price row segfaulted a 4 GB build, and it is the
-- same answer either way because the category is a function of the product, not the row.
CREATE OR REPLACE TEMP TABLE pk AS
SELECT product_key, vendor, cat(product_name) AS category, brand_class
FROM stg_product;

-- Orphan rows have no product row, so their vendor comes from the retired id form
-- (P5.9). Kept on their own rows, never folded into a vendor's denominator.
CREATE OR REPLACE TEMP TABLE tagged AS
SELECT s.src_rowid,
       s.product_key,
       s.observed_date,
       year(s.observed_date)                                    AS yr,
       s.unit_price,
       s.offer_type,
       s.old_unit_price,
       coalesce(pk.vendor, '(orphan: no product row)')          AS vendor,
       coalesce(pk.category, '(orphan: no product row)')        AS category,
       coalesce(pk.brand_class, '(orphan: no product row)')     AS brand_class,
       CASE
         WHEN s.product_key IS NULL            THEN '2. orphan'
         WHEN s.offer_type = 'unparsed'        THEN '3. unparsed'
         WHEN s.parse_confidence = 'ambiguous' THEN '1. ambiguous'
         ELSE                                       '0. retained'
       END                                                      AS class,
       (s.old_offer_type <> 'blank')                            AS is_sale_row,
       (s.product_key IS NULL)                                  AS is_orphan,
       (s.parse_confidence = 'ambiguous')                       AS is_ambiguous,
       (s.offer_type = 'unparsed')                              AS is_unparsed
FROM stg_price s
LEFT JOIN pk USING (product_key);

-- ============================ 1.1  THE LEDGER =====================================

-- 1. Headline ledger: rows removed by class, with the denominator.
SELECT class,
       count(*)                                                 AS rows,
       round(100.0 * count(*) / sum(count(*)) OVER (), 4)       AS pct_of_all_rows,
       count(DISTINCT product_key)                              AS distinct_keys,
       min(observed_date)                                       AS first_date,
       max(observed_date)                                       AS last_date
FROM tagged GROUP BY 1 ORDER BY 1;

-- 2. Do the classes OVERLAP? If a row is both ambiguous and unparsed the ledger above
--    counts it once, and the reader needs to know the classes are not disjoint.
SELECT count(*) FILTER (WHERE is_orphan AND is_ambiguous)    AS orphan_and_ambiguous,
       count(*) FILTER (WHERE is_orphan AND is_unparsed)     AS orphan_and_unparsed,
       count(*) FILTER (WHERE is_ambiguous AND is_unparsed)  AS ambiguous_and_unparsed
FROM tagged;

-- 3. Ledger by class x vendor. The denominator is the vendor's TOTAL rows, not its
--    excluded rows -- an earlier version partitioned over the filtered set and produced
--    "100% of vendor rows" for every single-class vendor, which is honesty rule 7 broken
--    in the column name itself.
--    Orphans have no vendor here; Q1b attributes them from the retired id form.
SELECT vendor, class, count(*) AS rows, any_total AS vendor_rows_total,
       round(100.0 * count(*) / any_total, 4) AS pct_of_vendor_rows
FROM (SELECT vendor, class, count(*) OVER (PARTITION BY vendor) AS any_total
      FROM tagged) t
WHERE class <> '0. retained'
GROUP BY vendor, class, any_total ORDER BY rows DESC, vendor, class;

-- 4. Ledger by class x year -- the axis the brief singles out.
SELECT yr, class, count(*) AS rows,
       round(100.0 * count(*) /
             sum(count(*)) OVER (PARTITION BY yr), 4)           AS pct_of_year_rows
FROM tagged GROUP BY 1,2 ORDER BY yr, class;

-- ============================ 1.2  BIAS: TIME =====================================

-- 5. THE TIME AXIS, per vendor per year: what share of each vendor-year is excluded?
--    A trend that crosses a vendor-year losing materially more than its neighbours is
--    reading an exclusion, not a price.
SELECT vendor, yr,
       count(*)                                                          AS rows_total,
       count(*) FILTER (WHERE class <> '0. retained')                    AS rows_excluded,
       round(100.0 * count(*) FILTER (WHERE class <> '0. retained') / count(*), 4) AS pct_excluded
FROM tagged
WHERE vendor <> '(orphan: no product row)'
GROUP BY 1,2 ORDER BY vendor, yr;

-- 6. The orphan block against the whole corpus by year -- P5.9 found an 8.412% / 0.357%
--    step at 2024-10-01, and D2 spans both sides of it.
SELECT yr,
       count(*)                                                          AS rows_total,
       count(*) FILTER (WHERE class = '2. orphan')                       AS orphan_rows,
       round(100.0 * count(*) FILTER (WHERE class = '2. orphan') / count(*), 4) AS pct_orphan
FROM tagged GROUP BY 1 ORDER BY 1;

-- ============================ 1.2  BIAS: PROMOTION TYPE ===========================

-- 7. Are excluded rows disproportionately SALE rows? This is the F1 axis, asked the
--    right way round: not "how many sale rows are excluded" but "is the excluded set
--    richer in sale rows than the retained set".
SELECT class,
       count(*)                                                          AS rows,
       count(*) FILTER (WHERE is_sale_row)                               AS sale_rows,
       round(100.0 * count(*) FILTER (WHERE is_sale_row) / count(*), 4)  AS pct_sale
FROM tagged GROUP BY 1 ORDER BY 1;

-- 8. Are excluded rows disproportionately DEEP discounts? Only rows with both an old and
--    a current value can answer, so the denominator is stated per class.
SELECT class,
       count(*) FILTER (WHERE old_unit_price IS NOT NULL AND unit_price IS NOT NULL
                          AND old_unit_price > 0)                        AS comparable_rows,
       round(median(100.0 * (old_unit_price - unit_price) / nullif(old_unit_price, 0))
             FILTER (WHERE old_unit_price IS NOT NULL AND unit_price IS NOT NULL
                       AND old_unit_price > 0 AND unit_price <= old_unit_price), 2) AS median_discount_pct
FROM tagged GROUP BY 1 ORDER BY 1;

-- 9. Offer-type mix: the multibuy exclusion was categorical once. Is any class skewed
--    toward one offer type rather than spread across them?
SELECT class, offer_type, count(*) AS rows,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY class), 3) AS pct_within_class
FROM tagged GROUP BY 1,2 ORDER BY 1, rows DESC, offer_type;

-- ============================ 1.2  BIAS: CATEGORY AND BRAND =======================

-- 10. Category mix of each excluded class against the retained population. A class that
--     matches the retained mix is a random slice on this axis; one that does not is a
--     distinct type, and D4's basket categories are the ones that matter.
SELECT category,
       count(*) FILTER (WHERE class = '0. retained')                     AS retained,
       round(100.0 * count(*) FILTER (WHERE class = '0. retained') /
             sum(count(*) FILTER (WHERE class = '0. retained')) OVER (), 2) AS pct_retained,
       count(*) FILTER (WHERE class = '1. ambiguous')                    AS ambiguous,
       round(100.0 * count(*) FILTER (WHERE class = '1. ambiguous') /
             nullif(sum(count(*) FILTER (WHERE class = '1. ambiguous')) OVER (), 0), 2) AS pct_ambiguous
FROM tagged GROUP BY 1 ORDER BY category;

-- 11. Brand class mix, same comparison. Private-label share is a D4-adjacent question
--     and an exclusion skewed toward one brand class would move it.
SELECT brand_class,
       count(*) FILTER (WHERE class = '0. retained')                     AS retained,
       round(100.0 * count(*) FILTER (WHERE class = '0. retained') /
             sum(count(*) FILTER (WHERE class = '0. retained')) OVER (), 2) AS pct_retained,
       count(*) FILTER (WHERE class = '1. ambiguous')                    AS ambiguous,
       round(100.0 * count(*) FILTER (WHERE class = '1. ambiguous') /
             nullif(sum(count(*) FILTER (WHERE class = '1. ambiguous')) OVER (), 0), 2) AS pct_ambiguous
FROM tagged GROUP BY 1 ORDER BY retained DESC, brand_class;
