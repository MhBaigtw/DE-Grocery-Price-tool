-- A4b: the actual missing-day windows per vendor (gaps of 2+ days), plus the
-- dataset-wide days on which NO vendor reported at all.
CREATE OR REPLACE TEMP VIEW obs AS
SELECT try_cast(substr(r.nowtime,1,10) AS DATE) AS d, p.vendor
FROM raw r JOIN product p ON p.id = r.product_id
WHERE try_cast(substr(r.nowtime,1,10) AS DATE) IS NOT NULL;
CREATE OR REPLACE TEMP VIEW vend_days AS SELECT vendor, d FROM obs GROUP BY 1,2;
CREATE OR REPLACE TEMP VIEW span AS
SELECT vendor, min(d) AS first_day, (SELECT max(d) FROM obs) AS last_day FROM vend_days GROUP BY 1;
CREATE OR REPLACE TEMP VIEW grid AS
SELECT s.vendor, cal.d, (vd.vendor IS NOT NULL) AS present
FROM span s
CROSS JOIN LATERAL (SELECT unnest(generate_series(s.first_day,s.last_day,INTERVAL 1 DAY))::DATE AS d) cal
LEFT JOIN vend_days vd ON vd.vendor=s.vendor AND vd.d=cal.d;
CREATE OR REPLACE TEMP VIEW runs AS
SELECT vendor, present, d,
       row_number() OVER (PARTITION BY vendor ORDER BY d)
     - row_number() OVER (PARTITION BY vendor,present ORDER BY d) AS grp
FROM grid;

-- 1. Every multi-day gap, per vendor.
SELECT vendor, min(d) AS gap_start, max(d) AS gap_end, count(*) AS gap_days
FROM runs WHERE NOT present
GROUP BY vendor, grp HAVING count(*) >= 2
ORDER BY gap_days DESC, gap_start;

-- 2. Days on which the WHOLE dataset is empty (no vendor reported).
WITH allcal AS (
  SELECT unnest(generate_series((SELECT min(d) FROM obs),(SELECT max(d) FROM obs),INTERVAL 1 DAY))::DATE AS d
)
SELECT a.d AS dataset_wide_missing_day
FROM allcal a LEFT JOIN (SELECT DISTINCT d FROM obs) o ON o.d=a.d
WHERE o.d IS NULL ORDER BY a.d;
