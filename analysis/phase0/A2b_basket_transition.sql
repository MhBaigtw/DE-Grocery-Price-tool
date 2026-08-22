-- A2b: locate the small-basket -> full-catalogue transition precisely.
-- CLAUDE.md / upstream docs say the small basket ran Feb 28 - Jul 10/11 2024.
-- This checks that claim against the data instead of assuming it.
CREATE OR REPLACE TEMP VIEW obs AS
SELECT try_cast(substr(r.nowtime,1,10) AS DATE) AS d, p.vendor
FROM raw r JOIN product p ON p.id = r.product_id
WHERE try_cast(substr(r.nowtime,1,10) AS DATE) IS NOT NULL;

-- Daily total rows across all vendors, for every day in May-July 2024,
-- with the day-over-day multiple. The transition is where the multiple explodes.
WITH daily AS (
  SELECT d, count(*) AS rows_all_vendors, count(DISTINCT vendor) AS vendors_present
  FROM obs WHERE d BETWEEN DATE '2024-05-25' AND DATE '2024-07-20'
  GROUP BY 1
)
SELECT d, vendors_present, rows_all_vendors,
       lag(rows_all_vendors) OVER (ORDER BY d) AS prev_day,
       round(rows_all_vendors * 1.0 / nullif(lag(rows_all_vendors) OVER (ORDER BY d),0), 2) AS x_prev_day
FROM daily ORDER BY d;
