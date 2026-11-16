-- N2: what the new integer nowtime values look like across the whole archive, and which
-- of them are not dates. Incident report sections 2 and 3 (proof 1).
-- Run with run_incident_query.py: `n` is the new-form archive, `o` the old-form one.
--
-- This is the source of the figure pinned by
-- dbt/tests/assert_null_observed_date_count_is_pinned.sql: 3 rows, values 2202 (x2) and
-- 20222602 (x1).

-- 1. Shape: rows, NULLs, range, distinct values.
SELECT count(*)                                AS raw_rows,
       count(*) FILTER (WHERE nowtime IS NULL) AS null_nowtime,
       min(nowtime)                            AS min_nowtime,
       max(nowtime)                            AS max_nowtime,
       count(DISTINCT nowtime)                 AS distinct_values
FROM n.raw;

-- 2. Digit count. Epoch seconds would be 10 digits, epoch milliseconds 13; a date written
--    as digits is 8.
SELECT length(nowtime::VARCHAR) AS digits, count(*) AS n_rows
FROM n.raw WHERE nowtime IS NOT NULL
GROUP BY digits ORDER BY digits;

-- 3. The same decode models/stg_price.sql uses, counted: how many rows it dates, how many
--    it leaves NULL, and the range of the dates.
WITH d AS (
    SELECT nowtime,
           CASE WHEN nowtime BETWEEN 10000101 AND 99991231
                     AND (nowtime // 100) % 100 BETWEEN 1 AND 12
                THEN CASE WHEN nowtime % 100 BETWEEN 1 AND day(last_day(make_date(
                                   (nowtime // 10000)::INTEGER,
                                   ((nowtime // 100) % 100)::INTEGER, 1)))
                          THEN make_date((nowtime // 10000)::INTEGER,
                                         ((nowtime // 100) % 100)::INTEGER,
                                         (nowtime % 100)::INTEGER)
                     END
           END AS observed_date
    FROM n.raw
)
SELECT count(*)                                      AS raw_rows,
       count(observed_date)                          AS rows_dated,
       count(*) FILTER (WHERE observed_date IS NULL) AS rows_not_a_date,
       min(observed_date)                            AS first_date,
       max(observed_date)                            AS last_date,
       count(DISTINCT observed_date)                 AS distinct_dates
FROM d;

-- 4. Every row whose nowtime is not a real 8-digit calendar date, in full. rowid here is
--    the SQLite rowid, read through sqlite_query so it is upstream's and not DuckDB's.
SELECT r.sqlite_rowid, r.nowtime, r.current_price, r.old_price, r.other, r.product_id, p.vendor
FROM sqlite_query(n, 'SELECT rowid AS sqlite_rowid, nowtime, current_price, old_price, other, product_id FROM raw
                      WHERE nowtime IS NULL OR nowtime < 10000101 OR nowtime > 99991231
                         OR (nowtime / 100) % 100 NOT BETWEEN 1 AND 12
                         OR nowtime % 100 NOT BETWEEN 1 AND 31') r
LEFT JOIN n.product p ON p.id = r.product_id
ORDER BY r.sqlite_rowid;

-- 5. The 15 newest and the 15 oldest values, verbatim. The table is NOT in date order, so
--    "newest" is by value with the rowid as the tie-break, never by position.
SELECT 'newest' AS which, sqlite_rowid, nowtime, product_id
FROM sqlite_query(n, 'SELECT rowid AS sqlite_rowid, nowtime, product_id FROM raw ORDER BY nowtime DESC, rowid DESC LIMIT 15')
UNION ALL
SELECT 'oldest', sqlite_rowid, nowtime, product_id
FROM sqlite_query(n, 'SELECT rowid AS sqlite_rowid, nowtime, product_id FROM raw ORDER BY nowtime ASC, rowid ASC LIMIT 15')
ORDER BY which, nowtime DESC, sqlite_rowid DESC;

-- 6. First and last rows by POSITION, to show the table is not date-ordered.
SELECT 'first rowids' AS which, sqlite_rowid, nowtime, product_id
FROM sqlite_query(n, 'SELECT rowid AS sqlite_rowid, nowtime, product_id FROM raw ORDER BY rowid ASC LIMIT 15')
UNION ALL
SELECT 'last rowids', sqlite_rowid, nowtime, product_id
FROM sqlite_query(n, 'SELECT rowid AS sqlite_rowid, nowtime, product_id FROM raw ORDER BY rowid DESC LIMIT 15')
ORDER BY which, sqlite_rowid;

-- 7. Rows per value for the newest dates.
SELECT nowtime, count(*) AS n_rows
FROM n.raw WHERE nowtime >= 20261101
GROUP BY nowtime ORDER BY nowtime;

-- 8. PROOF 1. data/provenance/20261105T125727Z.json records raw_rows_source = 79317547
--    for the archive whose extract date was 2026-11-04. If the integer is that date, the
--    rows at or before 20261104 in the cumulative archive are exactly that many.
SELECT count(*)              AS rows_on_or_before_20261104,
       79317547              AS raw_rows_source_in_provenance_20261105,
       count(*) = 79317547   AS exact_match
FROM n.raw WHERE nowtime <= 20261104;
