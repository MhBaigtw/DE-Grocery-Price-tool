-- R6: which Save-On-Foods store the prices come from, reproducibly.
--
-- WHY THIS FILE EXISTS. The scope correction (findings §9, W6, CLAUDE.md locked decision 3)
-- rests on figures read from Save-On-Foods product URLs: 97% of products at store 2210
-- (Kamloops, BC), 451 at store 1982, 2 at store 6634 (Calgary), and the dates each was in use.
-- They were first computed with throwaway queries that were deleted after running. The
-- published method note, README and findings then carried figures with no committed source --
-- found by the claims sweep, not by any check. This is that source.
--
-- The store id is the `/rsid/NNNN/` segment of `detail_url`; the channel is the path segment
-- before it (`pickup`, `planning`). Which physical store an id belongs to is NOT in the data:
-- 2210 = Westsyde, Kamloops, BC and 6634 = Heritage, Calgary, AB come from the retailer's
-- own store pages and public listings, cited in findings §9. Store 1982 is unidentified.
--
-- Run against hammer.duckdb (snapshot 20260911T200435Z), the build findings §9 describes.
SET threads = 2;

CREATE OR REPLACE TEMP TABLE sof AS
SELECT product_key,
       sku,
       regexp_extract(detail_url, '/rsid/([0-9]+)/', 1)       AS rsid,
       regexp_extract(detail_url, '/sm/([a-z]+)/rsid/', 1)    AS channel
FROM stg_product
WHERE vendor = 'SaveOnFoods';

-- 1. Products per store id and channel, with each id's share of all Save-On-Foods products.
SELECT coalesce(nullif(rsid, ''), '(none)')                         AS rsid,
       coalesce(nullif(channel, ''), '(none)')                      AS channel,
       count(*)                                                     AS products,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2)           AS pct_of_products
FROM sof
GROUP BY 1, 2
ORDER BY products DESC, rsid, channel;

-- 2. When each store id was in use, from the price rows that point at it.
SELECT coalesce(nullif(f.rsid, ''), '(none)')  AS rsid,
       count(DISTINCT f.product_key)           AS products,
       count(*)                                AS price_rows,
       min(s.observed_date)                    AS first_seen,
       max(s.observed_date)                    AS last_seen,
       count(DISTINCT s.observed_date)         AS dates
FROM sof f JOIN stg_price s ON s.product_key = f.product_key
GROUP BY 1
ORDER BY price_rows DESC, rsid;

-- 3. Is store 1982 a second address for store 2210's catalogue, or a separate set? Counted by
--    SKU: a product listed under both ids would appear in both sets.
SELECT (SELECT count(DISTINCT sku) FROM sof WHERE rsid = '1982')                        AS skus_1982,
       (SELECT count(DISTINCT sku) FROM sof WHERE rsid = '1982'
          AND sku IN (SELECT sku FROM sof WHERE rsid = '2210'))                         AS also_under_2210,
       (SELECT count(DISTINCT sku) FROM sof WHERE rsid = '1982'
          AND sku NOT IN (SELECT sku FROM sof WHERE rsid = '2210'))                     AS only_under_1982;
