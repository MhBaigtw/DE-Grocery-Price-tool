-- F4: how far does the D3 "impossibility" argument actually reach?
-- The Phase 0 draft said shrinkflation is "structurally impossible". This tests that
-- claim rather than asserting it, and finds where it has to be narrowed.
--
-- The argument has two populations, and they behave DIFFERENTLY:
--   (a) products with a non-blank sku  -> id = vendor||sku, unique, so exactly one
--       units string can ever be stored. A size change must overwrite in place.
--   (b) products with a BLANK sku      -> id is a hash of `concatted`, which EMBEDS
--       the unit string. A size change therefore produces a DIFFERENT id and a
--       SECOND row. History is not destroyed here -- it is merely unlinkable, because
--       there is no sku to join the two rows on.
SET threads = 4;

-- 1. Population split.
SELECT count(*) AS all_products,
       count(*) FILTER (WHERE trim(coalesce(sku,''))<>'')  AS with_sku_id_is_vendor_sku,
       count(*) FILTER (WHERE trim(coalesce(sku,''))='')   AS blank_sku_id_is_hash,
       round(100.0*count(*) FILTER (WHERE trim(coalesce(sku,''))='')/count(*),2) AS pct_blank_sku
FROM product;

-- 2. Does `concatted` embed the unit? If yes, (b) above holds.
--    Format is  vendor~product_name@units^brand . The units SLOT is compared after
--    stripping case and spaces, because `units` is stored normalised ('1l') while
--    concatted keeps the raw form ('1 L') -- a literal match understates this badly.
SELECT count(*) AS blank_sku_products,
       count(*) FILTER (WHERE trim(coalesce(units,''))='')                     AS units_blank,
       count(*) FILTER (WHERE trim(coalesce(units,''))<>'' AND
              replace(lower(regexp_extract(concatted,'@(.*)\^',1)),' ','')
            = replace(lower(units),' ',''))                                     AS units_slot_matches_units,
       round(100.0*count(*) FILTER (WHERE trim(coalesce(units,''))<>'' AND
              replace(lower(regexp_extract(concatted,'@(.*)\^',1)),' ','')
            = replace(lower(units),' ',''))
            / nullif(count(*) FILTER (WHERE trim(coalesce(units,''))<>''),0),2) AS pct_of_populated
FROM product WHERE trim(coalesce(sku,''))='';

-- 3. The decisive test for population (b): same vendor + same product_name, blank sku,
--    TWO OR MORE distinct unit strings. If these exist, size variation IS recorded for
--    blank-sku products -- just not attributable to one product identity.
SELECT count(*) AS name_groups_with_multiple_units,
       sum(n_rows) AS product_rows_involved
FROM (SELECT vendor, lower(trim(product_name)) AS n, count(*) AS n_rows
      FROM product WHERE trim(coalesce(sku,''))=''
      GROUP BY 1,2 HAVING count(DISTINCT coalesce(units,'')) > 1);

-- 4. A sample, to judge whether those are size changes or just co-existing sizes.
SELECT vendor, n AS product_name, rows, unit_strings FROM (
  SELECT vendor, lower(trim(product_name)) AS n,
         count(*) AS rows,
         string_agg(DISTINCT coalesce(units,'(blank)'), ' | ') AS unit_strings
  FROM product WHERE trim(coalesce(sku,''))=''
  GROUP BY 1,2 HAVING count(DISTINCT coalesce(units,'')) > 1
) ORDER BY hash(vendor||n) LIMIT 12;

-- 5. NOT TESTED, stated as a limitation rather than left implied.
--    "Could a sku be reissued at a different size?" cannot be answered from ONE
--    snapshot: the old row would already have been overwritten. Searching blank-sku
--    `concatted` values for other products' sku strings was tried and abandoned -- it
--    is quadratic over 161,300 x 25,728 and, worse, short numeric skus collide with
--    digits inside product names, so the false-positive rate would swamp any signal.
--    The honest position is that sku reissue is UNTESTED here and needs two snapshots
--    taken apart in time. That is exactly the experiment D3's narrowed claim proposes.

-- 6. THE DECISIVE TEST for population (b).
--    Where a blank-sku name-group carries two unit strings, are the two rows observed
--    CONCURRENTLY (two sizes on the shelf at once) or SEQUENTIALLY (one replaced the
--    other -- which is what a size change would look like)?
--    `product` has no date, so observation windows come from `raw` via product_id.
SET threads = 4;

CREATE OR REPLACE TEMP TABLE blank_windows AS
SELECT p.vendor, lower(trim(p.product_name)) AS n, p.id, p.units,
       min(try_cast(substr(r.nowtime,1,10) AS DATE)) AS first_seen,
       max(try_cast(substr(r.nowtime,1,10) AS DATE)) AS last_seen
FROM product p JOIN raw r ON r.product_id = p.id
WHERE trim(coalesce(p.sku,'')) = ''
GROUP BY 1,2,3,4;

CREATE OR REPLACE TEMP TABLE pairs AS
SELECT a.vendor, a.n,
       a.units AS units_a, b.units AS units_b,
       a.first_seen AS a_first, a.last_seen AS a_last,
       b.first_seen AS b_first, b.last_seen AS b_last,
       (a.first_seen <= b.last_seen AND b.first_seen <= a.last_seen) AS windows_overlap
FROM blank_windows a
JOIN blank_windows b
  ON a.vendor=b.vendor AND a.n=b.n AND a.id < b.id
 AND coalesce(a.units,'') <> coalesce(b.units,'');

SELECT count(*)                                          AS unit_pairs,
       count(*) FILTER (WHERE windows_overlap)           AS concurrent_shelf_sizes,
       count(*) FILTER (WHERE NOT windows_overlap)       AS sequential_candidate_size_change,
       round(100.0*count(*) FILTER (WHERE NOT windows_overlap)/count(*),2) AS pct_sequential
FROM pairs;

-- The sequential ones are the only shrinkflation candidates in the whole dataset.
SELECT vendor, n AS product_name, units_a, units_b, a_last, b_first,
       date_diff('day', a_last, b_first) AS gap_days
FROM pairs WHERE NOT windows_overlap
ORDER BY hash(vendor||n) LIMIT 15;
