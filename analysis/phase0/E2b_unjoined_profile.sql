-- E2b: profile the raw rows that do not join to product.
-- Which apparent vendor (from the product_id prefix), and over which dates?
WITH un AS (
  SELECT r.*, try_cast(substr(r.nowtime,1,10) AS DATE) AS d
  FROM raw r
  LEFT JOIN product p ON p.id = r.product_id
  WHERE p.id IS NULL
)
SELECT
  CASE
    WHEN product_id LIKE '%=' THEN '(base64-style id, vendor unknowable)'
    ELSE regexp_extract(product_id, '^([A-Za-z&''\- ]+)', 1)
  END                       AS apparent_vendor_prefix,
  count(*)                  AS unjoined_rows,
  count(DISTINCT product_id) AS distinct_ids,
  min(d)                    AS first_date,
  max(d)                    AS last_date,
  count(DISTINCT d)         AS distinct_dates
FROM un
GROUP BY 1
ORDER BY unjoined_rows DESC;
