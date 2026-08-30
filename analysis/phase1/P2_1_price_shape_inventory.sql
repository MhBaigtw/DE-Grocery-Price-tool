-- P2.1: enumerate every distinct SHAPE that current_price and old_price take, with
-- counts, per vendor. This is the input to the parser design in P2.2 -- we do not get to
-- choose which shapes exist, only whether we handle them.
--
-- Method: collapse each value to a signature by replacing digit runs with 'N' and letter
-- runs with 'a'. '3.29' -> 'N.N'; '2/$7.00' -> 'N/$N.N'; '329$' -> 'N$';
-- '1.99/100g' -> 'N.N/Na'. Signatures are what a parser must dispatch on.
--
-- Run against snapshot 2 (the superset). Snapshot 1 is cross-checked at the end so the
-- parser is not tuned to one publication.
ATTACH IF NOT EXISTS 'hammer2.duckdb' AS s2 (READ_ONLY);
SET threads = 4;

-- NOTE: letters are collapsed BEFORE digits. Doing it the other way round replaces digit
-- runs with 'N', then the letter pass rewrites that 'N' to 'a', and every shape collapses
-- to the same signature -- which is the bug the first version of this query had.
CREATE OR REPLACE TEMP MACRO sig(x) AS
  regexp_replace(
    regexp_replace(
      regexp_replace(replace(replace(coalesce(x,''), chr(10), '<NL>'), chr(13), ''),
                     '[A-Za-z]+', 'a', 'g'),
      '[0-9]+', 'N', 'g'),
    ' +', ' ', 'g');

CREATE OR REPLACE TEMP TABLE px AS
SELECT p.vendor, r.current_price AS cp, r.old_price AS op
FROM s2.raw r JOIN s2.product p ON p.id = r.product_id;

-- 1. current_price: overall shape census, scalar included.
SELECT sig(cp) AS shape,
       count(*) AS rows,
       round(100.0*count(*)/sum(count(*)) OVER (),4) AS pct,
       count(DISTINCT vendor) AS vendors,
       min(cp) AS example_a, max(cp) AS example_b,
       (try_cast(min(cp) AS DOUBLE) IS NOT NULL) AS casts_cleanly
FROM px WHERE cp IS NOT NULL AND trim(cp) <> ''
GROUP BY 1 ORDER BY rows DESC LIMIT 40;

-- 2. current_price: non-scalar shapes only, per vendor -- who must the parser serve?
SELECT vendor, sig(cp) AS shape, count(*) AS rows, min(cp) AS example
FROM px
WHERE cp IS NOT NULL AND trim(cp) <> '' AND try_cast(cp AS DOUBLE) IS NULL
GROUP BY 1,2 ORDER BY rows DESC LIMIT 40;

-- 3. old_price: same census. old_price drives D2, so its shapes matter as much.
SELECT sig(op) AS shape, count(*) AS rows,
       count(DISTINCT vendor) AS vendors, min(op) AS example,
       (try_cast(min(op) AS DOUBLE) IS NOT NULL) AS casts_cleanly
FROM px WHERE op IS NOT NULL AND trim(op) <> ''
GROUP BY 1 ORDER BY rows DESC LIMIT 25;

-- 4. Coverage summary: what fraction of rows each broad family accounts for.
SELECT
  count(*)                                                                       AS price_rows,
  count(*) FILTER (WHERE try_cast(cp AS DOUBLE) IS NOT NULL)                     AS scalar,
  count(*) FILTER (WHERE regexp_matches(cp, '^[0-9]+/\$[0-9.]+$'))               AS multibuy,
  count(*) FILTER (WHERE regexp_matches(cp, '^[0-9.]+/[0-9]*[a-z]+$'))           AS per_weight,
  count(*) FILTER (WHERE regexp_matches(cp, '^[0-9]+\$$'))                       AS cents_form,
  count(*) FILTER (WHERE cp IS NULL OR trim(cp) = '')                            AS blank,
  count(*) FILTER (WHERE try_cast(cp AS DOUBLE) IS NULL AND trim(coalesce(cp,'')) <> ''
                     AND NOT regexp_matches(cp, '^[0-9]+/\$[0-9.]+$')
                     AND NOT regexp_matches(cp, '^[0-9.]+/[0-9]*[a-z]+$')
                     AND NOT regexp_matches(cp, '^[0-9]+\$$'))                   AS still_unhandled
FROM px;

-- 5. Cross-check: do the same shape families hold in snapshot 1? A parser tuned to one
--    publication is a parser that breaks on the next one.
SELECT 'snapshot_1' AS snap,
       count(*) FILTER (WHERE try_cast(current_price AS DOUBLE) IS NOT NULL)                  AS scalar,
       count(*) FILTER (WHERE regexp_matches(current_price, '^[0-9]+/\$[0-9.]+$'))            AS multibuy,
       count(*) FILTER (WHERE regexp_matches(current_price, '^[0-9.]+/[0-9]*[a-z]+$'))        AS per_weight,
       count(*) FILTER (WHERE regexp_matches(current_price, '^[0-9]+\$$'))                    AS cents_form
FROM raw
UNION ALL
SELECT 'snapshot_2',
       count(*) FILTER (WHERE try_cast(current_price AS DOUBLE) IS NOT NULL),
       count(*) FILTER (WHERE regexp_matches(current_price, '^[0-9]+/\$[0-9.]+$')),
       count(*) FILTER (WHERE regexp_matches(current_price, '^[0-9.]+/[0-9]*[a-z]+$')),
       count(*) FILTER (WHERE regexp_matches(current_price, '^[0-9]+\$$'))
FROM s2.raw;
