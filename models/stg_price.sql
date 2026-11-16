-- stg_price -- one row per raw price observation, with a computable price.
--
-- Contract (Phase 1 brief 2.2):
--   * EVERY row in `raw` produces exactly one row here. Nothing is filtered.
--     Row count in == row count out. That is asserted, not assumed.
--   * Unparseable text is NOT dropped: it gets offer_type='unparsed' and keeps its
--     raw text, so the unparsed set stays countable and inspectable.
--   * A multibuy is NEVER stripped to its total. '2/$7.00' is 3.50, not 7.00.
--   * A cents-form price is NEVER read as dollars. '329$' is 3.29, not 329.00.
--
-- Shape: single SELECT, no side effects, so it drops into dbt as a staging model
-- unchanged when Section 5 wires up the test framework.
--
-- The LEFT JOIN to product supplies `vendor`, which the Walmart bare-integer-cents
-- rule needs. LEFT, not INNER: 878,559 rows resolve to no product (Phase 0 E2) and an
-- inner join would silently drop them, breaking the 1:1 contract above.
--
-- `observed_date` -- THE DATE DECODE (changed 2026-11-16).
--   * Old form, archives up to upstream's 2026-11-04 publication: `raw.nowtime` was TEXT,
--     a date-only string 'YYYY-MM-DD'. This model read it with
--     try_cast(substr(r.nowtime, 1, 10) AS DATE).
--   * New form, first refused by the schema gate on 2026-11-06: `raw.nowtime` is INTEGER,
--     the same calendar date written as digits, YYYYMMDD (20261104). Not an epoch, no time
--     of day, and archive-wide: every historical row changed with it. Upstream did not
--     announce it. Proof that the decode reproduces the old dates (905 of 907 overlapping
--     dates identical, 0 at +/-1 day): docs/incident-nowtime-type-change.md.
--   * The decode is integer arithmetic into make_date. There is NO string round trip and no
--     try_cast: substr(CAST(nowtime AS VARCHAR), 1, 10) yields '20261104', which try_cast
--     turns into NULL for every row without an error, and the build stays green.
--   * It validates before it builds: 8 digits, month 1-12, day within that month (leap
--     years included, via last_day). The CASEs are nested on purpose -- make_date raises on
--     an impossible date, so the month is proven before it is used to find the month's
--     length, and the day is proven before the date is built.
--   * AN INVALID VALUE IS NULL, KEPT, AND COUNTED -- the same treatment honesty rules 3
--     (an ambiguous parse) and 6 (a price row with no product row) give a value that
--     cannot be trusted. The row stays, with `nowtime_raw` holding what upstream sent; a
--     NULL observed_date falls out of every date-filtered headline number; and the count is
--     pinned by dbt/tests/assert_null_observed_date_count_is_pinned.sql. On the archive this
--     was written against that count is 3 of 80,411,080 rows: nowtime 2202 (twice) and
--     20222602, all Loblaws, three of the eight rows that had a NULL nowtime in the old
--     form (Phase 0 E1). They are not guessed at.
--   * The light path (scripts/refresh_light.py: Metro + Walmart) never loads those three
--     rows, so its count is 0. Only a full rebuild sees them.
--   * This model no longer builds a database in the old TEXT form: `//` on a VARCHAR is a
--     binder error, which is loud and is the intended failure. See
--     config/expected_schema.v1.json in docs/FILES.md.
--
-- `product_id` appears here because this IS the staging layer. Per brief 4.1 it must not
-- appear below it -- Section 4's owned key replaces it for everything downstream, so the
-- announced upstream type change stays an ingest-layer event.
SELECT
    r.rowid                                   AS src_rowid,
    product_key(pr.vendor, pr.sku, pr.concatted) AS product_key,
    r.product_id                              AS product_id,
    r.nowtime                                 AS nowtime_raw,
    CASE WHEN r.nowtime BETWEEN 10000101 AND 99991231
              AND (r.nowtime // 100) % 100 BETWEEN 1 AND 12
         THEN CASE WHEN r.nowtime % 100 BETWEEN 1 AND day(last_day(make_date(
                            (r.nowtime // 10000)::INTEGER,
                            ((r.nowtime // 100) % 100)::INTEGER, 1)))
                   THEN make_date((r.nowtime // 10000)::INTEGER,
                                  ((r.nowtime // 100) % 100)::INTEGER,
                                  (r.nowtime % 100)::INTEGER)
              END
    END                                       AS observed_date,

    -- current price
    r.current_price                           AS current_price_raw,
    p_offer_type(r.current_price)             AS offer_type,
    p_unit_price_v(pr.vendor, r.current_price)  AS unit_price,
    p_min_qty(r.current_price)                AS min_qty,
    p_price_basis(r.current_price)            AS price_basis,
    p_basis_stated(r.current_price)           AS price_basis_stated,
    p_normalization_v(pr.vendor, r.current_price) AS normalization,
    p_confidence_v(pr.vendor, r.current_price)  AS parse_confidence,

    -- old (struck-out) price, parsed by the same rules
    r.old_price                               AS old_price_raw,
    p_offer_type(r.old_price)                 AS old_offer_type,
    p_unit_price_v(pr.vendor, r.old_price)      AS old_unit_price,
    p_price_basis(r.old_price)                AS old_price_basis,
    p_basis_stated(r.old_price)               AS old_price_basis_stated,
    p_normalization_v(pr.vendor, r.old_price)   AS old_normalization,
    p_confidence_v(pr.vendor, r.old_price)      AS old_parse_confidence,

    -- carried through unparsed; `other` is free text and is not this model's job
    r.price_per_unit                          AS price_per_unit_raw,
    r.other                                   AS other_raw
FROM raw r
LEFT JOIN product pr ON pr.id = r.product_id
