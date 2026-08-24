-- P2.2 (test): the parser exercised against every shape found in P2.1, with the answer
-- written down in advance. A parser nobody checked is a parser that quietly invents
-- numbers -- and the failure mode here (329$ -> 329.00) is a 100x error that looks
-- entirely plausible. Expected values are literals so the test can actually fail.
.read models/price_parse_macros.sql

WITH cases(raw, want_type, want_unit_price, want_min_qty, want_basis, want_norm) AS (VALUES
  -- scalar
  ('3.29',            'scalar',     3.29,   1.0, 'each',     'none'),
  ('12',              'scalar',    12.00,   1.0, 'each',     'none'),
  ('1,071.90',        'scalar',  1071.90,   1.0, 'each',     'thousands_sep'),
  -- cents-form: MUST NOT become 329.00
  ('329$',            'scalar',     3.29,   1.0, 'each',     'cents_div100'),
  ('1400$',           'scalar',    14.00,   1.0, 'each',     'cents_div100'),
  ('Now$298',         'scalar',     2.98,   1.0, 'each',     'now_prefix_cents_div100'),
  ('99¢',             'scalar',     0.99,   1.0, 'each',     'cent_symbol_div100'),
  -- multibuy: MUST divide, never strip
  ('2/$7.00',         'multibuy',   3.50,   2.0, 'each',     'none'),
  ('3/$9.00',         'multibuy',   3.00,   3.0, 'each',     'none'),
  ('2/$1.20',         'multibuy',   0.60,   2.0, 'each',     'none'),
  -- per-weight
  ('3.69/100g',       'per_weight', 3.69,   1.0, 'per_100g', 'none'),
  ('36.90/kg',        'per_weight', 3.69,   1.0, 'per_100g', 'basis_rescaled'),
  ('12.46 avg/ea',    'per_weight',12.46,   1.0, 'each',     'none'),
  ('2.46 avg/lb',     'per_weight', 0.5423, 1.0, 'per_100g', 'basis_rescaled'),
  ('17.61avg.kg',     'per_weight', 1.761,  1.0, 'per_100g', 'basis_rescaled'),
  ('19.82/kg8.99/lb.','per_weight', 1.982,  1.0, 'per_100g', 'basis_rescaled'),
  ('0.50/100ml',      'per_weight', 0.50,   1.0, 'per_100ml','none'),
  ('8.80/1000g',      'per_weight', 0.88,   1.0, 'per_100g', 'basis_rescaled'),
  ('0.44/50g',        'per_weight', 0.88,   1.0, 'per_100g', 'basis_rescaled'),
  -- junk / no value
  ('was',             'unparsed',   NULL,   1.0,  NULL,       NULL),
  ('Kelloggs',        'unparsed',   NULL,   1.0,  NULL,       NULL),
  ('',                'blank',      NULL,   NULL, NULL,       NULL)
)
SELECT raw,
       p_offer_type(raw)     AS got_type,     want_type,
       round(p_unit_price(raw),4) AS got_unit_price, want_unit_price,
       p_min_qty(raw)        AS got_min_qty,  want_min_qty,
       p_price_basis(raw)    AS got_basis,    want_basis,
       p_normalization(raw)  AS got_norm,     want_norm,
       p_confidence(raw)     AS confidence,
       CASE WHEN p_offer_type(raw) IS NOT DISTINCT FROM want_type
             AND round(p_unit_price(raw),4) IS NOT DISTINCT FROM want_unit_price
             AND p_min_qty(raw)   IS NOT DISTINCT FROM want_min_qty
             AND p_price_basis(raw) IS NOT DISTINCT FROM want_basis
             AND p_normalization(raw) IS NOT DISTINCT FROM want_norm
            THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM cases ORDER BY verdict DESC, raw;
