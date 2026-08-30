-- F5: is D2's E8 attrition a RANDOM slice of each vendor's promotions, or a
-- DISTINCT TYPE of promotion?
--
-- F1 tested the wrong axis. It showed vendor SHARE barely moves, and concluded "smaller,
-- not biased". Vendor share is not the question: a drop can be perfectly proportional
-- across vendors and still remove one whole KIND of promotion from every vendor.
-- This tests the axis that matters -- promotion character, within vendor.
--
-- Three comparisons between dropped and retained events, per vendor:
--   (a) multibuy share      -- is the dropped set a different promotional mechanic?
--   (b) discount depth      -- computable for retained directly; for dropped multibuy
--                              by deriving unit price = offer_total / offer_qty
--   (c) sale run length     -- needs no price at all, so it is computable for BOTH
--                              sets and is the cleanest like-for-like axis
SET threads = 4;

CREATE OR REPLACE TEMP TABLE daily AS
SELECT p.vendor, p.sku,
       try_cast(substr(r.nowtime,1,10) AS DATE) AS d,
       max(CASE WHEN r.old_price IS NOT NULL AND trim(r.old_price)<>'' THEN 1 ELSE 0 END) AS on_sale,
       max(CASE WHEN try_cast(r.current_price AS DOUBLE) IS NULL
                 AND trim(coalesce(r.current_price,''))<>'' THEN 1 ELSE 0 END)            AS dirty,
       max(CASE WHEN regexp_matches(coalesce(r.current_price,''),'^[0-9]+/\$[0-9]') THEN 1 ELSE 0 END) AS multibuy,
       max(CASE WHEN regexp_matches(coalesce(r.current_price,''),'^[0-9.]+/[0-9]*[a-z]+$') THEN 1 ELSE 0 END) AS per_weight,
       -- scalar price for depth, where it exists
       max(try_cast(r.current_price AS DOUBLE))                                           AS px,
       max(try_cast(r.old_price     AS DOUBLE))                                           AS oldpx,
       -- derived unit price from a multibuy offer: "2/$7.00" -> 3.50
       max(try_cast(regexp_extract(coalesce(r.current_price,''),'^[0-9]+/\$([0-9.]+)',1) AS DOUBLE)
         / nullif(try_cast(regexp_extract(coalesce(r.current_price,''),'^([0-9]+)/\$',1) AS DOUBLE),0)) AS mb_unit_px
FROM raw r JOIN product p ON p.id = r.product_id
WHERE p.sku IS NOT NULL AND trim(p.sku) <> ''
  AND try_cast(substr(r.nowtime,1,10) AS DATE) >= DATE '2024-06-11'
GROUP BY 1,2,3;

-- sale runs, so duration is available per event
CREATE OR REPLACE TEMP TABLE runs AS
SELECT vendor, sku, d, on_sale, dirty, multibuy, per_weight, px, oldpx, mb_unit_px,
       -- determinism-ok: gaps-and-islands over `daily`, which is GROUP BY (key, date) and
       -- therefore holds exactly one row per key per date, so ORDER BY the date is a TOTAL
       -- order within the partition. Verified against the CREATE of `daily` above.
       row_number() OVER (PARTITION BY vendor,sku ORDER BY d)
     - row_number() OVER (PARTITION BY vendor,sku,on_sale ORDER BY d) AS grp,
       lag(on_sale) OVER (PARTITION BY vendor,sku ORDER BY d)         AS prev_on_sale
FROM daily;

CREATE OR REPLACE TEMP TABLE ev AS
SELECT vendor, sku, min(d) AS sale_start, count(*) AS sale_run_days,
       max(dirty) AS dirty_in_sale, max(multibuy) AS multibuy_in_sale,
       max(per_weight) AS perweight_in_sale,
       max(px) AS sale_px, max(oldpx) AS sale_oldpx, max(mb_unit_px) AS sale_mb_unit_px
FROM runs WHERE on_sale = 1
GROUP BY vendor, sku, grp;

-- attach the 14-day pre-window state (presence + dirtiness), matching D2/F1 exactly.
--
-- PERFORMANCE NOTE: D2 and F1 did this with two correlated subqueries per event. That
-- works at their size but is quadratic-ish and, on this larger event table, spilled
-- 3.4 GB and did not finish. A RANGE window frame over the ordered daily table computes
-- the identical thing in one pass. Same definition, same numbers -- statement 1 below
-- reconciles against F1 precisely so the rewrite is checkable, not just faster.
CREATE OR REPLACE TEMP TABLE pre AS
SELECT vendor, sku, d,
       count(*) OVER w  AS pre_days,
       max(dirty) OVER w AS dirty_pre
FROM daily
WINDOW w AS (PARTITION BY vendor, sku ORDER BY d
             RANGE BETWEEN INTERVAL 14 DAY PRECEDING AND INTERVAL 1 DAY PRECEDING);

CREATE OR REPLACE TEMP TABLE cohort AS
SELECT e.*, p.pre_days, p.dirty_pre,
       CASE WHEN coalesce(e.dirty_in_sale,0)=1 OR coalesce(p.dirty_pre,0)=1
            THEN 'dropped' ELSE 'retained' END AS grp
FROM ev e
JOIN pre p ON p.vendor=e.vendor AND p.sku=e.sku AND p.d=e.sale_start
WHERE p.pre_days = 14;

-- 1. Sanity: cohort sizes must reconcile with F1 (279,599 / 5,726 / 273,873).
SELECT grp, count(*) AS events FROM cohort GROUP BY grp ORDER BY grp;

-- 2. (a) MULTIBUY SHARE -- the headline test.
SELECT vendor, grp, count(*) AS events,
       count(*) FILTER (WHERE multibuy_in_sale=1)                          AS multibuy_events,
       round(100.0*count(*) FILTER (WHERE multibuy_in_sale=1)/count(*),2)  AS pct_multibuy,
       count(*) FILTER (WHERE perweight_in_sale=1)                         AS perweight_events,
       round(100.0*count(*) FILTER (WHERE perweight_in_sale=1)/count(*),2) AS pct_perweight
FROM cohort GROUP BY vendor, grp ORDER BY vendor, grp;

-- 3. (c) SALE RUN LENGTH -- computable for both cohorts, no price needed.
SELECT vendor, grp, count(*) AS events,
       round(avg(sale_run_days),2)    AS mean_run_days,
       round(median(sale_run_days),1) AS median_run_days,
       round(quantile_cont(sale_run_days,0.90),1) AS p90_run_days
FROM cohort GROUP BY vendor, grp ORDER BY vendor, grp;

-- 4. (b) DISCOUNT DEPTH. Retained uses the scalar price; dropped uses the derived
--    multibuy unit price. Only rows where both sides exist and old > new are used;
--    the denominator is printed so the exclusion is visible.
SELECT vendor, grp,
       count(*) FILTER (WHERE depth IS NOT NULL)                    AS depth_computable,
       count(*)                                                     AS events_in_cohort,
       round(100.0*count(*) FILTER (WHERE depth IS NOT NULL)/count(*),1) AS pct_computable,
       round(avg(depth)    FILTER (WHERE depth IS NOT NULL),2)      AS mean_pct_off,
       round(median(depth) FILTER (WHERE depth IS NOT NULL),2)      AS median_pct_off
FROM (
  SELECT vendor, grp,
         CASE WHEN grp='retained' AND sale_px IS NOT NULL AND sale_oldpx > sale_px
                THEN 100.0*(sale_oldpx-sale_px)/sale_oldpx
              WHEN grp='dropped' AND sale_mb_unit_px IS NOT NULL AND sale_oldpx > sale_mb_unit_px
                THEN 100.0*(sale_oldpx-sale_mb_unit_px)/sale_oldpx
         END AS depth
  FROM cohort)
GROUP BY vendor, grp ORDER BY vendor, grp;
