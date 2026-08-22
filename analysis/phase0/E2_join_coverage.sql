-- E2 (bug / integrity check): do all raw.product_id values resolve to a product row?
-- The upstream docs say join raw.product_id -> product.id. Anything that fails to join
-- is a price with no product metadata: no vendor, no name, no sku, no upc.
-- Also profiles the two observed product_id shapes (base64-style vs vendor-prefixed).
SELECT
  count(*)                                                        AS raw_rows,
  count(p.id)                                                     AS rows_joined,
  count(*) - count(p.id)                                          AS rows_unjoined,
  round(100.0 * (count(*) - count(p.id)) / count(*), 6)           AS pct_unjoined,
  count(*) FILTER (WHERE r.product_id LIKE '%==' OR r.product_id LIKE '%=')
                                                                  AS id_shape_base64ish,
  count(*) FILTER (WHERE NOT (r.product_id LIKE '%==' OR r.product_id LIKE '%='))
                                                                  AS id_shape_other
FROM raw r
LEFT JOIN product p ON p.id = r.product_id;
