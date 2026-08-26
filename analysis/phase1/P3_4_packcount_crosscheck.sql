-- P3.4 (brief 2.4, folded in): use price_per_unit's IMPLIED pack count as a cross-check
-- ON the unit parser -- not as a field to be validated against it.
--
-- Section 2.4 established that upstream's `price_per_unit` is current_price / pack_count,
-- while stg_price.unit_price is the price of the listing. Naively comparing them measures
-- nothing. But the ratio between them IS a pack count, derived from a completely
-- independent source -- upstream's own arithmetic rather than our text parsing.
--
--     implied_pack = unit_price / price_per_unit_value       (when both are per-each)
--
-- Where that implied count disagrees with the one we parsed from `units`, one of the two
-- is wrong. This is the strongest validation available for the unit parser, because the
-- two derivations share no inputs and no code.
SET threads = 4;

-- Parse upstream's price_per_unit. Restricted to the per-each forms, where an implied
-- pack count is meaningful. A per-100g figure implies nothing about pack size.
CREATE OR REPLACE TEMP TABLE ppu AS
SELECT s.src_rowid, pr.vendor, pr.sku,
       s.unit_price,
       s.price_per_unit_raw,
       p_unit_price(replace(s.price_per_unit_raw, '$', ''))  AS ppu_value,
       p_price_basis(replace(s.price_per_unit_raw, '$', '')) AS ppu_basis,
       sp.pack_count                                          AS parsed_pack,
       sp.unit_parse_confidence,
       sp.units_raw,
       sp.product_name
FROM stg_price s
JOIN product pr    ON pr.id = s.product_id
JOIN stg_product sp ON sp.product_id = s.product_id
WHERE s.price_per_unit_raw IS NOT NULL AND trim(s.price_per_unit_raw) <> ''
  AND s.unit_price IS NOT NULL AND s.unit_price > 0
  AND s.price_basis = 'each'
  AND s.parse_confidence <> 'ambiguous'   -- exclude the 20,578 known-uncertain rows
  AND hash(s.src_rowid) % 25 = 0;         -- deterministic 4% sample; n reported below

CREATE OR REPLACE TEMP TABLE implied AS
SELECT *, unit_price / nullif(ppu_value, 0) AS implied_pack
FROM ppu
WHERE ppu_basis = 'each' AND ppu_value IS NOT NULL AND ppu_value > 0;

-- 1. Denominator first.
SELECT (SELECT count(*) FROM ppu)                             AS sampled_rows,
       (SELECT count(*) FROM implied)                         AS both_per_each,
       (SELECT count(*) FROM implied WHERE parsed_pack IS NOT NULL) AS with_parsed_pack;

-- 2. THE CROSS-CHECK: does the implied pack count match the parsed one?
SELECT vendor,
       count(*)                                                              AS rows,
       count(*) FILTER (WHERE abs(implied_pack - parsed_pack) <= 0.05)       AS agree,
       round(100.0 * count(*) FILTER (WHERE abs(implied_pack - parsed_pack) <= 0.05)
             / count(*), 2)                                                  AS pct_agree,
       round(median(implied_pack), 2)                                        AS median_implied,
       round(median(parsed_pack), 2)                                         AS median_parsed
FROM implied WHERE parsed_pack IS NOT NULL
GROUP BY vendor ORDER BY pct_agree;

-- 3. Where they disagree, WHICH side looks wrong? An implied pack that is a clean
--    integer while the parsed one is 1 suggests the parser missed a multipack.
SELECT CASE
         WHEN abs(implied_pack - round(implied_pack)) <= 0.02 AND round(implied_pack) > 1
              AND parsed_pack = 1 THEN 'a. parser likely MISSED a multipack'
         WHEN abs(implied_pack - 1) <= 0.05 AND parsed_pack > 1
              THEN 'b. parser likely INVENTED a multipack'
         WHEN abs(implied_pack - round(implied_pack)) > 0.02
              THEN 'c. implied pack not an integer -- upstream figure suspect'
         ELSE 'd. other disagreement' END                                    AS diagnosis,
       count(*) AS rows,
       round(median(implied_pack), 3) AS median_implied,
       round(median(parsed_pack), 2)  AS median_parsed
FROM implied
WHERE parsed_pack IS NOT NULL AND abs(implied_pack - parsed_pack) > 0.05
GROUP BY 1 ORDER BY rows DESC;

-- 4. Sample of the most useful case: parser said 1, upstream implies a clean multipack.
SELECT vendor, sku, units_raw, product_name,
       round(unit_price, 2) AS listing_price, price_per_unit_raw,
       round(implied_pack, 2) AS implied_pack, parsed_pack
FROM implied
WHERE parsed_pack = 1 AND implied_pack > 1.5
  AND abs(implied_pack - round(implied_pack)) <= 0.02
ORDER BY hash(src_rowid) LIMIT 15;
