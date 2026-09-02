---
name: ai-generated-code-review
description: "Usa al revisar código generado por IA contra el schema real."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos, linux]
metadata:
  hermes:
    tags: [code-review, ai-generated, mysql, verification, production]
    related_skills: [mysql-production-migrations, requesting-code-review, code-quality-review]
---

# AI-Generated Code Review

Checklist para auditar código que generó una IA externa (worker, servicio,
endpoint) ANTES de aceptarlo. El caso que lo originó: dos versiones de un
worker de planes de mantenimiento — ambas pasaban `tsc --noEmit` y ambas
tenían bugs graves que solo aparecen verificando contra el schema real y el
código existente.

## Regla de oro

**tsc compila ≠ funciona.** Los errores más caros del código generado por IA
no son de tipos — son de contrato con la realidad (nombres de columnas,
semántica de datos, cableado). Verificar SIEMPRE contra el schema real.

## Checklist genérico

### 1. Cableado — el bug más silencioso

La IA genera la clase + la función de arranque pero NADIE la llama. Verificar:
```bash
grep -rn "startXWorker\|modules/X/worker" backend/src/ --include="*.ts" | grep -v "worker.ts:"
```
Vacío = el código existe pero nunca corre. Un "worker" sin arranque en
`index.ts` (carga condicional + import dinámico, patrón del proyecto) es
código muerto.

**Ojo con DOS gates de env con nombres parecidos** (caso real, go-live
mantenimiento): `index.ts` arranca el worker solo si
`MANTENIMIENTO_WORKER_ENABLED === "1"`, pero `docker-compose.prod.yml` definía
`WORKER_ENABLED` (un worker DISTINTO, el de notificaciones/cola) y no el de
mantenimiento → el worker de disparadores corría el build local pero estaba
muerto en prod. Al revisar cableado, grep el nombre EXACTO de la variable que
chequea `index.ts`/el arranque, y verificar que el compose/`.env` de prod la
setee — no asumir que "ya hay un WORKER_ENABLED".

### 2. SQL embebido: tsc NO valida SQL

Typos en strings SQL pasan tsc y matan en runtime. Ejemplo real:
`p.evento_dias_desp after` (columna real `evento_dias_despues`, alias basura)
→ ERROR 1054 en TODA corrida, 0 resultados, falla silenciosa. Verificar cada
identificador SQL contra el schema real:
```bash
grep -rn "columna_buscada" backend/src/modules/<modulo>/migrations/*.sql
```
Fíjate en: nombres de columnas completos (sin truncar), alias sin palabras
reservadas, tablas que realmente existen.

### 3. Columnas VARCHAR que parecen booleanos

Si el schema dice `activo VARCHAR(100)` y el código compara
`sensor.activo === "baja"` o `=== true`, es código muerto o incorrecto.
Los valores reales importan: `'en_servicio'`, `'pendiente'`, `'MANTENIMIENTO'`.
Siempre: `SELECT DISTINCT columna FROM tabla` (o grep del dump) antes de
asumir la semántica de una columna.

### 4. INNER JOIN mata filas NULL

Cualquier `JOIN` sobre una columna nullable (`activos_id NULL` = plan por
categoría) elimina filas válidas. Verificar qué filas se pierden con un
INNER JOIN vs LEFT JOIN: si el diseño permite NULL en esa columna, el JOIN
debe ser LEFT.

### 5. Filtros de vigencia consistentes

Cuando un sistema tiene `activo = 1` + `fecha_fin` (vigencia), TODAS las
queries del mismo dominio deben filtrarlos. Las IAs los ponen en una query
y los olvidan en la siguiente → el código procesa entidades dadas de baja.

### 6. Contratos de payload frontend ↔ backend (enums, nombres de campo, valores)

Cuando la IA genera el FRONTEND contra un backend que no escribió, inventa contratos
que `tsc` no detecta (caso real: 9 bugs en una sesión, todos pasando tsc):

- **Estados fantasma**: la UI usa valores que el ENUM real no tiene (`asignada`/
  `completada` en OT). Síntoma clásico: la OT nunca puede cerrarse porque
  `en_revision` solo ofrece una transición inexistente → 400. Comparar CADA estado/
  enum de la UI contra el ENUM de la migración.
- **Nombres de campo divergentes**: frontend manda `id_temporal`, backend lee
  `temp_id` → las subtareas fallan siempre con "referencia un padre que no existe".
  Grep el nombre que LEE el backend (handler), no el que manda el frontend.
- **Interfaces TS que inventan el schema (la dirección inversa)**: la IA tipa el
  frontend con columnas que NO existen y renderiza con esos nombres → columna vacía
  que tsc no detecta. Casos reales en mantenimiento: `OtManoObra.tecnicos_id` (columna
  real `usuarios_id`), `OtTarea/OtEvento/OtFirma.ordenes_trabajo_id` (real `ot_id`),
  `ProgramacionMantenimiento.planes_mantenimiento_id` (real `plan_id`); y renders que
  leen `mo.tecnico_nombre` / `mo.fecha` cuando el backend devuelve `usuario_nombre` /
  `fecha_registro` → el técnico y la fecha de mano de obra salen siempre "—"/vacío.
  Verificar CADA campo de la interface contra el `SELECT`/columna real del handler.
- **Endpoints fantasma en el cliente API**: un método del cliente llama a una ruta que
  el router no monta (ej. `GET /ots/:id/firmas` cuando solo existe `POST /:id/firmas`;
  las firmas ya vienen en el detalle) → 404 o código muerto. Cruce cada `api.get/post`
  del cliente con las rutas reales del `*.routes.ts`.
- **Valores de enum con locale/ñ**: `anios` (UI) vs `años` (worker) → fallback
  silencioso a `DAY` → un plan anual se dispara cada día. Verificar los values de
  los `<option>` contra los keys reales del backend.
- **Máquina de transiciones duplicada**: la UI espeja la máquina de estados del
  backend y la IA la inventa distinta. Parsear la del backend y comparar estado
  por estado (set de `next` iguales).
- **Helpers TZ mal copiados**: `toLocalIsoString` que devuelve `toISOString()`
  (resta la zona). Nunca `toISOString()` para enviar datetime-local del repo.

Verificación automatizada: script ad-hoc en **Python puro** (NO `grep -P`: no existe
en macOS BSD grep — usar `re`). Checks: ENUMs de migraciones vs tipos TS/UI, máquina
de transiciones frontend vs backend (parsear arrays multilínea con `\[(.*?)\],` —
las clases Tailwind `bg-[#0070F2]` cortan un `\]` simple), estados fantasma, campos
de payload, helpers TZ. Correr + build + revisión visual en runtime con usuario
con permisos reales (no el cliente sin rol — sus 403 son esperados y confunden).

### 7. Workers: acumulación con sensores — bugs que matan silenciosamente (evaluación 2026-08-12)

Lógica fina en workers de disparadores que pasa tsc y genera OTs incorrectas semanas
después:
- **Nunca persistir el estado viejo del sensor**: `UPDATE ... ultimo_estado = a.ultimo_estado`
  (el valor que ya tenía) = el estado NUNCA cambia → horas acumuladas con la máquina
  apagada. El worker debe LEER `lecturas_ultima` del `sensor_estado_id` (una query batch
  `IN (...)`, patrón Q5) y persistir la lectura ACTUAL; sumar el delta solo si el estado
  PREVIO era operando.
- **Gate por tipo de acumulador, no por nullabilidad del sensor**: `sensor_estado_id IS
  NULL` = "horas de calendario" solo aplica a `horas_operacion`. Un acumulador de
  eventos/ciclos con sensor NULL acumulaba horas de calendario ADEMÁS de su conteo →
  plan "cada 3 partos" disparaba por tiempo. Branch por `tipo`.
- **Fechas DATE**: `new Date('YYYY-MM-DD')` es medianoche UTC (20:00 local del día
  anterior en UTC-4) y `toISOString().slice(0,10)` corre la fecha al día siguiente de
  20:00-23:59 local. Helper `parseFechaLocal` (componentes locales) para base, comparación
  e INSERT; vencimientos con `23:59:59.999` local.
- **Campos muertos en UI**: modal que captura un campo y nunca lo envía (CerrarOTModal
  capturaba moneda) — eliminar, confunde.
- **Match enum-vs-varchar que NUNCA coincide (dead code silencioso)**: acumular
  "eventos"/"ciclos" con `a.tipo === c.tipo_evento` compara el enum del acumulador
  (`'eventos'`/`'ciclos'`) contra un varchar libre (`'golpe'`/`'parto'`) → nunca matchea,
  el contador jamás suma y un plan "cada N ciclos" nunca dispara. Sin error, sin log.
  Cuando una acumulación dependa de un `tipo_evento`/código libre, tiene que haber una
  columna de mapeo explícita (o filtrar por una dimensión que SÍ comparta ambos lados),
  no confiar en que los labels coincidan por nombre.

### 8. Test funcional de lógica privada con pool mock (patrón 2026-08-12)

Para verificar métodos privados de un worker/servicio SIN tocar BD ni refactorizar:
instanciar la clase con un `pool` fake (objeto con `query` que inspecciona el SQL y
devuelve filas según el query) + logger fake, y llamar el método vía `(w as any).metodo(...)`.
Correr con `npx tsx script.ts` desde el repo backend. Verifica las queries emitidas y los
valores calculados (ej: sensor ON acumula delta, sensor apagado fija estado 0, eventos no
suman tiempo, fecha local correcta). Los imports top-level del módulo (pool de
config/database) son lazy — no conectan si no se ejecutan queries reales.

## Verificación sin tocar producción

Cuando no se puede ejecutar contra la BD real (o el dueño la administra):

1. **Extraer la función real del archivo** con regex y probarla en Node
   (script ad-hoc): quitar tipos TS, `new Function`, casos de entrada/salida.
2. **Simular secuencias de datos** sobre las que opera la lógica.
3. **Greps de invariantes**: anti-patrones del contrato (`Number(x)`, `=== 1`,
   `as any`, `new Date(id)` — id usado como fecha).
4. `npx tsc --noEmit` como gate mínimo, nunca como verificación suficiente.
5. **Nunca afirmar "verificado" sin output de comando real.**

## Verificación contra producción

- BD prod = SOLO SELECTs, y los corre el dueño del server. Entregar comandos
  listos, no ejecutarlos.
- Verificar valores reales de columnas con `SELECT DISTINCT` antes de asumir
  semántica.
- El dump local (`init-db/*.sql`) sirve para leer el schema real sin tocar la BD.
