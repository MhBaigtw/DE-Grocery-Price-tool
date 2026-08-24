-- F7: what exactly do the 92.45% / 94.31% / 90.64% / 89.39% numbers in F3 measure?
--
-- THEY ARE BRAND-FIELD NON-NULL COVERAGE. They are NOT classification accuracy.
-- They state how many products carry any brand string at all -- the ceiling on what any
-- classifier could reach -- and say nothing about whether the private/national split
-- assigned within that population is correct.
--
-- This query separates the two and quantifies the error sources in the classification.
SET threads = 2;

CREATE OR REPLACE TEMP MACRO nb(b) AS upper(trim(coalesce(b,'')));
CREATE OR REPLACE TEMP MACRO is_pl(vendor, b) AS
  CASE vendor
    WHEN 'Metro' THEN nb(b) IN ('SELECTION','SELECTION BIO','IRRÉSISTIBLE','IRRESISTIBLE',
        'IRRÉSISTIBLES','IRRESISTIBLES','LIFE SMART','FRONT STREET BAKERY','METROGO!','METRO',
        'ECONOMAX','PREMIÈRE MOISSON','PREMIERE MOISSON')
    WHEN 'Loblaws' THEN nb(b) IN ('PRESIDENT''S CHOICE','PC','PC ORGANICS','PC BLUE MENU',
        'PC BLACK LABEL','NO NAME','FARMER''S MARKET','JOE FRESH','LIFE BRAND','EVERYDAY ESSENTIALS')
    WHEN 'NoFrills' THEN nb(b) IN ('PRESIDENT''S CHOICE','PC','PC ORGANICS','PC BLUE MENU',
        'PC BLACK LABEL','NO NAME','FARMER''S MARKET','JOE FRESH','EVERYDAY ESSENTIALS')
    WHEN 'Walmart' THEN nb(b) IN ('GREAT VALUE','YOUR FRESH MARKET','OUR FINEST','EQUATE',
        'MARKETSIDE','PARENT''S CHOICE','MAINSTAYS','ATHLETIC WORKS','GEORGE','SAM''S CHOICE')
    WHEN 'SaveOnFoods' THEN nb(b) IN ('WESTERN FAMILY','SAVE-ON-FOODS','BAKE SHOP',
        'ONLY GOODNESS','BIG PACIFIC','BLUSH LANE')
    WHEN 'Voila' THEN nb(b) IN ('COMPLIMENTS','COMPLIMENTS BALANCE','PANACHE','SENSATIONS',
        'SIGNAL','BIG 8','OUR FINEST')
    ELSE FALSE END;

CREATE OR REPLACE TEMP MACRO is_junk(b) AS
  lower(trim(coalesce(b,''))) IN ('out of stock','out of stock.','unbranded','n/a','na',
                                  'none','error','null','-','.','--');

-- 1. Coverage (the F3 number) vs the classification it permits, side by side.
SELECT vendor,
       count(*)                                                        AS products,
       round(100.0*count(*) FILTER (WHERE nb(brand)<>'')/count(*),2)   AS pct_brand_coverage_THE_F3_NUMBER,
       count(*) FILTER (WHERE nb(brand)='')                            AS unclassifiable_blank,
       count(*) FILTER (WHERE is_junk(brand))                          AS junk_brand_values,
       count(*) FILTER (WHERE is_pl(vendor,brand))                     AS classified_private_label,
       count(*) FILTER (WHERE nb(brand)<>'' AND NOT is_junk(brand)
                          AND NOT is_pl(vendor,brand))                 AS classified_national_brand
FROM product GROUP BY vendor ORDER BY pct_brand_coverage_THE_F3_NUMBER DESC;

-- 2. ERROR SOURCE 1 -- false negatives: retailer-exclusive brands NOT on the list.
--    A brand carried by exactly one vendor, in volume, is a private-label candidate.
--    Anything here that is genuinely private label is currently mis-filed as national.
WITH bv AS (
  SELECT nb(brand) AS b, vendor, count(*) AS n
  FROM product WHERE nb(brand)<>'' AND NOT is_junk(brand) GROUP BY 1,2),
excl AS (
  SELECT b, min(vendor) AS only_vendor, sum(n) AS products, count(*) AS vendor_count
  FROM bv GROUP BY b HAVING count(*) = 1)
SELECT only_vendor AS vendor, b AS brand_exclusive_to_one_vendor, products,
       is_pl(only_vendor, b) AS already_on_list
FROM excl
WHERE products >= 120 AND NOT is_pl(only_vendor, b)
ORDER BY products DESC LIMIT 25;

-- 3. ERROR SOURCE 2 -- the case-split bug. Does it affect THIS classifier?
--    The classifier folds case via nb(), so it should be immune. Verify rather than
--    assume: count products whose brand differs from its own upper-case form, and
--    confirm the private/national verdict is identical either way.
SELECT count(*)                                                              AS products_with_mixed_case_brand,
       count(*) FILTER (WHERE is_pl(vendor,brand) <> is_pl(vendor,upper(brand))) AS verdict_changes_under_case_fold,
       count(DISTINCT nb(brand)) FILTER (WHERE brand <> upper(trim(brand)))  AS distinct_brands_affected
FROM product WHERE nb(brand)<>'' AND brand <> upper(trim(brand));

-- 4. ERROR SOURCE 3 -- junk values inflating the NATIONAL BRAND count specifically.
SELECT vendor, brand, count(*) AS products_counted_as_national_brand
FROM product WHERE is_junk(brand) GROUP BY 1,2 ORDER BY 3 DESC;
