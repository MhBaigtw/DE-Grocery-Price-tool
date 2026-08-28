-- Every price row must reach a verdict: either a unit_price, or an EXPLICIT unparsed /
-- blank offer_type. A row with neither has been silently lost by the parser.
--
-- This is the test that would have caught the original failure mode -- a naive
-- CAST(current_price AS DOUBLE) dropping 1.8% of rows with no error.
SELECT src_rowid, current_price_raw, offer_type, unit_price, parse_confidence
FROM {{ ref('stg_price') }}
WHERE unit_price IS NULL
  AND offer_type NOT IN ('unparsed', 'blank')
