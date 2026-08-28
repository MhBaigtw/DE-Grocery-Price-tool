-- RECONCILIATION (brief 5.2): row count in == row count out, with any deliberate
-- reduction named and asserted. Silent row loss is the failure mode this catches.
--
-- stg_price claims to be 1:1 with `raw`. There is no deliberate reduction, so the
-- expected difference is exactly zero.
--
-- A dbt test passes when it returns NO rows, so this returns the mismatch if there is one.
SELECT
    (SELECT count(*) FROM {{ source('hammer', 'raw') }})  AS raw_rows,
    (SELECT count(*) FROM {{ ref('stg_price') }})         AS model_rows,
    (SELECT count(*) FROM {{ source('hammer', 'raw') }})
  - (SELECT count(*) FROM {{ ref('stg_price') }})         AS difference
WHERE (SELECT count(*) FROM {{ source('hammer', 'raw') }})
   <> (SELECT count(*) FROM {{ ref('stg_price') }})
