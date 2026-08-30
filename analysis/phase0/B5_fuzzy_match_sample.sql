-- B5: sanity-check the fuzzy UPC matches.
-- Sample 30 GTINs shared between a reliable-group vendor and a fuzzy-group vendor and
-- put the two product descriptions side by side.
-- THIS IS A JUDGEMENT CALL. The query selects the sample reproducibly (ordered by a
-- hash, so it is deterministic and not cherry-picked); the verdict on each row is
-- human eyeballing and is recorded as such in the findings doc, not as a metric.
CREATE OR REPLACE TEMP MACRO digits(x) AS regexp_replace(coalesce(x,''), '[^0-9]', '', 'g');
CREATE OR REPLACE TEMP MACRO gtin14(x) AS lpad(digits(x), 14, '0');

CREATE OR REPLACE TEMP VIEW g AS
SELECT gtin14(upc) AS gtin, vendor, product_name, units, brand,
       CASE WHEN vendor IN ('Metro','Galleria','SaveOnFoods','Walmart') THEN 'reliable' ELSE 'fuzzy' END AS tier
FROM product
WHERE length(digits(upc)) BETWEEN 11 AND 14 AND digits(upc) !~ '^0+$';

SELECT r.gtin,
       r.vendor AS reliable_vendor, r.product_name AS reliable_name, r.units AS reliable_units,
       f.vendor AS fuzzy_vendor,    f.product_name AS fuzzy_name,    f.units AS fuzzy_units
FROM g r
JOIN g f ON f.gtin = r.gtin AND r.tier='reliable' AND f.tier='fuzzy'
-- determinism-ok: total order within gtin -- reliable vendor, fuzzy vendor, then both
-- product names. Two rows tying on all four are the same pair of names at the same pair
-- of vendors, i.e. interchangeable for an eyeball sample.
QUALIFY row_number() OVER (PARTITION BY r.gtin
                            ORDER BY r.vendor, f.vendor, r.product_name, f.product_name) = 1
ORDER BY hash(r.gtin)
LIMIT 30;
