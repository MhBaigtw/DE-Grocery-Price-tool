-- P2.1b: URGENT -- `old_price` is not always a price, and D2 keys its sale definition
-- on `old_price` being non-blank.
--
-- The shape census (P2.1) found 869,497 rows whose old_price is letters only. Samples:
-- 'was', 'Kelloggs', 'Mastro'. D2 counts every non-blank old_price as evidence of a sale.
-- If a brand name in that field creates a phantom sale event, D2's 566,564 is inflated.
-- This measures it rather than assuming either way.
ATTACH IF NOT EXISTS 'hammer2.duckdb' AS s2 (READ_ONLY);
SET threads = 4;

-- 1. What non-numeric values does old_price actually take, and how often?
SELECT lower(trim(r.old_price)) AS value, count(*) AS rows,
       count(DISTINCT p.vendor) AS vendors, string_agg(DISTINCT p.vendor, ',') AS vendor_list
FROM s2.raw r JOIN s2.product p ON p.id = r.product_id
WHERE r.old_price IS NOT NULL AND trim(r.old_price) <> ''
  AND try_cast(r.old_price AS DOUBLE) IS NULL
  AND NOT regexp_matches(r.old_price, '[0-9]')
GROUP BY 1 ORDER BY rows DESC LIMIT 25;

-- 2. Per vendor: how much of "has an old_price" is actually a price?
SELECT p.vendor,
       count(*) FILTER (WHERE r.old_price IS NOT NULL AND trim(r.old_price) <> '')  AS d2_counts_as_sale,
       count(*) FILTER (WHERE r.old_price IS NOT NULL AND trim(r.old_price) <> ''
                          AND NOT regexp_matches(r.old_price, '[0-9]'))             AS NO_DIGITS_AT_ALL,
       round(100.0*count(*) FILTER (WHERE r.old_price IS NOT NULL AND trim(r.old_price) <> ''
                          AND NOT regexp_matches(r.old_price, '[0-9]'))
             / nullif(count(*) FILTER (WHERE r.old_price IS NOT NULL AND trim(r.old_price) <> ''),0),2)
                                                                                    AS pct_junk
FROM s2.raw r JOIN s2.product p ON p.id = r.product_id
GROUP BY p.vendor ORDER BY pct_junk DESC;

-- 3. Does 'was' co-occur with a sale signal in `other`? If yes it is a real sale whose
--    price was lost; if no it is noise. These need different handling.
SELECT lower(trim(r.old_price)) AS old_price_value,
       count(*) AS rows,
       count(*) FILTER (WHERE lower(coalesce(r.other,'')) LIKE '%sale%'
                           OR lower(coalesce(r.other,'')) LIKE '%rollback%') AS with_sale_flag,
       round(100.0*count(*) FILTER (WHERE lower(coalesce(r.other,'')) LIKE '%sale%'
                           OR lower(coalesce(r.other,'')) LIKE '%rollback%')/count(*),2) AS pct_with_sale_flag
FROM s2.raw r
WHERE r.old_price IS NOT NULL AND trim(r.old_price) <> ''
  AND NOT regexp_matches(r.old_price, '[0-9]')
GROUP BY 1 ORDER BY rows DESC LIMIT 12;

-- 4. Cents-form is NOT Loblaws-only. Walmart has its own 'Now$298' variant.
--    Correcting the Phase 1 section 1.5 claim.
SELECT p.vendor,
       count(*) FILTER (WHERE regexp_matches(r.current_price, '^[0-9]+\$$'))         AS bare_cents_form,
       count(*) FILTER (WHERE regexp_matches(r.current_price, '^[Nn]ow\$[0-9]+$'))   AS now_prefixed_cents,
       count(*) FILTER (WHERE regexp_matches(coalesce(r.old_price,''), '^[0-9]+\$$')) AS old_price_cents,
       count(*) FILTER (WHERE regexp_matches(coalesce(r.old_price,''), '^[0-9]+¢$'))  AS old_price_cent_symbol
FROM s2.raw r JOIN s2.product p ON p.id = r.product_id
GROUP BY p.vendor
HAVING bare_cents_form + now_prefixed_cents + old_price_cents + old_price_cent_symbol > 0
ORDER BY 2 DESC;
