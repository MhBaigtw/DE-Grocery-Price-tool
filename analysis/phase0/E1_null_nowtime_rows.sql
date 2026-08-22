-- E1 (bug): rows in `raw` with a NULL nowtime -- price observations with no date.
-- These cannot be placed on a timeline and are silently dropped by any date filter.
-- Show every one of them, joined to product metadata.
SELECT r.rowid AS raw_rowid, r.nowtime, r.current_price, r.old_price,
       r.price_per_unit, r.other, r.product_id,
       p.vendor, p.product_name, p.units, p.sku, p.upc
FROM raw r
LEFT JOIN product p ON p.id = r.product_id
WHERE r.nowtime IS NULL
   OR try_cast(substr(r.nowtime,1,10) AS DATE) IS NULL;
