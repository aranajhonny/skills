# MySQL dump + migrations → SQLite .db for DBeaver ER Diagram

When the user wants a DBeaver/phpMyAdmin-style ER diagram (visible relations,
FK lines, table layout) but there's no local MySQL or production must not be
touched: **generate a SQLite `.db` file and open it in DBeaver → right click →
ER Diagram**.

- Don't use Excalidraw or HTML for this — the user rejects it explicitly
  ("I asked for the excalidraw not html" / "it doesn't work for me"). They want
  DBeaver's native ER.
- SQLite needs no server: it's a file. DBeaver opens it as a SQLite connection.
- Don't touch production: the dump is a copy; migrations apply only to the .db.

## Recipe (Python + sqlite3, stdlib)

1. **Extract CREATE TABLE from the dump**: mysqldump emits
   `DROP TABLE IF EXISTS \`t\`;` before each table. Split on
   `DROP TABLE IF EXISTS`, and in each block search for
   `(CREATE TABLE\s+\`?\w+\`?\s*\(.+?\)\s*ENGINE[^;]*;)` with DOTALL.
   - The non-greedy `.+?` cuts at the FIRST `)` — fails with nested
     ENUM/COMMENT. If it fails, parse manually: find the opening `(` and count
     depth until the balanced closing parenthesis.
2. **Clean MySQL syntax** (critical, naive conversion fails):
   - Remove: `ENGINE=...`, `DEFAULT CHARSET=...`, `COLLATE=...`,
     `AUTO_INCREMENT=\d+`, `ON UPDATE CURRENT_TIMESTAMP`, `CHARACTER SET \S+`,
     `unsigned`, `ZEROFILL`
   - Remove `COMMENT '...'` — careful with multi-line comments and internal
     commas: `COMMENT\s+'[^']*'\s*,` (with DOTALL flags) before splitting on
     commas.
   - Types: BIGINT/INT/TINYINT/SMALLINT/MEDIUMINT/YEAR → INTEGER;
     DECIMAL/FLOAT/DOUBLE → REAL; VARCHAR/CHAR/TEXT/LONGTEXT/ENUM/JSON/BLOB/TIMESTAMP/DATETIME/DATE → TEXT
   - `AUTO_INCREMENT` → REMOVE completely (SQLite auto-increments with
     `INTEGER PRIMARY KEY`; leaving `AUTOINCREMENT` loose gives a syntax error).
   - `CURRENT_TIMESTAMP` → `(datetime('now'))`; `NOW()` → `datetime('now')`
   - Backticks → bare (`re.sub(r'`(\w+)`', r'\1', sql)`)
3. **FOREIGN KEY with CONSTRAINT**: the dump uses
   `CONSTRAINT \`fk_name\` FOREIGN KEY (...) REFERENCES ...`. `re.match` doesn't
   catch it (the line starts with CONSTRAINT). Use `re.search` for
   `FOREIGN\s+KEY\s*\(([^)]+)\)\s*REFERENCES\s+`?(\w+)`?\s*\(([^)]+)\)`.
   Re-emit as `FOREIGN KEY (col) REFERENCES tbl(col)` at the end of the CREATE.
   - Without this, DBeaver shows the tables WITHOUT relation lines (the FKs are
     lost).
4. **KEY/INDEX/PRIMARY lines**: discard them; FKs are re-emitted separately.
   Column with inline `AUTO_INCREMENT` → `INTEGER PRIMARY KEY AUTOINCREMENT`.
5. **ALTER TABLE ADD COLUMN** (migrations on existing tables): convert the type
   and run `ALTER TABLE t ADD COLUMN c tipo`; ignore MODIFY/CHANGE in SQLite.
6. **Views**: recreate with `CREATE VIEW IF NOT EXISTS` (mysqldump doesn't bring
   them as VIEW).
7. **Verify**: (a) tables in source == tables in sqlite_master;
   (b) each expected table exists — a CREATE that fails silently leaves holes
   (e.g. `planes_mantenimiento` failed on the ENUM parser; recreate it manually
   with simple SQLite types and reference the same tables).

## Reference structure of the maintenance schema (Track)

Scalability chain by variable type:
`capacidades_por_modelo.tipo_sensor` (catalog, INSERT) → `sensores_instalados`
(concrete sensor on an asset) → `lecturas.valor` (readings). The maintenance
plan references `sensores_instalados(id)`, not the catalog.

New module tables (26): roles (4) + categorias_inventario + inventario (3) +
OT (7, includes firmas_ot) + planes (11) + technicians/third parties.
Doc: docs/mantenimiento-fundacion.md.