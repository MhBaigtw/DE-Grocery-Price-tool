-- N1: what type is raw.nowtime, in both forms of the archive, as each layer reports it.
-- Incident report sections 2 and 5 ("Schema"). Run with run_incident_query.py: `n` is the
-- new-form archive, `o` the old-form one.
--
-- Three answers, because they are three different questions:
--   * what upstream DECLARED (the CREATE TABLE text),
--   * what SQLite actually STORES per value (typeof -- SQLite types are per value, so a
--     column declared INTEGER could still hold text in some rows),
--   * what DuckDB REPORTS after reading it, which is what scripts/check_schema.py sees.

-- 1. The declarations.
SELECT 'new' AS archive, name, sql
FROM sqlite_query(n, 'SELECT name, sql FROM sqlite_master WHERE type = ''table'' AND name IN (''raw'', ''product'')')
UNION ALL
SELECT 'old', name, sql
FROM sqlite_query(o, 'SELECT name, sql FROM sqlite_master WHERE type = ''table'' AND name IN (''raw'', ''product'')')
ORDER BY archive, name;

-- 2. The storage class of every nowtime value. DuckDB's scanner reads a column through
--    its declared type, so this asks SQLite itself, per row.
SELECT 'new' AS archive, t AS sqlite_typeof, n_rows
FROM sqlite_query(n, 'SELECT typeof(nowtime) AS t, count(*) AS n_rows FROM raw GROUP BY 1')
UNION ALL
SELECT 'old', t, n_rows
FROM sqlite_query(o, 'SELECT typeof(nowtime) AS t, count(*) AS n_rows FROM raw GROUP BY 1')
ORDER BY archive, sqlite_typeof;

-- 3. What DuckDB reports: every column of both tables, both archives. This is the
--    comparison against config/expected_schema.json -- nowtime is the only difference.
SELECT table_name, column_index AS position, column_name,
       max(data_type) FILTER (WHERE database_name = 'o') AS type_old,
       max(data_type) FILTER (WHERE database_name = 'n') AS type_new,
       max(data_type) FILTER (WHERE database_name = 'o')
         IS DISTINCT FROM max(data_type) FILTER (WHERE database_name = 'n') AS changed
FROM duckdb_columns()
WHERE database_name IN ('n', 'o') AND table_name IN ('raw', 'product')
GROUP BY table_name, column_index, column_name
ORDER BY table_name, position, column_name;

-- 4. raw.product_id specifically: the change that WAS announced has not landed.
SELECT 'new' AS archive, t AS sqlite_typeof, n_rows
FROM sqlite_query(n, 'SELECT typeof(product_id) AS t, count(*) AS n_rows FROM raw GROUP BY 1')
ORDER BY sqlite_typeof;
