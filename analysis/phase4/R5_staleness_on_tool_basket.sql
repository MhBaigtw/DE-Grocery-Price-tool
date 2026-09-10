-- R5: the same staleness measure, on the exact population the tool will display.
--
-- WHY. R3 and R4 measure every reliable barcode carried by the three chains -- 5,188 of
-- them. The tool does not ship 5,188. It ships the comparison basket: barcodes co-observed
-- at two or more of the three chains on 90+ dates, which is 3,190 (Phase 3 D1; 3,477 is the
-- wider figure that includes Galleria, and Galleria is out of scope per Phase 2 §3.7).
--
-- A staleness figure printed in the interface is a claim about the prices on screen, so it
-- has to be computed on the prices on screen. If the two populations disagree, the narrower
-- one governs the disclosure and the difference gets reported rather than averaged away.
-- The basket is selected for being well observed, so if anything it should be MORE
-- observable and possibly more promoted; the direction is not obvious, which is why this is
-- measured instead of argued.
SET threads = 2;

-- Same construction as analysis/phase3/D1_dashboard_extract.sql, deliberately duplicated
-- rather than referenced, so this file runs standalone and its basket is auditable here.
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

-- 1. Confirm the basket is the one the dashboard ships, so the two cannot drift apart.
SELECT (SELECT count(*) FROM g90) AS tool_basket_barcodes,
       (SELECT count(*) FROM obs WHERE gtin14 IN (SELECT gtin14 FROM g90)) AS product_days;

-- 2. The disclosure number: share of displayed prices wrong by age, on the tool's basket,
--    2025 onward.
WITH kk AS (SELECT unnest([1,2,3,7,14]) AS k),
o AS (SELECT * FROM obs WHERE gtin14 IN (SELECT gtin14 FROM g90) AND d >= DATE '2025-01-01'),
pairs AS (
  SELECT kk.k, a.vendor, f.px AS px_k, a.px
  FROM o a CROSS JOIN kk
  LEFT JOIN o f ON f.gtin14 = a.gtin14 AND f.vendor = a.vendor AND f.basis = a.basis
               AND f.d = a.d + kk.k)
SELECT vendor, k AS days_since_capture,
       count(*) FILTER (WHERE px_k IS NOT NULL)                            AS pairs,
       count(*) FILTER (WHERE px_k IS NULL)                                AS unobserved_at_k,
       round(100.0*count(*) FILTER (WHERE px_k IS NOT NULL AND abs(px_k - px) > 0.005)
             / nullif(count(*) FILTER (WHERE px_k IS NOT NULL), 0), 2)     AS pct_wrong
FROM pairs GROUP BY vendor, k ORDER BY vendor, days_since_capture;

-- 3. Pooled across the three chains -- the single figure the interface would print, since a
--    user searching one product does not know in advance which chains will answer.
WITH kk AS (SELECT unnest([1,2,3,7,14]) AS k),
o AS (SELECT * FROM obs WHERE gtin14 IN (SELECT gtin14 FROM g90) AND d >= DATE '2025-01-01'),
pairs AS (
  SELECT kk.k, f.px AS px_k, a.px
  FROM o a CROSS JOIN kk
  LEFT JOIN o f ON f.gtin14 = a.gtin14 AND f.vendor = a.vendor AND f.basis = a.basis
               AND f.d = a.d + kk.k)
SELECT k AS days_since_capture,
       count(*) FILTER (WHERE px_k IS NOT NULL)                            AS pairs,
       round(100.0*count(*) FILTER (WHERE px_k IS NOT NULL AND abs(px_k - px) > 0.005)
             / nullif(count(*) FILTER (WHERE px_k IS NOT NULL), 0), 2)     AS pct_wrong
FROM pairs GROUP BY k ORDER BY days_since_capture;
