-- PINNED COUNT: the rows with no observed_date are exactly the ones we know about.
--
-- Why it exists. `stg_price.observed_date` is NULL when `raw.nowtime` is not a real
-- 8-digit calendar date (models/stg_price.sql). That is deliberate: an unreadable date is
-- NULL, kept and counted, the same treatment honesty rules 3 and 6 give a value that
-- cannot be trusted. But "NULL when unreadable" is also exactly what a BROKEN decode
-- produces for every row. On 2026-11-16 there was no test on this column at all, and
-- substr(CAST(nowtime AS VARCHAR), 1, 10) through try_cast would have emptied it and
-- shipped (docs/incident-nowtime-type-change.md). So the count is not left to be
-- whatever it turns out to be. It is committed here, and a build that disagrees fails.
--
-- THE COMMITTED FIGURE: 3 rows on a full load. On the archive upstream published on
-- 2026-11-14 (sha256 3b0fed4c...), of 80,411,080 rows:
--     nowtime 2202       2 rows   (Loblaws)
--     nowtime 20222602   1 row    (Loblaws)
-- These are three of the eight rows that had a NULL nowtime in the old text form
-- (Phase 0 E1); upstream gave the other five real dates in the same release.
-- Source: analysis/incident_nowtime/N2_archive_stats_and_invalid_values.sql.
--
-- On a FILTERED load the figure is 0. The light path (scripts/refresh_light.py) loads
-- Metro and Walmart only and never loads those Loblaws rows. A filtered load is
-- recognised by the `load_filter` row scripts/load_snapshot.py writes to
-- `_snapshot_provenance`; a full load writes no such row.
--
-- Two assertions, because the count alone can be right by accident:
--   1. every NULL-dated row carries one of the committed invalid values -- so a decode
--      that loses even one real date fails, on any load;
--   2. each committed value appears exactly as often as committed -- so upstream
--      repairing these rows, or adding new unreadable ones, is noticed too.
-- When upstream changes the set, this file is updated deliberately, with the new figure
-- and where it came from. It is never loosened to make a build pass.
--
-- A dbt test passes when it returns NO rows.
WITH committed(nowtime_raw, full_load_rows) AS (
    VALUES (2202, 2), (20222602, 1)
),
load AS (
    SELECT count(*) > 0 AS is_filtered
    FROM {{ source('hammer', '_snapshot_provenance') }}
    WHERE k = 'load_filter'
),
found AS (
    SELECT nowtime_raw, count(*) AS n
    FROM {{ ref('stg_price') }}
    WHERE observed_date IS NULL
    GROUP BY nowtime_raw
)
SELECT 'a row outside the committed invalid values has no observed_date' AS problem,
       f.nowtime_raw, f.n AS rows_found, 0 AS rows_committed
FROM found f
WHERE f.nowtime_raw IS NULL
   OR f.nowtime_raw NOT IN (SELECT nowtime_raw FROM committed)
UNION ALL
SELECT 'the count for a committed invalid value has moved',
       c.nowtime_raw, coalesce(f.n, 0),
       CASE WHEN l.is_filtered THEN 0 ELSE c.full_load_rows END
FROM committed c
CROSS JOIN load l
LEFT JOIN found f ON f.nowtime_raw = c.nowtime_raw
WHERE coalesce(f.n, 0) <> CASE WHEN l.is_filtered THEN 0 ELSE c.full_load_rows END
