-- Junk does not default to a real category (brief 3.3). A blank or sentinel brand must
-- yield an unclassifiable_* verdict, never 'national_brand' -- letting unknowns fall
-- through biases private-label share downward by exactly the invisible amount.
SELECT product_key, vendor, brand_raw, brand_class
FROM {{ ref('stg_product') }}
WHERE brand_class = 'national_brand'
  AND (
        trim(coalesce(brand_raw, '')) = ''
     OR lower(trim(brand_raw)) IN ('out of stock', 'unbranded', 'n/a', 'na',
                                   'none', 'null', 'error', '-', '.')
  )
