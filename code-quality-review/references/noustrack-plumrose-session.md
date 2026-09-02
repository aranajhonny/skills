# Caso: NousTrack (Legacy PHP + PostgreSQL — Plumrose)

## Contexto de la sesión

Jhonny pidió analizar `/Users/jhonny/lab/nous` — sistema legacy PHP, ~522 archivos, PostgreSQL.
Resultó ser un sistema usado en producción en **Plumrose** (empresa de alimentos venezolana), construido
~2012-2014 por estudiantes universitarios.

## Hallazgos clave

### Arquitectura: Thin PHP over Fat PostgreSQL

- 522 archivos PHP, ninguno >800 líneas — todos son CRUD simples
- ~50+ funciones PL/pgSQL, triggers, vistas materializadas — **ahí está la lógica real**
- Patrón: PHP es capa de presentación delgada, la DB tiene el cerebro
- Sin framework, sin ORM, sin PDO — pg_query() directo
- Conexiones múltiples por página (condb.php + permisos.php + auditoria.php = 3-4 por request)

### Seguridad (mixta)

- `filtrar_campo()` con whitelist por tipo es decente para 2012
- `filtrar_sql()` escapa + bloquea DDL — no es prepared statement pero cubre lo básico
- MD5 para passwords — 🔴 obsoleto
- Hardcoded credentials `@BigNous$2014` en cada archivo — 🔴 crítico
- XSS: mensajes de sesión se renderizan sin escapar — 🟡 alto

### Lo más valioso: el modelo de dominio

**Módulo de mantenimiento** — patrones de dominio directamente aplicables a ThermalTrack:
1. Programación Cíclica vs Incremental (tiempo vs sensor)
2. Banda de tolerancia (val_min/max, tiempo_min/max)
3. Jerarquía Maestro→Plan→Detalle→Instrucción (4 niveles)
4. Composición de equipos por partes/subcomponentes
5. Asignación geográfica jerárquica (Cliente→Zona→Área→Unidad)
6. Traducción valor_promedio → días estimados
7. Proveedor por detalle con herencia

Detalles en `track-mantenimiento/references/noustrack-legacy-dominio-mantenimiento.md`

### Contexto del equipo

"Estudiantes venezolanos de universidad" + "funcionó en producción en Plumrose" = 
no juzgar por la calidad del PHP sino valorar que un grupo sin experiencia armó 
un sistema que operó una empresa real por años.

## Lecciones para futuros análisis

1. Siempre preguntar por la capa de DB — en sistemas legacy, lo pesado no está en el código visible
2. El contexto del equipo explica el 80% de las decisiones técnicas
3. El modelo de datos vale más que la implementación — extraerlo antes de descartar el sistema
4. Un sistema que funcionó en producción real merece respeto aunque el código duela
5. La dualidad estudiantes/universidad/venezuela + sistema real/empresa es un patrón recurrente en LATAM
