{{ config(materialized='table') }}

-- Shared body with ../../models/stg_product.sql. See stg_price.sql for why both exist.
SELECT
    product_key(p.vendor, p.sku, p.concatted)   AS product_key,
    product_key_basis(p.sku)                    AS product_key_basis,
    p.id                                        AS product_id,
    p.vendor                                    AS vendor,
    p.sku                                       AS sku,
    p.upc                                       AS upc_raw,
    p.product_name                              AS product_name,
    p.detail_url                                AS detail_url,
    p.concatted                                 AS concatted,

    p.units                                     AS units_raw,
    u_qty(p.units)                              AS unit_qty,
    u_uom(p.units)                              AS unit_uom,
    u_pack_count(p.units)                       AS pack_count,
    u_total_qty(p.units)                        AS total_qty,
    u_confidence(p.units)                       AS unit_parse_confidence,

    p.brand                                     AS brand_raw,
    b_class(p.vendor, p.brand)                  AS brand_class,
    b_class_coarse(p.vendor, p.brand)           AS brand_class_coarse,

    CASE
      WHEN p.vendor IN ('Metro','Galleria','SaveOnFoods') THEN 'vendor_upc'
      WHEN p.vendor = 'Walmart'                            THEN 'matched_upc'
      ELSE                                                      'fuzzy'
    END                                         AS upc_tier
FROM {{ source('hammer', 'product') }} p
