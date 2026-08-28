-- The OWNED product key.
--
-- Locked decision 5: product identity is derived and owned by us, never borrowed from
-- upstream. Nothing below the staging layer may reference `raw.product_id`, so the
-- announced string->number change stays an ingest-layer event.
--
-- CONSTRUCTION, and why each part is the way it is:
--
--   product_key = md5( vendor || US || sku )                     where sku is present
--   product_key = md5( vendor || US || '#c:' || concatted )      where it is not
--
--   US is chr(31), ASCII UNIT SEPARATOR. It is a delimiter that cannot appear in a
--   vendor name or a SKU, so ('Metro','12'||'34') and ('Metro','1234') cannot collide
--   through concatenation. A '|' would be a guess about the data; chr(31) is a
--   guarantee about the encoding.
--
--   md5 is 128-bit. The earlier analysis queries used DuckDB's 64-bit hash() as a
--   workaround for a statistics bug, and that produced ONE collision in 161,300 keys --
--   which silently merged two distinct products into a single price series and moved the
--   D2 event count by 6. At 64 bits a collision is expected around 2^32 keys by the
--   birthday bound, but the bound is probabilistic: 161,300 keys already hit one. 128
--   bits removes the concern entirely rather than deferring it, and md5's hex output is
--   pure ASCII, which also sidesteps the invalid-UTF-8 statistics bug that motivated the
--   original workaround. Both problems, one construction.
--
--   md5 is used as a CHECKSUM, not for security. Adversarial collisions are not a threat
--   model for a grocery price key.
--
-- The blank-sku branch keys on `concatted` (vendor~name@units^brand), which is unique per
-- product row. It is a weaker identity -- Phase 1 section 1.4 found 12 rows where upstream
-- re-keyed a product from the hash form to the vendor||sku form after recovering a SKU --
-- so `product_key_basis` records which branch was taken and downstream can filter on it.

-- NO PRODUCT ROW MEANS NO KEY.
--
-- `stg_price` LEFT JOINs `product`, because 878,559 rows (snapshot 1) resolve to no
-- product row at all (Phase 0 E2) and an INNER join would silently drop them. Those rows
-- reach this macro with vendor, sku and concatted ALL NULL.
--
-- The first version of `k_source` wrote `coalesce(vendor, '?')`, which turned every one
-- of those rows into the SAME key -- md5('?' || US || '#c:'). That is not a missing key,
-- it is a manufactured identity: 878,559 price rows of unknown provenance sharing one
-- product. It is the same defect section 3.5 spent the whole section removing from the
-- 64-bit hash, at 878,559x the scale, and it was found by the section 5 relationships
-- test rather than by reading the macro.
--
-- `product.vendor` is never NULL and never blank in either snapshot (verified, both), so
-- "vendor IS NULL" means exactly "no product row" and nothing else. Such a row gets a
-- NULL key: unknown identity is representable, and a NULL propagates into a join as an
-- absence rather than as a false match.
CREATE OR REPLACE MACRO k_has_sku(sku) AS (sku IS NOT NULL AND trim(sku) <> '');

CREATE OR REPLACE MACRO k_source(vendor, sku, concatted) AS
  CASE WHEN vendor IS NULL THEN NULL
       WHEN k_has_sku(sku)
       THEN vendor || chr(31) || trim(sku)
       ELSE vendor || chr(31) || '#c:' || coalesce(concatted, '')
  END;

CREATE OR REPLACE MACRO product_key(vendor, sku, concatted) AS
  md5(k_source(vendor, sku, concatted));

CREATE OR REPLACE MACRO product_key_basis(sku) AS
  CASE WHEN k_has_sku(sku) THEN 'vendor_sku' ELSE 'vendor_concatted' END;
