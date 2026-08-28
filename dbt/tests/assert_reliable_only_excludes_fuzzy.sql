-- `is_reliable_only` is the flag D4's headline basket filters on. It must never be true
-- for a GTIN that any fuzzy-tier vendor also carries.
SELECT product_key, vendor, gtin14, n_vendors_on_gtin, n_fuzzy_vendors_on_gtin
FROM {{ ref('int_upc_match') }}
WHERE is_reliable_only
  AND (n_fuzzy_vendors_on_gtin > 0 OR n_vendors_on_gtin < 2)
