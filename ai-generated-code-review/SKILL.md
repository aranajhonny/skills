---
name: ai-generated-code-review
description: "Use when reviewing AI-generated code against the real schema."
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

Checklist for auditing code that an external AI generated (worker, service,
endpoint) BEFORE accepting it. The case that originated it: two versions of a
maintenance-plan worker — both passed `tsc --noEmit` and both had severe bugs
that only show up when verified against the real schema and the existing code.

## Golden rule

**tsc compiles ≠ it works.** The most expensive errors in AI-generated code are
not type errors — they are contract errors with reality (column names, data
semantics, wiring). ALWAYS verify against the real schema.

## Generic checklist

### 1. Wiring — the most silent bug

The AI generates the class plus the startup function but NOBODY calls it. Verify:
```bash
grep -rn "startXWorker\|modules/X/worker" backend/src/ --include="*.ts" | grep -v "worker.ts:"
```
Empty = the code exists but never runs. A "worker" without a startup entry in
`index.ts` (conditional load + dynamic import, the project's pattern) is dead
code.

**Watch for TWO env gates with similar names** (real case, maintenance go-live):
`index.ts` starts the worker only if `MANTENIMIENTO_WORKER_ENABLED === "1"`, but
`docker-compose.prod.yml` defined `WORKER_ENABLED` (a DIFFERENT worker, the
notifications/queue one) and not the maintenance one → the trigger worker ran in
the local build but was dead in prod. When reviewing wiring, grep the EXACT
variable name that `index.ts`/the startup checks, and verify the prod
compose/`.env` sets it — don't assume that "there's already a WORKER_ENABLED".

### 2. Embedded SQL: tsc does NOT validate SQL

Typos in SQL strings pass tsc and kill at runtime. Real example:
`p.evento_dias_desp after` (real column `evento_dias_despues`, garbage alias)
→ ERROR 1054 on EVERY run, 0 results, silent failure. Verify each SQL
identifier against the real schema:
```bash
grep -rn "columna_buscada" backend/src/modules/<modulo>/migrations/*.sql
```
Check: full column names (not truncated), aliases without reserved words,
tables that really exist.

### 3. VARCHAR columns that look like booleans

If the schema says `activo VARCHAR(100)` and the code compares
`sensor.activo === "baja"` or `=== true`, it's dead or wrong code. Real values
matter: `'en_servicio'`, `'pendiente'`, `'MANTENIMIENTO'`. Always run
`SELECT DISTINCT columna FROM tabla` (or grep the dump) before assuming a
column's semantics.

### 4. INNER JOIN kills NULL rows

Any `JOIN` over a nullable column (`activos_id NULL` = plan by category)
removes valid rows. Check which rows are lost with an INNER JOIN vs LEFT JOIN:
if the design allows NULL in that column, the JOIN must be LEFT.

### 5. Consistent validity filters

When a system has `activo = 1` + `fecha_fin` (validity), ALL queries in the same
domain must filter them. AIs put them in one query and forget them in the next
→ the code processes entities that were retired.

### 6. Frontend ↔ backend payload contracts (enums, field names, values)

When the AI generates the FRONTEND against a backend it didn't write, it invents
contracts that `tsc` doesn't catch (real case: 9 bugs in one session, all
passing tsc):

- **Ghost states**: the UI uses values the real ENUM doesn't have (`asignada`/
  `completada` in OTs). Classic symptom: the OT can never be closed because
  `en_revision` only offers a nonexistent transition → 400. Compare EVERY UI
  state/enum against the migration's ENUM.
- **Divergent field names**: frontend sends `id_temporal`, backend reads
  `temp_id` → subtasks always fail with "references a parent that doesn't
  exist". Grep the name the BACKEND reads (handler), not what the frontend
  sends.
- **TS interfaces that invent the schema (the reverse direction)**: the AI types
  the frontend with columns that DON'T exist and renders with those names →
  empty column that tsc doesn't detect. Real cases in maintenance:
  `OtManoObra.tecnicos_id` (real column `usuarios_id`),
  `OtTarea/OtEvento/OtFirma.ordenes_trabajo_id` (real `ot_id`),
  `ProgramacionMantenimiento.planes_mantenimiento_id` (real `plan_id`); and
  renders that read `mo.tecnico_nombre` / `mo.fecha` when the backend returns
  `usuario_nombre` / `fecha_registro` → the technician and labor date always
  show "—"/empty. Verify EVERY interface field against the handler's real
  `SELECT`/column.
- **Ghost endpoints in the API client**: a client method calls a route the
  router doesn't mount (e.g. `GET /ots/:id/firmas` when only `POST /:id/firmas`
  exists; the signatures already come in the detail) → 404 or dead code.
  Cross-check every `api.get/post` in the client against the real
  `*.routes.ts`.
- **Enum values with locale/ñ**: `anios` (UI) vs `años` (worker) → silent
  fallback to `DAY` → an annual plan fires every day. Verify the `<option>`
  values against the backend's real keys.
- **Duplicated transition machine**: the UI mirrors the backend state machine
  and the AI invents a different one. Parse the backend's and compare state by
  state (same set of `next`).
- **TZ helpers mis-copied**: `toLocalIsoString` that returns `toISOString()`
  (subtracts the zone). Never `toISOString()` for sending datetime-local from
  the repo.

Automated verification: ad-hoc script in **pure Python** (NOT `grep -P`: it
doesn't exist in macOS BSD grep — use `re`). Checks: migration ENUMs vs TS/UI
types, frontend vs backend transition machine (parse multi-line arrays with
`\\[(.*?)\\],` — Tailwind classes like `bg-[#0070F2]` break a single `\\]`),
ghost states, payload fields, TZ helpers. Run + build + visual review at
runtime with a user that has real permissions (not the role-less client — their
403s are expected and confusing).

### 7. Workers: accumulation with sensors — bugs that kill silently (evaluation 2026-08-12)

Fine logic in trigger workers that passes tsc and generates wrong OTs weeks
later:
- **Never persist the sensor's old state**: `UPDATE ... ultimo_estado = a.ultimo_estado`
  (the value it already had) = the state NEVER changes → accumulated hours with
  the machine off. The worker must READ `lecturas_ultima` from `sensor_estado_id`
  (a batch `IN (...)` query, pattern Q5) and persist the CURRENT reading; add the
  delta only if the PREVIOUS state was operating.
- **Gate by accumulator type, not by sensor nullability**:
  `sensor_estado_id IS NULL` = "calendar hours" only applies to
  `horas_operacion`. An event/cycle accumulator with a NULL sensor accumulated
  calendar hours IN ADDITION to its count → a "every 3 births" plan fired by
  time. Branch by `tipo`.
- **DATE fields**: `new Date('YYYY-MM-DD')` is UTC midnight (20:00 local of the
  previous day in UTC-4) and `toISOString().slice(0,10)` moves the date to the
  next day from 20:00-23:59 local. Helper `parseFechaLocal` (local components)
  for base, comparison and INSERT; due dates with `23:59:59.999` local.
- **Dead UI fields**: modal captures a field and never sends it
  (CerrarOTModal captured currency) — remove, it confuses.
- **Enum-vs-varchar match that NEVER matches (silent dead code)**: accumulating
  "events"/"cycles" with `a.tipo === c.tipo_evento` compares the accumulator
  enum (`'eventos'`/`'ciclos'`) against a free varchar (`'golpe'`/`'parto'`) →
  never matches, the counter never adds and a "every N cycles" plan never fires.
  No error, no log. When an accumulation depends on a `tipo_evento`/free code,
  there must be an explicit mapping column (or filter on a dimension both sides
  actually share), don't rely on labels matching by name.

### 8. Functional test of private logic with a mock pool (pattern 2026-08-12)

To verify a worker/service's private methods WITHOUT touching the DB or
refactoring: instantiate the class with a fake `pool` (an object whose `query`
inspects the SQL and returns rows based on the query) + fake logger, and call
the method via `(w as any).metodo(...)`. Run with `npx tsx script.ts` from the
backend repo. It verifies the emitted queries and the computed values (e.g.
sensor ON accumulates delta, sensor off sets state 0, events don't add time,
correct local date). The module's top-level imports (config/database pool) are
lazy — they don't connect unless real queries run.

## Verification without touching production

When you can't run against the real DB (or its owner administers it):

1. **Extract the real function from the file** with regex and test it in Node
   (ad-hoc script): strip TS types, `new Function`, input/output cases.
2. **Simulate the data sequences** the logic operates on.
3. **Invariant greps**: contract anti-patterns (`Number(x)`, `=== 1`,
   `as any`, `new Date(id)` — id used as a date).
4. `npx tsc --noEmit` as a minimum gate, never as sufficient verification.
5. **Never claim "verified" without real command output.**

## Verification against production

- Prod DB = SELECTs ONLY, and the server owner runs them. Deliver ready
  commands, don't execute them.
- Verify real column values with `SELECT DISTINCT` before assuming semantics.
- The local dump (`init-db/*.sql`) serves to read the real schema without
  touching the DB.