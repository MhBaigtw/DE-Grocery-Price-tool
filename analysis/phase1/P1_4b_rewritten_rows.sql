-- P1.4b: exactly which rows changed on the 4 rewritten dates, and how.
--
-- METHOD NOTE, learned the hard way. The first version of this query joined the two
-- snapshots ON (product_id, nowtime). That is WRONG on this dataset and produced a
-- false alarm: Phase 0 B6 established that one product can appear many times in one
-- day's scrape with CONFLICTING prices (49,329 such product-days at Loblaws alone), so
-- the join cross-products a clean row in one snapshot against a duplicate corrupted row
-- in the other and reports a change that does not exist. Both rows are present in both
-- snapshots.
--
-- The correct comparison is a MULTISET difference: group each snapshot by the full row
-- content, count occurrences, and diff the counts. That is duplicate-safe by
-- construction.
-- P1.4 established the rewrite exists; this identifies it well enough to report
-- upstream and to decide whether it threatens reproducibility.
ATTACH IF NOT EXISTS 'hammer2.duckdb' AS s2 (READ_ONLY);
SET threads = 4;

CREATE OR REPLACE TEMP TABLE dates AS
SELECT unnest([DATE '2026-07-25', DATE '2026-07-26', DATE '2026-07-27', DATE '2026-08-03']) AS d;

CREATE OR REPLACE TEMP TABLE a AS
SELECT try_cast(substr(nowtime,1,10) AS DATE) AS d, product_id, current_price, old_price,
       price_per_unit, other
FROM raw WHERE try_cast(substr(nowtime,1,10) AS DATE) IN (SELECT d FROM dates);

CREATE OR REPLACE TEMP TABLE b AS
SELECT try_cast(substr(nowtime,1,10) AS DATE) AS d, product_id, current_price, old_price,
       price_per_unit, other
FROM s2.raw WHERE try_cast(substr(nowtime,1,10) AS DATE) IN (SELECT d FROM dates);

-- 1. Multiset difference per date: which exact row-contents gained or lost copies.
CREATE OR REPLACE TEMP TABLE ma AS
SELECT d, product_id, coalesce(current_price,'') cp, coalesce(old_price,'') op,
       coalesce(price_per_unit,'') ppu, coalesce(other,'') oth, count(*) AS n
FROM a GROUP BY ALL;

CREATE OR REPLACE TEMP TABLE mb AS
SELECT d, product_id, coalesce(current_price,'') cp, coalesce(old_price,'') op,
       coalesce(price_per_unit,'') ppu, coalesce(other,'') oth, count(*) AS n
FROM b GROUP BY ALL;

SELECT d,
       count(*) FILTER (WHERE coalesce(ma.n,0) < coalesce(mb.n,0)) AS distinct_rows_gained,
       count(*) FILTER (WHERE coalesce(ma.n,0) > coalesce(mb.n,0)) AS distinct_rows_lost,
       sum(greatest(coalesce(mb.n,0)-coalesce(ma.n,0),0))          AS copies_gained,
       sum(greatest(coalesce(ma.n,0)-coalesce(mb.n,0),0))          AS copies_lost
FROM ma FULL OUTER JOIN mb USING (d, product_id, cp, op, ppu, oth)
GROUP BY d ORDER BY d;

-- 2. The actual differing rows, side by side.
SELECT d, product_id, cp, op, oth,
       coalesce(ma.n,0) AS copies_snap1, coalesce(mb.n,0) AS copies_snap2
FROM ma FULL OUTER JOIN mb USING (d, product_id, cp, op, ppu, oth)
WHERE coalesce(ma.n,0) <> coalesce(mb.n,0)
ORDER BY d, product_id LIMIT 40;

-- 3. Same rows, with vendor/product metadata attached.
SELECT x.d, p.vendor, p.product_name, x.cp AS current_price, x.oth AS other,
       x.copies_snap1, x.copies_snap2
FROM (SELECT d, product_id, cp, op, ppu, oth,
             coalesce(ma.n,0) AS copies_snap1, coalesce(mb.n,0) AS copies_snap2
      FROM ma FULL OUTER JOIN mb USING (d, product_id, cp, op, ppu, oth)
      WHERE coalesce(ma.n,0) <> coalesce(mb.n,0)) x
LEFT JOIN s2.product p ON p.id = x.product_id
ORDER BY x.d, p.vendor LIMIT 40;
