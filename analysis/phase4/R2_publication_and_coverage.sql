-- R2: the other half of staleness. R1 measures how fast prices move; R2 measures how
-- reliably we are told about it.
--
-- WHY THIS IS SEPARATE. A refresh interval only bounds staleness if the data behind it is
-- current. Two things break that independently of how often we refresh:
--   (a) publication lag  -- upstream publishes the file some time after the scrape;
--   (b) extract failure  -- a vendor is simply absent from a day's scrape (CLAUDE.md,
--       known contamination). A vendor missing for 4 days is 4 days stale no matter how
--       often the job runs.
-- Honesty rule 1 applies directly: a missing day is not an unchanged price, so a gap in
-- (b) is staleness we must disclose, not smooth.
--
-- Publication lag itself (1.3) is NOT measurable from the database -- it lives in the
-- snapshot manifests, of which there are two. It is reported as n=2 in the findings, not
-- as a distribution, and this file deliberately does not fabricate one.
SET threads = 2;

CREATE OR REPLACE TEMP TABLE vd AS
SELECT sp.vendor, s.observed_date AS d, count(*) AS rows
FROM stg_price s JOIN stg_product sp USING (product_key)
WHERE s.observed_date >= DATE '2024-06-11'
GROUP BY 1,2;

-- 1. Per-vendor freshness at the edge of the data: the last date each vendor was seen,
--    against the last date ANY vendor was seen. This is the staleness a user would face
--    at the moment of a refresh, before the refresh interval is added.
SELECT vendor,
       max(d)                                                   AS last_seen,
       (SELECT max(d) FROM vd)                                  AS dataset_last_date,
       date_diff('day', max(d), (SELECT max(d) FROM vd))        AS days_behind_edge
FROM vd GROUP BY 1 ORDER BY days_behind_edge DESC, vendor;

-- 2. Extract-failure profile per vendor, 2025-01-01 onward: how many calendar days in the
--    window have no rows at all for that vendor, and the longest consecutive absence.
--    The longest absence is the term that dominates worst-case staleness.
WITH cal AS (
  SELECT unnest(generate_series(DATE '2025-01-01', (SELECT max(d) FROM vd), INTERVAL 1 DAY))::DATE AS d),
vend AS (SELECT DISTINCT vendor FROM vd),
grid AS (SELECT v.vendor, c.d FROM vend v CROSS JOIN cal c),
present AS (
  SELECT g.vendor, g.d, (x.d IS NOT NULL) AS seen
  FROM grid g LEFT JOIN vd x ON x.vendor = g.vendor AND x.d = g.d),
runs AS (
  -- determinism-ok: the running sum is over (vendor) ordered by d, and `present` has
  -- exactly one row per (vendor, d) by construction, so the ordering is total.
  SELECT vendor, d, seen,
         sum(CASE WHEN seen THEN 1 ELSE 0 END)
             OVER (PARTITION BY vendor ORDER BY d
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS grp
  FROM present),
gaps AS (
  SELECT vendor, grp, count(*) AS missing_days
  FROM runs WHERE NOT seen GROUP BY 1,2)
SELECT p.vendor,
       count(*)                                              AS days_in_window,
       count(*) FILTER (WHERE p.seen)                        AS days_present,
       count(*) FILTER (WHERE NOT p.seen)                    AS days_missing,
       round(100.0*count(*) FILTER (WHERE p.seen)/count(*), 2) AS pct_days_present,
       coalesce((SELECT max(missing_days) FROM gaps g WHERE g.vendor = p.vendor), 0) AS longest_absence_days,
       coalesce((SELECT count(*) FROM gaps g WHERE g.vendor = p.vendor), 0)          AS n_absences
FROM present p GROUP BY 1 ORDER BY longest_absence_days DESC, p.vendor;

-- 3. The same, restricted to the tool's actual scope: the three comparable chains and the
--    reliable-barcode basket. A gap that affects 8 chains but not these 3 does not bind
--    the tool's disclosure.
WITH basket AS (
  SELECT DISTINCT m.product_key, m.vendor
  FROM int_upc_match m
  WHERE m.is_reliable_only AND m.vendor IN ('Metro','SaveOnFoods','Walmart')),
bd AS (
  SELECT b.vendor, s.observed_date AS d, count(DISTINCT s.product_key) AS n_products
  FROM stg_price s JOIN basket b ON b.product_key = s.product_key
  WHERE s.observed_date >= DATE '2025-01-01'
    AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
    AND s.unit_price IS NOT NULL AND s.unit_price > 0
  GROUP BY 1,2)
SELECT vendor,
       count(*)                                       AS days_with_basket_rows,
       round(median(n_products), 0)                   AS median_basket_products_per_day,
       round(quantile_cont(n_products, 0.05), 0)      AS p05_products_per_day,
       min(n_products)                                AS min_products_per_day,
       max(d)                                         AS last_day
FROM bd GROUP BY 1 ORDER BY vendor;

-- 4. Dataset-level publication continuity: consecutive scrape dates and the gaps between
--    them, across the whole history. One row per gap longer than a day.
WITH ds AS (SELECT DISTINCT d FROM vd),
sq AS (
  -- determinism-ok: lag() over a DISTINCT date column ordered by itself -- total by
  -- construction, one row per date.
  SELECT d, lag(d) OVER (ORDER BY d) AS prev_d FROM ds)
SELECT prev_d AS gap_starts_after, d AS resumed_on, date_diff('day', prev_d, d) AS gap_days
FROM sq WHERE date_diff('day', prev_d, d) > 1 ORDER BY gap_days DESC, prev_d;
