# MySQL dump + migraciones → SQLite .db para ER Diagram en DBeaver

Cuando el usuario quiere un diagrama ER estilo DBeaver/phpMyAdmin (relaciones visibles,
líneas FK, layout de tablas) pero no hay MySQL local o no se quiere tocar producción:
**generar un archivo SQLite `.db` y abrirlo en DBeaver → click derecho → ER Diagram**.

- No usar Excalidraw ni HTML para esto — el usuario lo rechaza explícitamente
  ("te pedí el excalidraw no html" / "no me sirve"). Quiere el ER nativo de DBeaver.
- SQLite no requiere servidor: es un archivo. DBeaver lo abre como conexión SQLite.
- No tocar producción: el dump es copia; las migraciones se aplican solo al .db.

## Receta (Python + sqlite3, stdlib)

1. **Extraer CREATE TABLE del dump**: mysqldump emite `DROP TABLE IF EXISTS \`t\`;`
   antes de cada tabla. Splitear por `DROP TABLE IF EXISTS`, y en cada bloque buscar
   `(CREATE TABLE\s+`?\w+`?\s*\(.+?\)\s*ENGINE[^;]*;)` con DOTALL.
   - El `.+?` no-greedy corta en el PRIMER `)` — falla con ENUM/COMMENT anidados.
     Si falla, parsear manualmente: encontrar el `(` de apertura y contar profundidad
     hasta el paréntesis de cierre balanceado.
2. **Limpiar sintaxis MySQL** (crítico, la conversión ingenua falla):
   - Quitar: `ENGINE=...`, `DEFAULT CHARSET=...`, `COLLATE=...`, `AUTO_INCREMENT=\d+`,
     `ON UPDATE CURRENT_TIMESTAMP`, `CHARACTER SET \S+`, `unsigned`, `ZEROFILL`
   - Quitar `COMMENT '...'` — ojo con comentarios multi-línea y comas internas:
     `COMMENT\s+'[^']*'\s*,` (con flags DOTALL) antes de partir por comas.
   - Tipos: BIGINT/INT/TINYINT/SMALLINT/MEDIUMINT/YEAR → INTEGER;
     DECIMAL/FLOAT/DOUBLE → REAL; VARCHAR/CHAR/TEXT/LONGTEXT/ENUM/JSON/BLOB/TIMESTAMP/DATETIME/DATE → TEXT
   - `AUTO_INCREMENT` → ELIMINAR por completo (SQLite auto-incrementa con
     `INTEGER PRIMARY KEY`; dejar `AUTOINCREMENT` suelto da syntax error).
   - `CURRENT_TIMESTAMP` → `(datetime('now'))`; `NOW()` → `datetime('now')`
   - Backticks → desnudos (`re.sub(r'`(\w+)`', r'\1', sql)`)
3. **FOREIGN KEY con CONSTRAINT**: el dump usa
   `CONSTRAINT \`fk_name\` FOREIGN KEY (...) REFERENCES ...`. `re.match` no lo agarra
   (la línea empieza con CONSTRAINT). Usar `re.search` para
   `FOREIGN\s+KEY\s*\(([^)]+)\)\s*REFERENCES\s+`?(\w+)`?\s*\(([^)]+)\)`.
   Re-emitir como `FOREIGN KEY (col) REFERENCES tbl(col)` al final del CREATE.
   - Sin esto, DBeaver muestra las tablas SIN líneas de relación (los FKs se pierden).
4. **Líneas KEY/INDEX/PRIMARY**: descartarlas; los FKs se re-emiten aparte.
   Columna con `AUTO_INCREMENT` inline → `INTEGER PRIMARY KEY AUTOINCREMENT`.
5. **ALTER TABLE ADD COLUMN** (migraciones sobre tablas existentes): convertir el tipo
   y ejecutar `ALTER TABLE t ADD COLUMN c tipo`; ignorar MODIFY/CHANGE en SQLite.
6. **Vistas**: recrear con `CREATE VIEW IF NOT EXISTS` (mysqldump no las trae como VIEW).
7. **Verificar**: (a) tablas en fuente == tablas en sqlite_master;
   (b) cada tabla esperada existe — una CREATE que falla en silencio deja huecos
   (ej. `planes_mantenimiento` falló por parser de ENUM; recrearla manualmente con
   tipos SQLite simples y referenciar las mismas tablas).

## Estructura de referencia del esquema de mantenimiento (Track)

Cadena de escalabilidad por tipo de variable:
`capacidades_por_modelo.tipo_sensor` (catálogo, INSERT) → `sensores_instalados`
(sensor concreto en activo) → `lecturas.valor` (lecturas). El plan de mantenimiento
referencia `sensores_instalados(id)`, no el catálogo.

Tablas nuevas del módulo (26): roles (4) + categorias_inventario + inventario (3) +
OT (7, incluye firmas_ot) + planes (11) + técnicos/terceros. Doc: docs/mantenimiento-fundacion.md.
