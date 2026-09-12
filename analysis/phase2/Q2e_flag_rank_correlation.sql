-- Q2e: the rank correlation between the two definitions of "on sale", reproducibly.
--
-- WHY THIS FILE EXISTS. The writeup published "rank correlation between the two orderings:
-- 0.196" with no committed query behind it. That breaks honesty rule 4: every published
-- number has a committed SQL file that regenerates it. This is that file, written after the
-- fact, and the finding it produced is below.
--
-- WHAT WAS WRONG WITH 0.196. Two of the eight chains cannot be measured under the second
-- definition at all. Metro's promotional-text field is empty on every row; Galleria's carries
-- only availability text ("Out of Stock") and no promotional vocabulary. Their promotional
-- rate computes as 0.0, and 0.196 ranked those zeros as if they were measurements -- tied
-- for last. That is the same error the dashboard caught before launch: 0% read as "never
-- confirmed" when the truth is "cannot be checked". A chain that cannot be measured has no
-- rank, and a correlation over ranks it does not have is not a correlation over the data.
--
-- So this file reports both: the published construction, reproduced exactly so the old
-- figure is accounted for, and the correlation over the chains that can actually be
-- measured both ways, re-ranked among themselves.
--
-- Same cohort and definitions as Q2d_flag_semantics.sql statement 3: 2025-01-01 onward,
-- ambiguous and unparsed rows excluded, the same generous promotional detector. Run against
-- the Phase 2 analysis build (snapshot 20260822T134045Z).
SET threads = 2;

CREATE OR REPLACE TEMP MACRO other_says_sale(x) AS
  (x IS NOT NULL AND trim(x) <> ''
   AND regexp_matches(lower(x),
       '(sale|rollback|clearance|deal|save|special|reduced|[0-9]+ *for *\$|was |price *drop)')
   AND NOT regexp_full_match(lower(trim(x)), '(out of stock|low stock|in stock)'));

CREATE OR REPLACE TEMP TABLE rates AS
SELECT sp.vendor,
       count(*)                                                                 AS rows,
       count(*) FILTER (WHERE s.other_raw IS NOT NULL AND trim(s.other_raw) <> '') AS other_populated,
       count(*) FILTER (WHERE other_says_sale(s.other_raw))                      AS other_promotional,
       100.0 * count(*) FILTER (WHERE s.old_offer_type <> 'blank') / count(*)    AS pct_struck,
       100.0 * count(*) FILTER (WHERE other_says_sale(s.other_raw)) / count(*)   AS pct_promo
FROM stg_price s JOIN stg_product sp USING (product_key)
WHERE s.parse_confidence <> 'ambiguous'
  AND s.offer_type <> 'unparsed'
  AND s.observed_date >= DATE '2025-01-01'
GROUP BY 1;

-- 1. The per-chain table, with measurability stated rather than encoded as a number.
--    A chain whose promotional-text detector never fires on any row cannot be ranked by it.
SELECT vendor,
       rows,
       other_populated,
       other_promotional,
       round(pct_struck, 3)                                        AS pct_struck_out,
       CASE WHEN other_promotional > 0 THEN round(pct_promo, 3) END AS pct_promotional_text,
       (other_promotional > 0)                                      AS promo_measurable
FROM rates
ORDER BY pct_struck DESC, vendor;

-- 2. The correlation, both ways. Spearman's rho as the Pearson correlation of average ranks
--    (ties share the mean of the ranks they span), plus the textbook 1 - 6*sum(d^2)/(n(n^2-1))
--    form, which is what 0.196 used and which drifts slightly from the exact value when
--    ranks are tied.
WITH all8 AS (
  SELECT vendor,
         -- determinism-ok: rank() gives tied values the same rank whatever their physical
         -- order, and the tie correction depends only on the size of the tied group, so the
         -- average rank is a pure function of the value.
         rank() OVER (ORDER BY pct_struck DESC)
           + (count(*) OVER (PARTITION BY pct_struck) - 1) / 2.0   AS rk_a,
         -- determinism-ok: as above.
         rank() OVER (ORDER BY pct_promo DESC)
           + (count(*) OVER (PARTITION BY pct_promo) - 1) / 2.0    AS rk_b
  FROM rates),
six AS (
  SELECT vendor,
         -- determinism-ok: as above, over the measurable chains only, re-ranked among
         -- themselves so an unmeasurable chain cannot shift anyone's rank.
         rank() OVER (ORDER BY pct_struck DESC)
           + (count(*) OVER (PARTITION BY pct_struck) - 1) / 2.0   AS rk_a,
         -- determinism-ok: as above.
         rank() OVER (ORDER BY pct_promo DESC)
           + (count(*) OVER (PARTITION BY pct_promo) - 1) / 2.0    AS rk_b
  FROM rates WHERE other_promotional > 0)
SELECT 'published: all eight, unmeasurable chains ranked as 0.0' AS construction,
       count(*)                                                   AS n,
       round(corr(rk_a, rk_b), 3)                                 AS spearman_rho,
       round(1 - 6 * sum(power(rk_a - rk_b, 2)) / (count(*) * (power(count(*), 2) - 1)), 3)
                                                                  AS rho_textbook_formula
FROM all8
UNION ALL
SELECT 'corrected: the chains measurable both ways, re-ranked',
       count(*),
       round(corr(rk_a, rk_b), 3),
       round(1 - 6 * sum(power(rk_a - rk_b, 2)) / (count(*) * (power(count(*), 2) - 1)), 3)
FROM six
ORDER BY n DESC;

-- 3. The ranks the writeup's table shows: struck-out price ranked across all eight (every
--    chain is measurable that way), promotional text ranked across the measurable six only.
WITH a AS (
  SELECT vendor,
         -- determinism-ok: rank() over a value; ties share a rank regardless of row order.
         rank() OVER (ORDER BY pct_struck DESC) AS rank_struck_of_8
  FROM rates),
b AS (
  SELECT vendor,
         -- determinism-ok: rank() over a value; ties share a rank regardless of row order.
         rank() OVER (ORDER BY pct_promo DESC) AS rank_promo_of_measurable
  FROM rates WHERE other_promotional > 0)
SELECT a.vendor, a.rank_struck_of_8, b.rank_promo_of_measurable
FROM a LEFT JOIN b USING (vendor)
ORDER BY a.rank_struck_of_8, a.vendor;
