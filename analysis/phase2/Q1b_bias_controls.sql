-- Q1.2 (continued): the controls that decide whether an exclusion is BIASED or merely
-- CONCENTRATED, plus the D2 event-level and D4 basket-level ledgers.
--
-- Q1 found that orphan rows are 29.91% sale rows against 17.63% for retained rows -- a
-- 1.70x enrichment on precisely the axis D2 measures. Before that is reported as a bias,
-- it has to survive the obvious confound:
--
--   72.6% of orphan rows are Metro (P5.9). If Metro simply runs more promotions than the
--   average vendor, then "orphans are sale-rich" is a statement about Metro, not about
--   orphaning, and controlling for vendor would make it vanish.
--
-- THIS IS THE F1 MISTAKE. Phase 0's F1 compared sale behaviour across vendors when the
-- question was within-vendor, and the wrong axis reversed the answer. So the enrichment
-- is recomputed WITHIN each apparent vendor, against that vendor's own retained rows.
-- If it survives per vendor, it is a property of orphaning. If it collapses, it was
-- Metro's promotion rate all along.
SET threads = 4;

-- Apparent vendor for orphan rows, from the retired id form (P5.9). One regex, applied
-- only to the 878,559 orphan rows rather than to all 71.8M.
CREATE OR REPLACE TEMP TABLE orphan_rows AS
SELECT s.src_rowid,
       regexp_extract(s.product_id,
         '^(Metro|Walmart|Loblaws|NoFrills|TandT|Voila|Galleria|SaveOnFoods)', 1) AS vendor,
       year(s.observed_date)                     AS yr,
       (s.old_offer_type <> 'blank')             AS is_sale_row,
       s.offer_type,
       s.unit_price,
       s.old_unit_price
FROM stg_price s
WHERE s.product_key IS NULL;

-- Retained rows, per vendor, with the same attributes. This is the comparison group.
CREATE OR REPLACE TEMP TABLE retained_rows AS
SELECT sp.vendor,
       year(s.observed_date)                     AS yr,
       (s.old_offer_type <> 'blank')             AS is_sale_row,
       s.offer_type,
       s.unit_price,
       s.old_unit_price
FROM stg_price s JOIN stg_product sp USING (product_key)
WHERE s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed';

-- 1. THE CONTROL THAT DECIDES IT: orphan sale rate vs the SAME vendor's retained sale
--    rate. A ratio near 1.00 means orphaning is neutral on this axis for that vendor.
SELECT coalesce(nullif(o.vendor, ''), '(unattributable)')          AS vendor,
       o.orphan_rows,
       round(o.pct_sale_orphan, 3)                                 AS pct_sale_orphan,
       r.retained_rows,
       round(r.pct_sale_retained, 3)                               AS pct_sale_retained,
       round(o.pct_sale_orphan / nullif(r.pct_sale_retained, 0), 3) AS enrichment_ratio
FROM (SELECT vendor, count(*) AS orphan_rows,
             100.0*count(*) FILTER (WHERE is_sale_row)/count(*) AS pct_sale_orphan
      FROM orphan_rows GROUP BY 1) o
FULL JOIN (SELECT vendor, count(*) AS retained_rows,
                  100.0*count(*) FILTER (WHERE is_sale_row)/count(*) AS pct_sale_retained
           FROM retained_rows GROUP BY 1) r USING (vendor)
ORDER BY o.orphan_rows DESC NULLS LAST, vendor;

-- 2. Same control on OFFER TYPE. Orphans looked 11x richer in multibuy overall, and
--    multibuy is the promotion type F5 found was once categorically excluded.
SELECT coalesce(nullif(o.vendor, ''), '(unattributable)')           AS vendor,
       round(o.pct_multibuy_orphan, 3)                              AS pct_multibuy_orphan,
       round(r.pct_multibuy_retained, 3)                            AS pct_multibuy_retained,
       round(o.pct_multibuy_orphan / nullif(r.pct_multibuy_retained, 0), 2) AS ratio
FROM (SELECT vendor, 100.0*count(*) FILTER (WHERE offer_type='multibuy')/count(*) AS pct_multibuy_orphan
      FROM orphan_rows GROUP BY 1) o
FULL JOIN (SELECT vendor, 100.0*count(*) FILTER (WHERE offer_type='multibuy')/count(*) AS pct_multibuy_retained
           FROM retained_rows GROUP BY 1) r USING (vendor)
-- vendor breaks the tie: every vendor but Metro has no multibuy in either
-- population, so `ratio` alone leaves seven rows in arbitrary order.
ORDER BY ratio DESC NULLS LAST, vendor;

-- 3. Orphan rows per apparent vendor per year -- the time axis the brief asks for, with
--    the vendor attribution restored. Q1 result 9 could not show this because orphans
--    have no `product` row and therefore no vendor column.
SELECT coalesce(nullif(vendor, ''), '(unattributable)') AS vendor, yr,
       count(*) AS orphan_rows,
       count(*) FILTER (WHERE is_sale_row) AS orphan_sale_rows
FROM orphan_rows GROUP BY 1,2 ORDER BY vendor, yr;

-- ============================ D2 EVENT-LEVEL LEDGER ================================
-- The ledger so far counts ROWS. D2 counts EVENTS -- maximal runs of consecutive on-sale
-- days per product -- and an exclusion that removes many rows from few events costs less
-- than one that removes few rows from many events. Both numbers are needed.

-- Retained-population events, using P2_3's definition unchanged.
CREATE OR REPLACE TEMP TABLE daily AS
SELECT s.product_key AS k, s.observed_date AS d,
       max(CASE WHEN s.old_offer_type <> 'blank' THEN 1 ELSE 0 END) AS on_sale,
       max(CASE WHEN s.parse_confidence = 'ambiguous' THEN 1 ELSE 0 END) AS has_ambiguous
FROM stg_price s
WHERE s.product_key IS NOT NULL
GROUP BY 1,2;

-- determinism-ok: gaps-and-islands over `daily`, which is GROUP BY (key, date) and
-- therefore holds exactly one row per key per date, so ORDER BY the date is a TOTAL
-- order within the partition. Verified against the CREATE of `daily` above.
CREATE OR REPLACE TEMP TABLE runs AS
SELECT *, row_number() OVER (PARTITION BY k ORDER BY d)
        - row_number() OVER (PARTITION BY k, on_sale ORDER BY d) AS grp
FROM daily;

CREATE OR REPLACE TEMP TABLE ev AS
SELECT k, min(d) AS sale_start, count(*) AS run_days,
       max(has_ambiguous) AS touched_ambiguous
FROM runs WHERE on_sale = 1 GROUP BY k, grp;

-- 4. D2 events, and how many an ambiguous-row exclusion touches. An event is touched if
--    ANY of its days carries an ambiguous price.
SELECT count(*)                                          AS d2_sale_events,
       count(*) FILTER (WHERE touched_ambiguous = 1)     AS events_touching_ambiguous,
       round(100.0*count(*) FILTER (WHERE touched_ambiguous = 1)/count(*), 4) AS pct_touched
FROM ev;

-- 5. Events LOST to orphaning: events that exist in the orphan population and can never
--    be keyed. Computed on `product_id` DELIBERATELY and ONLY to size the exclusion --
--    this number is a measurement of what is missing, never an input to a finding, and
--    locked decision 5 still forbids keying a published series this way.
CREATE OR REPLACE TEMP TABLE odaily AS
SELECT s.product_id AS k, s.observed_date AS d,
       max(CASE WHEN s.old_offer_type <> 'blank' THEN 1 ELSE 0 END) AS on_sale
FROM stg_price s WHERE s.product_key IS NULL
GROUP BY 1,2;

-- determinism-ok: gaps-and-islands over `odaily`, which is GROUP BY (product_id, date)
-- and therefore one row per id per date, so ORDER BY the date is a total order.
CREATE OR REPLACE TEMP TABLE oruns AS
SELECT *, row_number() OVER (PARTITION BY k ORDER BY d)
        - row_number() OVER (PARTITION BY k, on_sale ORDER BY d) AS grp
FROM odaily;

SELECT count(*)                    AS orphan_sale_events_lost,
       count(DISTINCT k)           AS distinct_orphan_ids,
       round(median(run_days), 1)  AS median_run_days
FROM (SELECT k, count(*) AS run_days FROM oruns WHERE on_sale = 1 GROUP BY k, grp);

-- ============================ D4 BASKET LEDGER =====================================
-- D4's basket is the reliable-tier UPC set. Orphans cannot reach it (no product row, so
-- no UPC), which makes their D4 exclusion exactly zero -- stated as a number, not
-- asserted. Ambiguous rows CAN reach it, so that is the number that matters.

CREATE OR REPLACE TEMP TABLE basket AS
SELECT m.product_key, m.gtin14
FROM int_upc_match m WHERE m.is_reliable_only;

-- 6. D4 exclusion ledger: rows and GTINs removed from the basket, by class.
SELECT (SELECT count(DISTINCT gtin14) FROM basket)                        AS basket_gtins,
       count(*)                                                           AS basket_price_rows,
       count(*) FILTER (WHERE s.parse_confidence = 'ambiguous')           AS rows_excl_ambiguous,
       count(DISTINCT b.gtin14) FILTER (WHERE s.parse_confidence = 'ambiguous') AS gtins_touched_ambiguous,
       count(*) FILTER (WHERE s.offer_type = 'unparsed')                  AS rows_excl_unparsed,
       0                                                                  AS rows_excl_orphan_by_construction
FROM stg_price s JOIN basket b USING (product_key);

-- 7. D4 basket: is the ambiguous exclusion concentrated in a few GTINs or spread thin?
--    A thin spread costs precision; a concentration removes specific products.
SELECT CASE WHEN pct_amb = 0 THEN 'a. none'
            WHEN pct_amb < 1 THEN 'b. <1% of history'
            WHEN pct_amb < 10 THEN 'c. 1-10%'
            WHEN pct_amb < 50 THEN 'd. 10-50%'
            ELSE 'e. >=50% (unusable)' END AS share_of_history_ambiguous,
       count(*) AS gtins
FROM (SELECT b.gtin14,
             100.0*count(*) FILTER (WHERE s.parse_confidence='ambiguous')/count(*) AS pct_amb
      FROM stg_price s JOIN basket b USING (product_key) GROUP BY 1)
GROUP BY 1 ORDER BY 1;

-- ============================ THE TIME AXIS, AT EVENT LEVEL ========================
-- The brief asks specifically: per vendor, per year, the share of D2 events lost, and
-- whether any vendor-year loses enough to distort a trend. Rows are not events, and a
-- vendor-year that loses 4% of rows may lose far more or far less of its events.

-- Retained events, attributed to vendor and to the year the event STARTS in.
CREATE OR REPLACE TEMP TABLE ev_v AS
SELECT sp.vendor, year(e.sale_start) AS yr, count(*) AS events
FROM ev e JOIN stg_product sp ON sp.product_key = e.k
GROUP BY 1,2;

-- Orphan events, same attribution, from the retired id form.
CREATE OR REPLACE TEMP TABLE oev_v AS
SELECT coalesce(nullif(regexp_extract(k,
         '^(Metro|Walmart|Loblaws|NoFrills|TandT|Voila|Galleria|SaveOnFoods)', 1), ''),
       '(unattributable)')                     AS vendor,
       year(sale_start)                        AS yr,
       count(*)                                AS events_lost
FROM (SELECT k, min(d) AS sale_start FROM oruns WHERE on_sale = 1 GROUP BY k, grp)
GROUP BY 1,2;

-- 8. Share of D2 events lost to orphaning, per vendor per year. This is the number that
--    decides whether a D2 trend line can cross 2024 safely.
SELECT coalesce(a.vendor, b.vendor)                     AS vendor,
       coalesce(a.yr, b.yr)                             AS yr,
       coalesce(a.events, 0)                            AS events_retained,
       coalesce(b.events_lost, 0)                       AS events_lost,
       round(100.0 * coalesce(b.events_lost, 0)
             / nullif(coalesce(a.events, 0) + coalesce(b.events_lost, 0), 0), 3) AS pct_events_lost
FROM ev_v a FULL JOIN oev_v b ON a.vendor = b.vendor AND a.yr = b.yr
ORDER BY vendor, yr;

-- 9. The same, collapsed to a per-vendor worst-year summary, so the answer to "does any
--    vendor-year lose enough to distort a trend" is one readable table.
SELECT vendor,
       round(min(pct), 3)  AS best_year_pct_lost,
       round(max(pct), 3)  AS worst_year_pct_lost,
       round(max(pct) - min(pct), 3) AS spread_pp
FROM (SELECT coalesce(a.vendor, b.vendor) AS vendor,
             100.0 * coalesce(b.events_lost, 0)
               / nullif(coalesce(a.events, 0) + coalesce(b.events_lost, 0), 0) AS pct
      FROM ev_v a FULL JOIN oev_v b ON a.vendor = b.vendor AND a.yr = b.yr)
WHERE vendor IS NOT NULL
GROUP BY 1 ORDER BY spread_pp DESC, vendor;
