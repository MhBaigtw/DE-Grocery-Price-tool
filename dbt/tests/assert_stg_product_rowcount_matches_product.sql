-- RECONCILIATION: stg_product is 1:1 with `product`. No deliberate reduction.
SELECT
    (SELECT count(*) FROM {{ source('hammer', 'product') }}) AS source_rows,
    (SELECT count(*) FROM {{ ref('stg_product') }})          AS model_rows
WHERE (SELECT count(*) FROM {{ source('hammer', 'product') }})
   <> (SELECT count(*) FROM {{ ref('stg_product') }})
