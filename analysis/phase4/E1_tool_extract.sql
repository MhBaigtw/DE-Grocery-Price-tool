-- E1: the static extract behind the price-lookup tool.
--
-- The tool is a static page with no backend, so every value it can display is computed here
-- and written as JSON. The browser never sees a price row and never joins anything.
--
-- WHAT THIS FILE ENFORCES, AND WHY IT IS THE FILE THAT ENFORCES IT.
-- An interface can only be as honest as the data it is handed. Four rules below are
-- therefore made structural rather than left to the page to remember:
--
--   1. NO POOLED STALENESS, ANYWHERE. Pooled across the three chains the 7-day staleness is
--      27.52%, which understates Save-On-Foods -- the chain a user is most likely to be
--      wrong about -- by over 9 pp (Phase 4 §1.3e). No pooled figure is computed in this
--      file, so none can be displayed. Staleness is per chain or it does not exist.
--
--   2. ABSENCE IS A PROPERTY OF THE COMPARISON, NOT OF A ROW. "Cheapest" and "cheapest of
--      the two chains that had a recent price" are different claims. Every product carries
--      a `comparison` object naming exactly which chains were compared and which were not,
--      with the reason and the date, plus the sentence the interface is licensed to print.
--      Walmart was absent 85 of 598 days since 2025-01-01 (§1.3b), so this is the most
--      likely wrong answer the tool can give, and it is prevented here rather than there.
--
--   3. PER-CHAIN OBSERVED DATE AND PER-CHAIN STALENESS ARE FIRST-CLASS FIELDS. Not derived
--      client-side. The page cannot compute a comparison this file has not licensed,
--      because it is not given the parts.
--
--   4. EVERY PRICE CARRIES ITS BASIS AND IS ONLY EVER COMPARED WITHIN IT (brief 2.4). A
--      per-weight price and an each-price are different quantities. Offers on a minority
--      basis are exported and shown, but marked not comparable, with the reason.
--
-- The staleness curve is RECOMPUTED here rather than copied from the findings, so meta.json
-- cannot drift away from the build that produced it.
--
-- EXCLUSIONS, per the standing rules: ambiguous prices (honesty rule 3), rows with no
-- product record (honesty rule 6), unparseable prices. Counted into meta.json (brief 2.1).
SET threads = 2;

-- ============================ THE BASKET =========================================
-- Same construction as analysis/phase3/D1_dashboard_extract.sql, deliberately rebuilt here
-- rather than imported, so this file runs standalone and its basket is auditable in place.
-- It must come out at 3,190; statement 1 asserts that.
CREATE OR REPLACE TEMP TABLE obs AS
SELECT m.gtin14, m.vendor, s.observed_date AS d, s.price_basis AS basis,
       -- determinism-ok: min() over (gtin, vendor, date, basis) -- Phase 0 B6 proves this
       -- grain is not unique; min() is a total order and is the Phase 2/3 convention.
       min(s.unit_price) AS px
FROM stg_price s
JOIN int_upc_match m ON m.product_key = s.product_key
WHERE m.is_reliable_only
  AND m.vendor IN ('Metro','SaveOnFoods','Walmart')
  AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
  AND s.unit_price IS NOT NULL AND s.unit_price > 0
  AND s.observed_date >= DATE '2024-06-11'
GROUP BY 1,2,3,4;

CREATE OR REPLACE TEMP TABLE g90 AS
SELECT gtin14 FROM (SELECT gtin14, count(DISTINCT d) AS co_days
                    FROM (SELECT gtin14, d FROM obs GROUP BY 1,2
                          HAVING count(DISTINCT vendor) >= 2)
                    GROUP BY 1)
WHERE co_days >= 90;

CREATE OR REPLACE TEMP TABLE params AS
SELECT max(d) AS extract_date FROM obs;

-- ============================ THE STALENESS CURVE ================================
-- Per chain, share of prices that differ k days after capture, measured forward on the
-- tool's own basket. NO POOLED ROW IS PRODUCED (constraint 1).
CREATE OR REPLACE TEMP TABLE stale AS
WITH kk AS (SELECT unnest([1,2,3,7,14]) AS k),
o AS (SELECT * FROM obs WHERE gtin14 IN (SELECT gtin14 FROM g90) AND d >= DATE '2025-01-01'),
pairs AS (
  SELECT kk.k, a.vendor, a.px, f.px AS px_k
  FROM o a CROSS JOIN kk
  LEFT JOIN o f ON f.gtin14 = a.gtin14 AND f.vendor = a.vendor AND f.basis = a.basis
               AND f.d = a.d + kk.k)
SELECT vendor, k,
       count(*) FILTER (WHERE px_k IS NOT NULL)                          AS pairs,
       round(100.0*count(*) FILTER (WHERE px_k IS NOT NULL AND abs(px_k - px) > 0.005)
             / nullif(count(*) FILTER (WHERE px_k IS NOT NULL), 0), 2)   AS pct_wrong
FROM pairs GROUP BY vendor, k;

-- ============================ PRICES, RECENT WINDOW ==============================
-- 200 days back: comfortably longer than the longest vendor absence observed (49 days,
-- §1.3b), so a chain that has been away still has a findable last observation.
CREATE OR REPLACE TEMP TABLE recent AS
SELECT m.gtin14, m.vendor, s.observed_date AS d, s.price_basis AS basis,
       -- determinism-ok: aggregates over (gtin, vendor, date, basis), which Phase 0 B6
       -- proves is not unique. min() on price matches the basket convention above; min() on
       -- min_qty and max() on the sale flag are likewise total orders over the same group.
       min(s.unit_price)                                            AS px,
       min(s.min_qty)                                               AS min_qty,
       max(CASE WHEN s.old_offer_type <> 'blank' THEN 1 ELSE 0 END) AS on_sale
FROM stg_price s
JOIN int_upc_match m ON m.product_key = s.product_key
WHERE m.is_reliable_only
  AND m.vendor IN ('Metro','SaveOnFoods','Walmart')
  AND m.gtin14 IN (SELECT gtin14 FROM g90)
  AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
  AND s.unit_price IS NOT NULL AND s.unit_price > 0
  AND s.observed_date >= (SELECT extract_date FROM params) - 200
GROUP BY 1,2,3,4;

-- The latest observation per chain per basis, and then the chain's headline basis: the one
-- carrying its most recent observation, ties broken by basis name so the choice is total.
CREATE OR REPLACE TEMP TABLE latest_by_basis AS
SELECT gtin14, vendor, basis, max(d) AS last_d
FROM recent GROUP BY 1,2,3;

CREATE OR REPLACE TEMP TABLE chain_basis AS
SELECT gtin14, vendor,
       -- determinism-ok: arg_max over (last_d, basis) within (gtin, vendor); basis is a
       -- GROUP BY key of latest_by_basis so it is unique in the group, and appending it to
       -- the ordering key makes the tie-break total.
       arg_max(basis, (last_d, basis)) AS basis,
       max(last_d)                     AS last_d
FROM latest_by_basis GROUP BY 1,2;

CREATE OR REPLACE TEMP TABLE offer AS
SELECT r.gtin14, r.vendor, r.basis, r.d AS observed_date, r.px, r.min_qty, r.on_sale,
       date_diff('day', r.d, (SELECT extract_date FROM params)) AS days_behind
FROM recent r
JOIN chain_basis cb ON cb.gtin14 = r.gtin14 AND cb.vendor = r.vendor
                   AND cb.basis = r.basis AND cb.last_d = r.d;

-- ============================ SALE CONTEXT, PER PRODUCT ==========================
-- Brief 2.2: enough history to show whether today's price is unusual, as a per-product
-- signal. Phrased as fact, never as accusation -- the findings forbid "retailer X inflates
-- before sales" (Phase 2, what must never be said), and this is a count of days, not a
-- verdict. The window is the 14 days BEFORE the latest observation.
CREATE OR REPLACE TEMP TABLE sale_ctx AS
SELECT o.gtin14, o.vendor,
       count(*) FILTER (WHERE r.d < o.observed_date)                       AS prior_days_observed,
       min(r.px) FILTER (WHERE r.d < o.observed_date)                      AS prior_14d_low,
       max(r.px) FILTER (WHERE r.d < o.observed_date)                      AS prior_14d_high,
       count(*) FILTER (WHERE r.d < o.observed_date
                          AND abs(r.px - o.px) <= 0.005)                   AS prior_days_at_this_price
FROM offer o
JOIN recent r ON r.gtin14 = o.gtin14 AND r.vendor = o.vendor AND r.basis = o.basis
             AND r.d > o.observed_date - 15 AND r.d <= o.observed_date
GROUP BY 1,2;

-- ============================ RECENT HISTORY, AS SPELLS ==========================
-- 42 days -- six flyer cycles, from the 8-10 day median hold in §1.2. Exported as runs of
-- constant price rather than one point per day: same information, a fraction of the bytes,
-- and gaps stay visible because a spell covers only the days actually observed
-- (honesty rule 1).
CREATE OR REPLACE TEMP TABLE hist_src AS
SELECT r.*,
       -- determinism-ok: lag() over (gtin, vendor, basis) ordered by d -- `recent` is
       -- grouped to one row per (gtin, vendor, d, basis), so the ordering is total.
       lag(r.px) OVER w                     AS prev_px,
       date_diff('day', lag(r.d) OVER w, r.d) AS gap
FROM recent r
WHERE r.d > (SELECT extract_date FROM params) - 42
WINDOW w AS (PARTITION BY r.gtin14, r.vendor, r.basis ORDER BY r.d);

CREATE OR REPLACE TEMP TABLE spells AS
SELECT gtin14, vendor, basis, spell,
       min(d) AS from_date, max(d) AS to_date, count(*) AS observed_days,
       -- determinism-ok: price is constant within a spell by construction, so min() is the
       -- value itself; max() on the flag is a total order over the same group.
       min(px) AS px, max(on_sale) AS on_sale
FROM (
  SELECT h.*,
         -- determinism-ok: running sum over (gtin, vendor, basis) ordered by d; one row per
         -- (gtin, vendor, basis, d) by construction, so the ordering is total.
         sum(CASE WHEN h.prev_px IS NULL
                    OR abs(h.px - h.prev_px) > 0.005
                    OR h.gap > 3 THEN 1 ELSE 0 END)
             OVER (PARTITION BY h.gtin14, h.vendor, h.basis ORDER BY h.d
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS spell
  FROM hist_src h)
GROUP BY 1,2,3,4;

-- ============================ DISPLAY NAMES ======================================
-- One name per barcode. The same GTIN carries different names at different chains, so the
-- choice must be deterministic: the (name, brand, size) tuple appearing on the most price
-- rows, ties broken lexicographically.
CREATE OR REPLACE TEMP TABLE name_pick AS
SELECT gtin14, product_name, brand_raw, units_raw
FROM (
  SELECT m.gtin14,
         coalesce(nullif(trim(sp.product_name), ''), '(no name)') AS product_name,
         coalesce(nullif(trim(sp.brand_raw), ''), '')             AS brand_raw,
         -- Size comes from the PARSED quantity, not `units_raw`. The raw string is often
         -- the product name with the size glued to the end -- "marvel spidey and his
         -- amazing friends170g" -- and printing that would be worse than printing nothing.
         -- Where the unit parse failed there is no size, which is the honest answer.
         CASE WHEN sp.unit_parse_confidence IN ('exact','derived') AND sp.unit_qty IS NOT NULL
              THEN CASE WHEN coalesce(sp.pack_count, 1) > 1
                        THEN CAST(CAST(sp.pack_count AS INTEGER) AS VARCHAR) || ' x '
                        ELSE '' END
                   || rtrim(rtrim(format('{:.2f}', sp.unit_qty), '0'), '.')
                   || ' ' || coalesce(sp.unit_uom, '')
              ELSE '' END                                          AS units_raw,
         count(*)                                                 AS n,
         -- determinism-ok: row_number() over the full tuple -- (n, name, brand, units) is
         -- unique within a gtin because the tuple is the GROUP BY key, so no tie survives.
         row_number() OVER (PARTITION BY m.gtin14
                            ORDER BY count(*) DESC, coalesce(nullif(trim(sp.product_name),''),'(no name)'),
                                     coalesce(nullif(trim(sp.brand_raw),''),''),
                                     CASE WHEN sp.unit_parse_confidence IN ('exact','derived') AND sp.unit_qty IS NOT NULL
                                          THEN CASE WHEN coalesce(sp.pack_count, 1) > 1
                                                    THEN CAST(CAST(sp.pack_count AS INTEGER) AS VARCHAR) || ' x '
                                                    ELSE '' END
                                               || rtrim(rtrim(format('{:.2f}', sp.unit_qty), '0'), '.')
                                               || ' ' || coalesce(sp.unit_uom, '')
                                          ELSE '' END) AS rn
  FROM stg_price s
  JOIN int_upc_match m ON m.product_key = s.product_key
  JOIN stg_product sp  ON sp.product_key = s.product_key
  WHERE m.is_reliable_only AND m.vendor IN ('Metro','SaveOnFoods','Walmart')
    AND m.gtin14 IN (SELECT gtin14 FROM g90)
    AND s.observed_date >= DATE '2025-01-01'
  GROUP BY 1,2,3,4)
WHERE rn = 1;

-- ============================ THE COMPARISON VERDICT =============================
-- Constraint 2. A chain participates only if its latest observation is within 7 days of the
-- extract date AND it is on the product's majority basis. Everything else is exported with
-- a reason, never dropped (brief 3.2).
CREATE OR REPLACE TEMP TABLE majority_basis AS
SELECT gtin14,
       -- determinism-ok: arg_max over (n, basis); basis is the GROUP BY key so it is unique
       -- within the gtin and the composite ordering key is total.
       arg_max(basis, (n, basis)) AS basis
FROM (SELECT gtin14, basis, count(*) AS n FROM offer GROUP BY 1,2)
GROUP BY 1;

CREATE OR REPLACE TEMP TABLE offer_flagged AS
SELECT o.*, mb.basis AS product_basis,
       (o.days_behind <= 7)                                AS is_recent,
       (o.days_behind <= 7 AND o.basis = mb.basis)         AS comparable,
       CASE WHEN o.days_behind > 7 AND o.basis <> mb.basis THEN 'no recent price, and a different price basis'
            WHEN o.days_behind > 7                        THEN 'no recent price'
            WHEN o.basis <> mb.basis                      THEN 'priced on a different basis'
            ELSE NULL END                                  AS not_comparable_reason,
       -- Measured staleness exists ONLY for ages up to the longest horizon measured
       -- (14 days). Beyond that the figure is NULL and the flag says so, rather than the
       -- 14-day number standing in for an age of 200 days. 1,137 of 6,093 offers are in
       -- that state, so this is not a hypothetical (honesty rule 9).
       CASE WHEN o.days_behind <= 14 THEN st.pct_wrong END  AS staleness_pct,
       CASE WHEN o.days_behind <= 14 THEN st.k END          AS staleness_horizon_days,
       (o.days_behind > 14)                                 AS staleness_exceeds_measured
FROM offer o
JOIN majority_basis mb ON mb.gtin14 = o.gtin14
LEFT JOIN stale st ON st.vendor = o.vendor
     AND st.k = CASE WHEN o.days_behind <= 1 THEN 1
                     WHEN o.days_behind = 2  THEN 2
                     WHEN o.days_behind = 3  THEN 3
                     WHEN o.days_behind <= 7 THEN 7
                     ELSE 14 END;

-- ============================ ASSERTIONS AND ACCOUNTING ==========================

-- 1. The basket is the one the dashboard and the findings use. If this is not 3,190 the
--    extract has drifted from the published figures and must not ship.
SELECT (SELECT count(*) FROM g90)                       AS tool_basket_barcodes,
       (SELECT extract_date FROM params)                AS extract_date,
       (SELECT count(*) FROM offer_flagged)             AS offers,
       (SELECT count(*) FROM spells)                    AS history_spells,
       (SELECT count(*) FROM name_pick)                 AS named_products,
       (SELECT count(DISTINCT gtin14) FROM offer_flagged) AS products_shipped,
       (SELECT count(*) FROM g90)
         - (SELECT count(DISTINCT gtin14) FROM offer_flagged) AS omitted_no_recent_observation,
       ((SELECT count(*) FROM g90) = 3190)              AS basket_matches_published;

-- 2. Exclusion accounting for the extract (brief 2.1, honesty rule 7). Counted over the
--    same chains and the same window the extract reads.
SELECT count(*)                                                        AS rows_in_scope,
       count(*) FILTER (WHERE s.product_key IS NULL)                   AS excl_no_product,
       count(*) FILTER (WHERE s.parse_confidence = 'ambiguous')         AS excl_ambiguous,
       count(*) FILTER (WHERE s.offer_type = 'unparsed')                AS excl_unparsed,
       count(*) FILTER (WHERE s.unit_price IS NULL OR s.unit_price <= 0) AS excl_nonpositive
FROM stg_price s
LEFT JOIN int_upc_match m ON m.product_key = s.product_key
WHERE s.observed_date >= (SELECT extract_date FROM params) - 200
  AND m.is_reliable_only AND m.vendor IN ('Metro','SaveOnFoods','Walmart');

-- 3. How the comparison verdict actually lands. This is the number constraint 2 exists for:
--    how often the tool can say "cheapest" without qualification, and how often it cannot.
SELECT n_comparable,
       count(*)                                          AS products,
       round(100.0*count(*) / sum(count(*)) OVER (), 2)  AS pct
FROM (SELECT gtin14, count(*) FILTER (WHERE comparable) AS n_comparable
      FROM offer_flagged GROUP BY 1)
GROUP BY 1 ORDER BY n_comparable;

-- 4. Which chains drop out of comparisons, and why. Per chain, never pooled.
SELECT vendor,
       count(*)                                                   AS offers,
       count(*) FILTER (WHERE comparable)                         AS comparable,
       count(*) FILTER (WHERE NOT is_recent)                      AS excluded_no_recent_price,
       count(*) FILTER (WHERE is_recent AND basis <> product_basis) AS excluded_basis_mismatch,
       round(100.0*count(*) FILTER (WHERE comparable)/count(*), 2) AS pct_comparable,
       max(days_behind)                                           AS worst_days_behind
FROM offer_flagged GROUP BY 1 ORDER BY pct_comparable, vendor;

-- 5. The per-chain staleness curve as it will be written to meta.json. No pooled row exists
--    in this result set and none is computed anywhere in this file.
SELECT vendor, k AS days_since_capture, pairs, pct_wrong
FROM stale ORDER BY vendor, k;

-- ============================ EXPORTS ============================================

-- Exclusion counts, materialised so meta.json quotes the same numbers result 2 prints.
CREATE OR REPLACE TEMP TABLE shipped AS
SELECT (SELECT count(*) FROM g90)                          AS basket_barcodes,
       (SELECT count(DISTINCT gtin14) FROM offer_flagged)  AS products_shipped,
       (SELECT count(*) FROM g90)
         - (SELECT count(DISTINCT gtin14) FROM offer_flagged) AS omitted_no_recent_observation;

CREATE OR REPLACE TEMP TABLE excl AS
SELECT count(*)                                                          AS rows_in_scope,
       count(*) FILTER (WHERE s.product_key IS NULL)                     AS no_product_record,
       count(*) FILTER (WHERE s.parse_confidence = 'ambiguous')           AS ambiguous_price,
       count(*) FILTER (WHERE s.offer_type = 'unparsed')                  AS unparseable_price,
       count(*) FILTER (WHERE s.unit_price IS NULL OR s.unit_price <= 0)  AS nonpositive_price
FROM stg_price s
LEFT JOIN int_upc_match m ON m.product_key = s.product_key
WHERE s.observed_date >= (SELECT extract_date FROM params) - 200
  AND m.is_reliable_only AND m.vendor IN ('Metro','SaveOnFoods','Walmart');

-- meta.json -- build provenance, extract vintage, per-chain freshness, per-chain staleness
-- curve, exclusion counts, scope and attribution. NO POOLED STALENESS FIGURE EXISTS HERE.
COPY (
  SELECT (SELECT v FROM _build_stamp WHERE k = 'built_utc')            AS built_utc,
         (SELECT extract_date FROM params)                             AS extract_date,
         '20260822T134045Z'                                            AS snapshot_id,
         (SELECT basket_barcodes FROM shipped)                         AS basket_barcodes,
         (SELECT products_shipped FROM shipped)                        AS products_shipped,
         (SELECT struct_pack(
                   count := omitted_no_recent_observation,
                   note := 'Barcodes in the comparison basket with no observation at any of the three chains in the last 200 days. They are delisted or dormant, have no price to show, and are not in products.json. Stated here so this count and the published basket size cannot silently disagree.')
          FROM shipped)                                                AS omitted,
         (SELECT list(struct_pack(
                   chain := vendor,
                   last_observed := last_d,
                   days_behind := date_diff('day', last_d, (SELECT extract_date FROM params)),
                   products := n_products,
                   staleness := stal) ORDER BY vendor)
          FROM (SELECT cb.vendor,
                       max(cb.last_d)             AS last_d,
                       count(DISTINCT cb.gtin14)  AS n_products,
                       (SELECT list(struct_pack(days := k, pct_wrong := pct_wrong, pairs := pairs)
                                    ORDER BY k)
                        FROM stale st WHERE st.vendor = cb.vendor) AS stal
                FROM chain_basis cb GROUP BY cb.vendor ORDER BY cb.vendor)) AS chains,
         (SELECT struct_pack(
                   note := 'Rows dropped before the extract was built, over the same chains and the same 200-day window.',
                   rows_in_scope := rows_in_scope,
                   no_product_record := no_product_record,
                   ambiguous_price := ambiguous_price,
                   unparseable_price := unparseable_price,
                   nonpositive_price := nonpositive_price)
          FROM excl)                                                   AS exclusions,
         struct_pack(
           geography := 'In-store pickup prices for one neighbourhood in Toronto. Not national, not provincial.',
           products := 'National brands only. Store brands share no barcode and cannot be compared.',
           chains := 'Metro, Save-On-Foods and Walmart. Galleria is excluded because its catalogue barely overlaps the others.',
           comparison := 'Per product only. This tool produces no basket, no total, and no cheapest-store verdict.',
           staleness := 'Reported per chain. There is deliberately no pooled figure: pooling understates the chain you are most likely to be wrong about.'
         )                                                             AS scope,
         'The underlying data was sourced from ProjectHammer.org'       AS attribution
) TO 'tool/data/meta.json' (FORMAT JSON, ARRAY false);

-- products.json -- one object per barcode: the offers, and the comparison verdict that
-- names exactly which chains were compared.
COPY (
  WITH off AS (
    SELECT f.gtin14,
           -- determinism-ok: this list() IS ordered -- see `ORDER BY f.comparable DESC,
           -- f.px, f.vendor` at the close of the struct_pack below. vendor is unique per
           -- gtin in offer_flagged, so that ordering is total. Flagged only because the
           -- ORDER BY sits further down than the linter's line-local check reaches.
           list(struct_pack(
             chain := f.vendor,
             price := round(f.px, 2),
             basis := f.basis,
             min_qty := f.min_qty,
             observed_date := f.observed_date,
             days_behind := f.days_behind,
             is_recent := f.is_recent,
             on_sale := (f.on_sale = 1),
             comparable := f.comparable,
             not_comparable_reason := f.not_comparable_reason,
             staleness_pct := f.staleness_pct,
             staleness_horizon_days := f.staleness_horizon_days,
             staleness_exceeds_measured := f.staleness_exceeds_measured,
             prior_14d := struct_pack(
               days_observed := coalesce(c.prior_days_observed, 0),
               low := c.prior_14d_low,
               high := c.prior_14d_high,
               days_at_this_price := coalesce(c.prior_days_at_this_price, 0))
           ) ORDER BY f.comparable DESC, f.px, f.vendor)                  AS offers,
           count(*) FILTER (WHERE f.comparable)                           AS n_cmp,
           -- determinism-ok: arg_min over (px, vendor) restricted to comparable offers;
           -- vendor is unique per gtin in offer_flagged, so the composite key is total.
           arg_min(f.vendor, (f.px, f.vendor)) FILTER (WHERE f.comparable)   AS cheapest,
           arg_min(f.min_qty, (f.px, f.vendor)) FILTER (WHERE f.comparable)  AS cheapest_min_qty,
           -- determinism-ok: product_basis is functionally determined by gtin14 -- it comes
           -- from majority_basis, which has exactly one row per gtin.
           any_value(f.product_basis)                                     AS product_basis,
           list(f.vendor ORDER BY f.vendor) FILTER (WHERE f.comparable)    AS compared,
           list(struct_pack(chain := f.vendor,
                            last_observed := f.observed_date,
                            days_behind := f.days_behind,
                            reason := f.not_comparable_reason)
                ORDER BY f.vendor) FILTER (WHERE NOT f.comparable)         AS unavailable
    FROM offer_flagged f
    LEFT JOIN sale_ctx c ON c.gtin14 = f.gtin14 AND c.vendor = f.vendor
    GROUP BY f.gtin14)
  SELECT o.gtin14                                    AS gtin14,
         n.product_name                              AS name,
         nullif(n.brand_raw, '')                     AS brand,
         nullif(n.units_raw, '')                     AS size,
         o.product_basis                             AS basis,
         o.offers                                    AS offers,
         struct_pack(
           basis := o.product_basis,
           n_compared := o.n_cmp,
           compared := coalesce(o.compared, []::VARCHAR[]),
           unavailable := coalesce(o.unavailable,
                            []::STRUCT(chain VARCHAR, last_observed DATE,
                                       days_behind BIGINT, reason VARCHAR)[]),
           cheapest := CASE WHEN o.n_cmp >= 2 THEN o.cheapest END,
           cheapest_requires_min_qty := CASE WHEN o.n_cmp >= 2 AND o.cheapest_min_qty > 1
                                             THEN o.cheapest_min_qty END,
           claim := CASE
             WHEN o.n_cmp = 0 THEN 'No chain has a price from the last 7 days. Nothing can be compared.'
             WHEN o.n_cmp = 1 THEN 'Only ' || o.compared[1] || ' has a price from the last 7 days. There is nothing to compare it with.'
             ELSE 'Cheapest of the ' || o.n_cmp || ' chains with a price from the last 7 days: '
                  || list_aggregate(o.compared, 'string_agg', ' and ') || '.'
           END)                                      AS comparison
  FROM off o JOIN name_pick n ON n.gtin14 = o.gtin14
  ORDER BY o.gtin14
) TO 'tool/data/products.json' (FORMAT JSON, ARRAY true);

-- history.json -- 42 days of price spells per barcode per chain. Runs of constant price,
-- not one point per day: gaps stay visible because a spell covers only observed days.
COPY (
  SELECT gtin14, vendor AS chain, basis,
         list(struct_pack(from_date := from_date, to_date := to_date,
                          price := round(px, 2), observed_days := observed_days,
                          on_sale := (on_sale = 1))
              ORDER BY from_date)                    AS spells
  FROM spells GROUP BY gtin14, vendor, basis
  ORDER BY gtin14, chain, basis
) TO 'tool/data/history.json' (FORMAT JSON, ARRAY true);

-- 6. Fingerprint the written files, so verify_twice's byte comparison of stdout covers the
--    JSON as well as the printed results. Without this the files could differ between runs
--    while the printed output agreed -- which is the same hole verify_twice exists to close.
SELECT 'history.json'  AS file, length(content) AS bytes, md5(content) AS md5 FROM read_text('tool/data/history.json')
UNION ALL
SELECT 'meta.json',     length(content), md5(content) FROM read_text('tool/data/meta.json')
UNION ALL
SELECT 'products.json', length(content), md5(content) FROM read_text('tool/data/products.json')
ORDER BY file;
