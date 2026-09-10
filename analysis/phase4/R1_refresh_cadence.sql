-- R1: measure the refresh cadence. Produces no schedule by itself -- it produces the
-- numbers a schedule has to be derived from.
--
-- WHY MEASURE RATHER THAN PICK. A refresh interval is a claim about how long a displayed
-- price stays true. Picking "daily" or "weekly" first and justifying it afterwards would
-- assume exactly the thing the data can answer: how long a price actually holds, and when
-- it moves.
--
-- SCOPE. The tool covers Metro, Save-On-Foods and Walmart (Phase 2 §3.7 excluded Galleria
-- -- its catalogue barely overlaps), national brands only, one Toronto neighbourhood. All
-- eight chains are measured here for context, because a cadence that is a flyer artefact
-- at three chains and not at the other five would be worth knowing; the recommendation is
-- scoped to the three the tool actually shows.
--
-- EXCLUSIONS, per the standing rules: ambiguous prices (honesty rule 3), rows with no
-- product record (honesty rule 6), unparseable prices. Counted in result 1.
--
-- A MISSING DAY IS NOT AN UNCHANGED PRICE (honesty rule 1). Every duration below is
-- measured in OBSERVED days and in calendar span, and the two are reported separately,
-- because a product not seen for a week has not held its price for a week -- it has not
-- been looked at.
SET threads = 2;

-- One price per product per day per basis. Basis is carried because a per-weight price and
-- an each-price are different quantities and a change between them is not a price change.
CREATE OR REPLACE TEMP TABLE daily AS
SELECT s.product_key                                   AS k,
       s.observed_date                                 AS d,
       s.price_basis                                   AS basis,
       -- determinism-ok: min() over (key, date, basis), which Phase 0 B6 proves is not
       -- unique -- one product appears many times a day with conflicting prices. min() is
       -- a total order and is the convention used throughout Phases 2 and 3.
       min(s.unit_price)                               AS px,
       max(CASE WHEN s.old_offer_type <> 'blank' THEN 1 ELSE 0 END) AS on_sale
FROM stg_price s
WHERE s.product_key IS NOT NULL
  AND s.parse_confidence <> 'ambiguous'
  AND s.offer_type <> 'unparsed'
  AND s.unit_price IS NOT NULL AND s.unit_price > 0
  AND s.observed_date >= DATE '2024-06-11'      -- full-catalogue era only
GROUP BY 1,2,3;

CREATE OR REPLACE TEMP TABLE prod AS
SELECT product_key AS k, vendor, product_key_basis FROM stg_product;

-- 1. Exclusion accounting for this measurement, per honesty rule 7.
SELECT (SELECT count(*) FROM stg_price WHERE observed_date >= DATE '2024-06-11')  AS rows_in_window,
       (SELECT count(*) FROM stg_price WHERE observed_date >= DATE '2024-06-11'
          AND product_key IS NULL)                                               AS excl_no_product,
       (SELECT count(*) FROM stg_price WHERE observed_date >= DATE '2024-06-11'
          AND parse_confidence = 'ambiguous')                                    AS excl_ambiguous,
       (SELECT count(*) FROM stg_price WHERE observed_date >= DATE '2024-06-11'
          AND offer_type = 'unparsed')                                           AS excl_unparsed,
       (SELECT count(*) FROM daily)                                              AS product_days_measured;

-- Consecutive observations of the same product on the same basis.
-- determinism-ok: lag() over (PARTITION BY k, basis ORDER BY d) -- `daily` is GROUP BY
-- (k, d, basis), so exactly one row per key per date per basis and the ordering is total.
CREATE OR REPLACE TEMP TABLE steps AS
SELECT k, basis, d, px, on_sale,
       lag(px) OVER w                          AS prev_px,
       lag(d)  OVER w                          AS prev_d,
       date_diff('day', lag(d) OVER w, d)      AS gap_days
FROM daily
WINDOW w AS (PARTITION BY k, basis ORDER BY d);

-- A change: consecutive OBSERVED prices differ by more than half a cent. Restricted to
-- adjacent-day observations (gap = 1) for the day-of-week analysis, because a change
-- observed across a 9-day gap cannot be attributed to a weekday.
CREATE OR REPLACE TEMP TABLE changes AS
SELECT s.*, p.vendor,
       (abs(s.px - s.prev_px) > 0.005) AS changed
FROM steps s JOIN prod p ON p.k = s.k
WHERE s.prev_px IS NOT NULL;

-- ============================ 1.1  DAY-OF-WEEK ===================================

-- 2. THE FLYER CYCLE TEST. Share of adjacent-day price changes falling on each weekday,
--    per chain. A flat 14.3% everywhere means no weekly cycle; a spike means a flyer day.
--    Restricted to gap_days = 1 so the change is attributable to a single weekday.
SELECT c.vendor,
       dayname(c.d)                                                        AS weekday,
       count(*) FILTER (WHERE c.changed)                                   AS changes,
       count(*)                                                            AS observations,
       round(100.0*count(*) FILTER (WHERE c.changed)/count(*), 2)          AS pct_of_obs_that_changed,
       round(100.0*count(*) FILTER (WHERE c.changed)
             / nullif(sum(count(*) FILTER (WHERE c.changed))
                      OVER (PARTITION BY c.vendor), 0), 2)                 AS pct_of_chains_changes
FROM changes c
WHERE c.gap_days = 1
GROUP BY 1,2 ORDER BY c.vendor, dayofweek(min(c.d));

-- 3. The same, collapsed to the concentration statistic -- how far the busiest weekday is
--    above an even 14.29% split. This is the number that decides whether a weekly-aligned
--    schedule beats an arbitrary one.
WITH dow AS (
  SELECT c.vendor, dayname(c.d) AS wd,
         100.0*count(*) FILTER (WHERE c.changed)
         / nullif(sum(count(*) FILTER (WHERE c.changed)) OVER (PARTITION BY c.vendor),0) AS pct
  FROM changes c WHERE c.gap_days = 1 GROUP BY 1,2)
SELECT vendor,
       round(max(pct), 2)                          AS busiest_weekday_pct,
       round(min(pct), 2)                          AS quietest_weekday_pct,
       round(max(pct) - 14.29, 2)                  AS excess_over_even_split,
       -- determinism-ok: arg_max over (pct, wd) -- wd is the GROUP BY key of `dow` and is
       -- therefore unique within a vendor, so no tie can survive.
       arg_max(wd, pct)                            AS busiest_weekday
FROM dow GROUP BY 1 ORDER BY excess_over_even_split DESC, vendor;

-- ============================ 1.2  HOW LONG A PRICE HOLDS =========================

-- Spells of constant price. A new spell starts whenever the price changes OR the
-- observation gap exceeds 3 days -- past that, the price was not observed to hold, and
-- counting it as held would be forward-filling across a gap.
-- determinism-ok: the running sum is over (k, basis) ordered by d, and `daily`'s grain
-- makes that a total order.
CREATE OR REPLACE TEMP TABLE spells AS
SELECT k, basis, vendor, spell_id,
       count(*)                                    AS observed_days,
       date_diff('day', min(d), max(d)) + 1        AS calendar_span,
       max(on_sale)                                AS ever_on_sale
FROM (
  SELECT c.k, c.basis, c.vendor, c.d, c.on_sale,
         sum(CASE WHEN c.changed OR c.gap_days > 3 THEN 1 ELSE 0 END)
             OVER (PARTITION BY c.k, c.basis ORDER BY c.d
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS spell_id
  FROM changes c)
GROUP BY 1,2,3,4;

-- 4. HOW LONG A PRICE HOLDS, per chain. Only completed spells count -- a spell still
--    running at the end of the data is right-censored and would drag the median down.
SELECT s.vendor,
       count(*)                                              AS completed_spells,
       round(median(s.calendar_span), 1)                     AS median_days_held,
       round(quantile_cont(s.calendar_span, 0.90), 1)        AS p90_days_held,
       round(quantile_cont(s.calendar_span, 0.25), 1)        AS p25,
       round(median(s.observed_days), 1)                     AS median_observed_days,
       round(100.0*count(*) FILTER (WHERE s.calendar_span <= 7)/count(*), 2) AS pct_holding_7d_or_less
FROM spells s
GROUP BY 1 ORDER BY median_days_held, s.vendor;

-- 5. WITHDRAWN -- DO NOT QUOTE. Left in place, not deleted, so the mistake stays
--    findable and so nothing silently renumbers around it.
--
--    This asked: if the tool refreshes every k days, what share of displayed prices
--    are already wrong? It answers a different question. The denominator is
--    consecutive-observation pairs with gap <= k, and on a near-daily dataset that is
--    ~97% one-day pairs -- so every column re-measures the ONE-day rate. Metro reads
--    3.40% at k=1 and 4.19% at k=7; the correct 7-day figure is 27.45%, so this
--    understates by 6.5x. The flatness across k should have been the tell.
--
--    Replaced by analysis/phase4/R3_staleness_by_interval.sql, which measures it
--    forward: price on date d against the same product on date d+k.
--
--    The k=1 column alone is sound (it IS the one-day rate) and matches R3's k=1
--    within rounding. The rest is not.
SELECT c.vendor,
       count(*)                                                          AS observation_pairs,
       round(100.0*count(*) FILTER (WHERE c.changed AND c.gap_days <= 1)/
             nullif(count(*) FILTER (WHERE c.gap_days <= 1),0), 2)       AS pct_changed_by_1d,
       round(100.0*count(*) FILTER (WHERE c.changed AND c.gap_days <= 3)/
             nullif(count(*) FILTER (WHERE c.gap_days <= 3),0), 2)       AS pct_changed_by_3d,
       round(100.0*count(*) FILTER (WHERE c.changed AND c.gap_days <= 7)/
             nullif(count(*) FILTER (WHERE c.gap_days <= 7),0), 2)       AS pct_changed_by_7d,
       round(100.0*count(*) FILTER (WHERE c.changed AND c.gap_days <= 14)/
             nullif(count(*) FILTER (WHERE c.gap_days <= 14),0), 2)      AS pct_changed_by_14d
FROM changes c
GROUP BY 1 ORDER BY pct_changed_by_7d DESC, c.vendor;

-- 6. Does the weekday pattern hold across years, or is it a 2024 artefact? A schedule
--    built on a pattern that has since dissolved would be built on history.
WITH dow AS (
  SELECT c.vendor, year(c.d) AS yr, dayname(c.d) AS wd,
         100.0*count(*) FILTER (WHERE c.changed)
         / nullif(sum(count(*) FILTER (WHERE c.changed))
                  OVER (PARTITION BY c.vendor, year(c.d)),0) AS pct
  FROM changes c WHERE c.gap_days = 1 GROUP BY 1,2,3)
SELECT vendor, yr, round(max(pct),2) AS busiest_pct,
       -- determinism-ok: wd is unique within (vendor, yr) by the GROUP BY above.
       arg_max(wd, pct) AS busiest_weekday
FROM dow GROUP BY 1,2 ORDER BY vendor, yr;

-- 7. Sale spells vs regular spells. A sale price that holds for 7 days is a flyer week; if
--    sale spells are much shorter than regular ones, the refresh has to track the shorter.
SELECT s.vendor,
       round(median(s.calendar_span) FILTER (WHERE s.ever_on_sale = 1), 1) AS median_days_on_sale_price,
       round(median(s.calendar_span) FILTER (WHERE s.ever_on_sale = 0), 1) AS median_days_regular_price,
       count(*) FILTER (WHERE s.ever_on_sale = 1)                          AS n_sale_spells,
       count(*) FILTER (WHERE s.ever_on_sale = 0)                          AS n_regular_spells
FROM spells s GROUP BY 1 ORDER BY s.vendor;
