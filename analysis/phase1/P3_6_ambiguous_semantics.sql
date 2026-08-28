-- P3.6 / P3.7: how big is the ambiguous set, where does it sit, and does D4 depend on it?
--
-- Three populations now carry parse_confidence='ambiguous', all for the same reason: the
-- literal reading and the cents reading are both defensible and the evidence does not
-- separate them. Converting would be a guess; leaving them silently parsed as dollars
-- would ALSO be a guess -- the same unevidenced "bare integer means dollars" default that
-- was wrong for Walmart on 66,538 rows. Flagging is the only option that does not pick.
--
--   Walmart  bare integers 10-99   (adjudication split 1,767 dollars / 1,048 cents)
--   Galleria bare integers, all    (only 131 adjudicable, split 21/21 -- no evidence)
--   Voila    thousands-separator   (7 sweep pairs say cents; 23 rows, too few to convert)
SET threads = 4;

-- 1. Size of the ambiguous set, per vendor, as a share of that vendor's rows.
SELECT p.vendor,
       count(*)                                                       AS price_rows,
       count(*) FILTER (WHERE s.parse_confidence = 'ambiguous')        AS ambiguous_rows,
       round(100.0 * count(*) FILTER (WHERE s.parse_confidence = 'ambiguous') / count(*), 3)
                                                                       AS pct_of_vendor_rows,
       count(DISTINCT s.product_key) FILTER (WHERE s.parse_confidence = 'ambiguous')
                                                                       AS distinct_products
FROM stg_price s JOIN product p ON p.id = s.product_id
GROUP BY p.vendor ORDER BY ambiguous_rows DESC;

-- 2. Does the ambiguous set concentrate in a category D4 relies on? D4's basket is
--    reliable-tier UPCs (Metro, Galleria, Save-On-Foods, Walmart) -- and TWO of those four
--    vendors are exactly the ones with ambiguous prices, so this is not a hypothetical.
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

SELECT cat(p.product_name) AS category,
       count(*)                                                        AS ambiguous_rows,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2)              AS pct_of_ambiguous,
       count(DISTINCT p.vendor)                                        AS vendors
FROM stg_price s JOIN product p ON p.id = s.product_id
WHERE s.parse_confidence = 'ambiguous'
GROUP BY 1 ORDER BY ambiguous_rows DESC;

-- 3. THE D4 QUESTION, asked directly: how many of D4's reliable-tier basket GTINs have
--    any ambiguous price row at all?
CREATE OR REPLACE TEMP MACRO digits(x) AS regexp_replace(coalesce(x,''), '[^0-9]', '', 'g');
CREATE OR REPLACE TEMP MACRO gtin14(x) AS lpad(digits(x), 14, '0');

CREATE OR REPLACE TEMP TABLE rel_only AS
SELECT gtin14(upc) AS gtin FROM product
WHERE length(digits(upc)) BETWEEN 11 AND 14 AND NOT digits(upc) ~ '^0+$'
GROUP BY 1
HAVING count(DISTINCT vendor) >= 2
   AND count(DISTINCT vendor) FILTER (WHERE vendor NOT IN
       ('Metro','Galleria','SaveOnFoods','Walmart')) = 0;

SELECT (SELECT count(*) FROM rel_only)                                  AS d4_reliable_gtins,
       count(DISTINCT gtin14(p.upc))                                    AS gtins_with_ambiguous_rows,
       round(100.0 * count(DISTINCT gtin14(p.upc))
             / (SELECT count(*) FROM rel_only), 2)                      AS pct_of_basket_touched
FROM stg_price s
JOIN product p     ON p.id = s.product_id
JOIN rel_only r    ON r.gtin = gtin14(p.upc)
WHERE s.parse_confidence = 'ambiguous';

-- 4. And how much of those GTINs' PRICE HISTORY is ambiguous? A basket product with one
--    bad day is usable; one that is ambiguous throughout is not.
WITH touched AS (
  SELECT gtin14(p.upc) AS gtin,
         count(*)                                                       AS rows_all,
         count(*) FILTER (WHERE s.parse_confidence = 'ambiguous')        AS rows_ambiguous
  FROM stg_price s
  JOIN product p  ON p.id = s.product_id
  JOIN rel_only r ON r.gtin = gtin14(p.upc)
  GROUP BY 1 HAVING count(*) FILTER (WHERE s.parse_confidence = 'ambiguous') > 0)
SELECT CASE WHEN rows_ambiguous * 1.0 / rows_all < 0.01 THEN 'a. <1% of history'
            WHEN rows_ambiguous * 1.0 / rows_all < 0.10 THEN 'b. 1-10%'
            WHEN rows_ambiguous * 1.0 / rows_all < 0.50 THEN 'c. 10-50%'
            ELSE                                             'd. >=50% -- unusable' END AS share_of_history,
       count(*) AS gtins
FROM touched GROUP BY 1 ORDER BY 1;

-- 5. Same question for D2: how many evaluable sale events touch an ambiguous price?
--    (D2 needs current_price across the 14 pre-sale days plus the sale day.)
SELECT p.vendor,
       count(DISTINCT s.product_key)                                    AS products_with_ambiguous,
       count(*)                                                         AS ambiguous_rows,
       count(*) FILTER (WHERE s.old_offer_type <> 'blank')              AS ambiguous_rows_on_a_sale_day
FROM stg_price s JOIN product p ON p.id = s.product_id
WHERE s.parse_confidence = 'ambiguous'
GROUP BY p.vendor ORDER BY ambiguous_rows DESC;
