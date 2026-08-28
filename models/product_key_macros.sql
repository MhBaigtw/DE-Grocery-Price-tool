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

CREATE OR REPLACE MACRO k_has_sku(sku) AS (sku IS NOT NULL AND trim(sku) <> '');

CREATE OR REPLACE MACRO k_source(vendor, sku, concatted) AS
  CASE WHEN k_has_sku(sku)
       THEN coalesce(vendor, '?') || chr(31) || trim(sku)
       ELSE coalesce(vendor, '?') || chr(31) || '#c:' || coalesce(concatted, '')
  END;

CREATE OR REPLACE MACRO product_key(vendor, sku, concatted) AS
  md5(k_source(vendor, sku, concatted));

CREATE OR REPLACE MACRO product_key_basis(sku) AS
  CASE WHEN k_has_sku(sku) THEN 'vendor_sku' ELSE 'vendor_concatted' END;
