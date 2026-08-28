-- P2.3: re-run the D2 exclusion count against the parsed model.
--
-- Phase 0 / F1 / F5 measured how many sale events are lost because `current_price`
-- cannot be cast to a number. That was a PRE-PARSE limit. stg_price now derives a
-- unit_price for 100.00% of current_price rows, so this re-measures the loss.
--
-- Prior numbers to beat:
--   279,599 evaluable events;  5,726 lost under F1's rule (sale-start day + pre-window)
--                              6,421 lost under F5's rule (any day of the sale run)
--   Metro multibuy events excluded entirely: 925
--
-- Definitions are held identical to F5 so the comparison is like-for-like; only the
-- "is this price usable" test changes, from `try_cast IS NOT NULL` to
-- `stg_price.unit_price IS NOT NULL`.
SET threads = 4;

-- Keyed on the OWNED product_key (md5, 128-bit), NOT the 64-bit workaround hash this
-- query originally used. That hash had one collision in 161,300 keys, which merged two
-- products into a single series and moved the counts below by 6 events. P3.5 proves the
-- owned key is collision-free across both snapshots, so the numbers here are exact.
-- md5's hex output is also pure ASCII, which sidesteps the DuckDB statistics bug on
-- VARCHAR sku columns that motivated the workaround in the first place.
CREATE OR REPLACE TEMP TABLE keymap AS
SELECT product_key AS k, any_value(vendor) AS vendor
FROM stg_product GROUP BY 1;

CREATE OR REPLACE TEMP TABLE daily AS
SELECT s.product_key AS k, s.observed_date AS d,
       max(CASE WHEN s.old_offer_type <> 'blank' THEN 1 ELSE 0 END)        AS on_sale,
       -- POST-PARSE dirty: no derivable unit price at all
       max(CASE WHEN s.unit_price IS NULL AND s.offer_type <> 'blank' THEN 1 ELSE 0 END) AS dirty_post,
       -- PRE-PARSE dirty: the old cast-based test, kept so both can be reported
       max(CASE WHEN try_cast(s.current_price_raw AS DOUBLE) IS NULL
                 AND trim(coalesce(s.current_price_raw,'')) <> '' THEN 1 ELSE 0 END)     AS dirty_pre,
       max(CASE WHEN s.offer_type = 'multibuy' THEN 1 ELSE 0 END)          AS multibuy
FROM stg_price s JOIN product p ON p.id = s.product_id
WHERE p.sku IS NOT NULL AND trim(p.sku) <> '' AND s.observed_date >= DATE '2024-06-11'
  AND s.product_key IS NOT NULL
GROUP BY 1,2;

CREATE OR REPLACE TEMP TABLE runs AS
SELECT *, row_number() OVER (PARTITION BY k ORDER BY d)
        - row_number() OVER (PARTITION BY k, on_sale ORDER BY d) AS grp
FROM daily;

CREATE OR REPLACE TEMP TABLE ev AS
SELECT k, min(d) AS sale_start,
       max(dirty_post) AS dirty_post_sale, max(dirty_pre) AS dirty_pre_sale,
       max(multibuy)   AS multibuy_sale
FROM runs WHERE on_sale = 1 GROUP BY k, grp;

CREATE OR REPLACE TEMP TABLE pre AS
SELECT k, d,
       count(*)        OVER w AS pre_days,
       max(dirty_post) OVER w AS dirty_post_pre,
       max(dirty_pre)  OVER w AS dirty_pre_pre
FROM daily
WINDOW w AS (PARTITION BY k ORDER BY d
             RANGE BETWEEN INTERVAL 14 DAY PRECEDING AND INTERVAL 1 DAY PRECEDING);

CREATE OR REPLACE TEMP TABLE cohort AS
SELECT e.*, p.pre_days, p.dirty_post_pre, p.dirty_pre_pre
FROM ev e JOIN pre p ON p.k=e.k AND p.d=e.sale_start
WHERE p.pre_days = 14;

-- 1. HEADLINE: pre-parse vs post-parse loss, whole sample.
SELECT count(*) AS evaluable_events,
       count(*) FILTER (WHERE coalesce(dirty_pre_sale,0)=1 OR coalesce(dirty_pre_pre,0)=1)   AS lost_PRE_parse,
       count(*) FILTER (WHERE coalesce(dirty_post_sale,0)=1 OR coalesce(dirty_post_pre,0)=1) AS lost_POST_parse,
       count(*) FILTER (WHERE coalesce(dirty_pre_sale,0)=1 OR coalesce(dirty_pre_pre,0)=1)
     - count(*) FILTER (WHERE coalesce(dirty_post_sale,0)=1 OR coalesce(dirty_post_pre,0)=1) AS RECOVERED,
       count(*) FILTER (WHERE coalesce(dirty_post_sale,0)=0 AND coalesce(dirty_post_pre,0)=0) AS usable_now
FROM cohort;

-- 2. Per vendor.
SELECT m.vendor,
       count(*) AS evaluable,
       count(*) FILTER (WHERE coalesce(dirty_pre_sale,0)=1 OR coalesce(dirty_pre_pre,0)=1)   AS lost_pre_parse,
       count(*) FILTER (WHERE coalesce(dirty_post_sale,0)=1 OR coalesce(dirty_post_pre,0)=1) AS lost_post_parse,
       count(*) FILTER (WHERE coalesce(dirty_pre_sale,0)=1 OR coalesce(dirty_pre_pre,0)=1)
     - count(*) FILTER (WHERE coalesce(dirty_post_sale,0)=1 OR coalesce(dirty_post_pre,0)=1) AS recovered
FROM cohort c JOIN keymap m USING (k) GROUP BY m.vendor ORDER BY recovered DESC;

-- 3. Metro's multibuy events specifically -- the 925 that were categorically excluded.
SELECT count(*) FILTER (WHERE multibuy_sale=1)                                  AS metro_multibuy_events,
       count(*) FILTER (WHERE multibuy_sale=1
                          AND coalesce(dirty_post_sale,0)=0
                          AND coalesce(dirty_post_pre,0)=0)                     AS multibuy_now_usable,
       round(100.0*count(*) FILTER (WHERE multibuy_sale=1
                          AND coalesce(dirty_post_sale,0)=0
                          AND coalesce(dirty_post_pre,0)=0)
             / nullif(count(*) FILTER (WHERE multibuy_sale=1),0),2)             AS pct_recovered
FROM cohort c JOIN keymap m USING (k) WHERE m.vendor = 'Metro';
