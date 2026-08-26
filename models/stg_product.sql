-- stg_product -- one row per product, with a parsed size and a brand class.
--
-- Contract:
--   * EVERY row in `product` produces exactly one row here. Nothing is filtered.
--   * An unparseable size yields NULL quantity with unit_parse_confidence='none' and
--     keeps its raw text. Nothing defaults to a fabricated 1.
--   * Junk brand values yield 'unclassifiable_*', NEVER 'national_brand' (brief 3.3).
--
-- `product.id` appears here because this IS the staging layer. Section 4's owned key
-- replaces it downstream, so the announced upstream type change stays an ingest event.
SELECT
    p.id                                        AS product_id,
    p.vendor                                    AS vendor,
    p.sku                                       AS sku,
    p.upc                                       AS upc_raw,
    p.product_name                              AS product_name,
    p.detail_url                                AS detail_url,
    p.concatted                                 AS concatted,

    -- size, parsed
    p.units                                     AS units_raw,
    u_qty(p.units)                              AS unit_qty,
    u_uom(p.units)                              AS unit_uom,
    u_pack_count(p.units)                       AS pack_count,
    u_total_qty(p.units)                        AS total_qty,
    u_confidence(p.units)                       AS unit_parse_confidence,

    -- brand, classified
    p.brand                                     AS brand_raw,
    b_class(p.vendor, p.brand)                  AS brand_class,
    b_class_coarse(p.vendor, p.brand)           AS brand_class_coarse,

    -- UPC tier, per CLAUDE.md's Known Contamination section. Carried here so downstream
    -- filters on a column rather than re-deriving a vendor list every time.
    CASE
      WHEN p.vendor IN ('Metro','Galleria','SaveOnFoods') THEN 'vendor_upc'
      WHEN p.vendor = 'Walmart'                            THEN 'matched_upc'
      ELSE                                                      'fuzzy'
    END                                         AS upc_tier
FROM product p
