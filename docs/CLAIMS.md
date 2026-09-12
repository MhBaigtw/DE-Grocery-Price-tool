# Claims manifest — where every published figure comes from

Every figure in `docs/writeup.md`, `README.md` and `docs/method-note.md` is listed here with
the committed file that regenerates it. `scripts/check_claims.py` fails if a figure in those
documents has no entry, if an entry's source is not a committed file, or if an entry no longer
matches anything (its sentence changed). Built 2026-09-12 by a sweep of all three documents.

### How an entry works

- **Figure** — the number exactly as the document prints it.
- **Anchor** — a phrase from the same line that contains the figure. It pins the entry to a
  position, so the same digits meaning different things need different entries. A pipe inside
  an anchor is written `\|`.
- **Source** — a committed query or script; or `derived: <arithmetic> from <file>`;
  or `provenance-lost`; or `not-a-figure: <reason>` for digits that are not measurements.
- **Note** — how the figure was checked. *Confirmed* means the number was found in that
  source's output from a local run (logs are gitignored); *traced* means the findings document
  that the source feeds prints the number, and the source was not re-run for this sweep.

Analysis figures are computed on snapshot `20260822T134045Z` (prices to 2026-08-21) unless the
note says otherwise. Tool figures are computed on snapshot `20260911T200435Z`.

The check sees digits only. A figure written in words ("sixfold", "eight chains") is not covered.

## docs/writeup.md

| Figure | Anchor | Source | Note |
|---|---|---|---|
| 71.8M | 71.8M price observations | analysis/phase2/Q1_exclusion_ledger.sql | confirmed: ledger total 71,809,333 |
| 8 | 8 Canadian chains | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: 8 vendors in statement 4 |
| 71.8 | 71.8 million | analysis/phase2/Q1_exclusion_ledger.sql | confirmed: 71,809,333 rows |
| 8 | (of 8) | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: statement 6 ranks 8 chains by struck-out price |
| 6 | (of 6) | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: statement 6 ranks 6 measurable chains |
| 32.4% | 32.4% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: Save-On-Foods 32.394 |
| 1 | **1** | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: statement 6 ranks |
| 8.6% | 8.6% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: Save-On-Foods 8.624 |
| 5 | **5** | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: statement 6 ranks |
| 29.0% | 29.0% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: Metro 28.978 |
| 2 | \| 2 \| | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: statement 6 ranks |
| 19.1% | 19.1% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: Voila 19.115 |
| 3 | \| 3 \| | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: statement 6 ranks |
| 19.4% | 19.4% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: Voila 19.391 |
| 17.8% | 17.8% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: Loblaws 17.779 |
| 4 | **4** | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: statement 6 ranks |
| 24.1% | 24.1% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: Loblaws 24.065 |
| 14.1% | 14.1% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: No Frills 14.114 and 14.134 |
| 5 | \| 5 \| | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: statement 6 ranks |
| 4 | \| 4 \| | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: statement 6 ranks |
| 12.2% | 12.2% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: Walmart 12.242 |
| 6 | \| 6 \| | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: statement 6 ranks |
| 17.1% | 17.1% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: Walmart 17.112 |
| 6.2% | 6.2% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: T&T 6.153 |
| 7 | \| 7 \| | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: statement 6 ranks |
| 0.9% | 0.9% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: T&T 0.879 |
| 0.8% | 0.8% | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: Galleria 0.777 |
| 8 | \| 8 \| | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: statement 6 ranks |
| 0.31 | 0.31 | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: 0.314, six measurable chains |
| 0.196 | as 0.196 | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: textbook formula over eight chains; had no committed query until 2026-09-12 |
| 99.5% | **99.5%** | analysis/phase2/Q2d_flag_semantics.sql | confirmed: No Frills 99.50 |
| 21.5% | **21.5%** | analysis/phase2/Q2d_flag_semantics.sql | confirmed: Save-On-Foods 21.46 |
| 6,003,385 | 6,003,385 | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed: Metro rows 6003385 |
| 228,608 | **228,608 sale events** | analysis/phase2/Q2a_presale_inflation.sql | confirmed |
| 21.3% | **21.3%** | analysis/phase2/Q2a_presale_inflation.sql | confirmed: 21.27 |
| 20.6% | 20.6% | analysis/phase2/Q2a_presale_inflation.sql | confirmed: median 20.59 |
| 4.4% | 4.4% | analysis/phase2/Q2a_presale_inflation.sql | confirmed |
| 14 | 14 days | analysis/phase2/Q2a_presale_inflation.sql | the look-back window the query defines |
| 3.4% | **3.4%** | analysis/phase2/Q2a_presale_inflation.sql | confirmed: 3.39 |
| 3.4% | 3.4% and 21.3% | analysis/phase2/Q2a_presale_inflation.sql | confirmed: 3.39 |
| 21.3% | 3.4% and 21.3% | analysis/phase2/Q2a_presale_inflation.sql | confirmed: 21.27 |
| 77% | 77% to 95% | analysis/phase2/Q2a_presale_inflation.sql | confirmed: five largest chains, Metro 76.78 low |
| 95% | 77% to 95% | analysis/phase2/Q2a_presale_inflation.sql | confirmed: Voila 95.15 high |
| 228,608 | Where 228,608 comes | analysis/phase2/Q2a_presale_inflation.sql | confirmed |
| 575,036 | 575,036 sale | analysis/phase2/Q2a_presale_inflation.sql | confirmed |
| 279,962 | 279,962 | analysis/phase2/Q2a_presale_inflation.sql | confirmed |
| 275,779 | 275,779 | analysis/phase2/Q2a_presale_inflation.sql | confirmed |
| 275,240 | 275,240 | analysis/phase2/Q2a_presale_inflation.sql | confirmed |
| 228,608 | **228,608** | analysis/phase2/Q2a_presale_inflation.sql | confirmed |
| 279,596 | 279,596 | analysis/phase1/P2_3_d2_reconciliation.sql | traced: Phase 1 findings §3.5, "D2 usable events 279,596, exact" |
| 13 | 13 points | derived: largest per-chain gap, 59.38 − 46.09 = 13.29, from analysis/phase2/Q4_d1_bounded.sql | confirmed inputs |
| 46.1% | 46.1% | analysis/phase2/Q4_d1_bounded.sql | confirmed: Walmart 46.09 |
| 59.4% | 59.4% | analysis/phase2/Q4_d1_bounded.sql | confirmed: Walmart 59.38 |
| 13.3 | 13.3 pts | derived: 59.38 − 46.09 from analysis/phase2/Q4_d1_bounded.sql | confirmed inputs |
| 20.8% | 20.8% | analysis/phase2/Q4_d1_bounded.sql | confirmed: Metro 20.77 |
| 30.0% | 30.0% | analysis/phase2/Q4_d1_bounded.sql | confirmed: Metro 30.04 |
| 9.3 | 9.3 pts | derived: 30.04 − 20.77 from analysis/phase2/Q4_d1_bounded.sql | confirmed inputs |
| 82.9% | 82.9% | analysis/phase2/Q4_d1_bounded.sql | confirmed: Galleria 82.85 |
| 82.1% | 82.1% | analysis/phase2/Q4_d1_bounded.sql | confirmed: Galleria 82.12 |
| 0.7 | 0.7 pts | derived: 82.12 − 82.85 from analysis/phase2/Q4_d1_bounded.sql | confirmed inputs |
| 0.7 | 0.7 to 13.3 | derived: range of the per-chain gaps from analysis/phase2/Q4_d1_bounded.sql | confirmed inputs |
| 13.3 | 0.7 to 13.3 | derived: range of the per-chain gaps from analysis/phase2/Q4_d1_bounded.sql | confirmed inputs |
| 3,477 | 3,477 distinct barcodes | analysis/phase2/Q3b_basket_blindspot.sql | confirmed |
| 8,448 | 8,448 product listings | analysis/phase2/Q3b_basket_blindspot.sql | confirmed |
| 3,465 | 3,465 products | analysis/phase4/E1_tool_extract.sql | confirmed: products_shipped, tool snapshot |
| 3,477 | 3,477 barcodes | analysis/phase2/Q3b_basket_blindspot.sql | confirmed |
| 8,448 | 8,448 listings | analysis/phase2/Q3b_basket_blindspot.sql | confirmed |
| 16,106 | 16,106 | analysis/phase2/Q3b_basket_blindspot.sql | confirmed |
| 30.6% | **30.6%** | analysis/phase2/Q3b_basket_blindspot.sql | confirmed |
| 28.8% | 28.8% | analysis/phase2/Q3b_basket_blindspot.sql | confirmed: 28.78 |
| 22.6% | **22.6%** | analysis/phase2/Q3b_basket_blindspot.sql | confirmed |
| 100% | 100% of 711 | analysis/phase2/Q3c_pairwise_stability.sql | checked 2026-09-12, tie case closed: the last statement bins every date — Walmart cheaper on 711, exactly 1.0 on 0, Metro cheaper on 0; the closest date was a ratio of 1.0264. Verified twice on the analysis snapshot |
| 711 | 100% of 711 | analysis/phase2/Q3c_pairwise_stability.sql | confirmed |
| 12.6% | about 12.6% | derived: 1 − 1/1.1447 from analysis/phase2/Q3c_pairwise_stability.sql | confirmed input |
| 17.9% | 17.9% cheaper | derived: 1 − 1/1.2186 from analysis/phase2/Q3c_pairwise_stability.sql | confirmed input; a withdrawn comparison, quoted in its withdrawal |
| 606 | 606 dates | analysis/phase2/Q3c_pairwise_stability.sql | confirmed; withdrawn comparison |
| 5.3% | 5.3% cheaper | derived: 1 − 0.9475 from analysis/phase2/Q3c_pairwise_stability.sql | confirmed input; withdrawn comparison |
| 91.7% | 91.7% | analysis/phase2/Q3c_pairwise_stability.sql | confirmed: 91.74, 611 of 666; the other 55 dates sit at exactly 1.0, none has Save-On-Foods cheaper. Withdrawn comparison |
| 666 | its 666 dates | analysis/phase2/Q3c_pairwise_stability.sql | confirmed: Metro / Save-On-Foods n_dates. Until 2026-09-12 the writeup said "91.7% of them", after 606, the wrong pair's date count |
| 711 | in 711 | analysis/phase2/Q3c_pairwise_stability.sql | confirmed |
| 6% | 6% on eggs | derived: 1.0639 − 1 from analysis/phase2/Q3c_pairwise_stability.sql | confirmed input, re-run 2026-09-12 on the analysis snapshot |
| 20% | 20% on produce | derived: 1.2035 − 1 from analysis/phase2/Q3c_pairwise_stability.sql | confirmed input, re-run 2026-09-12 |
| 51% | (51%) | analysis/phase2/Q3c_pairwise_stability.sql | confirmed: 50.96 |
| 17% | **17%** | derived: 1 − 1/1.2105 from analysis/phase2/Q3c_pairwise_stability.sql | confirmed input |
| 8% | **8%** | derived: 1 − 1/1.0913 from analysis/phase2/Q3c_pairwise_stability.sql | confirmed input |
| 56,176,157 | 56,176,157 | derived: sum of observations in statement 7 of analysis/phase4/R1_refresh_cadence.sql | confirmed: recomputed from the output, 56 rows |
| 14.3% | 14.3% | derived: 100 / 7, an even split over seven weekdays, as defined in analysis/phase4/R1_refresh_cadence.sql | a constant, not a measurement |
| 92.6% | **92.6%** | analysis/phase4/R1_refresh_cadence.sql | confirmed: Voila 92.62 |
| 0.1% | \| 0.1% \| | analysis/phase4/R1_refresh_cadence.sql | confirmed: Voila quietest 0.10 |
| 92.5% | **92.5%** | analysis/phase4/R1_refresh_cadence.sql | confirmed: Metro 92.50 |
| 0.4% | \| 0.4% \| | analysis/phase4/R1_refresh_cadence.sql | confirmed: Metro quietest 0.44 |
| 89.4% | **89.4%** | analysis/phase4/R1_refresh_cadence.sql | confirmed: Save-On-Foods 89.40 |
| 0.2% | \| 0.2% \| | analysis/phase4/R1_refresh_cadence.sql | confirmed: Save-On-Foods quietest 0.23 |
| 86.5% | **86.5%** | analysis/phase4/R1_refresh_cadence.sql | confirmed: Loblaws 86.50 |
| 0.6% | \| 0.6% \| | analysis/phase4/R1_refresh_cadence.sql | confirmed: Loblaws quietest 0.56 |
| 85.4% | **85.4%** | analysis/phase4/R1_refresh_cadence.sql | confirmed: No Frills 85.41 |
| 1.5% | \| 1.5% \| | analysis/phase4/R1_refresh_cadence.sql | confirmed: No Frills quietest 1.51 |
| 63.1% | **63.1%** | analysis/phase4/R1_refresh_cadence.sql | confirmed: Walmart 63.13 |
| 2.4% | \| 2.4% \| | analysis/phase4/R1_refresh_cadence.sql | confirmed: Walmart quietest 2.44 |
| 46.7% | \| 46.7% \| | analysis/phase4/R1_refresh_cadence.sql | confirmed: Galleria 46.74 |
| 4.8% | \| 4.8% \| | analysis/phase4/R1_refresh_cadence.sql | confirmed: Galleria quietest 4.83 |
| 44.9% | \| 44.9% \| | analysis/phase4/R1_refresh_cadence.sql | confirmed: T&T 44.93 |
| 4.9% | \| 4.9% \| | analysis/phase4/R1_refresh_cadence.sql | confirmed: T&T quietest 4.86 |
| 22.2% | 22.2% of the Metro | analysis/phase4/R1_refresh_cadence.sql | confirmed: Metro Thursday 22.21 |
| 0.1% | Sunday, 0.1% | analysis/phase4/R1_refresh_cadence.sql | confirmed: Metro Sunday 0.10 |
| 32% | 32% to | analysis/phase4/R1_refresh_cadence.sql | confirmed: T&T 2024 32.49 |
| 76% | 76%, | analysis/phase4/R1_refresh_cadence.sql | confirmed: T&T 2026 75.79 |
| 81% | 81% to 92% | analysis/phase4/R1_refresh_cadence.sql | confirmed: No Frills 2024 81.47 |
| 92% | 81% to 92% | analysis/phase4/R1_refresh_cadence.sql | confirmed: No Frills 2026 91.77 |
| 11.1% | **11.1%** | analysis/phase2/Q3b_basket_blindspot.sql | confirmed: 11.13 |
| 41.7% | 41.7% to 54.0% | analysis/phase2/Q3b_basket_blindspot.sql | confirmed: 41.69 |
| 54.0% | 41.7% to 54.0% | analysis/phase2/Q3b_basket_blindspot.sql | confirmed: 54.00 |
| 3.4% | 3.4%–21.3% bracket | analysis/phase2/Q2a_presale_inflation.sql | confirmed: 3.39 |
| 21.3% | 3.4%–21.3% bracket | analysis/phase2/Q2a_presale_inflation.sql | confirmed: 21.27 |
| 95 | 95th | analysis/phase2/Q3b_basket_blindspot.sql | the percentile the query computes |
| $13.99 | $13.99 | analysis/phase2/Q3b_basket_blindspot.sql | confirmed |
| $20.04 | $20.04 | analysis/phase2/Q3b_basket_blindspot.sql | confirmed |
| 22 | downloaded on 22 | not-a-figure: part of the date "22 August 2026", split across a line break | — |
| 21 | after 21 | not-a-figure: part of the date "21 August", split across a line break | — |

## README.md

| Figure | Anchor | Source | Note |
|---|---|---|---|
| 8 | from 8 vendor | analysis/phase0/A2_rows_per_vendor_per_day.sql | traced: Phase 0 findings, "all 8 vendors" |
| 3,465 | across 3,465 | analysis/phase4/E1_tool_extract.sql | confirmed: products_shipped, tool snapshot |
| 44% | For 44% | derived: (1,253 + 274) / 3,465 from analysis/phase4/E1_tool_extract.sql | confirmed inputs |
| 3,465 | Its 3,465 products | analysis/phase4/E1_tool_extract.sql | confirmed |
| 3,477 | basket's 3,477 | analysis/phase2/Q3b_basket_blindspot.sql | confirmed |
| 100.000% | 100.000% of price rows | analysis/phase1/P5_6_both_snapshots_parse.sql | traced: Phase 1 findings §5.6, both snapshots |
| 33 | 33 unparsed | analysis/phase1/P5_6_both_snapshots_parse.sql | traced: 33 in snapshot 1 and 33 in snapshot 2 |
| 71.8M | 71.8M / 72.0M | analysis/phase1/P5_6_both_snapshots_parse.sql | traced: 71,809,333 rows |
| 72.0M | 71.8M / 72.0M | analysis/phase1/P5_6_both_snapshots_parse.sql | traced: 72,022,652 rows |
| 0 | **0 collisions** | analysis/phase1/P3_5_key_collision_proof.sql | traced: Phase 1 findings, 187,087 keys, 0 collisions |
| 40 | 40 dbt tests | scripts/run_dbt_tests.py | confirmed: "40 tests passed" |
| 23 | 23 of 23 | scripts/test_dbt_contracts.py | confirmed: "23 of 23 cases behaved as expected" |
| 2 | under 2 percentage | derived: daily against weekly-on-Thursday mean staleness, largest gap 1.61 pp, from analysis/phase4/R4_refresh_day_matrix.sql | confirmed inputs |
| 3.4% | 3.4% and 21.3% | analysis/phase2/Q2a_presale_inflation.sql | confirmed: 3.39 |
| 21.3% | 3.4% and 21.3% | analysis/phase2/Q2a_presale_inflation.sql | confirmed: 21.27 |
| 100% | 100% of 711 | analysis/phase2/Q3c_pairwise_stability.sql | checked 2026-09-12, tie case closed, as the writeup entry: 711 of 711, 0 dates at exactly 1.0, closest 1.0264 |
| 711 | 100% of 711 | analysis/phase2/Q3c_pairwise_stability.sql | confirmed |
| 8 | all 8 categories | analysis/phase2/Q3c_pairwise_stability.sql | confirmed: re-run 2026-09-12, 8 categories for Metro / Walmart |
| 12.6% | 12.6% | derived: 1 − 1/1.1447 from analysis/phase2/Q3c_pairwise_stability.sql | confirmed input |
| 51% | (51%) | analysis/phase2/Q3c_pairwise_stability.sql | confirmed: 50.96 |
| 22.6% | about 22.6% | analysis/phase2/Q3b_basket_blindspot.sql | confirmed |
| 40 | 40 tests, both | scripts/run_dbt_tests.py | confirmed |
| 71.8M | 71.8M-row | analysis/phase2/Q1_exclusion_ledger.sql | confirmed: 71,809,333 |
| 3GB | 3GB | not-a-figure: a memory-limit parameter in an example command | — |
| 6 | (6 of 6) | scripts/test_check_schema.py | confirmed: re-run 2026-09-12 |
| 8 | (8 of 8) | scripts/test_check_determinism.py | confirmed: re-run 2026-09-12 |
| 23 | (23 of 23) | scripts/test_dbt_contracts.py | confirmed |
| 7 | (7 of 7) | scripts/test_check_claims.py | confirmed: run 2026-09-12 |
| 7 | refused  (7 of 7) | scripts/test_check_light_parity.py | confirmed: run 2026-09-12 |
| 12 | (12 of 12) | scripts/test_netlify_changes.py | confirmed: run 2026-09-12 |
| 1.4 GB | ~1.4 GB | derived: 498,288,065 + 950,260,692 bytes recorded by scripts/fetch_snapshot.py | the snapshot manifest's archive sizes |

## docs/method-note.md

| Figure | Anchor | Source | Note |
|---|---|---|---|
| 97% | 97% | analysis/phase4/R6_save_on_foods_store_ids.sql | confirmed: 15,766 of 16,258, 96.97%, tool snapshot. Had no committed source until this sweep |
| 17.9% | about 17.9% cheaper | derived: 1 − 1/1.2186 from analysis/phase2/Q3c_pairwise_stability.sql | confirmed input; withdrawn comparison |
| 5.3% | about 5.3% cheaper | derived: 1 − 0.9475 from analysis/phase2/Q3c_pairwise_stability.sql | confirmed input; withdrawn comparison |
| 6 | 6 of 6 cases | scripts/test_check_schema.py | confirmed: re-run 2026-09-12 |
| 8 | 8 of 8 cases | scripts/test_check_determinism.py | confirmed: re-run 2026-09-12 |
| 5 | 5 of 5 cases | scripts/test_verify_twice.py | confirmed: re-run 2026-09-12 |
| 22 | 22 of 22 columns | scripts/verify_reproducible.py | confirmed: "matches its definition across 22 columns" |
| 40 | 40 contract tests | scripts/run_dbt_tests.py | confirmed |
| 23 | 23 of 23 injected | scripts/test_dbt_contracts.py | confirmed |
| 1.70× | 1.70× | derived: 29.9058 / 17.6263 from analysis/phase2/Q1_exclusion_ledger.sql | confirmed inputs: pooled % sale, orphan against retained |
| 72.6% | 72.6% | derived: 637,508 / 878,559 from analysis/phase2/Q1b_bias_controls.sql | confirmed inputs |
| 1.22× | **1.22×** | analysis/phase2/Q1b_bias_controls.sql | confirmed: Metro ratio 1.224 |
| 11× | 11× | derived: 9.348 / 0.843 (pooled % multibuy, orphan against retained) from analysis/phase2/Q1_exclusion_ledger.sql | confirmed inputs: offer-type mix statement, 82,130 of 878,559 orphan rows against 597,793 of 70,883,862 retained; 11.09 |
| 1.77× | 1.77× | analysis/phase2/Q1b_bias_controls.sql | confirmed |
| 614 | **614** | derived: 57,212 − 56,598 from three runs of analysis/phase1/P2_9_bare_integer_adjudication.sql | historical: the pre-fix query, recorded in Phase 1 findings; the fixed query no longer varies, by design |
| 44 | **44** constructs | scripts/check_determinism.py | historical: its first run, Phase 2 findings §1.3; the count grows as queries are added |
| 16 | 16 were | scripts/check_determinism.py | historical: first run disposition |
| 28 | other 28 | scripts/check_determinism.py | historical: first run disposition |
| 3 | position 3 | not-a-figure: a column position in a SQL GROUP BY | — |
| 105,540 | 105,540 | provenance-lost | matches no state that can be reconstructed; recorded as lost in Phase 1 findings §5.8 and CLAUDE.md honesty rule 5 |
| 71,809,333 | 71,809,333 | analysis/phase2/Q1_exclusion_ledger.sql | confirmed |
| 70,883,862 | 70,883,862 | analysis/phase2/Q1_exclusion_ledger.sql | confirmed |
| 98.71% | 98.71% | analysis/phase2/Q1_exclusion_ledger.sql | confirmed |
| 878,559 | 878,559 | analysis/phase2/Q1_exclusion_ledger.sql | confirmed |
| 1.22% | 1.22% | analysis/phase2/Q1_exclusion_ledger.sql | confirmed: 1.2235 |
| 26.8% | 26.8% | analysis/phase2/Q1b_bias_controls.sql | confirmed: 26.766 |
| 0.4% | 0.4% | analysis/phase2/Q1b_bias_controls.sql | confirmed: 0.409 |
| 46,884 | 46,884 | analysis/phase2/Q1_exclusion_ledger.sql | confirmed |
| 0.07% | 0.07% | analysis/phase2/Q1_exclusion_ledger.sql | confirmed |
| 28 | 28 *(of 33 | analysis/phase2/Q1_exclusion_ledger.sql | confirmed: 28 unparsed in the disjoint ledger |
| 33 | of 33; | analysis/phase1/P5_6_both_snapshots_parse.sql | traced: 33 unparsed rows in snapshot 1 |
| 5 | other 5 are | analysis/phase2/Q1_exclusion_ledger.sql | traced: Phase 2 findings, 5 rows both orphan and unparsed |
| 8,797 | 8,797 sale events | analysis/phase2/Q1d_sku_filter_audit.sql | confirmed |
| 0.19% | 0.19% | derived: 539 / (279,599 + 539) from analysis/phase2/Q1d_sku_filter_audit.sql | confirmed inputs |
| 7 | 7 of 7 cases | scripts/test_check_claims.py | confirmed: run 2026-09-12 |
| 0.196 | correlation of 0.196 | analysis/phase2/Q2e_flag_rank_correlation.sql | confirmed |
| 197 | 197 figure occurrences | scripts/check_claims.py | confirmed: `--inventory` over the three documents as committed at 66ecb20, before this paragraph existed: 125 + 33 + 39 |
| 1 | and 1 with no | derived: the one figure for which the sweep had to write a new source, analysis/phase4/R6_save_on_foods_store_ids.sql, whose header records why | every other figure had a committed source before the sweep began |
| 15,766 | (15,766 of 16,258) | analysis/phase4/R6_save_on_foods_store_ids.sql | confirmed: store 2210, pickup |
| 16,258 | (15,766 of 16,258) | analysis/phase4/R6_save_on_foods_store_ids.sql | confirmed: all Save-On-Foods products, tool snapshot |
| 614 | that way; 614 | derived: 57,212 − 56,598 from three runs of analysis/phase1/P2_9_bare_integer_adjudication.sql | historical, as above |
| 44 | lint's 44 | scripts/check_determinism.py | historical: first run, as above |
| 16 | (16 plus 28) | scripts/check_determinism.py | historical: first run disposition |
| 28 | (16 plus 28) | scripts/check_determinism.py | historical: first run disposition |
| 197 | "197 figures checked" | scripts/check_claims.py | confirmed: the sweep's count, as above |
| 6,613 | counts 6,613 | scripts/check_claims.py | confirmed 2026-09-12: `--inventory --docs` over phase-0, 1, 2 and 4 findings and upstream-feedback.md, 1,641 + 1,868 + 1,833 + 996 + 275. Unreviewed extractor count; the document says so |
| 197 | 197 in these three | scripts/check_claims.py | confirmed: the sweep's count, as above |
