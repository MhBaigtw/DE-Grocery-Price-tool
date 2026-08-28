-- stg_price -- one row per raw price observation, with a computable price.
--
-- Contract (Phase 1 brief 2.2):
--   * EVERY row in `raw` produces exactly one row here. Nothing is filtered.
--     Row count in == row count out. That is asserted, not assumed.
--   * Unparseable text is NOT dropped: it gets offer_type='unparsed' and keeps its
--     raw text, so the unparsed set stays countable and inspectable.
--   * A multibuy is NEVER stripped to its total. '2/$7.00' is 3.50, not 7.00.
--   * A cents-form price is NEVER read as dollars. '329$' is 3.29, not 329.00.
--
-- Shape: single SELECT, no side effects, so it drops into dbt as a staging model
-- unchanged when Section 5 wires up the test framework.
--
-- The LEFT JOIN to product supplies `vendor`, which the Walmart bare-integer-cents
-- rule needs. LEFT, not INNER: 878,559 rows resolve to no product (Phase 0 E2) and an
-- inner join would silently drop them, breaking the 1:1 contract above.
--
-- `product_id` appears here because this IS the staging layer. Per brief 4.1 it must not
-- appear below it -- Section 4's owned key replaces it for everything downstream, so the
-- announced upstream type change stays an ingest-layer event.
SELECT
    r.rowid                                   AS src_rowid,
    product_key(pr.vendor, pr.sku, pr.concatted) AS product_key,
    r.product_id                              AS product_id,
    r.nowtime                                 AS nowtime_raw,
    try_cast(substr(r.nowtime, 1, 10) AS DATE) AS observed_date,

    -- current price
    r.current_price                           AS current_price_raw,
    p_offer_type(r.current_price)             AS offer_type,
    p_unit_price_v(pr.vendor, r.current_price)  AS unit_price,
    p_min_qty(r.current_price)                AS min_qty,
    p_price_basis(r.current_price)            AS price_basis,
    p_basis_stated(r.current_price)           AS price_basis_stated,
    p_normalization_v(pr.vendor, r.current_price) AS normalization,
    p_confidence_v(pr.vendor, r.current_price)  AS parse_confidence,

    -- old (struck-out) price, parsed by the same rules
    r.old_price                               AS old_price_raw,
    p_offer_type(r.old_price)                 AS old_offer_type,
    p_unit_price_v(pr.vendor, r.old_price)      AS old_unit_price,
    p_price_basis(r.old_price)                AS old_price_basis,
    p_basis_stated(r.old_price)               AS old_price_basis_stated,
    p_normalization_v(pr.vendor, r.old_price)   AS old_normalization,
    p_confidence_v(pr.vendor, r.old_price)      AS old_parse_confidence,

    -- carried through unparsed; `other` is free text and is not this model's job
    r.price_per_unit                          AS price_per_unit_raw,
    r.other                                   AS other_raw
FROM raw r
LEFT JOIN product pr ON pr.id = r.product_id
