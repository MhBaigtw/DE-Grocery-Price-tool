-- P3.2: is Walmart's real size recoverable, and is recovering it worth the complexity?
--
-- The brief asks for a RECOMMENDATION, not a decision. This gathers the evidence.
--
-- Phase 1 section 2.1 established the cause: `concatted` has the form
-- vendor~product_name@units^brand, and for Walmart the units SLOT holds a copy of the
-- product name while the brand slot sometimes holds price text. So the size is not in
-- `concatted` either -- the extractor never captured it into that field.
--
-- The remaining question is whether the size is present in the PRODUCT NAME, which for
-- Walmart often ends '..., 90 g' or '..., 400g'. If it is, a recovery rule is possible;
-- how often it is decides whether the rule is worth its maintenance cost.
SET threads = 4;

-- A size-suffix pattern on the product name: a trailing quantity + unit, optionally
-- preceded by a comma. Deliberately conservative -- it must not match a size mentioned
-- mid-name ("2% Milk") or a pack count that is not a size.
CREATE OR REPLACE TEMP MACRO name_size(x) AS
  regexp_extract(lower(coalesce(x, '')),
    '([0-9]+(?:\.[0-9]+)?\s?(?:kg|g|ml|l|lb|lbs|oz))\s*$', 1);

-- 1. Confirm the diagnosis: how often does the concatted units slot equal the name?
SELECT vendor,
       count(*)                                                              AS products,
       count(*) FILTER (WHERE lower(replace(regexp_extract(concatted, '@(.*)\^', 1), ' ', ''))
                            = lower(replace(coalesce(product_name,''), ' ', '')))
                                                                              AS units_slot_IS_the_name,
       round(100.0 * count(*) FILTER (WHERE lower(replace(regexp_extract(concatted, '@(.*)\^', 1), ' ', ''))
                            = lower(replace(coalesce(product_name,''), ' ', ''))) / count(*), 2)
                                                                              AS pct
FROM stg_product
GROUP BY vendor ORDER BY pct DESC;

-- 2. RECOVERABILITY: of Walmart products whose `units` failed to parse, how many carry a
--    size suffix on the product name?
SELECT vendor,
       count(*)                                                    AS unparsed_products,
       count(*) FILTER (WHERE name_size(product_name) <> '')       AS size_in_name,
       round(100.0 * count(*) FILTER (WHERE name_size(product_name) <> '') / count(*), 2)
                                                                    AS pct_recoverable
FROM stg_product
WHERE units_raw IS NOT NULL AND trim(units_raw) <> '' AND unit_qty IS NULL
GROUP BY vendor ORDER BY unparsed_products DESC;

-- 3. Would the recovered value be TRUSTWORTHY? Check the rule against Walmart products
--    where `units` DID parse: does the name suffix agree with the parsed size?
--    This is the honest test -- a rule validated only on rows it was built for is not
--    validated at all.
SELECT count(*)                                                              AS control_rows,
       count(*) FILTER (WHERE abs(u_qty(name_size(product_name)) - unit_qty)
                            <= 0.01 * unit_qty)                              AS agrees,
       round(100.0 * count(*) FILTER (WHERE abs(u_qty(name_size(product_name)) - unit_qty)
                            <= 0.01 * unit_qty) / count(*), 2)               AS pct_agree
FROM stg_product
WHERE vendor = 'Walmart' AND unit_qty IS NOT NULL
  AND name_size(product_name) <> '' AND u_qty(name_size(product_name)) IS NOT NULL;

-- 4. Sample, for judgement rather than arithmetic.
SELECT product_name, units_raw, name_size(product_name) AS recovered_size
FROM stg_product
WHERE vendor = 'Walmart' AND units_raw IS NOT NULL AND trim(units_raw) <> ''
  AND unit_qty IS NULL AND name_size(product_name) <> ''
ORDER BY hash(product_id) LIMIT 15;
