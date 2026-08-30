-- P3.3: junk-value handling. Junk does NOT default to a real category.
--
-- Phase 0 F7 measured brand-field coverage and bounded classifier error, but the
-- classifier itself let unknown brands fall through to 'national_brand'. That biases
-- private-label share downward by exactly the amount that is invisible, which is the
-- worst direction for a metric whose purpose is comparing the two groups.
--
-- stg_product.brand_class now has an explicit unclassifiable verdict, split three ways
-- so the REASON is visible: no vendor data at all, blank for this product, or a junk
-- sentinel like 'Out of stock'.
SET threads = 4;

-- 1. Classification per vendor, with every unclassifiable reason separated.
SELECT vendor,
       count(*)                                                        AS products,
       count(*) FILTER (WHERE brand_class = 'private_label')           AS private_label,
       count(*) FILTER (WHERE brand_class = 'national_brand')          AS national_brand,
       count(*) FILTER (WHERE brand_class = 'unclassifiable_blank')    AS unclass_blank,
       count(*) FILTER (WHERE brand_class = 'unclassifiable_junk')     AS unclass_junk,
       count(*) FILTER (WHERE brand_class = 'unclassifiable_no_vendor_data')
                                                                        AS unclass_no_data,
       round(100.0 * count(*) FILTER (WHERE brand_class LIKE 'unclassifiable%') / count(*), 2)
                                                                        AS pct_unclassifiable
FROM stg_product GROUP BY vendor ORDER BY pct_unclassifiable DESC;

-- 2. THE POINT OF THE CHANGE: what private-label share would have been reported if junk
--    and blanks had defaulted to national brand, versus what is reported now?
SELECT vendor,
       count(*) FILTER (WHERE brand_class = 'private_label')                       AS pl,
       -- old behaviour: everything not private label counted as national
       round(100.0 * count(*) FILTER (WHERE brand_class = 'private_label') / count(*), 2)
                                                                                    AS pl_share_if_junk_defaults,
       -- correct behaviour: denominator is only the classifiable population
       round(100.0 * count(*) FILTER (WHERE brand_class = 'private_label')
             / nullif(count(*) FILTER (WHERE brand_class NOT LIKE 'unclassifiable%'), 0), 2)
                                                                                    AS pl_share_classifiable_only,
       round(100.0 * count(*) FILTER (WHERE brand_class = 'private_label')
             / nullif(count(*) FILTER (WHERE brand_class NOT LIKE 'unclassifiable%'), 0), 2)
       - round(100.0 * count(*) FILTER (WHERE brand_class = 'private_label') / count(*), 2)
                                                                                    AS understatement_pp
FROM stg_product GROUP BY vendor
HAVING count(*) FILTER (WHERE brand_class NOT LIKE 'unclassifiable%') > 0
ORDER BY understatement_pp DESC;

-- 3. The junk values themselves, confirmed to land in unclassifiable_junk.
-- determinism-ok: brand_class is a pure function of (vendor, brand_raw) via b_class(),
-- which is the grouping key here, so it is constant within every group.
SELECT vendor, brand_raw, count(*) AS products, any_value(brand_class) AS lands_in
FROM stg_product WHERE brand_class = 'unclassifiable_junk'
GROUP BY vendor, brand_raw ORDER BY products DESC;

-- 4. `units` junk, for symmetry: the 'error' sentinel must not parse to a size.
SELECT units_raw, count(*) AS products, string_agg(DISTINCT vendor, ',') AS vendors,
       count(*) FILTER (WHERE unit_qty IS NOT NULL) AS wrongly_parsed
FROM stg_product
WHERE lower(trim(coalesce(units_raw,''))) IN ('error','n/a','na','none','null','-','.')
GROUP BY units_raw ORDER BY products DESC;
