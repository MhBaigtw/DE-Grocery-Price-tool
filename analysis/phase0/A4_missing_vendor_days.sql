-- A4: total missing vendor-days, and the longest consecutive gap per vendor.
-- A vendor-day is "expected" from that vendor's first observed date to the dataset's
-- last date. Missing = the vendor has zero rows on a calendar date in that span.
-- Honesty rule #1: a missing day is a hole, not a flat price. This query counts holes.
CREATE OR REPLACE TEMP VIEW obs AS
SELECT try_cast(substr(r.nowtime,1,10) AS DATE) AS d, p.vendor
FROM raw r JOIN product p ON p.id = r.product_id
WHERE try_cast(substr(r.nowtime,1,10) AS DATE) IS NOT NULL;

CREATE OR REPLACE TEMP VIEW vend_days AS
SELECT vendor, d, count(*) AS rows FROM obs GROUP BY 1,2;

CREATE OR REPLACE TEMP VIEW span AS
SELECT vendor, min(d) AS first_day, (SELECT max(d) FROM obs) AS last_day
FROM vend_days GROUP BY 1;

-- Every expected vendor-day, flagged present/missing.
CREATE OR REPLACE TEMP VIEW grid AS
SELECT s.vendor, cal.d,
       (vd.vendor IS NOT NULL) AS present
FROM span s
CROSS JOIN LATERAL (SELECT unnest(generate_series(s.first_day, s.last_day, INTERVAL 1 DAY))::DATE AS d) cal
LEFT JOIN vend_days vd ON vd.vendor = s.vendor AND vd.d = cal.d;

-- Longest consecutive run of missing days per vendor (gaps-and-islands).
CREATE OR REPLACE TEMP VIEW runs AS
SELECT vendor, present, d,
       row_number() OVER (PARTITION BY vendor ORDER BY d)
     - row_number() OVER (PARTITION BY vendor, present ORDER BY d) AS grp
FROM grid;

SELECT g.vendor,
       s.first_day                                            AS first_observed,
       count(*)                                               AS expected_vendor_days,
       count(*) FILTER (WHERE g.present)                      AS present_days,
       count(*) FILTER (WHERE NOT g.present)                  AS missing_days,
       round(100.0*count(*) FILTER (WHERE NOT g.present)/count(*),2) AS pct_missing,
       (SELECT max(cnt) FROM (SELECT count(*) AS cnt FROM runs r
          WHERE r.vendor=g.vendor AND NOT r.present GROUP BY r.grp)) AS longest_gap_days
FROM grid g JOIN span s ON s.vendor=g.vendor
GROUP BY g.vendor, s.first_day
ORDER BY missing_days DESC;
