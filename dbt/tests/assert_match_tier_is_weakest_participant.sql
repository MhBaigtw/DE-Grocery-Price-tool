-- The tier of a match is the WEAKEST tier of its participants. A GTIN carried by any
-- fuzzy-tier vendor must be tiered `fuzzy`, however reliable the other side is.
--
-- Taking the strongest participant would let one reliable vendor launder a fuzzy match
-- into a headline number -- the failure honesty rule 2 exists to prevent. 8,920 products
-- depend on this being enforced.
SELECT product_key, vendor, gtin14, vendor_upc_tier, match_tier, n_fuzzy_vendors_on_gtin
FROM {{ ref('int_upc_match') }}
WHERE n_fuzzy_vendors_on_gtin > 0
  AND n_vendors_on_gtin >= 2
  AND match_tier <> 'fuzzy'
