-- P2.2b: what the parser achieved, with the unparsed set kept countable and inspectable
-- (brief 2.2: "Never drop a row for being unparseable").
SET threads = 4;

-- 1. Headline coverage, current_price.
SELECT count(*)                                                   AS rows,
       count(*) FILTER (WHERE offer_type = 'scalar')              AS scalar,
       count(*) FILTER (WHERE offer_type = 'multibuy')            AS multibuy,
       count(*) FILTER (WHERE offer_type = 'per_weight')          AS per_weight,
       count(*) FILTER (WHERE offer_type = 'blank')               AS blank,
       count(*) FILTER (WHERE offer_type = 'unparsed')            AS unparsed,
       count(*) FILTER (WHERE unit_price IS NOT NULL)             AS has_unit_price,
       round(100.0*count(*) FILTER (WHERE unit_price IS NOT NULL)/count(*),4) AS pct_computable
FROM stg_price;

-- 2. Same for old_price -- D2 depends on this one.
SELECT count(*) FILTER (WHERE old_offer_type <> 'blank')                     AS rows_with_old_price,
       count(*) FILTER (WHERE old_offer_type = 'scalar')                     AS scalar,
       count(*) FILTER (WHERE old_offer_type = 'multibuy')                   AS multibuy,
       count(*) FILTER (WHERE old_offer_type = 'per_weight')                 AS per_weight,
       count(*) FILTER (WHERE old_offer_type = 'unparsed')                   AS unparsed,
       count(*) FILTER (WHERE old_unit_price IS NOT NULL)                    AS has_unit_price
FROM stg_price;

-- 3. Normalisation repairs applied, by kind. Every repair is named and counted; a
--    cents_div100 applied to the wrong shape would be a silent 100x error, so this
--    number is the one to watch across snapshots.
SELECT normalization, count(*) AS rows,
       count(DISTINCT p.vendor) AS vendors, string_agg(DISTINCT p.vendor, ',') AS vendor_list,
       min(unit_price) AS min_price, max(unit_price) AS max_price
FROM stg_price s JOIN product p ON p.id = s.product_id
WHERE normalization IS NOT NULL AND normalization <> 'none'
GROUP BY 1 ORDER BY rows DESC;

-- 4. Parse confidence distribution, per vendor.
SELECT p.vendor,
       count(*)                                                        AS rows,
       count(*) FILTER (WHERE parse_confidence='exact')                AS exact,
       count(*) FILTER (WHERE parse_confidence='derived')              AS derived,
       count(*) FILTER (WHERE parse_confidence='inferred')             AS inferred,
       count(*) FILTER (WHERE parse_confidence='none')                 AS none,
       round(100.0*count(*) FILTER (WHERE unit_price IS NOT NULL)/count(*),3) AS pct_computable
FROM stg_price s JOIN product p ON p.id = s.product_id
GROUP BY p.vendor ORDER BY pct_computable;

-- 5. THE UNPARSED SET -- every remaining shape, verbatim, with counts.
SELECT current_price_raw AS raw_text, count(*) AS rows,
       count(DISTINCT p.vendor) AS vendors, string_agg(DISTINCT p.vendor, ',') AS vendor_list
FROM stg_price s LEFT JOIN product p ON p.id = s.product_id
WHERE s.offer_type = 'unparsed'
GROUP BY 1 ORDER BY rows DESC LIMIT 25;
