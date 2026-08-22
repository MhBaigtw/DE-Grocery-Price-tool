-- A1: Row count of raw, row count of product, full date range of nowtime.
-- Snapshot: 20260822T134045Z
--
-- nowtime is stored as VARCHAR. We report both the raw string form (to expose any
-- format variation) and the parsed date range. We do NOT assume it parses.

-- 1. Distinct nowtime string lengths, to see whether the format is uniform.
SELECT length(nowtime) AS nowtime_strlen,
       count(*)        AS rows,
       min(nowtime)    AS example_min,
       max(nowtime)    AS example_max
FROM raw
GROUP BY 1
ORDER BY 1;

-- 2. Headline shape.
SELECT
  (SELECT count(*) FROM raw)                                       AS raw_rows,
  (SELECT count(*) FROM product)                                   AS product_rows,
  (SELECT count(DISTINCT vendor) FROM product)                     AS vendors,
  (SELECT count(DISTINCT nowtime) FROM raw)                        AS distinct_nowtime_values,
  (SELECT min(nowtime) FROM raw)                                   AS min_nowtime,
  (SELECT max(nowtime) FROM raw)                                   AS max_nowtime,
  (SELECT count(DISTINCT try_cast(substr(nowtime,1,10) AS DATE)) FROM raw) AS distinct_dates,
  (SELECT count(*) FROM raw WHERE try_cast(substr(nowtime,1,10) AS DATE) IS NULL) AS unparseable_nowtime_rows;
