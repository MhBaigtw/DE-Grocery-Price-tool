-- Unit parsing macros: `units` text -> (quantity, unit, pack_count).
--
-- Target shape, per the Phase 1 brief 3.1:
--   u_qty        the size of ONE item          ('2 x 500 mL' -> 500)
--   u_uom        canonical unit                 g | ml | count
--   u_pack_count how many items in the listing  ('2 x 500 mL' -> 2)
--   u_total_qty  qty * pack_count               (the size you actually buy)
--
-- Keeping per-item size and pack count SEPARATE matters: '2 x 500 mL' and '1 L' are the
-- same total volume but not the same product, and a shopper comparing unit prices needs
-- the 500 while a shopper comparing pack sizes needs the 2. Collapsing them at parse time
-- throws away a distinction that cannot be recovered downstream.
--
-- Every failure is explicit. Nothing defaults to 1 silently -- an unparsed unit yields
-- NULL quantity with u_confidence='none', never a fabricated size.
--
-- MACROS ARE DECLARED IN DEPENDENCY ORDER. DuckDB resolves a macro body at creation time,
-- so a helper referencing a macro defined further down the file fails to create.

-- ================================================================ primitives

-- Invisible-character normalisation. Phase 0 E5 found U+00A0 in 257 products' units,
-- where it is indistinguishable from a space and defeats \s.
CREATE OR REPLACE MACRO u_clean(x) AS
  regexp_replace(
    lower(trim(translate(coalesce(x, ''), chr(160) || chr(8201) || chr(8239), '   '))),
    '\s+', ' ', 'g');

-- Junk sentinels: values that are not a size at all. Phase 0 E3 (`error`, 409 products)
-- and the Walmart field-misalignment text. These are NOT sizes and must not parse.
CREATE OR REPLACE MACRO u_is_junk(x) AS
  u_clean(x) IN ('error', 'n/a', 'na', 'none', 'null', '-', '.', '');

-- The TRAILING multiplier must be stripped before the unit token is read: in '60gx6' the
-- unit token 'g' is followed by 'x', a word character, so the \b anchor never matches and
-- the whole value silently fails to parse. The captured unit letter is KEPT -- replacing
-- with '' instead of the backreference turns '60gx6' into '60' and loses the unit.
CREATE OR REPLACE MACRO u_core(x) AS
  regexp_replace(u_clean(x), '([a-z]) ?[x*] ?[0-9]+$', '\1');

-- the literal number attached to a unit token
CREATE OR REPLACE MACRO u_qty_lit(x) AS
  try_cast(regexp_extract(u_core(x),
    '([0-9]+(?:\.[0-9]+)?) ?(?:kilogram|kilograms|kg|gram|grams|g|pound|pounds|lbs|lb|ounce|ounces|oz|litre|litres|liter|liters|millilitre|millilitres|milliliter|milliliters|ml|l|fl ?oz|count|ct|pack|packs|pk|piece|pieces|pc|each|ea|un|units|unit)\b', 1)
  AS DOUBLE);

CREATE OR REPLACE MACRO u_tok_raw(x) AS
  regexp_extract(u_core(x),
    '[0-9] ?(kilogram|kilograms|kg|gram|grams|g|pound|pounds|lbs|lb|ounce|ounces|oz|litre|litres|liter|liters|millilitre|millilitres|milliliter|milliliters|ml|l|fl ?oz|count|ct|pack|packs|pk|piece|pieces|pc|each|ea|un|units|unit)\b', 1);

-- "N per pack" / "N per tray" / "N bunch": a count with a container word.
CREATE OR REPLACE MACRO u_perpack_n(x) AS
  try_cast(regexp_extract(u_clean(x), '^([0-9]+) (?:per )?(?:pack|tray|bunch|bag|box|case)$', 1) AS DOUBLE);

-- Leading  '12 x 355ml', '4 x 100g', '6x93.0ml'
CREATE OR REPLACE MACRO u_pack_lead(x) AS
  try_cast(regexp_extract(u_clean(x), '^([0-9]+) ?[x*] ?[0-9]', 1) AS DOUBLE);
-- Trailing '60gx6', '250mlx6', '93ml*6'
CREATE OR REPLACE MACRO u_pack_trail(x) AS
  try_cast(regexp_extract(u_clean(x), '[a-z] ?[x*] ?([0-9]+)$', 1) AS DOUBLE);

-- ================================================================ unit class

CREATE OR REPLACE MACRO u_uom_token(x) AS
  CASE
    WHEN u_tok_raw(x) IN ('kilogram','kilograms','kg','gram','grams','g','pound','pounds','lbs','lb','ounce','ounces','oz') THEN 'g'
    WHEN u_tok_raw(x) IN ('litre','litres','liter','liters','millilitre','millilitres','milliliter','milliliters','ml','l','fl oz','floz') THEN 'ml'
    WHEN u_tok_raw(x) IN ('count','ct','pack','packs','pk','piece','pieces','pc','each','ea','un','units','unit') THEN 'count'
    WHEN u_perpack_n(x) IS NOT NULL THEN 'count'
    ELSE NULL END;

-- the number attached to a count unit, from either form
CREATE OR REPLACE MACRO u_count_n(x) AS
  coalesce(u_qty_lit(x), u_perpack_n(x));

CREATE OR REPLACE MACRO u_uom(x) AS
  CASE WHEN u_is_junk(x) THEN NULL ELSE u_uom_token(x) END;

-- ================================================================ pack count

-- COUNT UNITS: the quantity IS the pack count.
-- '24ea' is a 24-pack, not one item of size 24. Representing it as qty=24 / pack=1 puts
-- the number in the wrong column: total size comes out right but pack size comes out as
-- 1, so a caller asking "how many items am I buying?" is told one.
--
-- This was caught by P3.4, which compares our pack count against the one implied by
-- upstream's own arithmetic (current_price / price_per_unit). The two derivations share
-- no inputs and no code, which is why the cross-check could see a flaw that no amount of
-- re-reading the parser would have surfaced.
CREATE OR REPLACE MACRO u_pack_count(x) AS
  CASE WHEN u_is_junk(x) THEN NULL
       -- an explicit multiplier always wins: '4 x 100g' is 4 packs of 100g
       WHEN u_pack_lead(x)  IS NOT NULL THEN u_pack_lead(x)
       WHEN u_pack_trail(x) IS NOT NULL THEN u_pack_trail(x)
       -- a bare count ('24ea', '6 each', '4 per pack') is a pack count
       WHEN u_uom_token(x) = 'count' AND u_count_n(x) IS NOT NULL THEN u_count_n(x)
       ELSE 1.0 END;

-- ================================================================ quantities

CREATE OR REPLACE MACRO u_factor(x) AS
  CASE u_tok_raw(x)
    WHEN 'kg' THEN 1000 WHEN 'kilogram' THEN 1000 WHEN 'kilograms' THEN 1000
    WHEN 'lb' THEN 453.592 WHEN 'lbs' THEN 453.592 WHEN 'pound' THEN 453.592 WHEN 'pounds' THEN 453.592
    WHEN 'oz' THEN 28.3495 WHEN 'ounce' THEN 28.3495 WHEN 'ounces' THEN 28.3495
    WHEN 'l' THEN 1000 WHEN 'litre' THEN 1000 WHEN 'litres' THEN 1000
    WHEN 'liter' THEN 1000 WHEN 'liters' THEN 1000
    WHEN 'fl oz' THEN 29.5735 WHEN 'floz' THEN 29.5735
    ELSE 1 END;

-- size of ONE item, in canonical units (g / ml / count)
CREATE OR REPLACE MACRO u_qty(x) AS
  CASE
    WHEN u_is_junk(x)                                           THEN NULL
    -- count units: one item is one item; the number lives in pack_count
    WHEN u_uom_token(x) = 'count' AND u_count_n(x) IS NOT NULL   THEN 1.0
    WHEN u_qty_lit(x) IS NOT NULL                                THEN u_qty_lit(x) * u_factor(x)
    ELSE NULL END;

-- total size of the listing
CREATE OR REPLACE MACRO u_total_qty(x) AS
  CASE WHEN u_qty(x) IS NULL THEN NULL
       ELSE u_qty(x) * coalesce(u_pack_count(x), 1.0) END;

-- confidence:
--   exact     a single unambiguous quantity+unit, or a bare count
--   derived   a pack multiplier had to be applied to a sized item
--   inferred  a count read from a container word ("4 per pack")
--   none      nothing parsed, or the value is junk
CREATE OR REPLACE MACRO u_confidence(x) AS
  CASE
    WHEN u_is_junk(x)                                                 THEN 'none'
    WHEN u_perpack_n(x) IS NOT NULL AND u_qty_lit(x) IS NULL          THEN 'inferred'
    WHEN u_uom_token(x) = 'count' AND u_count_n(x) IS NOT NULL        THEN 'exact'
    WHEN u_qty_lit(x) IS NOT NULL
     AND coalesce(u_pack_count(x), 1) > 1                             THEN 'derived'
    WHEN u_qty_lit(x) IS NOT NULL                                     THEN 'exact'
    ELSE 'none' END;
