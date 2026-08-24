-- P2.4: now that prices parse, how trustworthy is upstream's `price_per_unit`?
--
-- Phase 0 C2 could only test rows where a naive cast worked, and flagged the field as
-- untrustworthy on CLAUDE.md's say-so. With stg_price deriving a unit price for 100% of
-- rows, the comparison can be made on a proper denominator.
--
-- Comparison is made on the CANONICAL basis (per_100g / per_100ml / each), so a vendor
-- quoting $/kg and an upstream field quoting $/100g are not counted as disagreeing when
-- they are the same price.
SET threads = 4;

-- SAMPLED, and labelled as such. Parsing all 56M price_per_unit values through the full
-- macro stack costs many minutes for a question a sample answers just as well. The sample
-- is deterministic (hash of the source rowid, not random) so the number is reproducible,
-- and its size is reported alongside every percentage.
CREATE OR REPLACE TEMP TABLE ppu AS
SELECT s.src_rowid, p.vendor,
       s.price_per_unit_raw                                       AS ppu_raw,
       p_unit_price(replace(s.price_per_unit_raw, '$', ''))        AS ppu_value,
       p_price_basis(replace(s.price_per_unit_raw, '$', ''))       AS ppu_basis,
       s.unit_price                                                AS our_price,
       s.price_basis                                               AS our_basis,
       s.offer_type
FROM stg_price s JOIN product p ON p.id = s.product_id
WHERE s.price_per_unit_raw IS NOT NULL AND trim(s.price_per_unit_raw) <> ''
  AND hash(s.src_rowid) % 25 = 0;    -- deterministic 4% sample

-- 1. How much is comparable at all? Denominator stated explicitly.
SELECT count(*)                                                          AS rows_with_ppu,
       count(*) FILTER (WHERE ppu_value IS NOT NULL)                     AS ppu_parsed,
       count(*) FILTER (WHERE ppu_value IS NOT NULL AND our_price IS NOT NULL
                          AND ppu_basis = our_basis)                     AS comparable_same_basis,
       count(*) FILTER (WHERE ppu_value IS NOT NULL AND our_price IS NOT NULL
                          AND ppu_basis <> our_basis)                    AS different_basis
FROM ppu;

-- 2. Agreement rate per vendor, on the comparable subset.
SELECT vendor,
       count(*)                                                                    AS comparable_rows,
       count(*) FILTER (WHERE abs(ppu_value-our_price) <= 0.01*abs(our_price))     AS agree_within_1pct,
       round(100.0*count(*) FILTER (WHERE abs(ppu_value-our_price) <= 0.01*abs(our_price))/count(*),2)
                                                                                   AS pct_agree,
       round(100.0*count(*) FILTER (WHERE abs(ppu_value-our_price) > 0.10*abs(our_price))/count(*),2)
                                                                                   AS pct_disagree_gt_10pct,
       round(median(abs(ppu_value-our_price)/nullif(abs(our_price),0))*100,3)       AS median_abs_pct_diff
FROM ppu
WHERE ppu_value IS NOT NULL AND our_price IS NOT NULL AND ppu_basis = our_basis AND our_price > 0
GROUP BY vendor ORDER BY pct_agree;

-- 3. Ten disagreements for manual adjudication -- which side is right?
SELECT vendor, offer_type, ppu_raw, round(ppu_value,4) AS upstream_says,
       round(our_price,4) AS we_say, our_basis,
       round(100.0*abs(ppu_value-our_price)/nullif(our_price,0),1) AS pct_diff
FROM ppu
WHERE ppu_value IS NOT NULL AND our_price IS NOT NULL AND ppu_basis = our_basis
  AND our_price > 0 AND abs(ppu_value-our_price) > 0.10*abs(our_price)
ORDER BY hash(src_rowid) LIMIT 10;
