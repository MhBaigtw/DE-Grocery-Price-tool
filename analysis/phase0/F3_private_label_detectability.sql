-- F3: can private label be told apart from national brand using the `brand` field?
-- Metro's freeze claim is scoped to "all private label and national brand grocery
-- products", so the distinction is load-bearing for D1 -- and for any per-vendor
-- comparison of freeze behaviour.
--
-- Method: a documented list of each retailer's own labels, matched case-insensitively
-- against `brand`. The list is written out explicitly so it can be argued with and
-- extended; it is a judgement input, not a derived fact. What is NOT a judgement call
-- is brand-field COVERAGE, which caps how far the classification can go at all.
SET threads = 4;

CREATE OR REPLACE TEMP MACRO nb(b) AS upper(trim(coalesce(b,'')));

CREATE OR REPLACE TEMP MACRO is_private_label(vendor, b) AS
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

-- 1. THE COVERAGE CEILING: how much of each catalogue can be classified at all.
SELECT vendor,
       count(*)                                                                AS products,
       count(*) FILTER (WHERE trim(coalesce(brand,''))<>'')                    AS brand_populated,
       round(100.0*count(*) FILTER (WHERE trim(coalesce(brand,''))<>'')/count(*),2) AS pct_brand_populated,
       count(*) FILTER (WHERE is_private_label(vendor, brand))                 AS private_label,
       count(*) FILTER (WHERE trim(coalesce(brand,''))<>''
                          AND NOT is_private_label(vendor, brand))             AS national_brand,
       count(*) FILTER (WHERE trim(coalesce(brand,''))='')                     AS UNCLASSIFIABLE,
       CASE WHEN count(*) FILTER (WHERE trim(coalesce(brand,''))<>'') = 0
            THEN 'NO - brand field empty'
            WHEN count(*) FILTER (WHERE is_private_label(vendor, brand)) = 0
            THEN 'NO - no private label identified'
            WHEN 100.0*count(*) FILTER (WHERE trim(coalesce(brand,''))<>'')/count(*) < 75
            THEN 'PARTIAL - low coverage'
            ELSE 'YES' END                                                     AS distinguishable
FROM product GROUP BY vendor ORDER BY pct_brand_populated DESC;

-- 2. Case-inconsistency in the brand field: the same label under multiple spellings
--    inflates apparent brand diversity and breaks naive GROUP BY brand.
SELECT vendor, upper(trim(brand)) AS brand_upper,
       count(DISTINCT brand) AS distinct_raw_spellings,
       string_agg(DISTINCT brand, ' | ') AS spellings,
       count(*) AS products
FROM product WHERE trim(coalesce(brand,''))<>''
GROUP BY 1,2 HAVING count(DISTINCT brand) > 1
ORDER BY products DESC LIMIT 12;

-- 3. Non-brand values leaking into the brand field.
SELECT vendor, brand, count(*) AS products
FROM product
WHERE lower(trim(coalesce(brand,''))) IN
      ('out of stock','out of stock.','unbranded','n/a','na','none','error','null','-')
GROUP BY 1,2 ORDER BY products DESC;
