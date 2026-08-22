-- F2: characterise D1's 474 well-covered Metro SKUs against the full 14,288.
-- Question: is the usable subset representative, or is it a particular slice?
--
-- NOTE ON "CATEGORY": the dataset has no category column. Category here is a crude
-- keyword probe on product_name, identical in method to D4. It is indicative, not a
-- taxonomy, and is labelled as such wherever it is quoted.
SET threads = 4;

CREATE OR REPLACE TEMP TABLE metro_win AS
SELECT p.sku,
       any_value(p.product_name)                                   AS product_name,
       any_value(p.brand)                                          AS brand,
       count(DISTINCT try_cast(substr(r.nowtime,1,10) AS DATE))    AS days_present
FROM raw r JOIN product p ON p.id = r.product_id
WHERE p.vendor = 'Metro'
  AND p.sku IS NOT NULL AND trim(p.sku) <> ''
  AND r.current_price IS NOT NULL AND trim(r.current_price) <> ''
  AND try_cast(substr(r.nowtime,1,10) AS DATE) BETWEEN DATE '2024-11-01' AND DATE '2025-02-05'
GROUP BY p.sku;

-- cohort flag: the D1 "well covered" set is >= 90% of the 97-day window
CREATE OR REPLACE TEMP TABLE cohort AS
SELECT *, CASE WHEN days_present >= 0.90*97 THEN 'well_covered_474' ELSE 'rest_of_catalogue' END AS grp
FROM metro_win;

-- Metro private-label brands, observed from the data (not assumed).
CREATE OR REPLACE TEMP MACRO metro_pl(b) AS
  upper(trim(coalesce(b,''))) IN ('SELECTION','IRRÉSISTIBLE','IRRESISTIBLE','LIFE SMART',
    'FRONT STREET BAKERY','METROGO!','METRO','ECONOMAX','PREMIÈRE MOISSON','PREMIERE MOISSON',
    'SELECTION BIO','IRRÉSISTIBLES','IRRESISTIBLES');

-- 1. Cohort sizes + brand-field coverage + private-label share.
SELECT grp,
       count(*)                                                              AS skus,
       count(*) FILTER (WHERE brand IS NOT NULL AND trim(brand)<>'')         AS brand_populated,
       round(100.0*count(*) FILTER (WHERE brand IS NOT NULL AND trim(brand)<>'')/count(*),2) AS pct_brand_populated,
       count(*) FILTER (WHERE metro_pl(brand))                               AS private_label,
       round(100.0*count(*) FILTER (WHERE metro_pl(brand))/count(*),2)       AS pct_private_label,
       count(*) FILTER (WHERE brand IS NOT NULL AND trim(brand)<>'' AND NOT metro_pl(brand)) AS national_brand,
       round(100.0*count(*) FILTER (WHERE brand IS NOT NULL AND trim(brand)<>'' AND NOT metro_pl(brand))/count(*),2) AS pct_national_brand
FROM cohort GROUP BY grp ORDER BY grp;

-- 2. Top brands in the well-covered 474 vs their share of the whole window catalogue.
WITH b AS (
  SELECT upper(trim(coalesce(brand,'(blank)'))) AS bn,
         count(*) FILTER (WHERE grp='well_covered_474') AS in_474,
         count(*)                                       AS in_all
  FROM cohort GROUP BY 1)
SELECT bn AS brand,
       in_474, in_all,
       round(100.0*in_474/sum(in_474) OVER (),2) AS pct_of_474,
       round(100.0*in_all/sum(in_all) OVER (),2) AS pct_of_catalogue,
       round(100.0*in_474/nullif(in_all,0),1)    AS retention_pct
FROM b WHERE in_all >= 40 ORDER BY in_474 DESC LIMIT 20;

-- 3. Category probe (keyword on product_name), both cohorts.
SELECT grp, cat, count(*) AS skus,
       round(100.0*count(*)/sum(count(*)) OVER (PARTITION BY grp),2) AS pct_of_cohort
FROM (
  SELECT grp, CASE
    WHEN regexp_matches(lower(product_name),'(bread|bagel|bun|tortilla|pita|croissant)') THEN 'a. bread & bakery'
    WHEN regexp_matches(lower(product_name),'(milk|cream|yogur|yoghur|cheese|butter|margarine)') THEN 'b. dairy'
    WHEN regexp_matches(lower(product_name),'egg') THEN 'c. eggs'
    WHEN regexp_matches(lower(product_name),'(apple|banana|orange|potato|onion|carrot|tomato|lettuce|berry|berries|grape|pepper|broccoli|cucumber|salad)') THEN 'd. produce'
    WHEN regexp_matches(lower(product_name),'(chicken|beef|pork|turkey|bacon|ham|sausage|fish|salmon|tuna|shrimp)') THEN 'e. meat & fish'
    WHEN regexp_matches(lower(product_name),'(rice|pasta|flour|sugar|cereal|oat|noodle|soup|sauce)') THEN 'f. pantry staples'
    WHEN regexp_matches(lower(product_name),'(juice|coffee|tea|soda|water|cola|drink|beverage)') THEN 'g. beverages'
    WHEN regexp_matches(lower(product_name),'(frozen|pizza|ice cream)') THEN 'h. frozen'
    ELSE 'i. other' END AS cat
  FROM cohort)
GROUP BY grp, cat ORDER BY cat, grp;
