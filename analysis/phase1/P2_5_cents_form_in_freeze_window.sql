-- P2.5: cents-form contamination inside D1's surviving freeze window.
--
-- Why this matters: D1's 2024-25 window is already a NO-GO. The 2025-26 window
-- (2025-11-01 .. 2026-02-05) is the only one still standing, on a provisional GO. The
-- cents-form defect (Phase 1 section 1.5) began 2025-10-22 -- ten days before that window
-- opens -- and runs at ~175 Loblaws rows/day throughout it. A price freeze is a claim
-- about prices NOT CHANGING, so a price that reads 329 on one day and 3.29 on the next
-- would look like a 100x price move. This quantifies the exposure.
SET threads = 4;

CREATE OR REPLACE TEMP TABLE win AS
SELECT DATE '2025-11-01' AS d0, DATE '2026-02-05' AS d1;

-- 1. Loblaws rows inside the window carrying cents-form, current_price and old_price
--    reported SEPARATELY as asked.
SELECT p.vendor,
       count(*)                                                                  AS loblaws_rows_in_window,
       count(*) FILTER (WHERE s.normalization = 'cents_div100')                  AS cents_form_current_price,
       round(100.0*count(*) FILTER (WHERE s.normalization = 'cents_div100')/count(*),3) AS pct_current,
       count(*) FILTER (WHERE s.old_normalization = 'cents_div100')              AS cents_form_old_price,
       round(100.0*count(*) FILTER (WHERE s.old_normalization = 'cents_div100')/count(*),3) AS pct_old,
       count(DISTINCT s.observed_date) FILTER (WHERE s.normalization = 'cents_div100') AS dates_affected
FROM stg_price s JOIN product p ON p.id = s.product_id, win w
WHERE p.vendor = 'Loblaws' AND s.observed_date BETWEEN w.d0 AND w.d1
GROUP BY p.vendor;

-- 2. All vendors in the window, so the Loblaws share is in context.
SELECT p.vendor,
       count(*) AS rows_in_window,
       count(*) FILTER (WHERE s.normalization IN ('cents_div100','now_prefix_cents_div100')) AS cents_form_current,
       count(*) FILTER (WHERE s.old_normalization IN ('cents_div100','cent_symbol_div100'))  AS cents_form_old
FROM stg_price s JOIN product p ON p.id = s.product_id, win w
WHERE s.observed_date BETWEEN w.d0 AND w.d1
GROUP BY p.vendor ORDER BY cents_form_current DESC;

-- 3. D2 sale events at Loblaws inside the window whose old_price is cents-form.
CREATE OR REPLACE TEMP TABLE daily AS
SELECT p.sku, s.observed_date AS d,
       max(CASE WHEN s.old_offer_type <> 'blank' THEN 1 ELSE 0 END)               AS on_sale,
       max(CASE WHEN s.old_normalization = 'cents_div100' THEN 1 ELSE 0 END)      AS old_cents,
       max(CASE WHEN s.normalization    = 'cents_div100' THEN 1 ELSE 0 END)       AS cur_cents
FROM stg_price s JOIN product p ON p.id = s.product_id
WHERE p.vendor='Loblaws' AND p.sku IS NOT NULL AND trim(p.sku)<>''
  AND s.observed_date >= DATE '2024-06-11'
GROUP BY 1,2;

CREATE OR REPLACE TEMP TABLE ev AS
SELECT sku, min(d) AS sale_start, max(old_cents) AS old_cents, max(cur_cents) AS cur_cents
-- determinism-ok: gaps-and-islands over `daily`, which is GROUP BY (key, date) and
-- therefore holds exactly one row per key per date, so ORDER BY the date is a TOTAL
-- order within the partition. Verified against the CREATE of `daily` above.
FROM (SELECT *, row_number() OVER (PARTITION BY sku ORDER BY d)
               - row_number() OVER (PARTITION BY sku, on_sale ORDER BY d) AS grp FROM daily)
WHERE on_sale = 1 GROUP BY sku, grp;

SELECT count(*)                                                       AS loblaws_sale_events_in_window,
       count(*) FILTER (WHERE old_cents = 1)                          AS with_cents_form_old_price,
       count(*) FILTER (WHERE cur_cents = 1)                          AS with_cents_form_current_price,
       count(*) FILTER (WHERE old_cents = 1 OR cur_cents = 1)         AS with_either,
       round(100.0*count(*) FILTER (WHERE old_cents=1 OR cur_cents=1)/count(*),2) AS pct_touched
FROM ev, win w WHERE sale_start BETWEEN w.d0 AND w.d1;

-- 4. Would an unparsed reader see a false price move? Show products whose raw text
--    flips between decimal and cents form on consecutive days inside the window.
SELECT s.product_id, p.product_name, s.observed_date, s.current_price_raw,
       s.unit_price AS parsed_correctly
FROM stg_price s JOIN product p ON p.id = s.product_id, win w
WHERE p.vendor='Loblaws' AND s.observed_date BETWEEN w.d0 AND w.d1
  AND s.normalization = 'cents_div100'
ORDER BY s.observed_date LIMIT 10;
