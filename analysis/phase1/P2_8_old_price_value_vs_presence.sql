-- P2.8 (brief item 2.7): old_price -- value versus presence.
--
-- D2 is not one analysis. Some of its sub-questions need old_price only as a SALE FLAG
-- (was this product on sale on this day?); others need its NUMERIC VALUE (how deep was
-- the discount?). The 869,495 rows where old_price is the literal string 'was' are usable
-- for the first and useless for the second, so the exposure is different per sub-analysis
-- and must be stated per sub-analysis rather than as one coverage number.
SET threads = 4;

-- 1. Presence vs usable value, per vendor. Both denominators stated.
SELECT p.vendor,
       count(*)                                                            AS price_rows,
       count(*) FILTER (WHERE s.old_offer_type <> 'blank')                 AS old_price_PRESENT,
       round(100.0*count(*) FILTER (WHERE s.old_offer_type <> 'blank')/count(*),2)
                                                                           AS pct_present,
       count(*) FILTER (WHERE s.old_unit_price IS NOT NULL)                AS old_price_USABLE_VALUE,
       round(100.0*count(*) FILTER (WHERE s.old_unit_price IS NOT NULL)/count(*),2)
                                                                           AS pct_usable,
       count(*) FILTER (WHERE s.old_offer_type <> 'blank'
                          AND s.old_unit_price IS NULL)                    AS present_but_no_value,
       round(100.0*count(*) FILTER (WHERE s.old_offer_type <> 'blank' AND s.old_unit_price IS NULL)
             / nullif(count(*) FILTER (WHERE s.old_offer_type <> 'blank'),0),2)
                                                                           AS pct_of_flags_valueless
FROM stg_price s JOIN product p ON p.id = s.product_id
GROUP BY p.vendor ORDER BY pct_of_flags_valueless DESC;

-- 2. The pre-sale-inflation test is the one that matters. It needs:
--      * old_price as a FLAG, to locate the sale event         -> 'was' rows are fine
--      * current_price VALUES across the 14 pre-sale days      -> unaffected by old_price
--      * old_price VALUE only if discount depth is reported
--    So: how many Loblaws sale events can support each variant?
CREATE OR REPLACE TEMP TABLE daily AS
SELECT hash(p.vendor||'|'||p.sku) AS k, s.observed_date AS dt,
       max(CASE WHEN s.old_offer_type <> 'blank' THEN 1 ELSE 0 END)   AS on_sale,
       max(CASE WHEN s.old_unit_price IS NOT NULL THEN 1 ELSE 0 END)  AS old_has_value,
       max(CASE WHEN s.unit_price IS NULL THEN 1 ELSE 0 END)          AS cur_missing
FROM stg_price s JOIN product p ON p.id = s.product_id
WHERE p.sku IS NOT NULL AND trim(p.sku)<>'' AND s.observed_date >= DATE '2024-06-11'
GROUP BY 1,2;

CREATE OR REPLACE TEMP TABLE ev AS
SELECT k, min(dt) AS sale_start, max(old_has_value) AS old_has_value, max(cur_missing) AS cur_missing
FROM (SELECT *, row_number() OVER (PARTITION BY k ORDER BY dt)
             - row_number() OVER (PARTITION BY k, on_sale ORDER BY dt) AS grp FROM daily)
WHERE on_sale = 1 GROUP BY k, grp;

CREATE OR REPLACE TEMP TABLE pre AS
SELECT k, dt, count(*) OVER w AS pre_days, max(cur_missing) OVER w AS pre_missing
FROM daily
WINDOW w AS (PARTITION BY k ORDER BY dt RANGE BETWEEN INTERVAL 14 DAY PRECEDING AND INTERVAL 1 DAY PRECEDING);

CREATE OR REPLACE TEMP TABLE keymap AS
SELECT hash(vendor||'|'||sku) AS k, any_value(vendor) AS vendor
FROM product WHERE sku IS NOT NULL AND trim(sku)<>'' GROUP BY 1;

SELECT m.vendor,
       count(*)                                                    AS evaluable_events,
       count(*) FILTER (WHERE e.old_has_value = 1)                 AS events_with_old_price_VALUE,
       round(100.0*count(*) FILTER (WHERE e.old_has_value=1)/count(*),2) AS pct_with_value,
       count(*) - count(*) FILTER (WHERE e.old_has_value = 1)      AS flag_only_no_value
FROM ev e
JOIN pre p ON p.k = e.k AND p.dt = e.sale_start AND p.pre_days = 14
JOIN keymap m ON m.k = e.k
GROUP BY m.vendor ORDER BY pct_with_value;
