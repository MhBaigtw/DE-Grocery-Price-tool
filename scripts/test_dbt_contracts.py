#!/usr/bin/env python3
"""Prove every dbt test in this project fails when it should.

Phase 1 brief 5.3: "Each test must be shown to fail when it should. A test that has never
failed has not been tested -- same standard as the schema check's control case."

METHOD, and why it is not run against the real database.

The obvious approach -- break a row in `stg_price` and watch the test go red -- is not
available. The analysis database is a 71.8M-row materialisation that CLAUDE.md's locked
decision 2 and `verify_reproducible.py` both require to be a pure function of an immutable
snapshot. Mutating it to test a test would destroy exactly the property the test suite
exists to protect, and rebuilding it afterwards costs an hour.

So this builds a FIXTURE database instead: tiny tables with the same names, columns and
types as the real models, populated with a handful of rows that satisfy every contract.
Then, for each test in turn:

  1. rebuild the clean fixture,
  2. inject one violation aimed at that specific test,
  3. run ONLY that test, and require it to FAIL.

Plus a CONTROL: the clean fixture with nothing injected must pass EVERY test. Without the
control, a suite that failed on everything would score a perfect result -- the same trap
`test_check_schema.py` documents.

The tests are the committed ones. Nothing is re-implemented here; dbt compiles and runs
the same SQL that runs against the real database, which is the only way this proves
anything about the real tests.

Exit codes: 0 all cases behaved as expected, 1 a case did not, 2 usage/environment error.
"""
import argparse
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

import duckdb

REPO = pathlib.Path(__file__).resolve().parent.parent
DBT = REPO / "dbt"
MACROS = ("product_key_macros.sql", "price_parse_macros.sql",
          "unit_parse_macros.sql", "brand_class_macros.sql")

# ---------------------------------------------------------------------------------
# The clean fixture. Small, hand-written, and every row satisfies every contract.
# Column lists mirror models/stg_price.sql, models/stg_product.sql and
# models/int_upc_match.sql -- if a model gains a column a test depends on, this fails
# loudly at fixture-build time rather than silently skipping the test.
# ---------------------------------------------------------------------------------
CLEAN_FIXTURE = """
CREATE OR REPLACE TABLE product AS
SELECT * FROM (VALUES
  ('MetroA',      'Metro',       'A1', '00012345678905', 'Metro Thing',  'u1', 'Metro~n@500g^SELECTION', '500g', 'SELECTION'),
  ('GalleriaB',   'Galleria',    'B1', '00012345678905', 'Galleria Thing','u2','Galleria~n@500g^Kelloggs','500g','Kelloggs'),
  ('SaveOnC',     'SaveOnFoods', 'C1', '00098765432109', 'SaveOn Thing', 'u3', 'SaveOnFoods~n@1L^Western','1 L','Western Family'),
  ('LoblawsD',    'Loblaws',     'D1', '00098765432109', 'Loblaws Thing','u4', 'Loblaws~n@1L^PC',      '1 L', 'PC'),
  ('WalmartE',    'Walmart',     'E1', '4011',           'Walmart Thing','u5', 'Walmart~n@1ea^Great Value','1ea','Great Value'),
  ('VoilaF',      'Voila',       '',   '',               'Voila Thing',  'u6', 'Voila~n@2 x 500 mL^x', '2 x 500 mL', '')
) AS t(id, vendor, sku, upc, product_name, detail_url, concatted, units, brand);

CREATE OR REPLACE TABLE raw AS
SELECT * FROM (VALUES
  ('MetroA',   '2026-08-01 10:00:00', '3.29',    'was',    '$3.29/500g', ''),
  ('MetroA',   '2026-08-02 10:00:00', '2/$7.00', NULL,     NULL,         'salepricefound'),
  ('GalleriaB','2026-08-01 10:00:00', '4.99',    NULL,     NULL,         ''),
  ('SaveOnC',  '2026-08-01 10:00:00', '36.90/kg',NULL,     NULL,         ''),
  ('LoblawsD', '2026-08-01 10:00:00', '329$',    '4.99',   NULL,         'salepricefound'),
  ('WalmartE', '2026-08-01 10:00:00', 'Now$298', '99¢', NULL,       'salepricefound'),
  ('VoilaF',   '2026-08-01 10:00:00', '',        NULL,     NULL,         ''),
  ('MissingXX','2026-08-01 10:00:00', '1.99',    NULL,     NULL,         '')
) AS t(product_id, nowtime, current_price, old_price, price_per_unit, other);
"""


def build_fixture(db_path: pathlib.Path) -> None:
    """Create the fixture database: sources, macros, then the three models."""
    if db_path.exists():
        db_path.unlink()
    con = duckdb.connect(str(db_path))
    con.execute("PRAGMA disable_progress_bar;")
    for mf in MACROS:
        con.execute((REPO / "models" / mf).read_text(encoding="utf-8"))
    con.execute(CLEAN_FIXTURE)
    # The models are built from the SAME committed SQL the real build uses. `rowid` is
    # not stable on a VALUES-built table, so src_rowid is assigned here instead.
    stg_price = (REPO / "models" / "stg_price.sql").read_text(encoding="utf-8")
    stg_price = stg_price.replace("r.rowid", "row_number() OVER ()")
    con.execute(f"CREATE OR REPLACE TABLE stg_price AS {stg_price}")
    con.execute("CREATE OR REPLACE TABLE stg_product AS "
                + (REPO / "models" / "stg_product.sql").read_text(encoding="utf-8"))
    con.execute("CREATE OR REPLACE TABLE int_upc_match AS "
                + (REPO / "models" / "int_upc_match.sql").read_text(encoding="utf-8"))
    con.close()


# ---------------------------------------------------------------------------------
# One violation per test. Each is the smallest edit that breaks exactly that contract.
# Keyed by the dbt node name so `dbt test --select <name>` runs only that one.
# ---------------------------------------------------------------------------------
INJECTIONS = {
    # --- singular tests -------------------------------------------------------------
    "assert_stg_price_rowcount_matches_raw":
        "DELETE FROM stg_price WHERE src_rowid = (SELECT min(src_rowid) FROM stg_price)",
    "assert_stg_product_rowcount_matches_product":
        "DELETE FROM stg_product WHERE vendor = 'Voila'",
    "assert_int_upc_match_rowcount_matches_stg_product":
        "DELETE FROM int_upc_match WHERE vendor = 'Voila'",
    "assert_no_price_row_lost_to_parsing":
        # the naive-CAST failure: a row with no price and no explicit unparsed verdict
        "UPDATE stg_price SET unit_price = NULL, offer_type = 'scalar' "
        "WHERE current_price_raw = '3.29'",
    "assert_multibuy_never_stripped_to_total":
        # '2/$7.00' stripped to its total instead of divided
        "UPDATE stg_price SET unit_price = 7.00 WHERE current_price_raw = '2/$7.00'",
    "assert_cents_form_never_read_as_dollars":
        # '329$' read as $329.00
        "UPDATE stg_price SET unit_price = 329.00 WHERE current_price_raw = '329$'",
    "assert_junk_brand_never_national":
        # an unknown brand falling through to a real category
        "UPDATE stg_product SET brand_raw = 'Out of stock', brand_class = 'national_brand' "
        "WHERE vendor = 'Walmart'",
    "assert_match_tier_is_weakest_participant":
        # a Loblaws-carried GTIN laundered up to its strongest participant
        "UPDATE int_upc_match SET match_tier = 'vendor_upc' "
        "WHERE gtin14 = '00098765432109'",
    "assert_reliable_only_excludes_fuzzy":
        "UPDATE int_upc_match SET is_reliable_only = true "
        "WHERE gtin14 = '00098765432109'",
    # --- generic (schema.yml) tests --------------------------------------------------
    "unique_stg_product_product_key":
        "INSERT INTO stg_product SELECT * FROM stg_product LIMIT 1",
    "not_null_stg_product_product_key":
        "UPDATE stg_product SET product_key = NULL WHERE vendor = 'Metro'",
    "unique_stg_price_src_rowid":
        "INSERT INTO stg_price SELECT * FROM stg_price LIMIT 1",
    "not_null_stg_price_src_rowid":
        "UPDATE stg_price SET src_rowid = NULL WHERE current_price_raw = '3.29'",
    "accepted_values_stg_price_offer_type__scalar__multibuy__per_weight__unparsed__blank":
        "UPDATE stg_price SET offer_type = 'mystery' WHERE current_price_raw = '3.29'",
    "accepted_values_stg_price_price_basis__each__per_100g__per_100ml":
        "UPDATE stg_price SET price_basis = 'per_lb' WHERE current_price_raw = '36.90/kg'",
    "not_null_stg_price_parse_confidence":
        "UPDATE stg_price SET parse_confidence = NULL WHERE current_price_raw = '3.29'",
    "relationships_stg_price_product_key__product_key__ref_stg_product_":
        "UPDATE stg_price SET product_key = md5('orphan') WHERE current_price_raw = '3.29'",
    "unique_int_upc_match_product_key":
        "INSERT INTO int_upc_match SELECT * FROM int_upc_match LIMIT 1",
    "accepted_values_int_upc_match_match_tier__vendor_upc__matched_upc__fuzzy__unmatched__no_upc__plu_short":
        "UPDATE int_upc_match SET match_tier = 'guessed' WHERE vendor = 'Metro'",
    "accepted_values_stg_product_brand_class__private_label__national_brand__unclassifiable_blank__unclassifiable_junk__unclassifiable_no_vendor_data":
        "UPDATE stg_product SET brand_class = 'probably_national' WHERE vendor = 'Metro'",
    "accepted_values_stg_product_vendor__Metro__Galleria__SaveOnFoods__Walmart__Loblaws__NoFrills__TandT__Voila":
        "UPDATE stg_product SET vendor = 'Costco' WHERE vendor = 'Metro'",
    "accepted_values_stg_product_product_key_basis__vendor_sku__vendor_concatted":
        "UPDATE stg_product SET product_key_basis = 'guess' WHERE vendor = 'Metro'",
}


def run_dbt(args: list[str], db_path: pathlib.Path) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env["FIXTURE_DB"] = str(db_path)
    env["DBT_PROFILES_DIR"] = str(DBT)
    return subprocess.run([sys.executable, "-m", "dbt.cli.main", *args,
                           "--target", "fixture", "--project-dir", str(DBT)],
                          capture_output=True, text=True, env=env, cwd=str(REPO))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="keep the fixture database")
    ap.add_argument("--only", default=None, help="run one case by name")
    args = ap.parse_args()

    workdir = pathlib.Path(tempfile.mkdtemp(prefix="dbt_contract_"))
    db_path = workdir / "fixture.duckdb"
    results, failures = [], 0

    try:
        # ---- CONTROL: clean fixture must pass every test --------------------------
        build_fixture(db_path)
        proc = run_dbt(["test"], db_path)
        control_ok = proc.returncode == 0
        n_tests = proc.stdout.count("PASS ")
        results.append(("CONTROL clean fixture passes every test", control_ok,
                        f"exit {proc.returncode}, {n_tests} tests passed"))
        if not control_ok:
            failures += 1
            print(proc.stdout[-4000:], file=sys.stderr)

        # ---- one violation per test ------------------------------------------------
        for name, sql in INJECTIONS.items():
            if args.only and args.only != name:
                continue
            build_fixture(db_path)
            con = duckdb.connect(str(db_path))
            con.execute(sql)
            con.close()
            proc = run_dbt(["test", "--select", name], db_path)
            ran = "1 of 1" in proc.stdout or "ERROR" in proc.stdout or "FAIL" in proc.stdout
            caught = proc.returncode != 0
            ok = caught and ran
            results.append((name, ok,
                            f"exit {proc.returncode}" if ran
                            else "TEST DID NOT RUN -- name may not match a dbt node"))
            if not ok:
                failures += 1
                print(f"\n--- {name} did not fail as expected ---", file=sys.stderr)
                print(proc.stdout[-3000:], file=sys.stderr)
    finally:
        if not args.keep:
            shutil.rmtree(workdir, ignore_errors=True)
        else:
            print(f"\nfixture kept at {workdir}")

    width = max(len(r[0]) for r in results)
    print()
    for name, ok, note in results:
        print(f"{'PASS' if ok else 'FAIL'}  {name:<{width}}  ({note})")
    print(f"\n{len(results) - failures} of {len(results)} cases behaved as expected.")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
