# Incident: `raw.nowtime` changed from text to integer

*Stage 1, the investigation, 2026-11-16. It changed no model, config, workflow or schema
file. Sections 1 to 7 are the investigation as it was written, before any fix. Section 8,
added the same day, records what Stage 2 then changed.*

*No build stamp: nothing in sections 1 to 7 was computed through `build_models.py`. The
numbers come from queries against the two SQLite files named in section 1, read directly.
Those queries are committed under `analysis/incident_nowtime/` (N1 to N6, with their own
runner) and were re-run from the committed files before this report was committed; the
table in section 8 says which query regenerates which number.*

## Verdict

- **The new `nowtime` is a calendar date written as digits, `YYYYMMDD`.** It is not an epoch.
- **There is no timezone shift.** The old value was a date-only string with no time of day,
  and the new integer carries the same calendar date. On the 907 dates where the old and new
  archives overlap, 905 match exactly at the same date and 0 match at one day either side.
  The other 2 differ only because upstream added 5 rows to them.
- **The change is archive-wide.** All 80,411,080 rows are stored as integers, 2024 included.
- **The gate reported one problem, but upstream changed three other things in the same
  rewrite** that no gate looks at: it repaired malformed prices, re-keyed `product_id` values
  on 361 historical dates, and gave dates to the 8 rows that used to have none (3 of them
  invalid). These will move published numbers. See section 5.

## 1. Route taken

Read the SQLite directly. No full load, no DuckDB database built.

| | Old | New |
|---|---|---|
| Source | `data/snapshots/20260911T200435Z/hammer-3-compressed.zip` (on disk) | downloaded 2026-11-16T19:50:53Z to 19:51:54Z |
| Upstream stamp | `2026-09-10 21:30:05.12 (Eastern Time)` | `2026-11-14 17:05:15.74 (Eastern Time)` |
| Zip bytes | 974,862,671 | 1,038,230,041 |
| Zip sha256 | `ac6a9b95…` (per manifest) | `3b0fed4c547788ef37d4067bac934b71387fa266be6a40b4f6c7ac00a122d32b` |
| `raw` rows | 73,741,443 | 80,411,080 |

Both were extracted into the session scratchpad and queried with Python `sqlite3` and with
DuckDB's SQLite scanner under a 2 GB memory limit. The new archive was not added to
`data/snapshots/` and no provenance record was written for it.

The old snapshot matters: the archive is cumulative, so the two files hold the same
observations for 2024-02-28 to 2026-09-10 in both forms. That overlap is the proof in
sections 3 and 4.

## 2. What the values look like

Column type as reported:

- SQLite declaration: `nowtime INTEGER` (was `nowtime TEXT`).
- SQLite storage class: `integer` for all 80,411,080 rows. No NULLs, no text.
- DuckDB via the SQLite scanner: `BIGINT` (was `VARCHAR`). This is what the gate saw.

MIN is `2202`. MAX is `20261114`. 971 distinct values. Digit counts: 80,411,078 values have
8 digits and 2 have 4 digits.

15 newest by value (rowid, `nowtime`, `product_id`):

```
(80282623, 20261114, 'Walmart2QDUZBVH7IMC')
(80282622, 20261114, 'Walmart66XKJ2PN2GG1')
(80282621, 20261114, 'Walmart6000206795865')
(80282620, 20261114, 'Walmart6000188434795')
(80282619, 20261114, 'Walmart1WIMIBB9O3I9')
(80282618, 20261114, 'Walmart7JII1MSW798I')
(80282617, 20261114, 'Walmart207372')
(80282616, 20261114, 'Walmart206703')
(80282615, 20261114, 'Walmart4VNRK3EHOGTX')
(80282614, 20261114, 'Walmart690PBF4EFMAR')
(80282613, 20261114, 'Walmart15GZUOMCIQRD')
(80282612, 20261114, 'Walmart10287354')
(80282611, 20261114, 'Walmart6000199216912')
(80282610, 20261114, 'Walmart5DSUZNCWKY89')
(80282609, 20261114, 'Walmart6000197422097')
```

15 oldest by value. The first three are the invalid values described below; the real
minimum date is `20240228`:

```
(25796471, 2202,     'Loblaws20176214004_EA')
(25798360, 2202,     'Loblaws21621119_EA')
(25798571, 20222602, 'Loblaws21097909_EA')
(80282624, 20240228, 'thVGGnfWtNeVUNUGQckgTg==')
(80282625, 20240228, '3vtrvVyu1c40wgC8Qtq9rA==')
(80282626, 20240228, 'mqGQqZ7CXlRTE+XhqRFjNA==')
(80282627, 20240228, 'TaE79+klcAMLyp5tH2iR6g==')
(80282628, 20240228, 'ObWPKO9Q1bX9IQhlgfECpg==')
(80282629, 20240228, 'D9oLfY3jEZP5OeEv2qkgFg==')
(80282630, 20240228, 'imx+0B8awo1ZmDwF62wfBg==')
(80282631, 20240228, 'zpRtv5ebDlRLE822yejrbg==')
(80282632, 20240228, '5bhSCqKsYS78wgvr2FIXEw==')
(80282633, 20240228, 'k6vA1QRqAN9+TLCFO0qxDg==')
(80282634, 20240228, '0UX/rF+sl9E313UiECrrHg==')
(80282635, 20240228, 'YQ7H0R1uNt9rLWFQK71mcA==')
```

Rows per value for the newest dates:

```
20261101   80,632      20261108  111,468
20261102  112,942      20261109  110,176
20261103  112,028      20261110  113,299
20261104  112,576      20261111  100,393
20261105  111,845      20261112  117,944
20261106  112,270      20261113  112,615
20261107  111,837      20261114   91,686
```

15 rows at the start of the table (rowid, `nowtime`, storage class, `product_id`):

```
(1,  20240622, 'integer', 'Voila961755EA')
(2,  20240622, 'integer', 'Voila961724EA')
(3,  20240622, 'integer', 'BzNsgOsvDIUDb08v7vnjBw==')
(4,  20240622, 'integer', 'sft7NoNEVFYgD8V5g75WRQ==')
(5,  20240622, 'integer', 'Voila497819EA')
(6,  20240622, 'integer', 'FlNw0icERMN1/KVK+EvMFg==')
(7,  20240622, 'integer', 'Voila834223EA')
(8,  20240622, 'integer', 'Voila593744EA')
(9,  20240622, 'integer', 'Voila36691EA')
(10, 20240622, 'integer', 'Voila674678EA')
(11, 20240622, 'integer', 'Voila955456EA')
(12, 20240622, 'integer', 'Voila955452EA')
(13, 20240622, 'integer', 'Voila145471EA')
(14, 20240622, 'integer', 'Voila304178EA')
(15, 20240622, 'integer', 'Voila961237EA')
```

15 rows at the end of the table:

```
(80411080, 20240610, 'integer', 'Walmart6000205258932')
(80411079, 20240610, 'integer', 'Walmart6000191273631')
(80411078, 20240610, 'integer', 'Walmart6000199516614')
(80411077, 20240610, 'integer', 'Walmart6000195993556')
(80411076, 20240610, 'integer', 'Walmart6000197208272')
(80411075, 20240610, 'integer', 'AixcpWt/KmrrlLRlwUsHTQ==')
(80411074, 20240610, 'integer', 'v5KIFs+vlE6y1qnPaG0XSQ==')
(80411073, 20240610, 'integer', 'Walmart5RXFJBQH5MDG')
(80411072, 20240610, 'integer', 'QjdVeEQmUnIfCbsjawhOpQ==')
(80411071, 20240610, 'integer', 'Walmart6000207988410')
(80411070, 20240610, 'integer', 'Walmart6000197290722')
(80411069, 20240610, 'integer', 'Walmart6000207989010')
(80411068, 20240610, 'integer', '3T1svIXgW9Yp2MqkqKTjoA==')
(80411067, 20240610, 'integer', 'Walmart6000197290000')
(80411066, 20240610, 'integer', 'Walmart6000206069857')
```

**The table is not in date order.** Rowid 1 is 2024-06-22 and the last rowid is 2024-06-10,
in both archives. "Newest" and "oldest" must be taken by value, never by position. The old
archive shows the same rows at the same relative positions as `'2024-06-22'` and
`'2024-06-10'`.

**Three values are not dates** (rowid, `nowtime`, `current_price`, `product_id`):

```
(25796471, 2202,     '2.49', 'Loblaws20176214004_EA')
(25798360, 2202,     '5.99', 'Loblaws21621119_EA')
(25798571, 20222602, '1.49', 'Loblaws21097909_EA')
```

These are 3 of the 8 Loblaws rows that had a NULL `nowtime` in the old archive (Phase 0 E1).
The other 5 now carry `20260201` or `20260202`. `2202` and `20222602` look like mangled forms
of 2026-02-02, but that is a guess and I did not decode them.

## 3. Which decode is correct

Ruled out by magnitude:

| Candidate | Expected size for 2024–2026 | Observed |
|---|---|---|
| Epoch seconds | 10 digits, about 1.7 billion | 8 digits, about 20 million. As epoch seconds, `20261114` is 1970-08-23. |
| Epoch milliseconds | 13 digits | 8 digits. As epoch ms, it is 1970-01-01 05:37. |
| `YYYYMMDD` | 8 digits, 20240228 to 20261114 | matches |

Decode used throughout: year = `n // 10000`, month = `(n // 100) % 100`, day = `n % 100`,
passed to `make_date`, which raises on an invalid date instead of returning NULL.

**Proof 1: the archive of 2026-11-04.** `data/provenance/20261105T125727Z.json` records
`raw_rows_source: 79317547` for the archive whose extract date was 2026-11-04. Rows in the
new archive with `nowtime <= 20261104`: **79,317,547**. Exact match. The decode puts exactly
the rows that existed on 11-05 on or before 2026-11-04, and 112,576 of them on that day.

**Proof 2: the committed extract of 2026-11-05.** `tool/data/products.json` at `origin/main`
holds 6,469 offers, each with the `observed_date` the old string logic produced. For each
barcode and chain I took the latest decoded date on or before 2026-11-04 in the new archive.

- 6,467 of 6,469 offers were found by barcode and chain.
- All 4,757 found offers dated 2026-11-04 decode to 2026-11-04.
- 1,692 of 1,710 offers dated before 2026-11-04 decode to their exact date.
- 18 do not match. None is off by one day: the new archive has a later row by days to weeks
  (for example extract 2026-09-09, archive 2026-11-04). My join was cruder than the extract's
  own rules, which drop unparseable prices and apply match tiers, so this is probably my
  check and not the decode. I did not confirm that.

**Proof 3: the full overlap** is in section 4.

## 4. The timezone question

**Decoding the integer as a plain date reproduces the old dates exactly. Nothing shifts.**

The premise needs one correction. The old `nowtime` was never a local timestamp. All
73,741,435 non-NULL old values are 10 characters, `'2024-02-28'` to `'2026-09-10'`, with no
time of day; Phase 0 A1 recorded this ("a date-only string, not a timestamp"). The
`substr(…, 1, 10)` in the model was taking the whole string. So there was no 19:00–23:59
window to move, and there is no hour-of-day distribution to compare in either form.

Row-level evidence, old string against new integer for the same observations:

- For each date I counted rows and summed a hash of (`current_price`, `old_price`,
  `price_per_unit`, `other`), on both sides.
- **905 of 907 overlapping dates match on both count and content at the same date.**
- **0 dates match at +1 day and 0 at −1 day.**
- All 308 dates in 2024 match.
- The 2 that differ are 2026-02-01 (100,357 old rows, 100,360 new) and 2026-02-02
  (100,817 old, 100,819 new). Those 5 extra rows are the formerly NULL-dated Loblaws rows.

One adjustment was needed to get that result, stated plainly: the old side's `current_price`
had `'..'` replaced with `'.'` before hashing, because upstream repaired those values (section
5). Without it only 6 dates match, and the three other columns still match on 905.

**What this does not establish:** which timezone upstream uses to assign the calendar date
when it scrapes. That was undocumented before and still is. It did not change with this
release, so it is not part of this incident, but a scrape near midnight has always been
dated by a rule we cannot see.

## 5. Blast radius

**Dates.** Every historical row is an integer now, so every `observed_date` is re-derived.
With the `YYYYMMDD` decode they come out identical to before on the whole overlap, 2024 as
well as 2026. So the 7-day freshness rule, the 2024-06-11 cutoff, the 200-day window,
`prior_days_observed` and `extract_date` (which is `max(observed_date)`) keep their meaning.
I did not run `E1_tool_extract.sql`; this is inferred from the dates being identical.

**Schema.** Confirmed against `config/expected_schema.json`: `raw.product_id` is still
`TEXT`/`VARCHAR`, and every other column in `product` and `raw` has the same name, type and
position. `nowtime` is the only schema difference. The announced `product_id` change has not
landed.

**Three content changes the gate cannot see**, all applied to history:

1. **Malformed prices repaired.** `'0..99'` is now `'0.99'`, and the same for other
   double-dot values. `current_price` differs on 901 of 907 dates. Sampled sizes: 3 of 1,150
   rows on 2024-02-28, 521 of 96,645 on 2025-06-15, 756 of 104,649 on 2026-09-10. I did not
   total it. These rows were presumably unparseable before and will parse now, which would
   move the extract's `unparseable_price` count (8,876 in the 11-05 meta). That link is a
   hypothesis; I did not test it.
2. **`product_id` values re-keyed on 361 dates**: every day from 2024-02-28 to early October
   2024, then scattered dates from October 2025 to 2026-07-28 (30, 30 and 28 dates in May,
   June and July 2026). On 2024-03-04, 90 of 530 rows changed, from name-based ids such as
   `Metro~Salted Butter@454 g^Selection` to code-based ids such as `Metro059749894784`.
   I only inspected that one date. The 2026 dates fall inside the tool's 200-day window and
   I have not looked at what changed on them.
3. **Orphan rows fell sharply.** Rows whose `product_id` matches no `product` row, over the
   same period up to 2026-09-10: 886,107 in the old archive, 255,533 in the new. Whole new
   archive: 274,480. Honesty rule 6 quotes 878,559 and 15,936; those figures describe an
   archive upstream has since rewritten.

Consequence: the first full rebuild on the new archive will move stamped numbers in the
findings docs for reasons unrelated to the date decode. Rule 5 requires each to be re-run
and restated with its delta.

**The 3 invalid values.** `make_date` raises on `2202` and `20222602`, so a strict decode
fails the build. They need a named rule. They are Loblaws rows, so the light path
(Metro and Walmart only) never loads them, but a full rebuild does.

**The gap you flagged, confirmed.** There is no test of any kind on `observed_date` in
`dbt/models/staging/schema.yml`; a search for the column there returns nothing. With
`substr(CAST(nowtime AS VARCHAR), 1, 10)` every value becomes an 8-character string that
`try_cast` turns into NULL, and nothing would stop the build. I did not use that shape.

## 6. Proposal (not applied)

1. **Decode explicitly and strictly in `stg_price`** (both copies): validate the integer is an
   8-digit real date, build it with `make_date`, and return NULL only for values that fail
   validation. No string round trip and no `try_cast` on the date.
2. **Pin the NULLs.** Add a test that the number of rows with a NULL `observed_date` equals a
   committed figure (3 on this archive, listed by rowid in the findings), so a decode that
   empties the column fails. Add an accepted-range test on `observed_date` (2024-02-28 to the
   snapshot date) for the same reason.
3. **Update `config/expected_schema.json` in its own commit**, with a note, as CLAUDE.md
   requires: `raw.nowtime` `VARCHAR` to `BIGINT`.
4. **Decide what happens to old snapshots.** One expected-schema file cannot accept both
   forms. Either the three retained snapshots become unbuildable under the current models,
   or the schema and decode are versioned by snapshot. `check_light_parity.py` and any rebuild
   from `data/snapshots/` depend on the answer. This is your call; I lean to versioning,
   because the old snapshots are the only copy of the pre-rewrite history.
5. **Take a full rebuild of the new archive on a machine that can hold it**, retain it in
   `data/snapshots/`, and restate every stamped figure that moves, starting with the orphan
   counts in rule 6.
6. **Update CLAUDE.md**: `nowtime` is `YYYYMMDD` with no time of day and no documented
   timezone; upstream rewrites history (prices, ids), which the "Known contamination" list
   does not currently say.
7. **Commit the queries behind this report** under `analysis/` if any number here is to be
   quoted elsewhere.

## 7. Still unsure

- **The 18 extract offers that decode to a later date** (section 3). No one-day pattern, and
  probably my simplified join, but unexplained.
- **What changed in `product_id` on the 2026 dates.** Only 2024-03-04 was inspected. If Metro
  ids changed inside the 200-day window, product identity and `prior_days_observed` could
  move for those products even though dates did not.
- **Whether `nowtime_raw` is used below staging** as text. I searched for `nowtime` and found
  it only in the two `stg_price` files and `test_dbt_contracts.py`, but did not trace
  `nowtime_raw` through the other models.
- **Upstream's date-assignment timezone**, as stated in section 4.
- **Whether upstream will rewrite history again.** The old and new archives disagree on
  content for the same dates, so "a snapshot is the truth for its period" no longer holds
  across snapshots. Nothing upstream announced this.

## 8. Stage 2: what was changed (2026-11-16)

Sections 1 to 7 are the investigation as written. This section records the fix and what
applying it turned up. It does not restate any stamped figure in the findings documents;
that is Stage 3 and needs a machine with room for a full load.

### 8.1 Where each number above comes from

Every query was re-run from its committed file, against the same two archives, before this
section was written. All figures reproduced.

| Numbers | Committed source |
|---|---|
| Declared type, storage class, DuckDB type, `product_id` still text (sections 2, 5) | `analysis/incident_nowtime/N1_schema_and_type.sql` |
| Rows, MIN, MAX, digit counts, the 3 invalid values, newest and oldest values, rows per date, the 79,317,547 match (sections 2, 3) | `N2_archive_stats_and_invalid_values.sql` |
| The old form is a 10-character date; the 8 undated rows and where they went (sections 2, 4) | `N3_old_form_and_undated_rows.sql` |
| 905 of 907, 0 at +1 day, 0 at −1 day, 308 of 308 in 2024, 6 without normalising, 901 / 2 / 2 / 2 by column (section 4) | `N4_overlap_date_proof.sql` |
| Price repairs on sample dates, 361 dates re-keyed, 90 of 530, orphans 886,107 to 255,533, and 274,480 (section 5) | `N5_history_rewrite.sql` |
| 6,469 offers, 6,467 found, 4,757 of 4,757, 1,692 of 1,710, 18 residual (section 3) | `N6_extract_of_20261105.sql` |
| The extract comparison in 8.4 | `compare_extract_histories.py` |

They run through `analysis/incident_nowtime/run_incident_query.py`, against upstream's
SQLite files directly. **They are reproducible only against the publication they were
written on** (sha256 `3b0fed4c…`), and that archive was not retained: it was downloaded for
an investigation, not by a full rebuild. Against a later publication the new-side counts
will be larger.

N6 adds one fact to section 3: the 18 offers that do not reproduce are later by 2, 8, 34,
49, 54 (five offers), 56 (seven offers), 59 and 75 days. None is one day out.

### 8.2 The fix

- **Schema contract, in its own commit.** `config/expected_schema.json` is version 2
  (`raw.nowtime` `BIGINT`). Version 1 is kept byte for byte as
  `config/expected_schema.v1.json` for the three retained snapshots. `refresh.py`,
  `refresh_light.py` and `check_light_parity.py` pass `--schema` through;
  `check_schema.py` already accepted it.
- **The decode**, in `models/stg_price.sql` and its dbt copy: integer arithmetic into
  `make_date`, validating 8 digits, month 1 to 12 and day within the month before building
  the date. No string round trip and no `try_cast`. `nowtime_raw` is kept.
- **An invalid value is NULL, kept, and counted.** The committed figure is **3 rows on a
  full load** (`2202` twice, `20222602` once; N2 query 4) and **0 on the light load**,
  which never loads those Loblaws rows.
- **Two dbt tests on `stg_price.observed_date`**, which had none:
  `date_within_snapshot_window` (2024-02-28 to the snapshot's download date) and
  `assert_null_observed_date_count_is_pinned`. Both are shown to fail when they should in
  `scripts/test_dbt_contracts.py`, which now reports 25 of 25 cases.
- **CLAUDE.md** records the integer form, the three invalid values and the history
  rewrite, appended to Known contamination.

### 8.3 What was verified, and on what

- Schema gate: version 1 passes against `hammer.duckdb` (snapshot `20260911T200435Z`);
  version 2 passes against a light load of the 2026-11-14 archive. Each fails against the
  other's data, as it should. `test_check_schema.py`: 6 of 6 on each pairing.
- Light load of the 2026-11-14 archive (Metro and Walmart): 16,435,581 of 80,411,080 rows.
  All 16,435,581 decode; 0 NULL; dates 2024-02-28 to 2026-11-14; 969 distinct dates; 0 rows
  where the decoded date disagrees with the digits.
- dbt suite against that light database: 42 of 42 tests.
- `refresh_light.py` end to end on that archive, into a scratch directory: every gate
  passed, extract date 2026-11-14.
- **Not verified: anything on a full load of the new archive.** The figure 3 comes from N2
  reading the SQLite directly, not from a built `stg_price`. The two new dbt tests have
  passed on the fixture and on a light load only.

### 8.4 What the fix turned up

1. **The retained snapshots pass their schema gate and still cannot be built by the current
   models.** The decode is integer arithmetic, and on a text `nowtime` the build stops with
   a binder error. That is loud and gives no wrong dates, but it means versioning the
   contract did not by itself keep the old snapshots buildable. Today they build only from
   the commit before the decode changed. Choosing between that and a decode selected by
   contract version is a Stage 3 decision.
2. **The new dbt tests do not run in the automated refresh.** The hosted runner installs no
   dbt; dbt runs only in a full rebuild. On the light path a decode that emptied the column
   would be stopped by the extract gate (no observations, no extract date), which is
   indirect. A decode that lost only some dates would not be stopped there.
3. **The shipped extract agrees with the last good one on every shared day.**
   Comparing the history built from the new archive with the one committed on 2026-11-05,
   over 2026-10-04 to 2026-11-04: 5,718 of 5,843 series identical, and no series has a
   different price or sale flag on any day both hold. The 125 that differ gained or lost
   whole days at the edges only: 118 series-days appear only in the new extract (on
   2026-11-03 and 2026-11-04) and 46 only in the old (on 2026-10-04 and 2026-10-05). A date
   shift would move interior days on every series; this does not. **The cause of those 125
   is not established.** Upstream changing which product a row belongs to is the likeliest,
   given section 5, and it was not tested.
4. **A hypothesis in section 5 is not supported.** It suggested the repaired `'0..99'`
   prices would lower the extract's `unparseable_price` count. That count was 8,876 in the
   2026-11-04 extract and is 9,652 in the one built from the new archive. The windows
   differ, so this does not refute it either; it is simply not evidence for it.
5. **The dbt suite no longer passes on the old databases.** `hammer.duckdb` and
   `hammer2.duckdb` hold a text `nowtime_raw` and 8 undated rows, and the pinned-count test
   is written for the integer form. README and the method note still say "40 dbt tests" on
   both snapshots and "23 of 23"; the suite is now 42 tests and 25 of 25 cases. Those
   published counts were left as they are, because "passing on both snapshots" can only be
   re-established by a full rebuild.
