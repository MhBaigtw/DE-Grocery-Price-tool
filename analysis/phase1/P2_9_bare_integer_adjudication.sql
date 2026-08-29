-- P2.9: is a bare integer price cents or dollars? Decided by evidence, not by guessing.
--
-- The magnitude sweep (P2.7) flagged 104,640 Walmart adjacent-day pairs moving by exactly
-- 100x. The sample showed the mechanism: the same SKU reads '298' one day (parsed as
-- $298.00) and 'Now$298' the next (parsed correctly as $2.98). So at Walmart a bare
-- integer is CENTS, and my parser has been reading 129,456 rows at 100x their true value
-- while reporting them as successfully parsed.
--
-- Galleria also has bare integers (26,306) but they look different: max $198 vs Walmart's
-- max $6,996, and only 779 are >= 100. A vendor-specific rule needs evidence per vendor,
-- so this adjudicates both rather than assuming they are the same defect.
--
-- Test: for each bare-integer observation, find the SAME sku's nearest non-bare price
-- within 7 days, and ask which reading -- raw, or raw/100 -- is closer.
SET threads = 4;

-- DETERMINISM NOTE (added in 5.8). The first version of this query keyed on the retired
-- 64-bit hash and, worse, resolved multiple candidate reference prices with any_value(),
-- which picks ARBITRARILY. Three runs over the same immutable snapshot and the same build
-- returned 57,008 / 57,212 / 56,598 for the 100-999 cents count: a published number that
-- moved by 614 between runs of the same query on the same data. That is honesty rule 4
-- broken by non-determinism rather than by staleness, and it is harder to notice.
--
-- The header above says "nearest non-bare price within 7 days". It now actually does
-- that: ranked by |day difference|, ties broken by the earlier date and then by price, so
-- the choice is total and repeatable.
--
-- The partition is (key, date, BARE VALUE), not (key, date). Phase 0 B6 found the same
-- product appearing many times in one day's scrape with CONFLICTING prices, so (key, date)
-- is not unique and partitioning on it silently picks one of the conflicting values --
-- which reintroduced the very non-determinism this note is about. Fixed after observing
-- rows migrate between magnitude bands across runs. This is the third time on this
-- dataset that a non-unique key has produced a moving number (see findings 1.4). The load-bearing claim was never affected -- zero
-- rows >= 100 match a dollars reading in every run -- but the supporting counts were.
CREATE OR REPLACE TEMP TABLE obs AS
SELECT p.product_key AS k, p.vendor, s.observed_date AS dt,
       s.current_price_raw AS txt,
       regexp_matches(s.current_price_raw, '^[0-9]+$')      AS is_bare,
       try_cast(s.current_price_raw AS DOUBLE)              AS bare_val,
       s.unit_price                                         AS parsed
FROM stg_price s JOIN stg_product p USING (product_key)
WHERE p.vendor IN ('Walmart','Galleria')
  AND p.product_key_basis = 'vendor_sku'
  AND s.unit_price IS NOT NULL AND s.observed_date >= DATE '2024-06-11';

-- reference price: same key, non-bare row, within 7 days
CREATE OR REPLACE TEMP TABLE ref AS
SELECT k, vendor, dt, parsed AS ref_px FROM obs WHERE NOT is_bare;

CREATE OR REPLACE TEMP TABLE adjud AS
SELECT vendor, k, dt, bare_val, ref_px FROM (
  SELECT b.vendor, b.k, b.dt, b.bare_val, r.ref_px,
         row_number() OVER (PARTITION BY b.k, b.dt, b.bare_val
                            ORDER BY abs(date_diff('day', b.dt, r.dt)),  -- nearest in time
                                     r.dt,                               -- then earlier date
                                     r.ref_px) AS rn                     -- then lowest price
  FROM obs b JOIN ref r
    ON r.k = b.k AND abs(date_diff('day', b.dt, r.dt)) <= 7 AND r.dt <> b.dt
  WHERE b.is_bare)
WHERE rn = 1;

-- 1. Which reading matches the neighbouring non-bare price?
SELECT vendor,
       count(*)                                                                  AS adjudicable_rows,
       count(*) FILTER (WHERE abs(bare_val       - ref_px) <= 0.15*ref_px)       AS matches_DOLLARS,
       count(*) FILTER (WHERE abs(bare_val/100.0 - ref_px) <= 0.15*ref_px)       AS matches_CENTS,
       round(100.0*count(*) FILTER (WHERE abs(bare_val/100.0 - ref_px) <= 0.15*ref_px)/count(*),2)
                                                                                 AS pct_cents,
       count(*) FILTER (WHERE abs(bare_val - ref_px) > 0.15*ref_px
                          AND abs(bare_val/100.0 - ref_px) > 0.15*ref_px)        AS neither
FROM adjud GROUP BY vendor ORDER BY vendor;

-- 2. Split by magnitude: is the answer the same for small integers as for large?
SELECT vendor,
       CASE WHEN bare_val < 10 THEN 'a. < 10'
            WHEN bare_val < 100 THEN 'b. 10-99'
            WHEN bare_val < 1000 THEN 'c. 100-999'
            ELSE 'd. 1000+' END                                                  AS magnitude,
       count(*)                                                                  AS rows,
       count(*) FILTER (WHERE abs(bare_val       - ref_px) <= 0.15*ref_px)       AS matches_dollars,
       count(*) FILTER (WHERE abs(bare_val/100.0 - ref_px) <= 0.15*ref_px)       AS matches_cents
FROM adjud GROUP BY 1,2 ORDER BY 1,2;

-- 3. Total exposure: all bare-integer rows, adjudicable or not.
SELECT p.vendor, count(*) AS bare_integer_rows,
       count(*) FILTER (WHERE try_cast(s.current_price_raw AS DOUBLE) >= 100) AS at_least_100
FROM stg_price s JOIN stg_product p USING (product_key)
WHERE regexp_matches(s.current_price_raw, '^[0-9]+$')
GROUP BY p.vendor ORDER BY bare_integer_rows DESC;
