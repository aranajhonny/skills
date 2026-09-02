# MySQL DB Audit Queries

Utility queries for reviewing a production MySQL/MariaDB database.

## Table sizes & row counts

```sql
SELECT TABLE_NAME, TABLE_ROWS,
       ROUND((DATA_LENGTH + INDEX_LENGTH)/1024/1024, 1) AS SIZE_MB,
       ENGINE, TABLE_COLLATION
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = '<database>'
ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC
LIMIT 30;
```

## Column types

```sql
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = '<database>'
  AND DATA_TYPE IN ('text', 'mediumtext', 'longtext')
  AND TABLE_NAME NOT LIKE 'telemetria%'
ORDER BY TABLE_NAME;
```

## Index audit

```sql
-- All indexes grouped (detect duplicates)
SELECT TABLE_NAME, INDEX_NAME, NON_UNIQUE,
       GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS COLUMNS
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = '<database>'
GROUP BY TABLE_NAME, INDEX_NAME, NON_UNIQUE
ORDER BY TABLE_NAME, INDEX_NAME;

-- Tables with no non-PK indexes (seq scan risks)
SELECT t.TABLE_NAME, t.TABLE_ROWS
FROM information_schema.TABLES t
LEFT JOIN information_schema.STATISTICS s
  ON s.TABLE_SCHEMA = t.TABLE_SCHEMA AND s.TABLE_NAME = t.TABLE_NAME
  AND s.INDEX_NAME != 'PRIMARY'
WHERE t.TABLE_SCHEMA = '<database>' AND t.TABLE_ROWS > 0
  AND s.INDEX_NAME IS NULL
ORDER BY t.TABLE_ROWS DESC;
```

## FK constraints

```sql
SELECT TABLE_NAME, CONSTRAINT_NAME, COLUMN_NAME,
       REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = '<database>' AND REFERENCED_TABLE_SCHEMA = '<database>';
```

## Character set audit

```sql
SELECT TABLE_NAME, TABLE_COLLATION, TABLE_ROWS
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = '<database>'
  AND TABLE_COLLATION LIKE 'utf8mb3%'
ORDER BY TABLE_ROWS DESC;
```

## Auto_increment churn

```sql
SELECT TABLE_NAME, AUTO_INCREMENT, TABLE_ROWS,
       (AUTO_INCREMENT - TABLE_ROWS) AS churn
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = '<database>' AND AUTO_INCREMENT IS NOT NULL
ORDER BY churn DESC;
```

## Zero-date check

```sql
SELECT TABLE_NAME, COLUMN_NAME
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = '<database>'
  AND DATA_TYPE IN ('timestamp', 'datetime')
  AND IS_NULLABLE = 'NO'
  AND COLUMN_DEFAULT IS NULL
ORDER BY TABLE_NAME;
```

Then sample actual zero-dates:
```sql
SELECT COUNT(*) AS zero_dates, MIN(fecha_col) AS oldest, MAX(fecha_col) AS newest
FROM <table>
WHERE fecha_col = '0000-00-00 00:00:00';
```

## FK columns without indexes

Detect FK columns that have no index (causes cascading seq scans on JOINs):

```sql
SELECT k.TABLE_NAME, k.COLUMN_NAME, k.CONSTRAINT_NAME,
       k.REFERENCED_TABLE_NAME, k.REFERENCED_COLUMN_NAME
FROM information_schema.KEY_COLUMN_USAGE k
LEFT JOIN information_schema.STATISTICS s
  ON s.TABLE_SCHEMA = k.TABLE_SCHEMA
  AND s.TABLE_NAME = k.TABLE_NAME
  AND s.COLUMN_NAME = k.COLUMN_NAME
WHERE k.TABLE_SCHEMA = '<database>'
  AND k.REFERENCED_TABLE_SCHEMA = '<database>'
  AND s.COLUMN_NAME IS NULL
ORDER BY k.TABLE_NAME, k.COLUMN_NAME;
```

## Data distribution sampling

For a suspected TEXT/VARCHAR that should be numeric:

```sql
SELECT
  CASE
    WHEN valor IS NULL THEN 'NULL'
    WHEN valor = '' THEN 'vacio'
    WHEN valor = '0' THEN 'cero'
    WHEN valor = '1' THEN 'uno'
    WHEN valor REGEXP '^-?[0-9]+$' THEN 'entero'
    WHEN valor REGEXP '^-?[0-9]+\\\\.[0-9]+$' THEN 'decimal'
    WHEN LEFT(valor, 1) = '{' THEN 'JSON'
    ELSE CONCAT('otro: ', LEFT(valor, 50))
  END AS categoria,
  COUNT(*) AS total
FROM <table>
GROUP BY categoria
ORDER BY total DESC;
```
