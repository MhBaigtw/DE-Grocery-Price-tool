-- Price parsing macros. Shared by stg_price.sql and by any query that needs to reason
-- about a raw price string without materialising the model.
--
-- Design: `offer_type` describes the COMMERCIAL OFFER (what is being sold, and how many).
-- `normalization` describes an ENCODING REPAIR applied to get a number out of the text.
-- These are deliberately separate columns. A cents-form price like '329$' is
-- commercially an ordinary scalar offer -- it is only *written* strangely -- so it gets
-- offer_type='scalar' and normalization='cents_div100'. Folding the encoding into
-- offer_type would make it impossible to ask "how many single-unit offers are there?"
-- without knowing every encoding quirk, which is the question D2 actually asks.
--
-- Every repair is named and countable. Nothing is silently coerced.

-- Normalise whitespace and the invisible characters that Phase 0 E5 found in `units`
-- and that also appear in price text.
CREATE OR REPLACE MACRO p_clean(x) AS
  regexp_replace(
    trim(translate(coalesce(x, ''), chr(160) || chr(8201) || chr(8239), '   ')),
    '\s+', ' ', 'g');

-- ---------------------------------------------------------------- shape predicates
CREATE OR REPLACE MACRO p_is_blank(x)      AS (x IS NULL OR trim(coalesce(x,'')) = '');
CREATE OR REPLACE MACRO p_is_scalar(x)     AS (try_cast(p_clean(x) AS DOUBLE) IS NOT NULL);
CREATE OR REPLACE MACRO p_is_thousands(x)  AS regexp_matches(p_clean(x), '^[0-9]{1,3}(,[0-9]{3})+(\.[0-9]+)?$');
CREATE OR REPLACE MACRO p_is_multibuy(x)   AS regexp_matches(p_clean(x), '^[0-9]+ ?/ ?\$[0-9]+(\.[0-9]+)?$');
CREATE OR REPLACE MACRO p_is_cents(x)      AS regexp_matches(p_clean(x), '^[0-9]+\$$');
CREATE OR REPLACE MACRO p_is_now_cents(x)  AS regexp_matches(lower(p_clean(x)), '^now\$[0-9]+$');
CREATE OR REPLACE MACRO p_is_cent_sym(x)   AS regexp_matches(p_clean(x), '^[0-9]+¢$');
-- per-weight: "3.69/100g", "36.90/kg", "12.46 avg/ea", "17.61avg.kg", "19.82/kg8.99/lb."
CREATE OR REPLACE MACRO p_is_perweight(x)  AS
  regexp_matches(lower(p_clean(x)), '^[0-9]+(\.[0-9]+)? ?(avg\.?)? ?[/.] ?[0-9]* ?[a-z]+\.?');

-- ---------------------------------------------------------------- component extraction
-- leading numeric amount, whatever the shape
CREATE OR REPLACE MACRO p_lead_num(x) AS
  try_cast(regexp_extract(p_clean(x), '([0-9]+(?:\.[0-9]+)?)', 1) AS DOUBLE);

-- multibuy: "2/$7.00" -> qty 2, total 7.00
CREATE OR REPLACE MACRO p_mb_qty(x) AS
  try_cast(regexp_extract(p_clean(x), '^([0-9]+) ?/ ?\$', 1) AS DOUBLE);
CREATE OR REPLACE MACRO p_mb_total(x) AS
  try_cast(regexp_extract(p_clean(x), '/ ?\$([0-9]+(?:\.[0-9]+)?)$', 1) AS DOUBLE);

-- per-weight denominator: a quantity and a unit, e.g. "100g", "1000g", "50g", "kg",
-- "lb", "ea". The quantity is optional and defaults to 1 ("36.90/kg" is 36.90 per 1 kg).
CREATE OR REPLACE MACRO p_den_raw(x) AS
  lower(replace(regexp_extract(lower(p_clean(x)),
    '(?:avg)?[ .]?/? ?([0-9]* ?(?:kg|lbs|lb|g|ml|l|oz|ea|each|item|un))\.?', 1), ' ', ''));

CREATE OR REPLACE MACRO p_den_qty(x) AS
  coalesce(try_cast(regexp_extract(p_den_raw(x), '^([0-9]+)', 1) AS DOUBLE), 1.0);

CREATE OR REPLACE MACRO p_den_unit(x) AS
  regexp_extract(p_den_raw(x), '([a-z]+)$', 1);

-- Denominator expressed in grams / millilitres, so arbitrary denominators are handled.
-- "1000g" -> 1000 g; "50g" -> 50 g; "kg" -> 1000 g; "lb" -> 453.592 g.
CREATE OR REPLACE MACRO p_den_grams(x) AS
  CASE p_den_unit(x)
    WHEN 'g'   THEN p_den_qty(x)
    WHEN 'kg'  THEN p_den_qty(x) * 1000.0
    WHEN 'lb'  THEN p_den_qty(x) * 453.592
    WHEN 'lbs' THEN p_den_qty(x) * 453.592
    WHEN 'oz'  THEN p_den_qty(x) * 28.3495
    ELSE NULL END;

CREATE OR REPLACE MACRO p_den_ml(x) AS
  CASE p_den_unit(x)
    WHEN 'ml' THEN p_den_qty(x)
    WHEN 'l'  THEN p_den_qty(x) * 1000.0
    ELSE NULL END;

CREATE OR REPLACE MACRO p_den_each(x) AS
  (p_den_unit(x) IN ('ea', 'each', 'item', 'un'));

-- CANONICAL BASIS. Mass is always expressed per 100 g and volume per 100 mL, so two
-- per-weight prices are directly comparable without the caller knowing which unit the
-- vendor happened to quote. The vendor's STATED denominator is kept alongside in
-- price_basis_stated, because "$2.46/lb" is what the shopper saw and discarding it
-- would make the model unable to reproduce the listing.
--   TRADEOFF: rescaling means unit_price is not always the number printed on the site.
--   The alternative -- keeping every denominator as its own basis -- keeps the printed
--   number but pushes unit conversion into every downstream query, where it will be done
--   inconsistently. Comparability is the whole point of this column, so it is rescaled
--   here, once, with the original preserved.
CREATE OR REPLACE MACRO p_basis(x) AS
  CASE
    WHEN p_den_each(x)                THEN 'each'
    WHEN p_den_grams(x) IS NOT NULL   THEN 'per_100g'
    WHEN p_den_ml(x)    IS NOT NULL   THEN 'per_100ml'
    ELSE NULL END;

CREATE OR REPLACE MACRO p_basis_stated(x) AS
  CASE WHEN p_den_raw(x) = '' THEN NULL ELSE p_den_raw(x) END;

-- scale factor to bring the quoted price onto the canonical basis
CREATE OR REPLACE MACRO p_basis_scale(x) AS
  CASE
    WHEN p_den_each(x)              THEN 1.0
    WHEN p_den_grams(x) IS NOT NULL THEN 100.0 / nullif(p_den_grams(x), 0)
    WHEN p_den_ml(x)    IS NOT NULL THEN 100.0 / nullif(p_den_ml(x), 0)
    ELSE NULL END;

-- ---------------------------------------------------------------- the classifier
-- Order matters: the most specific shapes are tested first, and `unparsed` is the
-- explicit fallback. There is no silent default.
CREATE OR REPLACE MACRO p_offer_type(x) AS
  CASE
    WHEN p_is_blank(x)                                    THEN 'blank'
    WHEN p_is_scalar(x)                                   THEN 'scalar'
    WHEN p_is_thousands(x)                                THEN 'scalar'
    WHEN p_is_cents(x)                                    THEN 'scalar'
    WHEN p_is_now_cents(x)                                THEN 'scalar'
    WHEN p_is_cent_sym(x)                                 THEN 'scalar'
    WHEN p_is_multibuy(x)                                 THEN 'multibuy'
    WHEN p_is_perweight(x) AND p_basis(x) IS NOT NULL     THEN 'per_weight'
    ELSE 'unparsed' END;

CREATE OR REPLACE MACRO p_normalization(x) AS
  CASE
    WHEN p_is_blank(x)                                    THEN NULL
    WHEN p_is_scalar(x)                                   THEN 'none'
    WHEN p_is_thousands(x)                                THEN 'thousands_sep'
    WHEN p_is_cents(x)                                    THEN 'cents_div100'
    WHEN p_is_now_cents(x)                                THEN 'now_prefix_cents_div100'
    WHEN p_is_cent_sym(x)                                 THEN 'cent_symbol_div100'
    WHEN p_is_multibuy(x)                                 THEN 'none'
    WHEN p_is_perweight(x) AND p_basis(x) IS NOT NULL
      THEN CASE WHEN p_basis_scale(x) = 1.0 THEN 'none' ELSE 'basis_rescaled' END
    ELSE NULL END;

-- unit_price: the price of ONE unit on the stated basis.
-- Multibuy is divided by its quantity -- never stripped to the total, which would
-- double the price (Phase 0 E8).
CREATE OR REPLACE MACRO p_unit_price(x) AS
  CASE
    WHEN p_is_blank(x)      THEN NULL
    WHEN p_is_scalar(x)     THEN try_cast(p_clean(x) AS DOUBLE)
    WHEN p_is_thousands(x)  THEN try_cast(replace(p_clean(x), ',', '') AS DOUBLE)
    WHEN p_is_cents(x)      THEN try_cast(replace(p_clean(x), '$', '') AS DOUBLE) / 100.0
    WHEN p_is_now_cents(x)  THEN try_cast(regexp_extract(lower(p_clean(x)), '^now\$([0-9]+)$', 1) AS DOUBLE) / 100.0
    WHEN p_is_cent_sym(x)   THEN try_cast(replace(p_clean(x), '¢', '') AS DOUBLE) / 100.0
    WHEN p_is_multibuy(x)   THEN p_mb_total(x) / nullif(p_mb_qty(x), 0)
    WHEN p_is_perweight(x) AND p_basis(x) IS NOT NULL THEN p_lead_num(x) * p_basis_scale(x)
    ELSE NULL END;

CREATE OR REPLACE MACRO p_min_qty(x) AS
  CASE WHEN p_is_multibuy(x) THEN p_mb_qty(x)
       WHEN p_is_blank(x)    THEN NULL
       ELSE 1 END;

CREATE OR REPLACE MACRO p_price_basis(x) AS
  CASE
    WHEN p_is_blank(x)                                THEN NULL
    WHEN p_is_perweight(x) AND p_basis(x) IS NOT NULL THEN p_basis(x)
    WHEN p_offer_type(x) = 'unparsed'                 THEN NULL
    ELSE 'each' END;

-- parse_confidence: how much interpretation was required.
--   exact       -- the text already was a number
--   derived     -- arithmetic on unambiguous components (multibuy division, cents/100)
--   inferred    -- a basis token had to be read out of free text (per-weight)
--   none        -- nothing was derived
CREATE OR REPLACE MACRO p_confidence(x) AS
  CASE
    WHEN p_is_blank(x)                                    THEN 'none'
    WHEN p_is_scalar(x)                                   THEN 'exact'
    WHEN p_is_thousands(x)                                THEN 'exact'
    WHEN p_is_cents(x) OR p_is_now_cents(x)
      OR p_is_cent_sym(x) OR p_is_multibuy(x)             THEN 'derived'
    WHEN p_is_perweight(x) AND p_basis(x) IS NOT NULL     THEN 'inferred'
    ELSE 'none' END;
