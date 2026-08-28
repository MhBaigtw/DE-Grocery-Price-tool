-- RECONCILIATION: int_upc_match is 1:1 with stg_product. Every product gets a tier,
-- including `no_upc` -- nothing is filtered out, which is what keeps denominators
-- available (honesty rule 5) and lower tiers auditable (honesty rule 2).
SELECT
    (SELECT count(*) FROM {{ ref('stg_product') }})   AS stg_product_rows,
    (SELECT count(*) FROM {{ ref('int_upc_match') }}) AS model_rows
WHERE (SELECT count(*) FROM {{ ref('stg_product') }})
   <> (SELECT count(*) FROM {{ ref('int_upc_match') }})
