{# The parsing macros are plain DuckDB CREATE MACRO statements, shared with
   run_query.py and verify_reproducible.py which have no dbt in them. DuckDB persists
   macros in the database catalog, so they survive between sessions -- which means dbt
   does not need to re-declare them, only to insist they are present.

   Rewriting them as Jinja macros would create a second definition that could drift from
   the first, and the plain-SQL path would silently keep using the old one. One
   definition, loaded by scripts/build_models.py, asserted here. #}
{% macro assert_duckdb_macros() %}
  {% if execute %}
    {% set probe %}
      SELECT p_offer_type('3.29') AS a, u_uom('500g') AS b,
             b_class('Metro', 'SELECTION') AS c,
             product_key('Metro', '123', 'x') AS d
    {% endset %}
    {% set results = run_query(probe) %}
    {% if results is none or results.rows | length == 0 %}
      {{ exceptions.raise_compiler_error(
           "DuckDB parsing macros are not loaded in this database. "
           "Run: python scripts/build_models.py --db hammer.duckdb") }}
    {% endif %}
  {% endif %}
  {{ return('') }}
{% endmacro %}
