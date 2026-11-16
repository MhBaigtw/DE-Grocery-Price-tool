-- N6: PROOF 2. The extract the last good refresh committed carries, for every offer, the
-- observed_date the OLD string logic produced. Does the new decode land the same products
-- on the same dates?
-- Incident report section 3. Run with run_incident_query.py and
--   --extract <products.json from `git show 97a2886:tool/data/products.json`>
--
-- For each barcode + chain in that extract, take the latest decoded date on or before
-- 2026-11-04 in the new archive and compare it with the extract's observed_date.
--
-- THIS JOIN IS CRUDER THAN THE EXTRACT, on purpose and with a known cost. It matches on a
-- zero-padded barcode and takes ANY row for it. analysis/phase4/E1_tool_extract.sql also
-- drops unparseable and non-positive prices and applies match tiers and a price basis. So
-- a product can have a later row here that the extract rightly ignored. That is the
-- likeliest reason for the 18 offers that do not reproduce -- it has NOT been confirmed,
-- and the report says so. What matters for the decode is that none of the 18 is off by
-- one day.

CREATE TEMP TABLE extract_offers AS
SELECT p.gtin14 AS gtin14, o.chain AS vendor, o.observed_date::DATE AS extract_date
FROM read_json(getvariable('extract_json')) p, unnest(p.offers) AS t(o);

CREATE TEMP TABLE decoded_last AS
SELECT lpad(regexp_replace(p.upc, '[^0-9]', '', 'g'), 14, '0') AS gtin14,
       p.vendor                                                AS vendor,
       max(make_date((r.nowtime // 10000)::INTEGER, ((r.nowtime // 100) % 100)::INTEGER,
                     (r.nowtime % 100)::INTEGER))              AS decoded_date
FROM n.raw r JOIN n.product p ON p.id = r.product_id
WHERE p.vendor IN ('Metro', 'Walmart') AND r.nowtime BETWEEN 20260401 AND 20261104
GROUP BY ALL;

-- 1. The headline counts.
SELECT (SELECT count(*) FROM extract_offers)                                    AS extract_offers,
       count(*)                                                                 AS found_by_barcode_and_chain,
       count(*) FILTER (WHERE extract_date = DATE '2026-11-04')                 AS found_dated_20261104,
       count(*) FILTER (WHERE extract_date = DATE '2026-11-04'
                          AND decoded_date = extract_date)                      AS of_those_decode_to_20261104,
       count(*) FILTER (WHERE extract_date < DATE '2026-11-04')                 AS found_dated_earlier,
       count(*) FILTER (WHERE extract_date < DATE '2026-11-04'
                          AND decoded_date = extract_date)                      AS of_those_decode_exactly,
       count(*) FILTER (WHERE decoded_date <> extract_date)                     AS do_not_reproduce
FROM extract_offers JOIN decoded_last USING (gtin14, vendor);

-- 2. The ones that do not reproduce, by how far apart the two dates are. A decode that
--    shifted dates would show up here as a pile at +1 or -1.
SELECT decoded_date - extract_date AS days_decoded_is_later, count(*) AS offers
FROM extract_offers JOIN decoded_last USING (gtin14, vendor)
WHERE decoded_date <> extract_date
GROUP BY days_decoded_is_later
ORDER BY days_decoded_is_later;
