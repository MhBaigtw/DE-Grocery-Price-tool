-- P1.1: provenance and publication lag for both snapshots, per the G1 rule.
--
-- CLAUDE.md is explicit that publication lag and data gaps are DIFFERENT THINGS and must
-- be separate fields: `nowtime` is when a price was observed, the snapshot timestamp is
-- when we obtained the file containing it. A late upload is not missing scrape data.
-- This records both for each snapshot so the distinction stays measurable.
ATTACH IF NOT EXISTS 'hammer2.duckdb' AS s2 (READ_ONLY);

SELECT 'snapshot_1' AS snapshot,
       (SELECT v FROM _snapshot_provenance    WHERE k='snapshot_id')              AS snapshot_id,
       (SELECT v FROM _snapshot_provenance    WHERE k='upstream_lastupdated_raw') AS upstream_lastupdated,
       (SELECT max(nowtime) FROM raw)                                             AS max_nowtime,
       (SELECT count(*) FROM raw)                                                 AS raw_rows,
       (SELECT count(*) FROM product)                                             AS product_rows,
       date_diff('day', (SELECT max(try_cast(substr(nowtime,1,10) AS DATE)) FROM raw),
                        DATE '2026-08-22')                                        AS publication_lag_days
UNION ALL
SELECT 'snapshot_2',
       (SELECT v FROM s2._snapshot_provenance WHERE k='snapshot_id'),
       (SELECT v FROM s2._snapshot_provenance WHERE k='upstream_lastupdated_raw'),
       (SELECT max(nowtime) FROM s2.raw),
       (SELECT count(*) FROM s2.raw),
       (SELECT count(*) FROM s2.product),
       date_diff('day', (SELECT max(try_cast(substr(nowtime,1,10) AS DATE)) FROM s2.raw),
                        DATE '2026-08-24');

-- Growth between snapshots, at the coarsest level.
SELECT (SELECT count(*) FROM s2.raw)     - (SELECT count(*) FROM raw)     AS raw_rows_added_net,
       (SELECT count(*) FROM s2.product) - (SELECT count(*) FROM product) AS product_rows_added_net,
       (SELECT count(DISTINCT nowtime) FROM s2.raw)
     - (SELECT count(DISTINCT nowtime) FROM raw)                          AS distinct_dates_added;
