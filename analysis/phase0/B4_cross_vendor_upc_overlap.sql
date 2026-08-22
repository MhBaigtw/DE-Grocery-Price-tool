-- ===================================================================================
-- B4: THE HEADLINE NUMBER OF PHASE 0.
-- How many distinct UPCs appear at 2+, 3+, 5+ vendors -- and how many of those are
-- reliable-group-only? That last number is the honest ceiling on trustworthy
-- cross-vendor price comparison.
-- ===================================================================================
--
-- UPC NORMALISATION (this materially changes the answer -- see B4b):
-- Raw upc strings arrive at lengths 4..14. A UPC-A is 12 digits and an EAN-13 is 13;
-- an 11-digit value is almost always a UPC-A with the leading zero stripped. Joining
-- on the raw string therefore MISSES real cross-vendor matches. We normalise to
-- GTIN-14 (strip non-digits, left-pad to 14) and require >= 11 digits of signal;
-- shorter values (1,589 products) cannot identify a product and are excluded.
CREATE OR REPLACE TEMP MACRO digits(x)    AS regexp_replace(coalesce(x,''), '[^0-9]', '', 'g');
CREATE OR REPLACE TEMP MACRO gtin14(x)    AS lpad(digits(x), 14, '0');
CREATE OR REPLACE TEMP MACRO tier(v)      AS
  CASE WHEN v IN ('Metro','Galleria','SaveOnFoods','Walmart') THEN 'reliable' ELSE 'fuzzy' END;

CREATE OR REPLACE TEMP VIEW upc_vendor AS
SELECT DISTINCT gtin14(upc) AS gtin, vendor, tier(vendor) AS tier
FROM product
WHERE length(digits(upc)) BETWEEN 11 AND 14
  AND digits(upc) !~ '^0+$';

CREATE OR REPLACE TEMP VIEW per_gtin AS
SELECT gtin,
       count(DISTINCT vendor)                                     AS n_vendors,
       count(DISTINCT vendor) FILTER (WHERE tier='reliable')      AS n_reliable,
       count(DISTINCT vendor) FILTER (WHERE tier='fuzzy')         AS n_fuzzy,
       string_agg(DISTINCT vendor, ',' ORDER BY vendor)           AS vendors
FROM upc_vendor GROUP BY gtin;

-- 1. HEADLINE: overlap counts, and the reliable-only subset.
SELECT
  count(*)                                                        AS distinct_gtins_total,
  count(*) FILTER (WHERE n_vendors >= 2)                          AS at_2plus_vendors,
  count(*) FILTER (WHERE n_vendors >= 3)                          AS at_3plus_vendors,
  count(*) FILTER (WHERE n_vendors >= 5)                          AS at_5plus_vendors,
  count(*) FILTER (WHERE n_vendors >= 2 AND n_fuzzy = 0)          AS at_2plus_RELIABLE_ONLY,
  count(*) FILTER (WHERE n_vendors >= 3 AND n_fuzzy = 0)          AS at_3plus_RELIABLE_ONLY,
  count(*) FILTER (WHERE n_vendors >= 4 AND n_fuzzy = 0)          AS at_4plus_RELIABLE_ONLY,
  count(*) FILTER (WHERE n_vendors >= 2 AND n_reliable = 0)       AS at_2plus_FUZZY_ONLY,
  count(*) FILTER (WHERE n_vendors >= 2 AND n_reliable > 0 AND n_fuzzy > 0) AS at_2plus_MIXED
FROM per_gtin;

-- 2. Breakdown by exact vendor count and composition.
SELECT n_vendors,
       count(*) AS gtins,
       count(*) FILTER (WHERE n_fuzzy=0)                 AS reliable_only,
       count(*) FILTER (WHERE n_reliable=0)              AS fuzzy_only,
       count(*) FILTER (WHERE n_reliable>0 AND n_fuzzy>0) AS mixed
FROM per_gtin GROUP BY n_vendors ORDER BY n_vendors;

-- 3. Which vendor pairs actually overlap (2-vendor GTINs only).
SELECT vendors AS vendor_pair, count(*) AS shared_gtins,
       CASE WHEN max(n_fuzzy)=0 THEN 'reliable-only' ELSE 'involves fuzzy' END AS pair_tier
FROM per_gtin WHERE n_vendors = 2
GROUP BY vendors ORDER BY shared_gtins DESC LIMIT 30;
