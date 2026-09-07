-- Q1.4: category and brand bias of the orphan exclusion, tested from the retired id
-- string rather than from a join.
--
-- WHAT §1.2 SAID, AND WHY IT WAS TOO PESSIMISTIC. The first bias audit recorded category
-- and brand as "untestable" for orphan rows, on the grounds that both live in `product`
-- and an orphan has no `product` row. That is true of the JOIN and false of the DATA:
-- P5.9 established that 76.28% of orphan rows carry a `product_id` in the retired
-- `vendor~name@units^brand` form, which contains the name and the brand outright.
--
-- IS THIS A LOCKED-DECISION BREACH? No, and the distinction is worth writing down.
--
--   Locked decision 5 forbids the supplied row id as a PRODUCT IDENTITY -- keying,
--   joining, matching, or following a product through time with it. Its stated hazard is
--   that the id "changes daily", which is a statement about identity over time.
--
--   This query does none of that. It parses descriptive text out of a string and counts
--   distributions. There is no key, no join on the id, no product tracked across dates,
--   and no orphan row admitted to any finding. The output is a mix comparison and nothing
--   else.
--
--   Precedent, accepted at Section 1 sign-off: Q1b derives the orphan vendor prefix from
--   `product_id` and sizes orphan sale events on it, both labelled as measurements of what
--   is missing. This is the same class of use with two more fields read from the same
--   string. `scripts/check_layering.py` governs `models/`; this is `analysis/`, and the
--   check still passes.
--
-- THE CONFOUND, HANDLED UP FRONT. Comparing Metro's orphans against an all-vendor
-- retained mix would repeat the F1 mistake a third time -- it would measure Metro's
-- catalogue, not orphaning. So every comparison below is ALSO run vendor-matched, against
-- the retained rows of exactly the vendors the parsed orphans come from.
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

-- Parse the retired concatted id: vendor ~ name @ units ^ brand.
-- Nothing here is joined, keyed, or carried forward; the columns are read and counted.
CREATE OR REPLACE TEMP TABLE orphan_attr AS
SELECT s.src_rowid,
       year(s.observed_date)                                        AS yr,
       (s.old_offer_type <> 'blank')                                AS is_sale_row,
       regexp_extract(s.product_id, '^([^~]+)~', 1)                 AS o_vendor,
       regexp_extract(s.product_id, '^[^~]+~(.*)@', 1)              AS o_name,
       regexp_extract(s.product_id, '\^(.*)$', 1)                   AS o_brand
FROM stg_price s
WHERE s.product_key IS NULL
  AND s.product_id LIKE '%~%@%^%';

-- 1. COVERAGE, stated before any result: what fraction of the orphan block does this
--    speak for, and which vendors does it actually cover?
SELECT (SELECT count(*) FROM stg_price WHERE product_key IS NULL)     AS all_orphan_rows,
       count(*)                                                       AS parsable_rows,
       round(100.0*count(*) /
             (SELECT count(*) FROM stg_price WHERE product_key IS NULL), 2) AS pct_coverage,
       count(*) FILTER (WHERE o_name IS NULL OR trim(o_name) = '')     AS rows_with_no_name,
       count(*) FILTER (WHERE o_brand IS NULL OR trim(o_brand) = '')   AS rows_with_no_brand
FROM orphan_attr;

-- 2. Which vendors does the parsable set cover? If it is one vendor, the result is a
--    statement about that vendor's orphans and must be reported that way.
SELECT o_vendor, count(*) AS rows,
       round(100.0*count(*) / sum(count(*)) OVER (), 2) AS pct_of_parsable,
       count(*) FILTER (WHERE is_sale_row)              AS sale_rows
FROM orphan_attr GROUP BY 1 ORDER BY rows DESC, o_vendor;

-- 3. Sanity check on the parse itself: a sample, so the extraction can be eyeballed
--    rather than trusted.
SELECT o_vendor, o_name, o_brand, count(*) AS rows
FROM orphan_attr
GROUP BY 1,2,3 ORDER BY rows DESC, o_vendor, o_name LIMIT 12;

-- ============================ CATEGORY ============================================

-- Retained comparison group, restricted to the SAME vendors the parsed orphans come from.
CREATE OR REPLACE TEMP TABLE retained_matched AS
SELECT cat(sp.product_name) AS category, sp.brand_class, sp.vendor
FROM stg_price s JOIN stg_product sp USING (product_key)
WHERE s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
  AND sp.vendor IN (SELECT DISTINCT o_vendor FROM orphan_attr);

-- 4. THE ANSWER: category mix of parsed orphans vs the vendor-matched retained mix.
SELECT coalesce(o.category, r.category)                              AS category,
       o.rows                                                        AS orphan_rows,
       round(o.pct, 2)                                               AS pct_orphan,
       r.rows                                                        AS retained_rows,
       round(r.pct, 2)                                               AS pct_retained,
       round(o.pct / nullif(r.pct, 0), 2)                            AS ratio
FROM (SELECT cat(o_name) AS category, count(*) AS rows,
             100.0*count(*)/sum(count(*)) OVER () AS pct
      FROM orphan_attr GROUP BY 1) o
FULL JOIN (SELECT category, count(*) AS rows,
                  100.0*count(*)/sum(count(*)) OVER () AS pct
           FROM retained_matched GROUP BY 1) r USING (category)
ORDER BY category;

-- ============================ BRAND ===============================================
-- b_class is vendor-aware, so the parsed brand is classified through the SAME macro the
-- model uses. Anything else would compare two different classifications and call the
-- difference a bias.

-- 5. Brand-class mix of parsed orphans vs the vendor-matched retained mix.
SELECT coalesce(o.brand_class, r.brand_class)                        AS brand_class,
       o.rows                                                        AS orphan_rows,
       round(o.pct, 2)                                               AS pct_orphan,
       r.rows                                                        AS retained_rows,
       round(r.pct, 2)                                               AS pct_retained,
       round(o.pct / nullif(r.pct, 0), 2)                            AS ratio
FROM (SELECT b_class(o_vendor, o_brand) AS brand_class, count(*) AS rows,
             100.0*count(*)/sum(count(*)) OVER () AS pct
      FROM orphan_attr GROUP BY 1) o
FULL JOIN (SELECT brand_class, count(*) AS rows,
                  100.0*count(*)/sum(count(*)) OVER () AS pct
           FROM retained_matched GROUP BY 1) r USING (brand_class)
ORDER BY brand_class;

-- 6. Private-label share specifically -- the D4-adjacent number an exclusion skewed
--    toward one brand class would move.
SELECT 'parsed orphans' AS population,
       count(*)                                                                 AS rows,
       count(*) FILTER (WHERE b_class(o_vendor, o_brand) = 'private_label')      AS private_label,
       round(100.0*count(*) FILTER (WHERE b_class(o_vendor, o_brand) = 'private_label')
             / count(*), 3)                                                      AS pct_private_label
FROM orphan_attr
UNION ALL
SELECT 'retained, same vendors', count(*),
       count(*) FILTER (WHERE brand_class = 'private_label'),
       round(100.0*count(*) FILTER (WHERE brand_class = 'private_label') / count(*), 3)
FROM retained_matched;

-- 7. Does the category skew differ between orphan SALE rows and orphan rows overall?
--    If the excluded sale rows are a different category mix again, D2 inherits that.
SELECT cat(o_name) AS category,
       count(*)                                                       AS all_orphan_rows,
       count(*) FILTER (WHERE is_sale_row)                            AS orphan_sale_rows,
       round(100.0*count(*) FILTER (WHERE is_sale_row)
             / sum(count(*) FILTER (WHERE is_sale_row)) OVER (), 2)   AS pct_of_orphan_sale
FROM orphan_attr GROUP BY 1 ORDER BY category;

-- ============================ THE WITHIN-VENDOR CONTROL ============================
-- Results 4 and 5 pool across vendors, and the pooled brand result is not trustworthy:
-- 89.66% of parsable orphans are Metro, while the retained pool includes Voila, T&T and
-- Galleria, which are 100% `unclassifiable_no_vendor_data` (Phase 1 §3.3). That alone
-- would make orphans look brand-rich without any orphaning effect at all.
--
-- This is the F1 confound for the third time in one audit. Same treatment: compare each
-- vendor's orphans against THAT VENDOR's retained rows.

CREATE OR REPLACE TEMP TABLE retained_by_vendor AS
SELECT sp.vendor, cat(sp.product_name) AS category, sp.brand_class
FROM stg_price s JOIN stg_product sp USING (product_key)
WHERE s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed';

-- 8. CATEGORY, within vendor. Reported for the vendors with enough parsable orphans to
--    say anything (>= 2,000 rows); the rest are listed with their n and no verdict.
SELECT coalesce(o.vendor, r.vendor)            AS vendor,
       coalesce(o.category, r.category)        AS category,
       o.rows                                  AS orphan_rows,
       round(o.pct, 2)                         AS pct_orphan,
       round(r.pct, 2)                         AS pct_retained,
       round(o.pct / nullif(r.pct, 0), 2)      AS ratio
FROM (SELECT o_vendor AS vendor, cat(o_name) AS category, count(*) AS rows,
             100.0*count(*)/sum(count(*)) OVER (PARTITION BY o_vendor) AS pct
      FROM orphan_attr GROUP BY 1,2) o
FULL JOIN (SELECT vendor, category, count(*) AS rows,
                  100.0*count(*)/sum(count(*)) OVER (PARTITION BY vendor) AS pct
           FROM retained_by_vendor GROUP BY 1,2) r USING (vendor, category)
WHERE coalesce(o.vendor, r.vendor) IN ('Metro','Walmart','TandT')
ORDER BY vendor, category;

-- 9. BRAND CLASS, within vendor -- the control the pooled result 5 needs.
SELECT coalesce(o.vendor, r.vendor)            AS vendor,
       coalesce(o.brand_class, r.brand_class)  AS brand_class,
       o.rows                                  AS orphan_rows,
       round(o.pct, 2)                         AS pct_orphan,
       round(r.pct, 2)                         AS pct_retained,
       round(o.pct / nullif(r.pct, 0), 2)      AS ratio
FROM (SELECT o_vendor AS vendor, b_class(o_vendor, o_brand) AS brand_class, count(*) AS rows,
             100.0*count(*)/sum(count(*)) OVER (PARTITION BY o_vendor) AS pct
      FROM orphan_attr GROUP BY 1,2) o
FULL JOIN (SELECT vendor, brand_class, count(*) AS rows,
                  100.0*count(*)/sum(count(*)) OVER (PARTITION BY vendor) AS pct
           FROM retained_by_vendor GROUP BY 1,2) r USING (vendor, brand_class)
WHERE coalesce(o.vendor, r.vendor) IN ('Metro','Walmart','TandT')
ORDER BY vendor, brand_class;

-- 10. Private-label share, within vendor -- the single number D4 would inherit.
SELECT coalesce(o.vendor, r.vendor)                     AS vendor,
       o.orphan_rows,
       round(o.pct_pl_orphan, 3)                        AS pct_private_label_orphan,
       round(r.pct_pl_retained, 3)                      AS pct_private_label_retained,
       round(o.pct_pl_orphan / nullif(r.pct_pl_retained, 0), 2) AS ratio
FROM (SELECT o_vendor AS vendor, count(*) AS orphan_rows,
             100.0*count(*) FILTER (WHERE b_class(o_vendor, o_brand)='private_label')/count(*) AS pct_pl_orphan
      FROM orphan_attr GROUP BY 1) o
FULL JOIN (SELECT vendor,
                  100.0*count(*) FILTER (WHERE brand_class='private_label')/count(*) AS pct_pl_retained
           FROM retained_by_vendor GROUP BY 1) r USING (vendor)
ORDER BY o.orphan_rows DESC NULLS LAST, vendor;
