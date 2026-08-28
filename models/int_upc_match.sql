-- int_upc_match -- cross-vendor product identity, with a confidence tier on every match.
--
-- One row per (gtin, product_key). A product with a usable GTIN that no other vendor
-- carries still appears here, tiered `unmatched`; a product with no usable GTIN appears
-- tiered `no_upc`. Nothing is filtered out, so the denominator is always available
-- (honesty rule 5) and lower tiers stay auditable rather than deleted (honesty rule 2).
--
-- NO `product_id` BELOW STAGING. This model keys on `product_key` only, so the announced
-- upstream `raw.product_id` type change cannot reach any downstream consumer.
-- `scripts/check_layering.py` enforces that mechanically.
--
-- ---------------------------------------------------------------------------------
-- THE TIER OF A MATCH IS THE WEAKEST TIER OF ITS PARTICIPANTS.
--
-- Per-vendor UPC reliability (CLAUDE.md, Known Contamination):
--   vendor_upc   Metro, Galleria, Save-On-Foods  -- straight from the vendor
--   matched_upc  Walmart                          -- exact match against a Walmart source
--   fuzzy        Loblaws, No Frills, T&T, Voila   -- fuzzy-matched, QC'd, known errors
--
-- A Metro<->Loblaws match is not a `vendor_upc` match. It is only as trustworthy as its
-- fuzzy side, so it is tiered `fuzzy`. Taking the strongest participant would let one
-- reliable vendor launder a fuzzy match into a headline number, which is precisely the
-- failure honesty rule 2 exists to prevent.
--
-- GTIN normalisation follows Phase 0 B4: strip non-digits, left-pad to 14, require 11-14
-- digits of signal. Shorter values are PLU-style produce codes -- real, but they identify
-- a commodity rather than a package, so they are tiered `plu_short` and excluded from the
-- packaged-goods basket rather than silently mixed in.
-- ---------------------------------------------------------------------------------
WITH base AS (
    SELECT
        sp.product_key,
        sp.vendor,
        sp.upc_raw,
        regexp_replace(coalesce(sp.upc_raw, ''), '[^0-9]', '', 'g')            AS upc_digits,
        CASE
            WHEN sp.vendor IN ('Metro', 'Galleria', 'SaveOnFoods') THEN 'vendor_upc'
            WHEN sp.vendor = 'Walmart'                             THEN 'matched_upc'
            ELSE                                                        'fuzzy'
        END                                                                     AS vendor_upc_tier
    FROM stg_product sp
),
keyed AS (
    SELECT
        *,
        CASE
            WHEN length(upc_digits) BETWEEN 11 AND 14
             AND NOT regexp_full_match(upc_digits, '^0+$')
            THEN lpad(upc_digits, 14, '0')
        END                                                                     AS gtin14,
        (length(upc_digits) BETWEEN 4 AND 5)                                    AS is_plu_short
    FROM base
),
-- how many vendors, and of which tiers, carry each GTIN
gtin_span AS (
    SELECT
        gtin14,
        count(DISTINCT vendor)                                                  AS n_vendors,
        count(DISTINCT vendor) FILTER (WHERE vendor_upc_tier = 'vendor_upc')    AS n_vendor_upc,
        count(DISTINCT vendor) FILTER (WHERE vendor_upc_tier = 'matched_upc')   AS n_matched_upc,
        count(DISTINCT vendor) FILTER (WHERE vendor_upc_tier = 'fuzzy')         AS n_fuzzy,
        string_agg(DISTINCT vendor, ',' ORDER BY vendor)                        AS vendors_on_gtin
    FROM keyed
    WHERE gtin14 IS NOT NULL
    GROUP BY gtin14
)
SELECT
    k.product_key,
    k.vendor,
    k.gtin14,
    k.upc_raw,
    k.vendor_upc_tier,

    coalesce(g.n_vendors, 0)                                                    AS n_vendors_on_gtin,
    coalesce(g.n_fuzzy, 0)                                                      AS n_fuzzy_vendors_on_gtin,
    g.vendors_on_gtin,

    -- the match tier: weakest participant wins
    CASE
        WHEN k.gtin14 IS NULL AND k.is_plu_short          THEN 'plu_short'
        WHEN k.gtin14 IS NULL                             THEN 'no_upc'
        WHEN coalesce(g.n_vendors, 0) < 2                 THEN 'unmatched'
        WHEN coalesce(g.n_fuzzy, 0) > 0                   THEN 'fuzzy'
        WHEN coalesce(g.n_matched_upc, 0) > 0             THEN 'matched_upc'
        ELSE                                                   'vendor_upc'
    END                                                                         AS match_tier,

    -- the Phase 0 B4 headline set: 2+ vendors, every one of them reliable
    (k.gtin14 IS NOT NULL
     AND coalesce(g.n_vendors, 0) >= 2
     AND coalesce(g.n_fuzzy, 0) = 0)                                            AS is_reliable_only
FROM keyed k
LEFT JOIN gtin_span g USING (gtin14)
