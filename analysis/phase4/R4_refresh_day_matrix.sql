-- R4: what each candidate refresh DAY costs, day by day, until the next refresh.
--
-- WHY THIS IS NOT ARITHMETIC. R1 gives a per-weekday change rate and it is tempting to
-- compound those rates to get the staleness curve for a Friday refresh versus a Wednesday
-- one. That would assume changes on successive days are independent, which is exactly what
-- a flyer cycle is not: a product repriced on Thursday is more likely to be repriced the
-- following Thursday, and a compounding estimate would silently double-count. So the curve
-- is measured directly instead of derived, and honesty rule 9 keeps the estimate out.
--
-- WHAT IT ANSWERS. For a price captured on weekday W, what share is wrong h days later, for
-- h = 1..7. Read one row of W as "if I refresh on W, this is how the error grows until my
-- next refresh". The h = 7 column should be roughly FLAT across W -- every 7-day window
-- contains exactly one Thursday -- and if it is, that is the finding: choosing the refresh
-- day does not lower the worst case, it lowers the time spent at it.
--
-- A MISSING DAY IS NOT AN UNCHANGED PRICE (honesty rule 1). A pair is counted only when the
-- product is observed on both d and d+h. Unobserved counterparts are dropped and counted.
--
-- SCOPE. The three chains the tool compares, reliable-barcode basket, 2025 onward.
SET threads = 2;

CREATE OR REPLACE TEMP TABLE b AS
SELECT DISTINCT m.product_key AS k, m.vendor, m.gtin14
FROM int_upc_match m
WHERE m.is_reliable_only AND m.vendor IN ('Metro','SaveOnFoods','Walmart');

CREATE OR REPLACE TEMP TABLE bd AS
SELECT b.vendor, b.gtin14, s.observed_date AS d, s.price_basis AS basis,
       -- determinism-ok: min() over (gtin, vendor, date, basis) -- Phase 0 B6 proves this
       -- grain is not unique; min() is a total order and is the Phase 2/3 convention.
       min(s.unit_price) AS px
FROM stg_price s JOIN b ON b.k = s.product_key
WHERE s.observed_date >= DATE '2025-01-01'
  AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
  AND s.unit_price IS NOT NULL AND s.unit_price > 0
GROUP BY 1,2,3,4;

-- 1. The matrix. One row per chain per capture weekday, one column per horizon.
WITH hh AS (SELECT unnest([1,2,3,4,5,6,7]) AS h),
pairs AS (
  SELECT a.vendor, dayname(a.d) AS captured_on, dayofweek(a.d) AS dow, hh.h,
         (f.px IS NOT NULL)                              AS observed,
         (f.px IS NOT NULL AND abs(f.px - a.px) > 0.005) AS wrong
  FROM bd a CROSS JOIN hh
  LEFT JOIN bd f ON f.gtin14 = a.gtin14 AND f.vendor = a.vendor AND f.basis = a.basis
                AND f.d = a.d + hh.h),
r AS (
  SELECT vendor, captured_on, dow, h,
         round(100.0*count(*) FILTER (WHERE wrong)
               / nullif(count(*) FILTER (WHERE observed), 0), 2) AS pct_wrong,
         count(*) FILTER (WHERE observed)                        AS pairs
  FROM pairs GROUP BY vendor, captured_on, dow, h)
SELECT vendor, captured_on,
       max(pct_wrong) FILTER (WHERE h=1) AS d1,
       max(pct_wrong) FILTER (WHERE h=2) AS d2,
       max(pct_wrong) FILTER (WHERE h=3) AS d3,
       max(pct_wrong) FILTER (WHERE h=4) AS d4,
       max(pct_wrong) FILTER (WHERE h=5) AS d5,
       max(pct_wrong) FILTER (WHERE h=6) AS d6,
       max(pct_wrong) FILTER (WHERE h=7) AS d7,
       min(pairs)                        AS min_pairs
FROM r GROUP BY vendor, captured_on, dow ORDER BY vendor, dow;

-- 2. Collapsed to the two numbers a schedule is chosen on: the WORST error reached before
--    the next refresh, and the MEAN error across the days in between. Same weekly cadence,
--    seven different refresh days.
WITH hh AS (SELECT unnest([1,2,3,4,5,6,7]) AS h),
pairs AS (
  SELECT a.vendor, dayname(a.d) AS refresh_day, dayofweek(a.d) AS dow, hh.h,
         (f.px IS NOT NULL)                              AS observed,
         (f.px IS NOT NULL AND abs(f.px - a.px) > 0.005) AS wrong
  FROM bd a CROSS JOIN hh
  LEFT JOIN bd f ON f.gtin14 = a.gtin14 AND f.vendor = a.vendor AND f.basis = a.basis
                AND f.d = a.d + hh.h),
r AS (
  SELECT vendor, refresh_day, dow, h,
         100.0*count(*) FILTER (WHERE wrong)
         / nullif(count(*) FILTER (WHERE observed), 0) AS pct_wrong
  FROM pairs GROUP BY vendor, refresh_day, dow, h)
SELECT vendor, refresh_day,
       round(max(pct_wrong), 2)  AS worst_pct_wrong_before_next_refresh,
       round(avg(pct_wrong), 2)  AS mean_pct_wrong_across_the_week
FROM r GROUP BY vendor, refresh_day, dow
ORDER BY vendor, mean_pct_wrong_across_the_week;
