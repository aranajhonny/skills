---
name: database-schema-review
description: "Use when asked to audit/review a production database schema for improvements — identify type mismatches, index issues, charset problems, and code-schema gaps."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [database, audit, review, schema, mysql, postgres]
    related_skills: [postgres-survival-guide]
---

# Database Schema Review

Systematic workflow for auditing a production database schema and identifying improvements, prioritized by impact vs effort.

## Workflow

### 1. Get table sizes & row counts
Identify the largest tables first. The biggest table is where the biggest wins live.

### 2. Check data types
Look for `TEXT`/`VARCHAR(255)` used where `DECIMAL`/`INT`/`NUMERIC` belongs. Sample actual data to quantify the distribution:

```sql
SELECT
  CASE
    WHEN valor IS NULL THEN 'NULL'
    WHEN valor = '' THEN 'empty'
    WHEN valor = '0' THEN 'zero'
    WHEN valor = '1' THEN 'one'
    WHEN valor REGEXP '^-?[0-9]+$' THEN 'integer'
    WHEN valor REGEXP '^-?[0-9]+\\\\.[0-9]+$' THEN 'decimal'
    WHEN LEFT(valor, 1) = '{' THEN 'JSON'
    ELSE CONCAT('other: ', LEFT(valor, 50))
  END AS categoria,
  COUNT(*) AS total
FROM <table>
GROUP BY categoria
ORDER BY total DESC;
```

**Quick numeric check** (for columns that should be numeric):
```sql
SELECT
  SUM(CASE WHEN valor REGEXP '^-?[0-9]+(\\\\.[0-9]+)?$' THEN 1 ELSE 0 END) AS numeric_values,
  SUM(CASE WHEN valor REGEXP '^-?[0-9]+(\\\\.[0-9]+)?$' THEN 0 ELSE 1 END) AS non_numeric_values
FROM <table>;
```
### 3. Cross-reference schema with code

This is the most important step. Don't just say "change TEXT to DECIMAL" — trace the INSERT/UPDATE path in the application code. Edge-case fallbacks often forced the generic type:

- A `JSON.stringify(lectura)` fallback in the code means complex sensor payloads get stored as TEXT
- A single sensor with complex data (174/7.3M rows = 0.002%) doesn't justify TEXT for the whole table
- Fix options: add a separate `valor_json` column, extract the primary value as numeric, or fix the template mapping

**Real example from a 7.3M-row IoT table:**
- 99.9976% of values were numeric (temperatures, discrete 0/1, levels)
- 0.0024% were JSON — all from ONE test sensor with complex payload (`{nvl, alt, ltr, rle}`)
- The code had `valor ?? JSON.stringify(lectura)` — a fallback that triggered when no single numeric field was found
- After cleaning the test data, the column could safely become `DECIMAL(8,2)`

**Actionable pattern:**
When the data is >99.9% numeric but TEXT, check the code for a fallback path. If the fallback covers <10 rows per million, remove it and use a separate nullable `valor_json` column for the edge case.

### 4. Audit indexes
- **Missing FK indexes**: foreign key columns without an index cause cascading seq scans on joins
- **Duplicate indexes**: same column(s), different names (e.g., `idx_activos_id` and `idx_si_activos_id` both on `activos_id`). Detect by grouping STATISTICS by (TABLE_NAME, COLUMNS):

```sql
SELECT TABLE_NAME, INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS COLUMNS
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = '<database>'
GROUP BY TABLE_NAME, INDEX_NAME
ORDER BY TABLE_NAME, COLUMNS;
```
Look for rows where the same TABLE_NAME + COLUMNS appear with different INDEX_NAMEs.
- **Redundant indexes**: index with same left-prefix as another (e.g., UNIQUE(A,B) + INDEX(A) — the INDEX is redundant)
- **Missing indexes**: tables with >100 rows and no non-PK indexes

### 5. Check character sets
`utf8mb3` is deprecated in MySQL 8.0 and removed in 9.0. All tables should be `utf8mb4` or `utf8mb4_unicode_ci`. Low urgency unless upgrading MySQL.

### 6. Check for zero-dates
`0000-00-00 00:00:00` in timestamp columns breaks date range queries and migrations. Caused by inserting NULL into NOT NULL timestamp columns with default `0000-00-00`.

### 7. Check auto_increment vs actual rows
Large gaps between `AUTO_INCREMENT` and `TABLE_ROWS` reveal churn from soft-delete/recreate patterns.

### 8. Present findings
Format as a prioritized table:

| # | Issue | Impact | Effort |
|---|---|---|---|
| 1 | TEXT column for 99.99% numeric data | 🔴 High | Medium |
| 2 | Missing index on `eventos_usuario.fecha` | 🟡 Medium | Low |
| 3 | Duplicate index on `sensores_instalados` | 🟢 Low | Minimal |

### 9. Review migration SQL files (not just live schema)

When the deliverable is migration files (not yet executed), check for:

- **MySQL-8-incompatible syntax**: `CREATE TRIGGER IF NOT EXISTS` is MariaDB-only — fails on MySQL 8.0. `DELIMITER` is a CLI client directive, not valid SQL for migration runners/ORM executors. Both are silent landmines: the migration looks right in a .sql file but dies in production.
- **Doc ↔ SQL sync**: when a design doc accompanies the migrations, cross-verify (a) table counts claimed vs `CREATE TABLE` occurrences, (b) columns the doc lists vs actual CREATE TABLE body (a column removed in SQL but still listed in the doc is the classic drift), (c) FK claims (`ALTER TABLE ... ADD FOREIGN KEY` actually present).
- **String-search false positives**: when verifying "column X removed", the doc may contain the explanatory sentence "no tiene columnas X" — substring search flags it as present. Check context, not just `in`.
- **Constraint impossibility**: a UNIQUE KEY cannot reference a column from ANOTHER table (e.g. bucket expression using a column from a related table) — structurally invalid, fails at creation.
- **Fixed-window bucket semantics**: `UNIQUE(plan_id, activos_id, FLOOR(timestamp/ventana))` does NOT implement "no duplicate within N hours since last execution" — it aligns buckets to epoch (5:59 and 6:01 land in different buckets with 6h window). Sliding-window dedup cannot be expressed as a UNIQUE constraint; it needs atomic insert-guard or advisory locks.
- **FK ordering across migration files**: a `FOREIGN KEY (col) REFERENCES tabla_futura(id)` where `tabla_futura` is CREATEd in a LATER numbered migration fails at execution (MySQL requires the referenced table to exist). This is a silent landmine: the file parses fine, DBeaver shows it, but `mysql < 05.sql` dies. Fix options: (a) column + comment without the FK constraint, (b) reorder migrations, (c) `ALTER TABLE ... ADD FOREIGN KEY` at the end of the file that creates the referenced table. When a table legitimately references a later table, use the same pattern the codebase already uses for that case (check sibling tables for precedent).
- **Verify-before-inventing (schema design)**: before creating a NEW table for a concept, grep the existing dump/schema for a table that already serves it. Real case: an `eventos_activo` table was designed as the source for an "event" trigger, with a manual button/QR workflow — the platform already had `alertas` (auto-generated when sensors cross thresholds) plus `eventos` with `tipo_evento ENUM('conexion','desconexion','alarma','configuracion','error','mantenimiento')`. New table deleted; existing `alertas` became the source. Also verify domain facts against the actual catalog before using them in examples: a "vibration sensor → golpe" example was documented but no vibration sensor exists in production — the real sensors (temperature, humidity, level, discrete door 0/1, RPM) drive all the examples.
- **Multi-tenant UNIQUE pitfalls**: a bare `UNIQUE(usuarios_id)` on a per-org child table (e.g. `tecnicos`) breaks the same user being a technician in TWO companies — must be `UNIQUE(usuarios_id, organizaciones_id)`. Similarly, business codes like `codigo` on OT/solicitudes need `UNIQUE(organizaciones_id, codigo)`, not a global UNIQUE. When adding UNIQUE constraints to tenant-scoped tables, always include the tenant column in the key.

## Common Pitfalls

1. **Reporting type mismatches without checking the code** — the code may have a deliberate fallback. Always trace the write path before suggesting a type change.
2. **Assuming TEXT is "flexible"** — TEXT forces off-page storage in InnoDB. 99.9% numeric means DECIMAL is right. Handle the 0.1% edge case with a separate column or NULL.
3. **Suggesting changes the user didn't ask for** — when user says "do nothing, just analyze", respect it literally.

## Verification Checklist

- [ ] Largest tables identified and sized
- [ ] Data types checked vs actual data distribution
- [ ] Code paths that write to suspect columns traced
- [ ] Indexes audited (missing, duplicate, redundant)
- [ ] Character set status checked
- [ ] Zero-dates checked
- [ ] Migration files checked for MySQL-8-incompatible syntax (CREATE TRIGGER IF NOT EXISTS, DELIMITER)
- [ ] Doc ↔ SQL sync verified (counts, FK claims, removed columns not still listed)
- [ ] Findings prioritized by impact vs effort
- [ ] User asked before any action is taken

## Support files

- `references/mysql-audit-queries.md` — SQL queries for schema auditing
- `references/mysql-sqlite-er-diagram.md` — convert a MySQL dump + migrations to a SQLite `.db` for DBeaver's native ER Diagram (full recipe with conversion regexes and pitfalls)
