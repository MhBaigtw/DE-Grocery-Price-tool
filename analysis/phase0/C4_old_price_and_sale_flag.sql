-- C4: old_price coverage per vendor, and whether old_price agrees with `other`
-- indicating a sale.
-- `other` is a free-text grab-bag ("Out of Stock", "Best seller", "Made In Canada",
-- "Rollback", "2 for $6", "sale\n$3.50 MIN 2"). A sale signal is taken to be a
-- case-insensitive 'sale' OR 'rollback' (Walmart's word for a markdown).
-- Disagreement is reported BOTH ways, per the brief.
SET threads = 4;

CREATE OR REPLACE TEMP TABLE ev AS
SELECT p.vendor,
       (r.old_price IS NOT NULL AND trim(r.old_price) <> '')                       AS has_old_price,
       (r.other IS NOT NULL AND
        (lower(r.other) LIKE '%sale%' OR lower(r.other) LIKE '%rollback%'))        AS other_says_sale
FROM raw r JOIN product p ON p.id = r.product_id;

-- 1. Coverage + two-way disagreement.
SELECT vendor,
       count(*)                                                              AS price_rows,
       count(*) FILTER (WHERE has_old_price)                                 AS rows_with_old_price,
       round(100.0*count(*) FILTER (WHERE has_old_price)/count(*),2)         AS pct_with_old_price,
       count(*) FILTER (WHERE other_says_sale)                               AS rows_other_says_sale,
       round(100.0*count(*) FILTER (WHERE other_says_sale)/count(*),2)       AS pct_other_says_sale,
       -- old_price present but `other` does NOT say sale
       count(*) FILTER (WHERE has_old_price AND NOT other_says_sale)         AS oldprice_no_saleflag,
       round(100.0*count(*) FILTER (WHERE has_old_price AND NOT other_says_sale)
             / nullif(count(*) FILTER (WHERE has_old_price),0),2)            AS pct_of_oldprice_missing_flag,
       -- `other` says sale but there is NO old_price
       count(*) FILTER (WHERE other_says_sale AND NOT has_old_price)         AS saleflag_no_oldprice,
       round(100.0*count(*) FILTER (WHERE other_says_sale AND NOT has_old_price)
             / nullif(count(*) FILTER (WHERE other_says_sale),0),2)          AS pct_of_saleflag_missing_oldprice
FROM ev GROUP BY vendor ORDER BY pct_with_old_price DESC;

-- 2. Vendors that NEVER populate old_price -> excluded from all sale analysis.
SELECT vendor, count(*) AS price_rows,
       count(*) FILTER (WHERE has_old_price) AS rows_with_old_price
FROM ev GROUP BY vendor HAVING count(*) FILTER (WHERE has_old_price) = 0;
