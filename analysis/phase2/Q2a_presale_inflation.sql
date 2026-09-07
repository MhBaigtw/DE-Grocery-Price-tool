-- Q2A: D2 finding one -- was the advertised "regular" price actually being charged
-- before the sale?
--
-- `old_price` is the retailer's CLAIM about the regular price. The `current_price`
-- history is what was actually charged. The gap between them is the finding.
--
-- SCOPE, set by our own Section 1 bias audit rather than by preference:
--   HEADLINE WINDOW = 2025-01-01 .. 2026-08-21. Every vendor-year in it loses under 4.5%
--   of its events to orphaning and essentially 0% to the sku filter. 2024 is excluded
--   from the headline and reported separately, because it loses 26.8% of Metro's events
--   to orphaning, 26.3% of Walmart's and 21.9% of Galleria's to the sku filter, and a
--   cross-vendor comparison across those is measuring exclusions.
--
-- EXCLUSIONS APPLIED (CLAUDE.md honesty rules 3, 6, and Section 1.5):
--   * ambiguous prices      -- excluded, counted
--   * orphan (NULL key)     -- excluded by construction, counted
--   * vendor_concatted keys -- reported as a separate tier, not silently dropped
--
-- THE COMPARISON STATISTIC IS AN ARGUMENT, NOT A DETAIL. Three candidates disagree and
-- all three are computed:
--   modal   -- the price most often charged in the 14 days before the sale. Best answer
--              to "what was the shopper actually paying", robust to a one-day blip.
--   median  -- robust to outliers but can land between two real prices and match neither.
--   last    -- the price on the day before the sale started. Closest to what a shopper
--              would remember, but a single observation and therefore fragile.
-- The headline uses MODAL, because the claim being tested is "this was the regular
-- price", and "regular" means habitually charged, not centrally located. Sensitivity
-- across all three is reported and must be quoted with the headline.
SET threads = 4;

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

-- Daily grain. price_basis is carried because 2A.2 requires the claimed regular and the
-- observed level to be compared ONLY within a matching basis -- an each-price and a
-- per-weight price are not comparable without a size.
--
-- MEMORY NOTE: this table is kept to five narrow columns and floored at 2024-06-11.
-- Carrying the sale-day attributes here as well pushed the GROUP BY over a 5 GB budget,
-- because adding `basis` to the grain roughly doubles the group count. Those attributes
-- are only needed on sale days, so they are aggregated separately over a much smaller set.
SET threads = 2;

CREATE OR REPLACE TEMP TABLE daily AS
SELECT s.product_key                                                     AS k,
       s.observed_date                                                   AS d,
       s.price_basis                                                     AS basis,
       max(CASE WHEN s.old_offer_type <> 'blank' THEN 1 ELSE 0 END)      AS on_sale,
       -- determinism-ok: min() over (key, date, basis), which Phase 0 B6 proves is NOT
       -- unique -- one product appears many times a day with conflicting prices. An
       -- arbitrary pick would vary between runs; min() is total, and it takes the lowest
       -- price actually charged that day, which is the conservative reading for a test
       -- asking whether the pre-sale price was HIGH.
       min(s.unit_price)                                                 AS charged
FROM stg_price s
WHERE s.product_key IS NOT NULL              -- honesty rule 6
  AND s.parse_confidence <> 'ambiguous'      -- honesty rule 3
  AND s.offer_type <> 'unparsed'
  AND s.unit_price IS NOT NULL
  AND s.observed_date >= DATE '2024-06-11'
GROUP BY 1,2,3;

-- Sale-day attributes, over sale rows only.
CREATE OR REPLACE TEMP TABLE saleday AS
SELECT s.product_key AS k, s.observed_date AS d, s.price_basis AS basis,
       max(s.old_unit_price)                          AS claimed_regular,
       max(CASE WHEN s.min_qty > 1 THEN 1 ELSE 0 END) AS is_multibuy,
       max(s.min_qty)                                 AS max_min_qty
FROM stg_price s
WHERE s.product_key IS NOT NULL
  AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
  AND s.old_offer_type <> 'blank'
  AND s.observed_date >= DATE '2024-06-11'
GROUP BY 1,2,3;

-- determinism-ok: gaps-and-islands over `daily`, which is GROUP BY (key, date, basis) and
-- therefore one row per key per date per basis; ORDER BY (date) within (key, basis) is a
-- total order.
CREATE OR REPLACE TEMP TABLE runs AS
SELECT *, row_number() OVER (PARTITION BY k, basis ORDER BY d)
        - row_number() OVER (PARTITION BY k, basis, on_sale ORDER BY d) AS grp
FROM daily;

CREATE OR REPLACE TEMP TABLE ev AS
SELECT r.k, r.basis, min(r.d) AS sale_start, count(*) AS run_days,
       max(sd.claimed_regular) AS claimed_regular,
       max(sd.is_multibuy)     AS is_multibuy,
       max(sd.max_min_qty)     AS min_qty
FROM runs r
LEFT JOIN saleday sd ON sd.k = r.k AND sd.basis = r.basis AND sd.d = r.d
WHERE r.on_sale = 1 GROUP BY r.k, r.basis, r.grp;

-- The 14-day pre-window, computed on the SAME basis.
--
-- PERFORMANCE NOTE, because the obvious form does not finish. Written as window functions
-- over `daily` -- mode(), count(DISTINCT) and median() in a RANGE window across ~60M rows
-- -- this ran for over half an hour without completing. It is computed instead by
-- materialising each event's own 14-day lookback (~576k events x <=14 days) and
-- aggregating that with plain GROUP BYs. Same definition, same answer, and every
-- statistic is deterministic by construction rather than by annotation.
CREATE OR REPLACE TEMP TABLE prew AS
SELECT e.k, e.basis, e.sale_start, dd.d, dd.charged
FROM ev e
JOIN daily dd ON dd.k = e.k AND dd.basis = e.basis
             AND dd.d >= e.sale_start - INTERVAL 14 DAY
             AND dd.d <= e.sale_start - INTERVAL 1 DAY;

-- Modal pre-window price. A frequency tie is broken by the LOWEST tied price, making the
-- statistic total -- `mode()` alone would leave ties arbitrary.
-- determinism-ok: ORDER BY (frequency DESC, price ASC) is a total order within the
-- partition, because price is unique inside each (key, basis, sale_start, price) group by
-- construction of the GROUP BY beneath it.
CREATE OR REPLACE TEMP TABLE modal AS
SELECT k, basis, sale_start, charged AS pre_modal
FROM (SELECT k, basis, sale_start, charged,
             row_number() OVER (PARTITION BY k, basis, sale_start
                                ORDER BY count(*) DESC, charged ASC) AS rn
      FROM prew GROUP BY 1,2,3,4)
WHERE rn = 1;

CREATE OR REPLACE TEMP TABLE pre AS
SELECT p.k, p.basis, p.sale_start,
       count(*)                        AS pre_days,
       median(p.charged)               AS pre_median,
       min(p.charged)                  AS pre_min,
       max(p.charged)                  AS pre_max,
       count(DISTINCT p.charged)       AS pre_distinct_prices,
       -- determinism-ok: arg_max over `d`, and (k, basis, d) is unique in `daily` by its
       -- own GROUP BY, so there is exactly one candidate row and no tie is possible.
       arg_max(p.charged, p.d)         AS pre_last,
       any_value(m.pre_modal)          AS pre_modal
       -- determinism-ok: pre_modal is constant within (k, basis, sale_start) -- `modal`
       -- holds exactly one row per that key, so every row in the group carries the same
       -- value.
FROM prew p
JOIN modal m ON m.k = p.k AND m.basis = p.basis AND m.sale_start = p.sale_start
GROUP BY 1,2,3;

-- The evaluable cohort: 14 continuous pre-window days AND a usable claimed regular.
CREATE OR REPLACE TEMP TABLE cohort AS
SELECT e.k, e.basis, e.sale_start, e.run_days, e.claimed_regular, e.is_multibuy, e.min_qty,
       p.pre_median, p.pre_modal, p.pre_last, p.pre_min, p.pre_max, p.pre_distinct_prices,
       kk.vendor, kk.product_key_basis, kk.category, kk.brand_class,
       year(e.sale_start) AS yr
FROM ev e
JOIN pre p    ON p.k  = e.k AND p.basis = e.basis AND p.sale_start = e.sale_start
             AND p.pre_days = 14
JOIN (SELECT product_key AS k, vendor, product_key_basis,
             cat(product_name) AS category, brand_class FROM stg_product) kk
             ON kk.k = e.k
WHERE e.claimed_regular IS NOT NULL AND e.claimed_regular > 0;

-- ============================ COHORT ACCOUNTING ===================================

-- 1. The cohort, and every step that narrows it. Honesty rule 7.
SELECT 'a. sale events, all keys, all dates'                AS step, count(*) AS events FROM ev
UNION ALL SELECT 'b. + 14 continuous pre-window days',       count(*) FROM ev e
  JOIN pre p ON p.k=e.k AND p.basis=e.basis AND p.sale_start=e.sale_start AND p.pre_days=14
UNION ALL SELECT 'c. + usable claimed regular (old_price)',  count(*) FROM cohort
UNION ALL SELECT 'd. + vendor_sku tier only',                count(*) FROM cohort
  WHERE product_key_basis='vendor_sku'
UNION ALL SELECT 'e. HEADLINE: d, restricted to 2025-2026',  count(*) FROM cohort
  WHERE product_key_basis='vendor_sku' AND sale_start >= DATE '2025-01-01';

-- 2. The identity-tier split, per Section 1.5 -- reported, never silently dropped.
SELECT product_key_basis AS tier, count(*) AS events,
       count(*) FILTER (WHERE sale_start >= DATE '2025-01-01') AS events_2025_26
FROM cohort GROUP BY 1 ORDER BY 1;

-- ============================ 2A.1 / 2A.3  THE FINDING =============================

-- 3. HEADLINE, 2025-2026, vendor_sku tier: how often does the claimed regular exceed the
--    price actually charged in the 14 days before the sale? Reported per vendor with n.
--    A 2% tolerance absorbs rounding; the strict column reports any excess at all.
SELECT vendor,
       count(*)                                                                  AS n_events,
       count(*) FILTER (WHERE claimed_regular > pre_modal * 1.02)                AS claimed_above_modal,
       round(100.0*count(*) FILTER (WHERE claimed_regular > pre_modal * 1.02)/count(*), 2) AS pct_above_modal,
       round(100.0*count(*) FILTER (WHERE claimed_regular > pre_median * 1.02)/count(*), 2) AS pct_above_median,
       round(100.0*count(*) FILTER (WHERE claimed_regular > pre_last * 1.02)/count(*), 2)   AS pct_above_last,
       round(100.0*count(*) FILTER (WHERE claimed_regular > pre_max * 1.02)/count(*), 2)    AS pct_above_MAX_observed
FROM cohort
WHERE product_key_basis = 'vendor_sku' AND sale_start >= DATE '2025-01-01'
GROUP BY 1 ORDER BY pct_above_modal DESC, vendor;

-- 4. Magnitude distribution of the excess, where it exists. A 1% overstatement and a 40%
--    overstatement are different findings.
SELECT vendor,
       count(*)                                                        AS n_flagged,
       round(median(100.0*(claimed_regular - pre_modal)/pre_modal), 2) AS median_excess_pct,
       round(quantile_cont(100.0*(claimed_regular - pre_modal)/pre_modal, 0.25), 2) AS p25,
       round(quantile_cont(100.0*(claimed_regular - pre_modal)/pre_modal, 0.75), 2) AS p75,
       round(quantile_cont(100.0*(claimed_regular - pre_modal)/pre_modal, 0.95), 2) AS p95
FROM cohort
WHERE product_key_basis = 'vendor_sku' AND sale_start >= DATE '2025-01-01'
  AND claimed_regular > pre_modal * 1.02
GROUP BY 1 ORDER BY median_excess_pct DESC, vendor;

-- 5. SENSITIVITY: the same headline across all three statistics, pooled, so the choice of
--    statistic is visible rather than buried.
SELECT 'modal'  AS statistic, count(*) AS n,
       round(100.0*count(*) FILTER (WHERE claimed_regular > pre_modal  * 1.02)/count(*), 2) AS pct_claimed_above
FROM cohort WHERE product_key_basis='vendor_sku' AND sale_start >= DATE '2025-01-01'
UNION ALL SELECT 'median', count(*),
       round(100.0*count(*) FILTER (WHERE claimed_regular > pre_median * 1.02)/count(*), 2)
FROM cohort WHERE product_key_basis='vendor_sku' AND sale_start >= DATE '2025-01-01'
UNION ALL SELECT 'last observed', count(*),
       round(100.0*count(*) FILTER (WHERE claimed_regular > pre_last   * 1.02)/count(*), 2)
FROM cohort WHERE product_key_basis='vendor_sku' AND sale_start >= DATE '2025-01-01'
UNION ALL SELECT 'max observed (strictest)', count(*),
       round(100.0*count(*) FILTER (WHERE claimed_regular > pre_max    * 1.02)/count(*), 2)
FROM cohort WHERE product_key_basis='vendor_sku' AND sale_start >= DATE '2025-01-01';

-- 6. 2024 as a SEPARATELY CAVEATED extension, never pooled into the headline.
SELECT yr, vendor, count(*) AS n_events,
       round(100.0*count(*) FILTER (WHERE claimed_regular > pre_modal * 1.02)/count(*), 2) AS pct_above_modal
FROM cohort WHERE product_key_basis='vendor_sku'
GROUP BY 1,2 ORDER BY vendor, yr;

-- ============================ 2A.4  INNOCENT EXPLANATIONS ==========================
-- Each of these would produce a "claimed > observed" flag without any dishonesty, and
-- each is quantified rather than waved at.

-- 7. (i) A GENUINE PRICE RISE followed by a sale. If the price rose during the pre-window
--        and the claim matches the LATER level, the claim is accurate and the flag is an
--        artifact of comparing against a modal that includes the older, lower price.
--    (ii) A VOLATILE pre-window: more than 2 distinct prices in 14 days means there was
--        no single "regular" price to claim.
--    (iii) The claim matching a price ACTUALLY OBSERVED at some point in the window --
--        the strongest innocent explanation, because the retailer did charge it.
SELECT vendor,
       count(*)                                                                 AS n_flagged,
       count(*) FILTER (WHERE claimed_regular <= pre_max * 1.02)                AS claim_was_actually_charged,
       round(100.0*count(*) FILTER (WHERE claimed_regular <= pre_max * 1.02)/count(*), 2) AS pct_explained_by_observed,
       count(*) FILTER (WHERE pre_distinct_prices > 2)                          AS volatile_pre_window,
       round(100.0*count(*) FILTER (WHERE pre_distinct_prices > 2)/count(*), 2)  AS pct_volatile,
       count(*) FILTER (WHERE pre_last > pre_modal * 1.02)                      AS price_rose_in_window,
       round(100.0*count(*) FILTER (WHERE pre_last > pre_modal * 1.02)/count(*), 2) AS pct_rising
FROM cohort
WHERE product_key_basis='vendor_sku' AND sale_start >= DATE '2025-01-01'
  AND claimed_regular > pre_modal * 1.02
GROUP BY 1 ORDER BY n_flagged DESC, vendor;

-- 8. THE RESIDUAL: events where the claimed regular exceeds EVERY price observed in the
--    14-day pre-window. No innocent explanation above covers these -- the retailer never
--    charged the price it struck out.
SELECT vendor,
       count(*)                                                       AS n_events,
       count(*) FILTER (WHERE claimed_regular > pre_max * 1.02)       AS claim_never_charged,
       round(100.0*count(*) FILTER (WHERE claimed_regular > pre_max * 1.02)/count(*), 2) AS pct_never_charged,
       round(median(100.0*(claimed_regular - pre_max)/pre_max)
             FILTER (WHERE claimed_regular > pre_max * 1.02), 2)      AS median_excess_over_max_pct
FROM cohort
WHERE product_key_basis='vendor_sku' AND sale_start >= DATE '2025-01-01'
GROUP BY 1 ORDER BY pct_never_charged DESC, vendor;

-- 9. Multibuy events compared on derived unit_price with min_qty stated (2A.2).
SELECT is_multibuy, count(*) AS n_events, round(median(min_qty),0) AS median_min_qty,
       round(100.0*count(*) FILTER (WHERE claimed_regular > pre_modal * 1.02)/count(*), 2) AS pct_above_modal
FROM cohort WHERE product_key_basis='vendor_sku' AND sale_start >= DATE '2025-01-01'
GROUP BY 1 ORDER BY 1;

-- 10. Basis mix of the cohort, so 2A.2's "compare only within matching basis" is auditable.
SELECT basis, count(*) AS n_events,
       round(100.0*count(*) FILTER (WHERE claimed_regular > pre_modal * 1.02)/count(*), 2) AS pct_above_modal
FROM cohort WHERE product_key_basis='vendor_sku' AND sale_start >= DATE '2025-01-01'
GROUP BY 1 ORDER BY n_events DESC, basis;
