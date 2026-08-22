-- G1: publication lag, and why it is NOT a scrape gap.
--
-- Two different quantities, which A4 must not conflate:
--   * scrape gap      : the scraper did not observe a vendor on a day the published
--                       file otherwise covers. A real data hole.
--   * publication lag : the scrape happened, but the file we downloaded was published
--                       before that day's data was added. NOT a hole -- we simply do
--                       not have it yet, and a later snapshot will.
--
-- Within a SINGLE snapshot these are indistinguishable at the trailing edge: a vendor
-- absent on the final day could be a failed extract or an incomplete publication run.
-- The honest treatment is to exclude a trailing window from missing-day accounting and
-- say so, rather than to report unpublished days as missing.
--
-- Snapshot provenance travels inside the DB (_snapshot_provenance), so this query is
-- self-contained: it needs no external file to state which snapshot it describes.

-- 1. Snapshot identity + the two dates whose difference is publication lag.
SELECT
  (SELECT v FROM _snapshot_provenance WHERE k='snapshot_id')                        AS snapshot_id,
  (SELECT v FROM _snapshot_provenance WHERE k='upstream_lastupdated_raw')           AS upstream_lastupdated,
  (SELECT v FROM _snapshot_provenance WHERE k='hammer-3-compressed.zip.downloaded_utc') AS downloaded_utc,
  (SELECT v FROM _snapshot_provenance WHERE k='hammer-3-compressed.zip.sha256')     AS sqlite_sha256,
  max(try_cast(substr(nowtime,1,10) AS DATE))                                       AS max_nowtime,
  date_diff('day',
    max(try_cast(substr(nowtime,1,10) AS DATE)),
    try_cast(substr((SELECT v FROM _snapshot_provenance WHERE k='upstream_lastupdated_raw'),1,10) AS DATE)
  )                                                                                 AS publication_lag_days
FROM raw;

-- 2. Per-vendor trailing edge. A vendor whose last observed day is well before
--    max_nowtime has a genuine trailing gap; one that reaches max_nowtime does not.
SELECT p.vendor,
       max(try_cast(substr(r.nowtime,1,10) AS DATE))                      AS vendor_max_nowtime,
       (SELECT max(try_cast(substr(nowtime,1,10) AS DATE)) FROM raw)      AS dataset_max_nowtime,
       date_diff('day', max(try_cast(substr(r.nowtime,1,10) AS DATE)),
                 (SELECT max(try_cast(substr(nowtime,1,10) AS DATE)) FROM raw))
                                                                          AS days_behind_trailing_edge
FROM raw r JOIN product p ON p.id = r.product_id
GROUP BY p.vendor ORDER BY days_behind_trailing_edge DESC, p.vendor;

-- 3. A4 restated with the trailing edge excluded. If these counts match A4's, then
--    publication lag did not contaminate the missing-day numbers.
--    Trailing window = 3 days, a deliberate margin over the observed lag.
CREATE OR REPLACE TEMP VIEW obs AS
SELECT try_cast(substr(r.nowtime,1,10) AS DATE) AS d, p.vendor
FROM raw r JOIN product p ON p.id=r.product_id
WHERE try_cast(substr(r.nowtime,1,10) AS DATE) IS NOT NULL;
CREATE OR REPLACE TEMP VIEW vend_days AS SELECT vendor, d FROM obs GROUP BY 1,2;
CREATE OR REPLACE TEMP VIEW span AS
SELECT vendor, min(d) AS first_day,
       (SELECT max(d) FROM obs) - INTERVAL 3 DAY AS last_day_pub_safe
FROM vend_days GROUP BY 1;

SELECT s.vendor,
       count(*)                                  AS expected_days_pub_safe,
       count(*) FILTER (WHERE vd.vendor IS NULL) AS missing_days_pub_safe
FROM span s
CROSS JOIN LATERAL (
  SELECT unnest(generate_series(s.first_day, s.last_day_pub_safe::DATE, INTERVAL 1 DAY))::DATE AS d
) cal
LEFT JOIN vend_days vd ON vd.vendor=s.vendor AND vd.d=cal.d
GROUP BY s.vendor ORDER BY missing_days_pub_safe DESC;
