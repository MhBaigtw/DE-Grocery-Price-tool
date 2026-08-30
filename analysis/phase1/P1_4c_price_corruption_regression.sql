-- P1.4c: URGENT. The rewrite in P1.4b is not a correction -- it is a REGRESSION.
--
-- On the 4 rewritten dates, snapshot 1 holds '3.29' and snapshot 2 holds '329$' for the
-- same product on the same day. The decimal point is gone and a trailing '$' is appended.
-- That is a new, malformed price shape that did not exist in snapshot 1.
--
-- Two things must be measured before anything else in Phase 1:
--   (a) how many rows carry the malformed 'NNN$' shape, in each snapshot
--   (b) whether it is confined to those 4 dates or spreading through the archive
-- Because if a republish can silently corrupt already-published history, then our
-- immutability rule protects our copies but NOT the reproducibility of any claim built
-- on a newer snapshot.
ATTACH IF NOT EXISTS 'hammer2.duckdb' AS s2 (READ_ONLY);
SET threads = 4;

-- 1. Magnitude of the malformed shape in each snapshot.
SELECT 'snapshot_1' AS snapshot,
       count(*) FILTER (WHERE regexp_matches(current_price, '^[0-9]+\$$'))        AS malformed_NNN_dollar,
       count(*) FILTER (WHERE try_cast(current_price AS DOUBLE) IS NULL
                          AND trim(coalesce(current_price,'')) <> '')             AS all_non_scalar,
       count(*)                                                                    AS raw_rows
FROM raw
UNION ALL
SELECT 'snapshot_2',
       count(*) FILTER (WHERE regexp_matches(current_price, '^[0-9]+\$$')),
       count(*) FILTER (WHERE try_cast(current_price AS DOUBLE) IS NULL
                          AND trim(coalesce(current_price,'')) <> ''),
       count(*)
FROM s2.raw;

-- 2. Is it confined to the 4 known dates, or spreading?
SELECT try_cast(substr(nowtime,1,10) AS DATE) AS d,
       count(*) AS malformed_rows,
       count(DISTINCT product_id) AS products
FROM s2.raw
WHERE regexp_matches(current_price, '^[0-9]+\$$')
GROUP BY 1 ORDER BY 1;

-- 3. Which vendors, and does old_price have the same corruption?
SELECT p.vendor,
       count(*) FILTER (WHERE regexp_matches(r.current_price, '^[0-9]+\$$')) AS malformed_current_price,
       count(*) FILTER (WHERE regexp_matches(r.old_price,     '^[0-9]+\$$')) AS malformed_old_price
FROM s2.raw r JOIN s2.product p ON p.id = r.product_id
WHERE regexp_matches(r.current_price, '^[0-9]+\$$')
   OR regexp_matches(r.old_price,     '^[0-9]+\$$')
GROUP BY 1 ORDER BY 2 DESC;

-- 4. Is the corruption REVERSIBLE? '329$' should be '3.29' -- i.e. value/100.
--    Check against the same product's price on adjacent, uncorrupted days.
SELECT b.product_id, b.nowtime, b.current_price AS corrupted_snap2,
       a.current_price AS original_snap1,
       try_cast(replace(b.current_price,'$','') AS DOUBLE)/100.0 AS recovered_by_div100,
       (try_cast(replace(b.current_price,'$','') AS DOUBLE)/100.0
        = try_cast(a.current_price AS DOUBLE))                   AS recovery_matches_original
FROM s2.raw b
JOIN raw a ON a.product_id = b.product_id AND a.nowtime = b.nowtime
WHERE regexp_matches(b.current_price, '^[0-9]+\$$')
ORDER BY b.product_id, b.nowtime
LIMIT 20;

-- 5. Recovery rate across ALL corrupted rows that exist in both snapshots.
SELECT count(*) AS corrupted_rows_with_snapshot1_original,
       count(*) FILTER (WHERE try_cast(replace(b.current_price,'$','') AS DOUBLE)/100.0
                            = try_cast(a.current_price AS DOUBLE))          AS recoverable_by_div100,
       round(100.0*count(*) FILTER (WHERE try_cast(replace(b.current_price,'$','') AS DOUBLE)/100.0
                            = try_cast(a.current_price AS DOUBLE))/count(*),2) AS pct_recoverable
FROM s2.raw b
JOIN raw a ON a.product_id = b.product_id AND a.nowtime = b.nowtime
WHERE regexp_matches(b.current_price, '^[0-9]+\$$');
