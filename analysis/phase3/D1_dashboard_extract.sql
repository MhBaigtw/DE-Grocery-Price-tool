-- D1: the pre-aggregated data behind the dashboard.
--
-- The dashboard is a static page with no backend, so every number it shows has to be
-- computed here and written out as JSON. Nothing is recomputed in the browser, and the
-- browser never sees a price row.
--
-- SCOPE DISCIPLINE. The dashboard must not be mistakable for a shopping tool (brief 3.3),
-- so this extract deliberately does NOT produce per-product prices. There is no table here
-- that could be joined back into "what does item X cost at store Y". The finest grain
-- exported is a vendor-pair-by-date median ratio, which cannot answer a shopper's question
-- and is not meant to.
--
-- Every export carries its own n, because brief 3.5 requires n on the chart rather than in
-- a caption, and a chart cannot show an n the data does not carry.
SET threads = 2;

CREATE OR REPLACE TEMP TABLE obs AS
SELECT m.gtin14, m.vendor, s.observed_date AS d, s.price_basis AS basis,
       -- determinism-ok: min() over (gtin, vendor, date, basis), which Phase 0 B6 proves
       -- is not unique -- one product can appear many times a day with conflicting prices.
       -- min() is a total order and matches the convention used throughout Section 3.
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

-- ============================ 1. PAIRWISE COMPARISON OVER TIME ====================
-- One row per (pair, date) with the median price ratio and the number of products behind
-- it. n travels with the point so the chart can render it.
COPY (
  SELECT a.vendor || ' / ' || b.vendor            AS pair,
         a.d                                       AS date,
         count(*)                                  AS n_products,
         round(median(a.px / b.px), 4)             AS median_ratio
  FROM obs a
  JOIN obs b ON b.gtin14 = a.gtin14 AND b.d = a.d AND b.basis = a.basis
            AND b.vendor > a.vendor
  WHERE a.gtin14 IN (SELECT gtin14 FROM g90)
  GROUP BY 1,2 HAVING count(*) >= 30
  ORDER BY pair, date
) TO 'dashboard/data/pairwise_over_time.json' (FORMAT JSON, ARRAY true);

-- ============================ 2. THE STORE-BRAND BLIND SPOT =======================
-- What share of each chain's shelf the barcode-matched basket can and cannot see.
COPY (
  SELECT vendor,
         count(*)                                                                  AS price_rows,
         round(100.0*count(*) FILTER (WHERE brand_class='private_label')/count(*), 2) AS pct_rows_store_brand,
         round(100.0*sum(unit_price) FILTER (WHERE brand_class='private_label')
               / nullif(sum(unit_price), 0), 2)                                    AS pct_exposure_store_brand
  FROM (SELECT sp.vendor, sp.brand_class, s.unit_price
        FROM stg_price s JOIN stg_product sp USING (product_key)
        WHERE sp.vendor IN ('Metro','SaveOnFoods','Walmart')
          AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
          AND s.unit_price IS NOT NULL AND s.price_basis = 'each'
          AND s.observed_date >= DATE '2024-06-11')
  GROUP BY 1 ORDER BY pct_exposure_store_brand DESC, vendor
) TO 'dashboard/data/blindspot.json' (FORMAT JSON, ARRAY true);

-- ============================ 3. SALE FREQUENCY, WITHIN VENDOR ====================
-- Deliberately exported per vendor with NO cross-vendor ordering implied. The dashboard
-- states on the chart that the cross-vendor comparison is unavailable and why.
COPY (
  SELECT kk.vendor,
         count(*)                                                        AS n_products,
         round(median(100.0*x.days_on_sale/x.days_observed), 2)          AS median_pct_days_on_sale,
         round(100.0*count(*) FILTER (WHERE 100.0*x.days_on_sale/x.days_observed >= 50)
               / count(*), 2)                                            AS pct_products_over_half_the_time
  FROM (SELECT product_key AS k, count(*) AS days_observed, sum(on_sale) AS days_on_sale
        FROM (SELECT s.product_key, s.observed_date,
                     max(CASE WHEN s.old_offer_type <> 'blank' THEN 1 ELSE 0 END) AS on_sale
              FROM stg_price s
              WHERE s.product_key IS NOT NULL
                AND s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
                AND s.observed_date >= DATE '2025-01-01'
              GROUP BY 1,2)
        GROUP BY 1 HAVING count(*) >= 90) x
  JOIN (SELECT product_key AS k, vendor, product_key_basis FROM stg_product) kk ON kk.k = x.k
  WHERE kk.product_key_basis = 'vendor_sku'
  GROUP BY 1 ORDER BY vendor
) TO 'dashboard/data/sale_frequency.json' (FORMAT JSON, ARRAY true);

-- 3b. The corroboration rates that justify withholding the cross-vendor ranking. Shown on
--     the same screen so the absence is explained rather than merely stated.
COPY (
  -- `testable` separates "0% corroborated" from "there is nothing to corroborate
  -- against". Metro and Galleria carry no promotional text on ANY row, so their rate
  -- computes as 0.0 -- which would read on a chart as "their struck-out prices are never
  -- confirmed", a claim about those chains rather than about a missing field. The flag
  -- forces the dashboard to say "cannot be checked" instead.
  SELECT vendor,
         (count(*) FILTER (WHERE other_sale) > 0)                         AS testable,
         CASE WHEN count(*) FILTER (WHERE other_sale) = 0 THEN NULL
              ELSE round(100.0*count(*) FILTER (WHERE old_present AND other_sale)
                   / nullif(count(*) FILTER (WHERE old_present), 0), 2) END AS pct_corroborated,
         count(*) FILTER (WHERE old_present)                              AS n_flag_rows
  FROM (SELECT sp.vendor,
               (s.old_offer_type <> 'blank') AS old_present,
               (s.other_raw IS NOT NULL AND trim(s.other_raw) <> ''
                AND regexp_matches(lower(s.other_raw),
                    '(sale|rollback|clearance|deal|save|special|reduced|[0-9]+ *for *\$|was |price *drop)')
                AND NOT regexp_full_match(lower(trim(s.other_raw)),
                    '(out of stock|low stock|in stock)')) AS other_sale
        FROM stg_price s JOIN stg_product sp USING (product_key)
        WHERE s.parse_confidence <> 'ambiguous' AND s.offer_type <> 'unparsed'
          AND s.observed_date >= DATE '2025-01-01')
  GROUP BY 1 ORDER BY testable DESC, pct_corroborated DESC NULLS LAST, vendor
) TO 'dashboard/data/flag_corroboration.json' (FORMAT JSON, ARRAY true);

-- ============================ 4. THE EXCLUSION LEDGER =============================
COPY (
  SELECT CASE
           WHEN s.product_key IS NULL            THEN 'no product record'
           WHEN s.offer_type = 'unparsed'        THEN 'unparseable price'
           WHEN s.parse_confidence = 'ambiguous' THEN 'ambiguous price'
           ELSE                                       'kept'
         END                                     AS class,
         count(*)                                AS rows,
         round(100.0*count(*) / sum(count(*)) OVER (), 4) AS pct_of_all
  FROM stg_price s
  GROUP BY 1 ORDER BY rows DESC
) TO 'dashboard/data/exclusion_ledger.json' (FORMAT JSON, ARRAY true);

-- ============================ 5. HEADLINE FIGURES =================================
-- The small set of scalars the page quotes, exported rather than hand-typed into HTML so
-- they cannot drift from the analysis.
-- TWO BASKET COUNTS, both exported and both labelled, because they differ and a
-- dashboard quoting one while the writeup quotes the other would be a silent
-- contradiction. 3,477 is the full reliable-barcode basket including Galleria; the
-- comparison charts use only the three chains Galleria can be compared against, and that
-- basket is smaller. The dashboard must quote `comparison_barcodes` next to the charts.
COPY (
  SELECT (SELECT count(*) FROM stg_price)                              AS total_price_rows,
         (SELECT count(DISTINCT gtin14) FROM g90)                      AS comparison_barcodes,
         (SELECT count(*) FROM (
            SELECT gtin14 FROM (
              SELECT m.gtin14, count(DISTINCT s.observed_date) AS co_days
              FROM (SELECT m2.gtin14, s2.observed_date
                    FROM stg_price s2 JOIN int_upc_match m2 ON m2.product_key = s2.product_key
                    WHERE m2.is_reliable_only AND s2.parse_confidence <> 'ambiguous'
                      AND s2.offer_type <> 'unparsed' AND s2.unit_price IS NOT NULL
                      AND s2.observed_date >= DATE '2024-06-11'
                    GROUP BY 1,2 HAVING count(DISTINCT m2.vendor) >= 2) x
              JOIN int_upc_match m ON m.gtin14 = x.gtin14
              JOIN stg_price s ON s.product_key = m.product_key
                              AND s.observed_date = x.observed_date
              GROUP BY 1) y
            WHERE co_days >= 90))                                      AS full_basket_barcodes,
         (SELECT count(DISTINCT d) FROM obs)                           AS observed_dates,
         (SELECT min(d) FROM obs)                                      AS first_date,
         (SELECT max(d) FROM obs)                                      AS last_date
) TO 'dashboard/data/headline.json' (FORMAT JSON, ARRAY true);
