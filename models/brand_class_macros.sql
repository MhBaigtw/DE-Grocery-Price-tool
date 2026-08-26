-- Brand classification: private label vs national brand vs unclassifiable.
--
-- Metro's price-freeze statement is scoped to "all private label and national brand
-- grocery products", so the distinction is load-bearing for D1 -- and Phase 0 F7 showed
-- the limiting factor is brand-field COVERAGE, not classifier accuracy.
--
-- THE RULE THAT MATTERS (Phase 1 brief 3.3): junk does NOT default to a real category.
-- A blank brand, or a non-brand value like 'Out of stock', yields 'unclassifiable' --
-- never 'national_brand'. Letting unknowns fall through to national brand would bias
-- private-label share downward by exactly the amount we cannot see, which is the worst
-- possible direction for a metric whose whole purpose is to compare the two.

CREATE OR REPLACE MACRO b_norm(x) AS upper(trim(coalesce(x, '')));

-- Non-brand values found in the brand field (Phase 0 E15). Stock status, placeholders,
-- and punctuation-only strings. 451 rows across Walmart, Save-On-Foods and Metro.
CREATE OR REPLACE MACRO b_is_junk(x) AS
  lower(trim(coalesce(x, ''))) IN
    ('out of stock', 'out of stock.', 'unbranded', 'n/a', 'na', 'none', 'null',
     'error', '-', '--', '.', '..', '?', 'unknown');

-- Retailer own-label brands, per vendor. A JUDGEMENT INPUT, written out so it can be
-- argued with and extended rather than buried in a regex. Phase 0 F7 bounded the
-- false-negative risk at ~480 products (~3% of the private-label count) from labels not
-- on this list, identified by vendor-exclusivity plus name inspection.
CREATE OR REPLACE MACRO b_is_private_label(vendor, x) AS
  CASE vendor
    WHEN 'Metro' THEN b_norm(x) IN
      ('SELECTION','SELECTION BIO','IRRÉSISTIBLE','IRRESISTIBLE','IRRÉSISTIBLES',
       'IRRESISTIBLES','LIFE SMART','FRONT STREET BAKERY','METROGO!','METRO','ECONOMAX',
       'PREMIÈRE MOISSON','PREMIERE MOISSON','PLATINUM GRILL')
    WHEN 'Loblaws' THEN b_norm(x) IN
      ('PRESIDENT''S CHOICE','PC','PC ORGANICS','PC BLUE MENU','PC BLACK LABEL','NO NAME',
       'FARMER''S MARKET','JOE FRESH','LIFE BRAND','EVERYDAY ESSENTIALS','FROM OUR CHEFS',
       'ZENSHI')
    WHEN 'NoFrills' THEN b_norm(x) IN
      ('PRESIDENT''S CHOICE','PC','PC ORGANICS','PC BLUE MENU','PC BLACK LABEL','NO NAME',
       'FARMER''S MARKET','JOE FRESH','EVERYDAY ESSENTIALS')
    WHEN 'Walmart' THEN b_norm(x) IN
      ('GREAT VALUE','YOUR FRESH MARKET','OUR FINEST','EQUATE','MARKETSIDE',
       'PARENT''S CHOICE','MAINSTAYS','ATHLETIC WORKS','GEORGE','SAM''S CHOICE')
    WHEN 'SaveOnFoods' THEN b_norm(x) IN
      ('WESTERN FAMILY','SAVE-ON-FOODS','BAKE SHOP','ONLY GOODNESS','BIG PACIFIC',
       'BLUSH LANE','WESTERN CANADIAN','REDLAND FARMS','DELI FRESH')
    WHEN 'Voila' THEN b_norm(x) IN
      ('COMPLIMENTS','COMPLIMENTS BALANCE','PANACHE','SENSATIONS','SIGNAL','BIG 8',
       'OUR FINEST')
    ELSE FALSE END;

-- Vendors whose brand field is empty or near-empty: T&T (0.00%), Galleria (0.00%) and
-- Voila (0.81%). For these the question is not "which class" but "no data" -- and saying
-- so is more useful than a classification built on 0.8% of rows.
CREATE OR REPLACE MACRO b_vendor_has_brand_data(vendor) AS
  vendor NOT IN ('TandT', 'Galleria', 'Voila');

CREATE OR REPLACE MACRO b_class(vendor, x) AS
  CASE
    WHEN NOT b_vendor_has_brand_data(vendor)     THEN 'unclassifiable_no_vendor_data'
    WHEN b_norm(x) = ''                          THEN 'unclassifiable_blank'
    WHEN b_is_junk(x)                            THEN 'unclassifiable_junk'
    WHEN b_is_private_label(vendor, x)           THEN 'private_label'
    ELSE                                              'national_brand'
  END;

-- Coarse two-way view for callers that only need the split, with the unclassifiable
-- population kept visible rather than folded into either side.
CREATE OR REPLACE MACRO b_class_coarse(vendor, x) AS
  CASE WHEN b_class(vendor, x) LIKE 'unclassifiable%' THEN 'unclassifiable'
       ELSE b_class(vendor, x) END;
