{{ config(materialized='table') }}

-- Body is shared with ../../models/stg_price.sql, which scripts/build_models.py runs on
-- the non-dbt path. Only the source references differ: dbt resolves them through its
-- graph so lineage and tests attach, while the plain path reads the tables directly.
--
-- Contract (Phase 1 brief 2.2):
--   * EVERY row in `raw` produces exactly one row here. Nothing is filtered.
--   * Unparseable text keeps its raw value with offer_type='unparsed'.
--   * A multibuy is NEVER stripped to its total; a cents-form is NEVER read as dollars.
SELECT
    r.rowid                                     AS src_rowid,
    product_key(pr.vendor, pr.sku, pr.concatted) AS product_key,
    r.product_id                                AS product_id,
    r.nowtime                                   AS nowtime_raw,
    try_cast(substr(r.nowtime, 1, 10) AS DATE)  AS observed_date,

    r.current_price                             AS current_price_raw,
    p_offer_type(r.current_price)               AS offer_type,
    p_unit_price_v(pr.vendor, r.current_price)  AS unit_price,
    p_min_qty(r.current_price)                  AS min_qty,
    p_price_basis(r.current_price)              AS price_basis,
    p_basis_stated(r.current_price)             AS price_basis_stated,
    p_normalization_v(pr.vendor, r.current_price) AS normalization,
    p_confidence_v(pr.vendor, r.current_price)  AS parse_confidence,

    r.old_price                                 AS old_price_raw,
    p_offer_type(r.old_price)                   AS old_offer_type,
    p_unit_price_v(pr.vendor, r.old_price)      AS old_unit_price,
    p_price_basis(r.old_price)                  AS old_price_basis,
    p_basis_stated(r.old_price)                 AS old_price_basis_stated,
    p_normalization_v(pr.vendor, r.old_price)   AS old_normalization,
    p_confidence_v(pr.vendor, r.old_price)      AS old_parse_confidence,

    r.price_per_unit                            AS price_per_unit_raw,
    r.other                                     AS other_raw
FROM {{ source('hammer', 'raw') }} r
LEFT JOIN {{ source('hammer', 'product') }} pr ON pr.id = r.product_id
