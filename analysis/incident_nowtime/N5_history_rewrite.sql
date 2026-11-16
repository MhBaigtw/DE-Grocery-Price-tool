-- N5: what ELSE upstream changed in the same release. None of this is a schema change, so
-- the schema gate cannot see any of it.
-- Incident report section 5; CLAUDE.md "Known contamination". Run with
-- run_incident_query.py: `n` is the new-form archive, `o` the old-form one.
--
-- The comparison is always over the old file's own span (to 2026-09-10), so a difference
-- is a change to history, not new data.

-- 1. current_price repairs, on three sample dates: how many of the old rows carry a
--    current_price text that no longer exists on that date. EXCEPT ALL is a multiset
--    difference, so duplicates are counted properly.
SELECT d AS sample_date,
       (SELECT count(*) FROM o.raw WHERE nowtime = strftime(d, '%Y-%m-%d'))        AS rows_old,
       (SELECT count(*) FROM (
            SELECT current_price FROM o.raw WHERE nowtime = strftime(d, '%Y-%m-%d')
            EXCEPT ALL
            SELECT current_price FROM n.raw
            WHERE nowtime = strftime(d, '%Y%m%d')::BIGINT))                        AS rows_whose_price_text_changed
FROM (VALUES (DATE '2024-02-28'), (DATE '2025-06-15'), (DATE '2026-09-10')) AS t(d)
ORDER BY d;

-- 2. What the repair is, on 2026-09-10: the commonest price texts present only in the old
--    file, and only in the new one.
WITH gone AS (
    SELECT current_price FROM o.raw WHERE nowtime = '2026-09-10'
    EXCEPT ALL
    SELECT current_price FROM n.raw WHERE nowtime = 20260910
),
arrived AS (
    SELECT current_price FROM n.raw WHERE nowtime = 20260910
    EXCEPT ALL
    SELECT current_price FROM o.raw WHERE nowtime = '2026-09-10'
),
ranked AS (
    SELECT 'only in old' AS side, current_price, count(*) AS n_rows FROM gone GROUP BY ALL
    UNION ALL
    SELECT 'only in new', current_price, count(*) FROM arrived GROUP BY ALL
)
SELECT side, current_price, n_rows
FROM ranked
-- determinism-ok: ranked is grouped by (side, current_price), so current_price is unique within a side and breaks every tie in n_rows
QUALIFY row_number() OVER (PARTITION BY side ORDER BY n_rows DESC, current_price) <= 8
ORDER BY side DESC, n_rows DESC, current_price;

-- 3. product_id re-keying: on how many dates the multiset of product_id values changed,
--    and when. Sum-of-hash per date, as in N4.
CREATE TEMP TABLE pid_old AS
SELECT CAST(nowtime AS DATE) AS d, sum(hash(product_id)::HUGEINT) AS fp
FROM o.raw WHERE nowtime IS NOT NULL GROUP BY d;

CREATE TEMP TABLE pid_new AS
SELECT make_date((nowtime // 10000)::INTEGER, ((nowtime // 100) % 100)::INTEGER,
                 (nowtime % 100)::INTEGER) AS d,
       sum(hash(product_id)::HUGEINT) AS fp
FROM n.raw WHERE nowtime NOT IN (2202, 20222602) AND nowtime <= 20260910 GROUP BY d;

SELECT count(*) AS dates_where_product_ids_changed, min(d) AS first_date, max(d) AS last_date
FROM pid_old a JOIN pid_new b USING (d) WHERE a.fp <> b.fp;

SELECT date_trunc('month', d)::DATE AS month, count(*) AS dates_changed
FROM pid_old a JOIN pid_new b USING (d) WHERE a.fp <> b.fp
GROUP BY month ORDER BY month;

-- 4. One date in detail, 2024-03-04: how many rows changed id, and what the ids look like
--    on each side. The only date inspected at this level.
SELECT (SELECT count(*) FROM o.raw WHERE nowtime = '2024-03-04')            AS rows_old,
       (SELECT count(*) FROM (
            SELECT product_id FROM o.raw WHERE nowtime = '2024-03-04'
            EXCEPT ALL
            SELECT product_id FROM n.raw WHERE nowtime = 20240304))         AS rows_whose_id_changed;

SELECT 'only in old' AS side, product_id FROM (
    SELECT product_id FROM o.raw WHERE nowtime = '2024-03-04'
    EXCEPT SELECT product_id FROM n.raw WHERE nowtime = 20240304)
-- determinism-ok: EXCEPT returns distinct product_id values, so ordering by product_id alone is a total order
QUALIFY row_number() OVER (ORDER BY product_id) <= 6
UNION ALL
SELECT 'only in new', product_id FROM (
    SELECT product_id FROM n.raw WHERE nowtime = 20240304
    EXCEPT SELECT product_id FROM o.raw WHERE nowtime = '2024-03-04')
-- determinism-ok: EXCEPT returns distinct product_id values, so ordering by product_id alone is a total order
QUALIFY row_number() OVER (ORDER BY product_id) <= 6
ORDER BY side DESC, product_id;

-- 5. Orphan rows: a raw row whose product_id matches no product row (honesty rule 6).
--    Old archive, new archive over the same period, and the whole new archive.
SELECT (SELECT count(*) FROM o.raw r
        WHERE NOT EXISTS (SELECT 1 FROM o.product p WHERE p.id = r.product_id))   AS orphans_old,
       (SELECT count(*) FROM n.raw r
        WHERE r.nowtime <= 20260910
          AND NOT EXISTS (SELECT 1 FROM n.product p WHERE p.id = r.product_id))   AS orphans_new_same_period,
       (SELECT count(*) FROM n.raw r
        WHERE NOT EXISTS (SELECT 1 FROM n.product p WHERE p.id = r.product_id))   AS orphans_new_whole_archive,
       (SELECT count(*) FROM o.product)                                           AS product_rows_old,
       (SELECT count(*) FROM n.product)                                           AS product_rows_new;
