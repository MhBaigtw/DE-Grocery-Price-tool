-- D4: cross-vendor basket comparison, using ONLY the reliable-group-only UPC set (B4).
-- Two questions: how many products, and are they everyday staples or a random long tail?
-- NOTE: DuckDB's `~` is regexp_full_match, not a partial match. Unanchored keyword
-- alternations MUST use regexp_matches(); `~` silently returns false for them.
-- Category assignment is crude keyword matching on product_name -- deliberately so; it
-- is a coverage probe, not a taxonomy. Counts are indicative, not exact.
SET threads = 4;
CREATE OR REPLACE TEMP MACRO digits(x) AS regexp_replace(coalesce(x,''),'[^0-9]','','g');
CREATE OR REPLACE TEMP MACRO gtin14(x) AS lpad(digits(x),14,'0');

-- The B4 reliable-only set, restricted to GTINs actually co-observed at 2+ reliable
-- vendors on at least 90 shared days (B4d) -- a basket needs a usable history.
CREATE OR REPLACE TEMP TABLE rel_only AS
SELECT gtin14(upc) AS gtin FROM product
WHERE length(digits(upc)) BETWEEN 11 AND 14 AND digits(upc) !~ '^0+$'
GROUP BY 1
HAVING count(DISTINCT vendor) >= 2
   AND count(DISTINCT vendor) FILTER (WHERE vendor NOT IN ('Metro','Galleria','SaveOnFoods','Walmart')) = 0;

CREATE OR REPLACE TEMP TABLE codays AS
SELECT gtin14(p.upc) AS gtin, try_cast(substr(r.nowtime,1,10) AS DATE) AS d,
       count(DISTINCT p.vendor) AS nv
FROM raw r JOIN product p ON p.id=r.product_id
WHERE p.vendor IN ('Metro','Galleria','SaveOnFoods','Walmart')
  AND length(digits(p.upc)) BETWEEN 11 AND 14 AND digits(p.upc) !~ '^0+$'
  AND try_cast(substr(r.nowtime,1,10) AS DATE) >= DATE '2024-06-11'
GROUP BY 1,2;

CREATE OR REPLACE TEMP TABLE basket AS
SELECT c.gtin, count(*) FILTER (WHERE c.nv>=2) AS shared_days
FROM codays c JOIN rel_only o ON o.gtin=c.gtin
GROUP BY 1 HAVING count(*) FILTER (WHERE c.nv>=2) >= 90;

-- 1. Basket size at successive quality bars.
SELECT (SELECT count(*) FROM rel_only)                                        AS b4_reliable_only_gtins,
       (SELECT count(*) FROM basket)                                          AS gtins_with_90plus_shared_days,
       (SELECT count(*) FROM basket WHERE shared_days >= 365)                 AS gtins_with_365plus_shared_days;

-- 2. Everyday-category coverage of the 90+ shared-day basket.
CREATE OR REPLACE TEMP TABLE named AS
SELECT DISTINCT b.gtin, lower(p.product_name) AS nm
FROM basket b JOIN product p ON gtin14(p.upc)=b.gtin;

SELECT cat, count(DISTINCT gtin) AS gtins_in_basket FROM (
  SELECT gtin, CASE
    WHEN regexp_matches(nm, '(bread|bagel|bun|tortilla|pita)')                      THEN 'a. bread & bakery'
    WHEN regexp_matches(nm, '(milk|cream|yogur|yoghur|cheese|butter|margarine)')     THEN 'b. dairy'
    WHEN regexp_matches(nm, '\begg')                                                THEN 'c. eggs'
    WHEN regexp_matches(nm, '(apple|banana|orange|potato|onion|carrot|tomato|lettuce|berry|berries|grape|pepper|broccoli|cucumber)') THEN 'd. produce'
    WHEN regexp_matches(nm, '(chicken|beef|pork|turkey|bacon|ham|sausage|fish|salmon|tuna|shrimp)') THEN 'e. meat & fish'
    WHEN regexp_matches(nm, '(rice|pasta|flour|sugar|cereal|oat|noodle)')            THEN 'f. pantry staples'
    WHEN regexp_matches(nm, '(juice|coffee|tea|soda|water|cola|drink)')              THEN 'g. beverages'
    ELSE 'h. other / long tail' END AS cat
  FROM named) GROUP BY cat ORDER BY cat;

-- 3. A concrete look at the staples end of the basket.
SELECT b.gtin, b.shared_days,
       min(p.product_name) AS example_name,
       string_agg(DISTINCT p.vendor, ',') AS vendors
FROM basket b JOIN product p ON gtin14(p.upc)=b.gtin
WHERE regexp_matches(lower(p.product_name), '(bread|milk|egg|butter|cheese|rice|coffee)')
GROUP BY 1,2 ORDER BY b.shared_days DESC LIMIT 20;
