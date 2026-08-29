-- P5.9: characterise the 878,559 price rows that resolve to no product row.
--
-- Phase 0 E2 counted them and profiled them by apparent vendor prefix. It did not settle
-- WHAT THEY ARE, and section 5.1 made that question urgent: these are the rows whose
-- product_key was, until the orphan-key fix, a single manufactured identity shared by all
-- of them. They now carry a NULL key, which is honest but is not a policy. This query
-- produces the evidence for one.
--
-- THREE HYPOTHESES, and the observation that separates them:
--
--   (a) SCRAPE ARTIFACT -- a price was captured for something that was never a catalogue
--       entry. Predicts: orphan ids never appear in `product`, in any snapshot, ever.
--   (b) PRODUCT-TABLE COMPLETENESS GAP -- the catalogue is a snapshot of what is listed
--       TODAY while `raw` is the full history, so a delisted product's price history is
--       orphaned when it drops out of `product`. Predicts: orphan ids stop being observed
--       BEFORE the snapshot date, while joined ids run up to it.
--   (c) UPSTREAM DEFECT -- the id itself is malformed or the join key is broken.
--       Predicts: structurally odd ids (E2's URL-slug case), concentrated in time.
--
-- These are not exclusive; the answer may be a mixture, and the point is to say which
-- part is which rather than to pick a single label.
ATTACH IF NOT EXISTS 'hammer2.duckdb' AS s2 (READ_ONLY);
SET threads = 4;

CREATE OR REPLACE TEMP TABLE orphan AS
SELECT s.src_rowid, s.product_id, s.observed_date, s.current_price_raw,
       s.offer_type, s.unit_price, s.parse_confidence, s.old_price_raw, s.other_raw
FROM stg_price s
WHERE s.product_key IS NULL;

CREATE OR REPLACE TEMP TABLE oid AS
SELECT product_id,
       count(*)              AS rows,
       min(observed_date)    AS first_seen,
       max(observed_date)    AS last_seen,
       count(DISTINCT observed_date) AS days_seen,
       CASE WHEN product_id LIKE '%=' THEN '(base64-style, vendor unknowable)'
            ELSE regexp_extract(product_id, '^([A-Za-z&''\- ]+)', 1) END AS vendor_prefix
FROM orphan GROUP BY 1;

-- 1. HEADLINE: how many rows, ids, and what share of the whole.
SELECT (SELECT count(*) FROM stg_price)                      AS all_price_rows,
       (SELECT count(*) FROM orphan)                         AS orphan_rows,
       round(100.0*(SELECT count(*) FROM orphan)/(SELECT count(*) FROM stg_price), 4) AS pct_of_rows,
       (SELECT count(*) FROM oid)                            AS distinct_orphan_ids,
       (SELECT count(*) FROM product)                        AS product_rows;

-- 2. By vendor prefix, with each vendor's orphan rate against its OWN row count so the
--    concentration is readable (honesty rule 5: report the denominator).
WITH vend AS (
  SELECT sp.vendor, count(*) AS vendor_rows
  FROM stg_price s JOIN stg_product sp USING (product_key) GROUP BY 1
)
SELECT o.vendor_prefix,
       sum(o.rows)                        AS orphan_rows,
       count(*)                           AS distinct_ids,
       v.vendor_rows                      AS joined_rows_same_vendor,
       round(100.0*sum(o.rows)/nullif(v.vendor_rows + sum(o.rows), 0), 3) AS pct_of_vendor,
       min(o.first_seen)                  AS first_date,
       max(o.last_seen)                   AS last_date
FROM oid o LEFT JOIN vend v ON v.vendor = o.vendor_prefix
GROUP BY o.vendor_prefix, v.vendor_rows
ORDER BY orphan_rows DESC;

-- 3. TEMPORAL: do they cluster, or run at a steady background rate? Monthly, with the
--    orphan share of that month's rows -- a spike is a different animal from a constant.
WITH om AS (
  SELECT date_trunc('month', observed_date) AS month, count(*) AS orphan_rows
  FROM orphan GROUP BY 1),
am AS (
  SELECT date_trunc('month', observed_date) AS month, count(*) AS all_rows
  FROM stg_price GROUP BY 1)
SELECT am.month, coalesce(om.orphan_rows, 0) AS orphan_rows, am.all_rows,
       round(100.0*coalesce(om.orphan_rows,0)/nullif(am.all_rows,0), 3) AS pct_of_month
FROM am LEFT JOIN om USING (month) ORDER BY am.month;

-- 4. HYPOTHESIS (b): are orphan ids DELISTED products whose history was orphaned when
--    they left the catalogue? If so their observation window ends well before the
--    snapshot's last date, unlike joined products.
SELECT 'orphan ids'  AS population,
       count(*)                                                       AS ids,
       round(avg(days_seen), 1)                                       AS avg_days_seen,
       round(median(date_diff('day', last_seen,
                              (SELECT max(observed_date) FROM stg_price))), 0) AS median_days_since_last_seen,
       count(*) FILTER (WHERE last_seen >= (SELECT max(observed_date) FROM stg_price) - 7) AS still_seen_last_7d
FROM oid
UNION ALL
SELECT 'joined ids', count(*), round(avg(d), 1),
       round(median(date_diff('day', ls, (SELECT max(observed_date) FROM stg_price))), 0),
       count(*) FILTER (WHERE ls >= (SELECT max(observed_date) FROM stg_price) - 7)
FROM (SELECT product_id, count(DISTINCT observed_date) AS d, max(observed_date) AS ls
      FROM stg_price WHERE product_key IS NOT NULL GROUP BY 1);

-- 5. HYPOTHESIS (b), the decisive test: does upstream ever ADD an orphan id to `product`
--    later? Compare snapshot 1's orphan ids against snapshot 2's product table. If they
--    get registered later this is a publication lag; if none ever are, the catalogue
--    simply does not contain them.
SELECT count(*)                                                        AS orphan_ids_snap1,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM s2.product p WHERE p.id = o.product_id))
                                                                       AS now_in_snapshot2_product,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM s2.product p WHERE p.id = o.product_id))
                                                                       AS still_absent
FROM oid o;

-- 6. HYPOTHESIS (c): id shape. A malformed id is a different defect from a missing
--    catalogue row, and E2 already spotted URL-slug ids on 2026-02-01.
SELECT CASE
         WHEN product_id LIKE '%=' THEN 'base64-style (opaque, no sku)'
         WHEN regexp_full_match(product_id, '^[A-Za-z]+[0-9]+$') THEN 'vendor + numeric sku'
         WHEN regexp_full_match(product_id, '^[A-Za-z]+[A-Za-z0-9]+$') THEN 'vendor + alnum sku'
         WHEN regexp_matches(product_id, '-') THEN 'contains hyphens (URL-slug shaped)'
         ELSE 'other' END                                    AS id_shape,
       count(*)                                              AS ids,
       sum(rows)                                             AS orphan_rows
FROM oid GROUP BY 1 ORDER BY orphan_rows DESC;

-- 7. Are these rows USABLE prices at all? If they parse and look like groceries, the
--    exclusion question is real; if they are junk, it answers itself.
SELECT offer_type,
       count(*)                                              AS rows,
       count(*) FILTER (WHERE unit_price IS NOT NULL)        AS with_unit_price,
       round(median(unit_price), 2)                          AS median_unit_price,
       round(min(unit_price), 2)                             AS min_price,
       round(max(unit_price), 2)                             AS max_price
FROM orphan GROUP BY 1 ORDER BY rows DESC;

-- 8. D2 EXPOSURE: how many orphan rows carry a sale signal? These are the rows a sale
--    analysis would want, and cannot key.
SELECT count(*)                                                        AS orphan_rows,
       count(*) FILTER (WHERE old_price_raw IS NOT NULL
                          AND trim(old_price_raw) <> '')               AS with_old_price,
       count(*) FILTER (WHERE regexp_matches(lower(coalesce(other_raw,'')), 'sale')) AS with_sale_flag,
       count(DISTINCT product_id) FILTER (WHERE regexp_matches(lower(coalesce(other_raw,'')), 'sale'))
                                                                       AS distinct_ids_on_sale
FROM orphan;

-- 9. D4 EXPOSURE: D4's basket is reached through UPC, which lives in `product`. An orphan
--    row has no product row, therefore no UPC, therefore cannot reach the basket at all.
--    Stated as a number rather than asserted.
SELECT (SELECT count(*) FROM orphan)                                   AS orphan_rows,
       (SELECT count(*) FROM orphan o
         WHERE EXISTS (SELECT 1 FROM int_upc_match m
                        WHERE m.product_key IS NOT DISTINCT FROM NULL)) AS reachable_via_upc_model,
       'an orphan row has no product row, hence no upc, hence no gtin' AS why;

-- 10. The E2 URL-slug case, re-checked: is it confined to 2026-02-01?
SELECT observed_date, count(*) AS rows, count(DISTINCT product_id) AS ids
FROM orphan
WHERE regexp_matches(product_id, '-')
GROUP BY 1 ORDER BY rows DESC LIMIT 10;
