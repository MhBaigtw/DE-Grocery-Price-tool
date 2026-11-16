{# ACCEPTED RANGE for an observation date: no earlier than the first day upstream has data
   for, no later than the day the snapshot was downloaded.

   Why it exists. Until 2026-11-16 `stg_price.observed_date` had no test of any kind, and
   the date decode is the one expression every freshness rule, cutoff and history window
   in the project hangs from. When upstream changed `raw.nowtime` from text to an integer
   (docs/incident-nowtime-type-change.md) a wrong decode had nothing to stop it: reading
   20261104 as epoch seconds gives 1970-08-23, and nothing would have objected.

   The upper bound is the snapshot's own download date, read from `_snapshot_provenance`
   (written by scripts/load_snapshot.py), not today's date -- an old snapshot tested next
   year must still fail on a date after it was taken. snapshot_id is a UTC timestamp and
   upstream stamps its publications in Eastern time, which is behind UTC, so a real
   observation cannot be dated later than the download.

   NULLs pass this test on purpose. A NULL date is a different question with a different
   answer -- kept, counted and pinned by assert_null_observed_date_count_is_pinned.sql.

   The last branch fails the test when the snapshot date cannot be read. Without it a
   missing provenance row would make the upper bound NULL, the comparison NULL, and the
   test green: the same silent pass this test was written to end. #}
{% test date_within_snapshot_window(model, column_name, min_date) %}
WITH snap AS (
    SELECT count(*)                                              AS n,
           max(try_strptime(substr(v, 1, 8), '%Y%m%d'))::DATE    AS snapshot_date
    FROM {{ source('hammer', '_snapshot_provenance') }}
    WHERE k = 'snapshot_id'
)
SELECT {{ column_name }} AS offending_date, 'outside the window' AS why
FROM {{ model }}
WHERE {{ column_name }} < DATE '{{ min_date }}'
   OR {{ column_name }} > (SELECT snapshot_date FROM snap)
UNION ALL
SELECT NULL, 'the snapshot date could not be read from _snapshot_provenance'
FROM snap
WHERE n <> 1 OR snapshot_date IS NULL
{% endtest %}
