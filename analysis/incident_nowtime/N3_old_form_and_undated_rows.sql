-- N3: what the OLD nowtime was, and what became of the 8 rows that had none.
-- Incident report sections 2 and 4. Run with run_incident_query.py: `n` is the new-form
-- archive, `o` the old-form one.
--
-- The timezone question in the incident brief assumed the old value was a local
-- timestamp, so that a UTC decode could move late-evening rows onto the next day. Query 1
-- is why that cannot have happened: the old value had no time of day at all.

-- 1. Every old value is NULL or exactly 10 characters, 'YYYY-MM-DD'.
SELECT length(nowtime) AS string_length, count(*) AS n_rows,
       min(nowtime) AS min_value, max(nowtime) AS max_value
FROM o.raw
GROUP BY string_length ORDER BY string_length NULLS FIRST;

-- 2. The old rows with no date (Phase 0 E1 found these 8), by SQLite rowid.
SELECT sqlite_rowid, nowtime, current_price, old_price, other, product_id
FROM sqlite_query(o, 'SELECT rowid AS sqlite_rowid, nowtime, current_price, old_price, other, product_id FROM raw
                      WHERE nowtime IS NULL
                         OR nowtime NOT GLOB ''[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]''')
ORDER BY sqlite_rowid;

-- 3. Where those 8 rows went. For each one's (product_id, current_price), count rows per
--    date in the old archive and in the new one over the same period, and show only the
--    dates where the two counts differ. Each row leaves 'NULL' and arrives on exactly one
--    new value: a real date for 5 of them, 2202 or 20222602 for the other 3.
CREATE TEMP TABLE undated AS
SELECT DISTINCT product_id, current_price FROM o.raw WHERE nowtime IS NULL;

WITH old_side AS (
    SELECT r.product_id, r.current_price,
           coalesce(replace(r.nowtime, '-', ''), 'NULL') AS date_digits, count(*) AS n_old
    FROM o.raw r JOIN undated u
      ON u.product_id = r.product_id AND u.current_price = r.current_price
    GROUP BY ALL
),
new_side AS (
    SELECT r.product_id, r.current_price, r.nowtime::VARCHAR AS date_digits, count(*) AS n_new
    FROM n.raw r JOIN undated u
      ON u.product_id = r.product_id AND u.current_price = r.current_price
    WHERE r.nowtime <= 20260910
    GROUP BY ALL
)
SELECT coalesce(a.product_id, b.product_id)       AS product_id,
       coalesce(a.current_price, b.current_price) AS current_price,
       coalesce(a.date_digits, b.date_digits)     AS date_digits,
       coalesce(a.n_old, 0)                       AS rows_old,
       coalesce(b.n_new, 0)                       AS rows_new
FROM old_side a
FULL JOIN new_side b USING (product_id, current_price, date_digits)
WHERE coalesce(a.n_old, 0) <> coalesce(b.n_new, 0)
ORDER BY product_id, current_price, date_digits;
