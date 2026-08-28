-- A multibuy must be DIVIDED, never stripped to its total. '2/$7.00' is 3.50, not 7.00.
-- Stripping doubles the price and Phase 0 E8 found it would corrupt 679,923 rows.
--
-- Fails if any multibuy row's unit_price equals the total rather than total/qty.
SELECT src_rowid, current_price_raw, min_qty, unit_price
FROM {{ ref('stg_price') }}
WHERE offer_type = 'multibuy'
  AND min_qty > 1
  AND unit_price IS NOT NULL
  AND abs(unit_price - try_cast(regexp_extract(current_price_raw, '/\$([0-9.]+)$', 1) AS DOUBLE)) < 0.001
