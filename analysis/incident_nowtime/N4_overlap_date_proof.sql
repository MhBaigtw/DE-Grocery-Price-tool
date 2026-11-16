-- N4: THE PROOF. Does decoding the new integer as a plain calendar date put every
-- observation on the same date the old string put it on?
-- Incident report section 4. Run with run_incident_query.py: `n` is the new-form archive,
-- `o` the old-form one.
--
-- METHOD. The archive is cumulative, so the old file (to 2026-09-10) and the new file hold
-- the same observations for the whole of the old file's span, once as 'YYYY-MM-DD' and
-- once as YYYYMMDD. There is no row key to join on -- raw has none, and the SQLite rowids
-- are not preserved between releases -- so each DATE is fingerprinted instead: its row
-- count, and the sum of a hash over the content columns. A sum is order-independent, so
-- two dates have the same fingerprint exactly when they hold the same multiset of rows
-- (up to hash collision, which would have to happen on 905 dates at once).
--
-- If the decode shifted dates, the old fingerprint of day D would match the new
-- fingerprint of day D+1 or D-1. Queries 4 and 5 look for exactly that.
--
-- TWO THINGS ARE DELIBERATELY LEFT OUT OF THE FINGERPRINT, each because upstream changed
-- it in the same release and N5 measures it separately:
--   * product_id  -- re-keyed on 361 dates.
--   * the '..' in current_price -- upstream repaired '0..99' to '0.99'. The OLD side is
--     normalised with replace(current_price, '..', '.'). Query 6 shows what happens
--     without that normalisation, so the adjustment is visible and not buried.
--
-- The old date is a strict CAST of the full string, not try_cast and not substr. The new
-- date is the decode from models/stg_price.sql, with the three values that are not dates
-- excluded by value (N2 query 4).

CREATE TEMP TABLE old_dates AS
SELECT CAST(nowtime AS DATE)                                                AS d,
       count(*)                                                             AS n_rows,
       sum(hash(replace(current_price, '..', '.'), old_price, price_per_unit, other)::HUGEINT) AS fp,
       sum(hash(current_price, old_price, price_per_unit, other)::HUGEINT)  AS fp_unnormalised,
       sum(hash(current_price)::HUGEINT)   AS fp_current_price,
       sum(hash(old_price)::HUGEINT)       AS fp_old_price,
       sum(hash(price_per_unit)::HUGEINT)  AS fp_price_per_unit,
       sum(hash(other)::HUGEINT)           AS fp_other,
       sum(hash(product_id)::HUGEINT)      AS fp_product_id
FROM o.raw
WHERE nowtime IS NOT NULL
GROUP BY d;

CREATE TEMP TABLE new_dates AS
SELECT make_date((nowtime // 10000)::INTEGER, ((nowtime // 100) % 100)::INTEGER,
                 (nowtime % 100)::INTEGER)                                  AS d,
       count(*)                                                             AS n_rows,
       sum(hash(current_price, old_price, price_per_unit, other)::HUGEINT)  AS fp,
       sum(hash(current_price)::HUGEINT)   AS fp_current_price,
       sum(hash(old_price)::HUGEINT)       AS fp_old_price,
       sum(hash(price_per_unit)::HUGEINT)  AS fp_price_per_unit,
       sum(hash(other)::HUGEINT)           AS fp_other,
       sum(hash(product_id)::HUGEINT)      AS fp_product_id
FROM n.raw
WHERE nowtime NOT IN (2202, 20222602) AND nowtime <= 20260910
GROUP BY d;

-- 1. The two sides cover the same dates.
SELECT (SELECT count(*) FROM old_dates)        AS old_dates,
       (SELECT sum(n_rows) FROM old_dates)     AS old_rows,
       (SELECT count(*) FROM new_dates)        AS new_dates,
       (SELECT sum(n_rows) FROM new_dates)     AS new_rows,
       (SELECT count(*) FROM old_dates a FULL JOIN new_dates b USING (d)
        WHERE a.d IS NULL OR b.d IS NULL)      AS dates_on_one_side_only;

-- 2. THE RESULT: dates that match on row count AND content, at the SAME date.
SELECT count(*)                                                      AS overlapping_dates,
       count(*) FILTER (WHERE a.n_rows = b.n_rows AND a.fp = b.fp)   AS identical_at_same_date,
       count(*) FILTER (WHERE a.n_rows = b.n_rows AND a.fp = b.fp
                          AND year(d) = 2024)                        AS identical_in_2024,
       count(*) FILTER (WHERE year(d) = 2024)                        AS dates_in_2024
FROM old_dates a JOIN new_dates b USING (d);

-- 3. The dates that do not match, with their counts. These are the 5 formerly undated
--    Loblaws rows upstream gave real dates to (N3 query 3).
SELECT d, a.n_rows AS rows_old, b.n_rows AS rows_new, b.n_rows - a.n_rows AS delta
FROM old_dates a JOIN new_dates b USING (d)
WHERE NOT (a.n_rows = b.n_rows AND a.fp = b.fp)
ORDER BY d;

-- 4. THE SHIFT TEST, +1 day: old day D against new day D+1.
SELECT count(*) AS dates_matching_one_day_later
FROM old_dates a JOIN new_dates b ON b.d = a.d + 1
WHERE a.fp = b.fp;

-- 5. THE SHIFT TEST, -1 day.
SELECT count(*) AS dates_matching_one_day_earlier
FROM old_dates a JOIN new_dates b ON b.d = a.d - 1
WHERE a.fp = b.fp;

-- 6. The adjustment, shown: WITHOUT normalising '..' on the old side, how many dates
--    match, and which column is responsible.
SELECT count(*) FILTER (WHERE a.n_rows = b.n_rows AND a.fp_unnormalised = b.fp)  AS identical_without_normalising,
       count(*) FILTER (WHERE a.fp_current_price  <> b.fp_current_price)          AS dates_current_price_differs,
       count(*) FILTER (WHERE a.fp_old_price      <> b.fp_old_price)              AS dates_old_price_differs,
       count(*) FILTER (WHERE a.fp_price_per_unit <> b.fp_price_per_unit)         AS dates_price_per_unit_differs,
       count(*) FILTER (WHERE a.fp_other          <> b.fp_other)                  AS dates_other_differs,
       count(*) FILTER (WHERE a.fp_product_id     <> b.fp_product_id)             AS dates_product_id_differs
FROM old_dates a JOIN new_dates b USING (d);
