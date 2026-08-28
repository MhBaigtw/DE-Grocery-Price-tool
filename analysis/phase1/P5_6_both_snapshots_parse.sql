-- P5.6: the parse figures for BOTH snapshots, which is what the Phase 1 exit criteria
-- actually require.
--
-- THE GAP THIS CLOSES. The exit criteria say "Every price row in BOTH SNAPSHOTS has an
-- offer_type and either a unit_price or an explicit unparsed verdict." Section 2 reported
-- 71,809,333 rows -- snapshot 1 alone. Snapshot 2 adds 213,319 rows and 2 dates, and none
-- of them had ever been through the parser. The criterion was unmet and the findings
-- document did not say so.
--
-- The fix is to parse snapshot 2 as well rather than to narrow the criterion:
--   python scripts/load_snapshot.py 20260824T132829Z --db hammer2.duckdb
--   python scripts/build_models.py --db hammer2.duckdb --materialize table
--
-- WHY BOTH, RATHER THAN JUST THE NEWER ONE. Snapshot 2 carries every date snapshot 1 has
-- plus two more, so it is *nearly* a superset -- but not exactly: findings 1.4 found 12
-- rows that upstream re-keyed between the publications. "Nearly a superset" is not a
-- basis for discarding a snapshot, and locked decision 2 keeps both anyway. So both are
-- parsed and both are reported. Snapshot 1 remains the basis for the published Section
-- 2-4 numbers, because that is what they were computed on; snapshot 2 is the evidence
-- that the parser holds on a publication it never saw.
ATTACH IF NOT EXISTS 'hammer2.duckdb' AS s2 (READ_ONLY);
SET threads = 4;

-- 1. Row-count reconciliation, both snapshots. in == out, no deliberate reduction.
SELECT 'snapshot 1 (20260822T134045Z)' AS snapshot,
       (SELECT count(*) FROM raw)       AS raw_rows,
       (SELECT count(*) FROM stg_price) AS stg_price_rows,
       (SELECT count(*) FROM raw) - (SELECT count(*) FROM stg_price) AS difference
UNION ALL
SELECT 'snapshot 2 (20260824T132829Z)',
       (SELECT count(*) FROM s2.raw), (SELECT count(*) FROM s2.stg_price),
       (SELECT count(*) FROM s2.raw) - (SELECT count(*) FROM s2.stg_price);

-- 2. THE EXIT CRITERION, stated as a number: every row has an offer_type, and either a
--    unit_price or an explicit unparsed/blank verdict. A row with neither is silently
--    lost, which is what this counts.
SELECT 'snapshot 1' AS snapshot,
       count(*)                                                   AS rows,
       count(*) FILTER (WHERE offer_type IS NULL)                 AS missing_offer_type,
       count(*) FILTER (WHERE unit_price IS NULL
                          AND offer_type NOT IN ('unparsed','blank')) AS silently_lost,
       count(*) FILTER (WHERE offer_type = 'unparsed')            AS unparsed,
       count(*) FILTER (WHERE offer_type = 'blank')               AS blank,
       round(100.0 * count(*) FILTER (WHERE unit_price IS NOT NULL
                                        OR offer_type IN ('unparsed','blank'))
             / count(*), 6)                                        AS pct_resolved
FROM stg_price
UNION ALL
SELECT 'snapshot 2', count(*),
       count(*) FILTER (WHERE offer_type IS NULL),
       count(*) FILTER (WHERE unit_price IS NULL AND offer_type NOT IN ('unparsed','blank')),
       count(*) FILTER (WHERE offer_type = 'unparsed'),
       count(*) FILTER (WHERE offer_type = 'blank'),
       round(100.0 * count(*) FILTER (WHERE unit_price IS NOT NULL
                                        OR offer_type IN ('unparsed','blank')) / count(*), 6)
FROM s2.stg_price;

-- 3. offer_type census, both snapshots, so the shapes can be compared rather than just
--    the totals. A new shape appearing in snapshot 2 would show up here as a shift.
SELECT coalesce(a.offer_type, b.offer_type)        AS offer_type,
       a.n                                          AS snapshot_1,
       b.n                                          AS snapshot_2,
       coalesce(b.n, 0) - coalesce(a.n, 0)          AS delta
FROM      (SELECT offer_type, count(*) n FROM stg_price    GROUP BY 1) a
FULL JOIN (SELECT offer_type, count(*) n FROM s2.stg_price GROUP BY 1) b USING (offer_type)
ORDER BY coalesce(b.n, 0) DESC;

-- 4. Repairs applied, both snapshots. Each named and counted, per brief 2.2. A repair
--    whose count moved disproportionately with the row count would be a red flag.
SELECT coalesce(a.normalization, b.normalization)  AS normalization,
       a.n                                          AS snapshot_1,
       b.n                                          AS snapshot_2,
       coalesce(b.n, 0) - coalesce(a.n, 0)          AS delta
FROM      (SELECT normalization, count(*) n FROM stg_price    GROUP BY 1) a
FULL JOIN (SELECT normalization, count(*) n FROM s2.stg_price GROUP BY 1) b USING (normalization)
ORDER BY coalesce(b.n, 0) DESC;

-- 5. parse_confidence, both snapshots -- the ambiguous set must stay countable
--    (CLAUDE.md honesty rule 3).
SELECT coalesce(a.parse_confidence, b.parse_confidence) AS parse_confidence,
       a.n AS snapshot_1, b.n AS snapshot_2,
       coalesce(b.n, 0) - coalesce(a.n, 0) AS delta
FROM      (SELECT parse_confidence, count(*) n FROM stg_price    GROUP BY 1) a
FULL JOIN (SELECT parse_confidence, count(*) n FROM s2.stg_price GROUP BY 1) b USING (parse_confidence)
ORDER BY coalesce(b.n, 0) DESC;

-- 6. The owned key across both snapshots: the collision check section 3.5 claimed, which
--    could not be re-run after hammer2.duckdb was deleted.
--
--    The unit of comparison is the KEY SOURCE -- the exact string fed to md5 -- not the
--    product row. A first attempt at this compared distinct (product_key, vendor, sku,
--    concatted) tuples and reported 559 "collisions". Those were not collisions: they are
--    products whose `concatted` changed between publications (findings 1.3 measured 388
--    name and 541 brand changes, and `concatted` embeds both) while vendor and sku held
--    steady. `concatted` is not an input to the key where a sku exists, so a changed
--    `concatted` cannot change the key -- the query was counting a different thing and
--    calling it a collision. Comparing key sources is the test that means something.
WITH u AS (
  SELECT DISTINCT k_source(vendor, sku, concatted) AS ks, product_key FROM stg_product
  UNION
  SELECT DISTINCT k_source(vendor, sku, concatted),    product_key FROM s2.stg_product
)
SELECT count(DISTINCT ks)                                    AS distinct_key_sources,
       count(DISTINCT product_key)                           AS distinct_keys,
       count(DISTINCT ks) - count(DISTINCT product_key)      AS collisions
FROM u;

-- 7. THE DEFECT SECTION 5 FOUND: rows that resolve to no product row must have a NULL
--    key, not a shared one. Before the fix all 878,559 of them carried the SAME md5.
SELECT 'snapshot 1' AS snapshot,
       count(*) FILTER (WHERE product_key IS NULL)     AS null_key_rows,
       count(DISTINCT product_key)                     AS distinct_non_null_keys,
       (SELECT count(*) FROM stg_price s
         WHERE s.product_key IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM stg_product p
                            WHERE p.product_key = s.product_key)) AS orphan_keys_not_in_stg_product
FROM stg_price
UNION ALL
SELECT 'snapshot 2',
       count(*) FILTER (WHERE product_key IS NULL),
       count(DISTINCT product_key),
       (SELECT count(*) FROM s2.stg_price s
         WHERE s.product_key IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM s2.stg_product p
                            WHERE p.product_key = s.product_key))
FROM s2.stg_price;
