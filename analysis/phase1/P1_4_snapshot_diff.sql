-- P1.4: is upstream data append-only, or does published history get REWRITTEN?
--
-- This matters more than it sounds. If history is rewritten between publications, then
-- "the archive" is not a fixed object: a number computed from snapshot 1 may not be
-- reproducible from snapshot 2, and our immutability rule protects our copies but not
-- the meaning of a claim. CLAUDE.md's honesty rule 3 ("every published number is
-- reproducible") quietly assumes append-only. This tests the assumption.
--
-- Method: a per-date fingerprint of each snapshot -- row count, distinct products, and
-- an order-independent checksum over the full row content. Comparing fingerprints for
-- dates present in BOTH snapshots detects any rewrite, without a 72M x 72M join.
ATTACH IF NOT EXISTS 'hammer2.duckdb' AS s2 (READ_ONLY);
SET threads = 4;

CREATE OR REPLACE TEMP TABLE fp1 AS
SELECT try_cast(substr(nowtime,1,10) AS DATE) AS d,
       count(*)                    AS rows,
       count(DISTINCT product_id)  AS products,
       sum(hash(coalesce(product_id,'') || '|' || coalesce(current_price,'') || '|' ||
                coalesce(old_price,'')  || '|' || coalesce(price_per_unit,'') || '|' ||
                coalesce(other,'')))::HUGEINT AS content_checksum
FROM raw WHERE try_cast(substr(nowtime,1,10) AS DATE) IS NOT NULL
GROUP BY 1;

CREATE OR REPLACE TEMP TABLE fp2 AS
SELECT try_cast(substr(nowtime,1,10) AS DATE) AS d,
       count(*)                    AS rows,
       count(DISTINCT product_id)  AS products,
       sum(hash(coalesce(product_id,'') || '|' || coalesce(current_price,'') || '|' ||
                coalesce(old_price,'')  || '|' || coalesce(price_per_unit,'') || '|' ||
                coalesce(other,'')))::HUGEINT AS content_checksum
FROM s2.raw WHERE try_cast(substr(nowtime,1,10) AS DATE) IS NOT NULL
GROUP BY 1;

-- 1. Headline: how many shared dates are byte-identical vs rewritten?
SELECT count(*)                                                          AS dates_in_both,
       count(*) FILTER (WHERE a.rows = b.rows
                          AND a.products = b.products
                          AND a.content_checksum = b.content_checksum)   AS identical,
       count(*) FILTER (WHERE a.rows <> b.rows)                          AS row_count_changed,
       count(*) FILTER (WHERE a.rows = b.rows
                          AND a.content_checksum <> b.content_checksum)  AS same_count_content_changed,
       (SELECT count(*) FROM fp2 WHERE d NOT IN (SELECT d FROM fp1))     AS dates_only_in_snapshot2,
       (SELECT count(*) FROM fp1 WHERE d NOT IN (SELECT d FROM fp2))     AS dates_only_in_snapshot1
FROM fp1 a JOIN fp2 b USING (d);

-- 2. Every date that differs, with the size and direction of the change.
SELECT a.d, a.rows AS rows_snap1, b.rows AS rows_snap2,
       b.rows - a.rows                                   AS row_delta,
       a.products AS products_snap1, b.products AS products_snap2,
       (a.content_checksum <> b.content_checksum)        AS content_changed
FROM fp1 a JOIN fp2 b USING (d)
WHERE a.rows <> b.rows OR a.content_checksum <> b.content_checksum
ORDER BY abs(b.rows - a.rows) DESC, a.d
LIMIT 40;

-- 3. The dates only snapshot 2 has -- the genuinely new scrape days.
SELECT d AS new_date_in_snapshot2, rows, products
FROM fp2 WHERE d NOT IN (SELECT d FROM fp1) ORDER BY d;
