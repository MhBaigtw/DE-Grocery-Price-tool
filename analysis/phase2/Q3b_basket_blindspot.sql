-- Q3.5 / 3.6 / 3.7: what the UPC-matched basket cannot see, what it actually contains,
-- and what Galleria's absence from it says about Galleria.
--
-- 3.5 THE BLIND SPOT IS STRUCTURAL, NOT A PROPERTY OF THIS DATASET.
--
--   A cross-vendor basket built on UPC/GTIN can only contain products that carry the SAME
--   barcode at two or more vendors. Private label cannot: President's Choice is Loblaws',
--   Selection is Metro's, Great Value is Walmart's. A store brand has one seller by
--   definition, so it has no cross-vendor barcode match, so it can never enter the basket.
--
--   This would be true of any UPC-matched comparison on any grocery dataset. It is not a
--   coverage gap that more data or better matching fixes -- it is what UPC matching IS.
--   And it removes exactly the segment where banner-vs-banner price competition is
--   sharpest, which is the question a reader thinks D4 answers.
--
--   So the size of the blind spot has to be a number, not an adjective. Three measures
--   below: share of catalogue products, share of observed price rows, and a
--   price-weighted exposure proxy. The third is deliberately NOT called spend -- this
--   dataset has no quantities sold, so nothing here is a basket share. It is "how much of
--   the observed shelf, weighted by price" and is labelled that way.
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

CREATE OR REPLACE TEMP TABLE basket_gtin AS
SELECT gtin14 FROM (
  SELECT m.gtin14, count(DISTINCT s.observed_date) AS co_days
  FROM (SELECT gtin14, observed_date FROM (
          SELECT m2.gtin14, s2.observed_date, m2.vendor
          FROM stg_price s2 JOIN int_upc_match m2 ON m2.product_key = s2.product_key
          WHERE m2.is_reliable_only AND s2.parse_confidence <> 'ambiguous'
            AND s2.offer_type <> 'unparsed' AND s2.unit_price IS NOT NULL
            AND s2.observed_date >= DATE '2024-06-11')
        GROUP BY 1,2 HAVING count(DISTINCT vendor) >= 2) x
  JOIN int_upc_match m ON m.gtin14 = x.gtin14
  JOIN stg_price s ON s.product_key = m.product_key AND s.observed_date = x.observed_date
  GROUP BY 1) y
WHERE co_days >= 90;

-- Product-level view, with basket membership flagged.
CREATE OR REPLACE TEMP TABLE prod AS
SELECT sp.product_key, sp.vendor, sp.brand_class, sp.product_name,
       cat(sp.product_name) AS category, sp.total_qty, sp.unit_uom,
       (m.gtin14 IS NOT NULL AND m.gtin14 IN (SELECT gtin14 FROM basket_gtin)) AS in_basket
FROM stg_product sp LEFT JOIN int_upc_match m ON m.product_key = sp.product_key;

-- Row-level exposure, restricted to the four reliable-tier vendors, since those are the
-- only vendors D4 can involve at all.
CREATE OR REPLACE TEMP TABLE rows4 AS
SELECT p.vendor, p.brand_class, p.in_basket, s.unit_price
FROM stg_price s JOIN prod p ON p.product_key = s.product_key
WHERE p.vendor IN ('Metro','Galleria','SaveOnFoods','Walmart')
  AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
  AND s.unit_price IS NOT NULL AND s.price_basis = 'each'
  AND s.observed_date >= DATE '2024-06-11';

-- ============================ 3.5  THE BLIND SPOT, SIZED ==========================

-- 1. The headline: private label in the catalogue vs in the basket.
SELECT count(*) FILTER (WHERE brand_class = 'private_label')                  AS pl_products_catalogue,
       count(*) FILTER (WHERE brand_class = 'private_label' AND in_basket)    AS pl_products_in_basket,
       count(*) FILTER (WHERE in_basket)                                      AS all_basket_products,
       round(100.0*count(*) FILTER (WHERE brand_class = 'private_label' AND in_basket)
             / nullif(count(*) FILTER (WHERE in_basket), 0), 4)               AS pct_of_basket_that_is_pl
FROM prod;

-- 2. THE SIZE OF THE BLIND SPOT, three ways, for the four reliable-tier vendors.
--    "exposure" = sum of observed unit_price across price rows. NOT spend: this dataset
--    carries no quantities sold. It measures how much of the observed shelf, weighted by
--    price, sits in private label.
SELECT vendor,
       count(*)                                                               AS price_rows,
       round(100.0*count(*) FILTER (WHERE brand_class='private_label')/count(*), 2) AS pct_rows_private_label,
       round(100.0*sum(unit_price) FILTER (WHERE brand_class='private_label')
             / nullif(sum(unit_price), 0), 2)                                 AS pct_price_weighted_exposure,
       round(median(unit_price) FILTER (WHERE brand_class='private_label'), 2) AS median_px_private_label,
       round(median(unit_price) FILTER (WHERE brand_class='national_brand'), 2) AS median_px_national
FROM rows4 GROUP BY 1 ORDER BY pct_rows_private_label DESC, vendor;

-- 3. Pooled across the three vendors that HAVE brand data (Galleria has none), so the
--    blind spot has a single headline number.
SELECT round(100.0*count(*) FILTER (WHERE brand_class='private_label')/count(*), 2) AS pct_rows_pl,
       round(100.0*sum(unit_price) FILTER (WHERE brand_class='private_label')
             / nullif(sum(unit_price), 0), 2)                                       AS pct_exposure_pl,
       count(*)                                                                     AS n_rows
FROM rows4 WHERE vendor IN ('Metro','SaveOnFoods','Walmart');

-- 4. Where in the catalogue does private label sit? If it concentrates in the categories
--    the basket is already thin in, the blind spot compounds.
SELECT category,
       count(*) FILTER (WHERE brand_class='private_label')                    AS pl_products,
       count(*)                                                               AS all_products,
       round(100.0*count(*) FILTER (WHERE brand_class='private_label')/count(*), 2) AS pct_pl
FROM prod WHERE vendor IN ('Metro','SaveOnFoods','Walmart')
GROUP BY 1 ORDER BY pct_pl DESC, category;

-- ============================ 3.6  WHAT THE 3,477 ARE =============================

-- 5. Unit size: basket vs catalogue. A cross-vendor barcode favours standard pack sizes.
SELECT CASE WHEN in_basket THEN 'basket' ELSE 'rest of catalogue' END        AS population,
       count(*) FILTER (WHERE total_qty IS NOT NULL)                          AS n_with_size,
       round(median(total_qty) FILTER (WHERE unit_uom='g'), 1)                AS median_g,
       round(median(total_qty) FILTER (WHERE unit_uom='ml'), 1)               AS median_ml,
       round(100.0*count(*) FILTER (WHERE total_qty IS NULL)/count(*), 2)     AS pct_no_size
FROM prod WHERE vendor IN ('Metro','Galleria','SaveOnFoods','Walmart')
GROUP BY 1 ORDER BY 1;

-- 6. Price level: is the basket a cheap slice, an expensive slice, or typical?
SELECT CASE WHEN p.in_basket THEN 'basket' ELSE 'rest of catalogue' END       AS population,
       count(*)                                                               AS price_rows,
       round(median(s.unit_price), 2)                                         AS median_price,
       round(quantile_cont(s.unit_price, 0.25), 2)                            AS p25,
       round(quantile_cont(s.unit_price, 0.75), 2)                            AS p75,
       round(quantile_cont(s.unit_price, 0.95), 2)                            AS p95
FROM stg_price s JOIN prod p ON p.product_key = s.product_key
WHERE p.vendor IN ('Metro','Galleria','SaveOnFoods','Walmart')
  AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
  AND s.unit_price IS NOT NULL AND s.price_basis = 'each'
  AND s.observed_date >= DATE '2024-06-11'
GROUP BY 1 ORDER BY 1;

-- 7. Brand concentration: how many distinct brands carry the basket, and how top-heavy
--    is it? A basket dominated by a handful of multinationals is a different object from
--    one spread across hundreds of brands.
WITH b AS (
  SELECT sp.brand_raw, count(DISTINCT p.product_key) AS products
  FROM prod p JOIN stg_product sp ON sp.product_key = p.product_key
  WHERE p.in_basket AND sp.brand_raw IS NOT NULL AND trim(sp.brand_raw) <> ''
  GROUP BY 1)
SELECT count(*)                                                    AS distinct_brands,
       sum(products)                                               AS products_with_a_brand,
       round(100.0*sum(products) FILTER (WHERE rnk <= 10)/sum(products), 2)  AS pct_top10_brands,
       round(100.0*sum(products) FILTER (WHERE rnk <= 50)/sum(products), 2)  AS pct_top50_brands
-- determinism-ok: ORDER BY (products DESC, brand_raw) is a total order -- brand_raw is
-- the GROUP BY key of `b` and therefore unique within it, so no tie can survive.
FROM (SELECT *, row_number() OVER (ORDER BY products DESC, brand_raw) AS rnk FROM b);

-- 8. The top brands themselves, so "top-heavy" is inspectable.
SELECT sp.brand_raw, count(DISTINCT p.product_key) AS basket_products
FROM prod p JOIN stg_product sp ON sp.product_key = p.product_key
WHERE p.in_basket AND sp.brand_raw IS NOT NULL AND trim(sp.brand_raw) <> ''
GROUP BY 1 ORDER BY basket_products DESC, sp.brand_raw LIMIT 15;

-- ============================ 3.7  GALLERIA, AS A RESULT ==========================

-- 9. Is Galleria's absence a coverage failure on our side or a genuinely disjoint
--    catalogue? Its UPC coverage, its GTIN-bearing share, and how many of its GTINs any
--    other reliable vendor also carries.
SELECT sp.vendor,
       count(*)                                                               AS products,
       count(*) FILTER (WHERE sp.upc_raw IS NOT NULL AND trim(sp.upc_raw) <> '') AS with_upc,
       round(100.0*count(*) FILTER (WHERE sp.upc_raw IS NOT NULL AND trim(sp.upc_raw) <> '')/count(*), 2) AS pct_with_upc,
       count(*) FILTER (WHERE m.gtin14 IS NOT NULL)                           AS with_usable_gtin,
       round(100.0*count(*) FILTER (WHERE m.gtin14 IS NOT NULL)/count(*), 2)  AS pct_usable_gtin
FROM stg_product sp LEFT JOIN int_upc_match m ON m.product_key = sp.product_key
WHERE sp.vendor IN ('Metro','Galleria','SaveOnFoods','Walmart')
GROUP BY 1 ORDER BY pct_usable_gtin DESC, sp.vendor;

-- 10. Of the GTINs each reliable vendor DOES carry, what share is shared with at least
--     one other reliable vendor? This separates "few barcodes" from "different products".
SELECT m.vendor,
       count(DISTINCT m.gtin14)                                               AS gtins_carried,
       count(DISTINCT m.gtin14) FILTER (WHERE g.n_reliable >= 2)              AS shared_with_another,
       round(100.0*count(DISTINCT m.gtin14) FILTER (WHERE g.n_reliable >= 2)
             / nullif(count(DISTINCT m.gtin14), 0), 2)                        AS pct_shared
FROM int_upc_match m
JOIN (SELECT gtin14, count(DISTINCT vendor) AS n_reliable FROM int_upc_match
      WHERE gtin14 IS NOT NULL AND vendor IN ('Metro','Galleria','SaveOnFoods','Walmart')
      GROUP BY 1) g ON g.gtin14 = m.gtin14
WHERE m.vendor IN ('Metro','Galleria','SaveOnFoods','Walmart') AND m.gtin14 IS NOT NULL
GROUP BY 1 ORDER BY pct_shared DESC, m.vendor;

-- 11. What KIND of products are Galleria's 438 basket members, against its own catalogue?
SELECT cat(sp.product_name)                                                   AS category,
       count(DISTINCT sp.product_key) FILTER (WHERE p.in_basket)              AS in_basket,
       count(DISTINCT sp.product_key)                                         AS galleria_catalogue,
       round(100.0*count(DISTINCT sp.product_key) FILTER (WHERE p.in_basket)
             / nullif(count(DISTINCT sp.product_key), 0), 2)                  AS pct_of_category_in_basket
FROM stg_product sp JOIN prod p ON p.product_key = sp.product_key
WHERE sp.vendor = 'Galleria'
GROUP BY 1 ORDER BY category;
