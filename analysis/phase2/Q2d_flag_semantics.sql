-- Q2.7: is the 2B sale flag SEMANTICALLY EQUIVALENT across vendors?
--
-- 2B compares sale frequency across vendors. That comparison is only meaningful if the
-- thing being counted means the same thing at each vendor. 2B counts a day as "on sale"
-- when `old_offer_type <> 'blank'` -- i.e. when a struck-out price is present. That is one
-- mechanism. The dataset carries another: free text in `other`.
--
-- A FIRST LOOK AT `other` ALREADY SHOWS THE VOCABULARIES ARE NOT SHARED:
--
--     Voila        SALE                    1,923,684 rows
--     Walmart      Rollback                  353,568   (also: Best seller, Made In Canada,
--                                                       "1000+ bought in past month")
--     Loblaws      sale\n$3.50 MIN 2          86,764   (multibuy promo text)
--     SaveOnFoods  2 for $7                   88,036   (multibuy text, no "sale" word)
--     Galleria     Out of Stock            2,082,759   (availability, not promotion)
--     NoFrills     Low Stock                 285,449   (availability, not promotion)
--
-- So `other` is a per-vendor vocabulary, not a shared flag. It cannot be used as a
-- cross-vendor sale signal directly. What it CAN do is act as an INDEPENDENT WITNESS: if
-- `old_price` presence means "on sale" at every vendor, then at vendors whose `other`
-- carries a promotional token, the two should agree at comparable rates. If they diverge,
-- `old_price` presence is measuring different things in different places and 2B's
-- cross-vendor comparison has to be withdrawn.
SET threads = 2;

-- A deliberately GENEROUS promotional detector over `other`, built from the observed
-- vocabulary above. Generous on purpose: a narrow detector would manufacture disagreement
-- by missing a vendor's dialect, which is the error this query exists to avoid.
-- Availability words (Out of Stock, Low Stock) are explicitly NOT promotional.
CREATE OR REPLACE TEMP MACRO other_says_sale(x) AS
  (x IS NOT NULL AND trim(x) <> ''
   AND regexp_matches(lower(x),
       '(sale|rollback|clearance|deal|save|special|reduced|[0-9]+ *for *\$|was |price *drop)')
   AND NOT regexp_full_match(lower(trim(x)), '(out of stock|low stock|in stock)'));

CREATE OR REPLACE TEMP TABLE sig AS
SELECT sp.vendor,
       (s.old_offer_type <> 'blank')            AS old_present,
       (s.old_unit_price IS NOT NULL)           AS old_has_value,
       other_says_sale(s.other_raw)             AS other_sale,
       (s.other_raw IS NOT NULL AND trim(s.other_raw) <> '') AS other_nonblank
FROM stg_price s JOIN stg_product sp USING (product_key)
WHERE s.parse_confidence <> 'ambiguous'
  AND s.offer_type <> 'unparsed'
  AND s.observed_date >= DATE '2025-01-01';

-- 1. Does `other` carry ANY promotional vocabulary at each vendor? A vendor where it
--    never does cannot witness anything, and must be reported as untestable rather than
--    as agreeing or disagreeing.
SELECT vendor,
       count(*)                                                          AS rows,
       count(*) FILTER (WHERE other_nonblank)                            AS other_populated,
       round(100.0*count(*) FILTER (WHERE other_nonblank)/count(*), 2)   AS pct_other_populated,
       count(*) FILTER (WHERE other_sale)                                AS other_promotional,
       round(100.0*count(*) FILTER (WHERE other_sale)/count(*), 3)       AS pct_other_promotional
FROM sig GROUP BY 1 ORDER BY pct_other_promotional DESC, vendor;

-- 2. THE EQUIVALENCE TEST: the 2x2 of the two mechanisms, per vendor.
--    `both` / `old only` / `other only` / `neither`. If old_price presence is the same
--    signal everywhere, the conditional rates below should be broadly comparable at the
--    vendors where `other` is a usable witness.
SELECT vendor,
       count(*)                                                              AS rows,
       count(*) FILTER (WHERE old_present AND other_sale)                    AS both,
       count(*) FILTER (WHERE old_present AND NOT other_sale)                AS old_only,
       count(*) FILTER (WHERE NOT old_present AND other_sale)                AS other_only,
       round(100.0*count(*) FILTER (WHERE old_present AND other_sale)
             / nullif(count(*) FILTER (WHERE old_present), 0), 2)            AS pct_of_old_confirmed_by_other,
       round(100.0*count(*) FILTER (WHERE old_present AND other_sale)
             / nullif(count(*) FILTER (WHERE other_sale), 0), 2)             AS pct_of_other_confirmed_by_old
FROM sig GROUP BY 1 ORDER BY vendor;

-- 3. The 2B flag rate under each mechanism, side by side. If the two orderings of vendors
--    disagree, the cross-vendor ranking 2B publishes depends on which flag was chosen --
--    which is the definition of a non-equivalent measure.
SELECT vendor,
       round(100.0*count(*) FILTER (WHERE old_present)/count(*), 3)  AS pct_rows_old_present,
       round(100.0*count(*) FILTER (WHERE other_sale)/count(*), 3)   AS pct_rows_other_sale,
       round(100.0*count(*) FILTER (WHERE old_present OR other_sale)/count(*), 3) AS pct_rows_either
FROM sig GROUP BY 1 ORDER BY pct_rows_old_present DESC, vendor;

-- 4. Does `old_price` presence imply a usable VALUE at the same rate everywhere? A vendor
--    where presence and value diverge is flagging something structurally different --
--    this is the `was` population (§2.7 of Phase 1) seen from the equivalence angle.
SELECT vendor,
       count(*) FILTER (WHERE old_present)                                   AS old_present_rows,
       count(*) FILTER (WHERE old_present AND old_has_value)                 AS with_value,
       round(100.0*count(*) FILTER (WHERE old_present AND old_has_value)
             / nullif(count(*) FILTER (WHERE old_present), 0), 2)            AS pct_presence_with_value
FROM sig GROUP BY 1 ORDER BY pct_presence_with_value, vendor;

-- 5. THE VERDICT INPUT: for vendors where `other` is a usable witness (>=0.5% of rows
--    promotional), how far apart are the confirmation rates? A tight cluster supports
--    equivalence; a spread of tens of points refutes it.
SELECT count(*)                                                    AS testable_vendors,
       round(min(pct_conf), 2)                                     AS min_confirmation,
       round(max(pct_conf), 2)                                     AS max_confirmation,
       round(max(pct_conf) - min(pct_conf), 2)                     AS spread_pp
FROM (SELECT vendor,
             100.0*count(*) FILTER (WHERE old_present AND other_sale)
               / nullif(count(*) FILTER (WHERE old_present), 0) AS pct_conf,
             100.0*count(*) FILTER (WHERE other_sale)/count(*)  AS pct_promo
      FROM sig GROUP BY 1)
WHERE pct_promo >= 0.5 AND pct_conf IS NOT NULL;
