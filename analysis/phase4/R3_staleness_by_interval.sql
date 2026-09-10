-- R3: what a refresh interval actually costs, and what refresh DAY actually costs.
--
-- WHY THIS EXISTS. R1 result 5 asked "what share of prices change within k days" and got
-- the wrong answer. It divided by consecutive-observation pairs with gap <= k, and because
-- the dataset is near-daily that denominator is ~97% one-day pairs -- so it re-measured the
-- one-day rate k times over. Metro reads 3.40% at k=1 and 4.19% at k=14, which is not a
-- 14-day staleness rate, it is the daily rate with rounding noise. R1 result 5 is withdrawn
-- and this file replaces it.
--
-- THE CORRECT MEASURE is forward-looking: take an observation on date d, find the same
-- product on date d+k, and ask whether the price differs. That is exactly the question the
-- interface has to answer -- "this price was captured k days ago; how likely is it wrong?"
--
-- A MISSING DAY IS NOT AN UNCHANGED PRICE (honesty rule 1). A pair is only counted when the
-- product is observed on BOTH d and d+k. Products not observed at d+k are excluded and
-- counted, not treated as unchanged.
--
-- SCOPE. The three chains the tool compares, on the reliable-barcode basket, 2025 onward.
-- The recommendation is scoped to what the tool ships; R1 carries the eight-chain context.
SET threads = 2;

CREATE OR REPLACE TEMP TABLE b AS
SELECT DISTINCT m.product_key AS k, m.vendor, m.gtin14
FROM int_upc_match m
WHERE m.is_reliable_only AND m.vendor IN ('Metro','SaveOnFoods','Walmart');

CREATE OR REPLACE TEMP TABLE bd AS
SELECT b.vendor, b.gtin14, s.observed_date AS d, s.price_basis AS basis,
       -- determinism-ok: min() over (gtin, vendor, date, basis) -- Phase 0 B6 proves this
       -- is not unique; min() is a total order and is the Phase 2/3 convention.
       min(s.unit_price) AS px
FROM stg_price s JOIN b ON b.k = s.product_key
WHERE s.observed_date >= DATE '2025-01-01'
  AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
  AND s.unit_price IS NOT NULL AND s.unit_price > 0
GROUP BY 1,2,3,4;

-- 1. Denominator disclosure for this measurement (honesty rule 7).
SELECT count(*) AS basket_product_days,
       count(DISTINCT gtin14) AS barcodes,
       count(DISTINCT d) AS dates,
       min(d) AS first_date, max(d) AS last_date
FROM bd;

-- 2. THE SCHEDULE NUMBER. Share of prices that are wrong k days after they were captured.
--    One row per chain per k. `pairs` is the denominator; `unobserved_at_k` is how many
--    observations had no counterpart at d+k and were therefore dropped rather than assumed
--    unchanged.
WITH kk AS (SELECT unnest([1,2,3,7,14]) AS k),
pairs AS (
  SELECT kk.k, a.vendor, a.gtin14, a.d, a.px,
         f.px AS px_k
  FROM bd a CROSS JOIN kk
  LEFT JOIN bd f ON f.gtin14 = a.gtin14 AND f.vendor = a.vendor AND f.basis = a.basis
                AND f.d = a.d + kk.k)
SELECT vendor, k AS days_since_capture,
       count(*) FILTER (WHERE px_k IS NOT NULL)                              AS pairs,
       count(*) FILTER (WHERE px_k IS NULL)                                  AS unobserved_at_k,
       round(100.0*count(*) FILTER (WHERE px_k IS NOT NULL AND abs(px_k - px) > 0.005)
             / nullif(count(*) FILTER (WHERE px_k IS NOT NULL), 0), 2)       AS pct_wrong
FROM pairs GROUP BY 1,2 ORDER BY vendor, days_since_capture;

-- NOTE, left visible on purpose: this statement first shipped with `GROUP BY 1,2,3`,
-- where position 3 was an aggregate. It crashed on BOTH runs with the same Binder
-- Error and produced byte-identical output -- `diff` would have called that agreement.
-- verify_twice.py refused it because it asserts successful completion before it
-- compares bytes. Second occurrence of that class; see docs/method-note.md.
-- 3. THE REFRESH-DAY NUMBER. The same 7-day staleness, split by the weekday the price was
--    captured on. If changes cluster on Thursday, capturing on a Friday should leave a far
--    lower 7-day error than capturing on a Wednesday -- and the gap between the best and
--    worst weekday is the entire value of aligning the schedule to the flyer cycle.
WITH pairs AS (
  SELECT a.vendor, dayname(a.d) AS captured_on, dayofweek(a.d) AS dow, a.px, f.px AS px_7
  FROM bd a
  LEFT JOIN bd f ON f.gtin14 = a.gtin14 AND f.vendor = a.vendor AND f.basis = a.basis
                AND f.d = a.d + 7)
SELECT vendor, captured_on,
       count(*) FILTER (WHERE px_7 IS NOT NULL)                              AS pairs,
       round(100.0*count(*) FILTER (WHERE px_7 IS NOT NULL AND abs(px_7 - px) > 0.005)
             / nullif(count(*) FILTER (WHERE px_7 IS NOT NULL), 0), 2)       AS pct_wrong_after_7d
FROM pairs GROUP BY vendor, captured_on, dow ORDER BY vendor, dow;

-- 4. And the same for a 1-day interval, so daily-vs-weekly is a comparison of like with
--    like rather than an assertion.
WITH pairs AS (
  SELECT a.vendor, a.px, f.px AS px_1
  FROM bd a
  LEFT JOIN bd f ON f.gtin14 = a.gtin14 AND f.vendor = a.vendor AND f.basis = a.basis
                AND f.d = a.d + 1)
SELECT vendor,
       count(*) FILTER (WHERE px_1 IS NOT NULL)                              AS pairs,
       round(100.0*count(*) FILTER (WHERE px_1 IS NOT NULL AND abs(px_1 - px) > 0.005)
             / nullif(count(*) FILTER (WHERE px_1 IS NOT NULL), 0), 2)       AS pct_wrong_after_1d
FROM pairs GROUP BY 1 ORDER BY vendor;

-- ============================ 5. THE ABSENCE PROFILE ==============================
-- R2 found Walmart absent on 85 of 598 days with a single 49-day run, against 19-22 days
-- for every other chain -- and those 19-22 are the ONE dataset-wide gap (2025-08-10 to
-- 2025-08-30), not vendor behaviour. That makes vendor absence, not refresh interval, the
-- larger term in worst-case staleness, so it needs dating rather than just counting.
WITH cal AS (
  SELECT unnest(generate_series(DATE '2025-01-01', DATE '2026-08-21', INTERVAL 1 DAY))::DATE AS d),
vd AS (
  SELECT sp.vendor, s.observed_date AS d
  FROM stg_price s JOIN stg_product sp USING (product_key)
  WHERE sp.vendor IN ('Metro','SaveOnFoods','Walmart')
    AND s.observed_date >= DATE '2025-01-01'
  GROUP BY 1,2),
vend AS (SELECT DISTINCT vendor FROM vd),
present AS (
  SELECT v.vendor, c.d, (x.d IS NOT NULL) AS seen
  FROM vend v CROSS JOIN cal c
  LEFT JOIN vd x ON x.vendor = v.vendor AND x.d = c.d),
runs AS (
  -- determinism-ok: running sum over (vendor) ordered by d; `present` is one row per
  -- (vendor, d) by construction, so the ordering is total.
  SELECT vendor, d, seen,
         sum(CASE WHEN seen THEN 1 ELSE 0 END)
             OVER (PARTITION BY vendor ORDER BY d
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS grp
  FROM present)
SELECT vendor, min(d) AS absent_from, max(d) AS absent_to, count(*) AS days
FROM runs WHERE NOT seen GROUP BY vendor, grp
ORDER BY days DESC, vendor, absent_from;

-- 6. PARTIAL EXTRACTS. A chain can be present and nearly empty, which the absence count
--    above cannot see. Share of days on which a chain carried under half, and under a
--    tenth, of its own median basket coverage.
WITH bdd AS (
  SELECT b.vendor, s.observed_date AS d, count(DISTINCT b.gtin14) AS n
  FROM stg_price s JOIN b ON b.k = s.product_key
  WHERE s.observed_date >= DATE '2025-01-01'
    AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
    AND s.unit_price IS NOT NULL AND s.unit_price > 0
  GROUP BY 1,2),
med AS (SELECT vendor, median(n) AS m FROM bdd GROUP BY 1)
SELECT bdd.vendor,
       count(*)                                                          AS days_present,
       round(med.m, 0)                                                   AS median_coverage,
       count(*) FILTER (WHERE bdd.n < 0.5*med.m)                         AS days_under_half,
       count(*) FILTER (WHERE bdd.n < 0.1*med.m)                         AS days_under_tenth,
       round(100.0*count(*) FILTER (WHERE bdd.n < 0.5*med.m)/count(*), 2) AS pct_days_under_half
FROM bdd JOIN med USING (vendor)
GROUP BY bdd.vendor, med.m ORDER BY pct_days_under_half DESC, bdd.vendor;
