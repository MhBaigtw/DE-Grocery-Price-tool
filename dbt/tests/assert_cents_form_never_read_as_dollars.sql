-- A cents-form price must be divided by 100. '329$' is 3.29, not 329.00.
-- This is the defect class the P2.7 magnitude sweep found: a parse SUCCESS at the wrong
-- magnitude, which no coverage report can see.
--
-- Fails if any cents-normalised row kept the raw integer as its price.
SELECT src_rowid, current_price_raw, normalization, unit_price
FROM {{ ref('stg_price') }}
WHERE normalization IN ('cents_div100', 'now_prefix_cents_div100',
                        'cent_symbol_div100', 'bare_integer_cents')
  AND unit_price IS NOT NULL
  AND unit_price > 100
