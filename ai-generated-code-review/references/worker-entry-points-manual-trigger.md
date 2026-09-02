# Workers con entry points múltiples — el estado post-disparo debe correr para TODOS

Caso real 2026-08-17: `dispararManual` en `backend/src/modules/mantenimiento/
mantenimiento-worker.service.ts` (NousTrack/Track).

## El patrón que falla

Un worker de disparadores tiene dos entry points que comparten la MISMA función de
creación (`crearOTyEjecucion`):
1. El tick automático (loop cada N minutos, gate `MANTENIMIENTO_WORKER_ENABLED`),
   que llama con `tipo: "fecha" | "valor_sensor" | "acumulacion" | "evento"`.
2. El disparo manual (`POST /planes/:id/disparar`), que llama con `tipo: "manual"`.

El bloque de estado post-disparo (watermark de acumulación, programación marcada
'generada', histéresis) suele estar en un `if/else if` sobre `d.tipo` que solo cubre
los 4 tipos automáticos. El path `"manual"` no entra en NINGÚN branch → no avanza
nada. Síntoma diferido: el fix no rompe nada al probar (worker apagado), pero al
activar el worker automático los planes probados manualmente re-disparan OT
duplicadas:
- `acumulacion` → `acumulacion_ultimo_valor` no avanza → diferencia sigue ≥ límite.
- `fecha` → `programacion_mantenimiento` sigue `'pendiente'` → OT duplicada por la
  misma fecha programada.
- `valor_sensor` → `ultimo_estado_sensor` stale.

## El fix correcto

1. **Keyear el estado por el tipo DEL PLAN, no por el tipo de ejecución:**
   ```ts
   const tipoEstado = d.tipo === "manual" ? d.plan.disparador_tipo : d.tipo;
   ```
   El `if/else` usa `tipoEstado`. Para `evento` manual el branch existente ya es
   no-op (`solicitudId === null`); documentar con comentario.
2. **Acumulación manual:** leer el valor REAL del acumulador ANTES de crear la OT y
   pasarlo como `valorDisparador` (`SELECT valor_acumulado FROM acumuladores_activo
   WHERE activos_id = ? AND tipo = ?`; 0 si no existe). Si se pasa null, el
   `UPDATE ... acumulacion_ultimo_valor = ?` avanza a 0.
3. **Fecha manual:** marcar `'generada'` + sembrar la SUCESORA inline. La sucesora
   automática la siembra D5 (`sembrarProgramacion`) en cada tick — el path manual
   no tiene tick, así que sin sembrarla inline la cadena de mantenimiento se corta
   (o, al prender el worker, la siembra él con base en la última ejecución manual —
   pero solo si el worker corre).
4. **Misma transacción** que la OT (reusar `beginTransaction`/`commit` existentes,
   nunca segunda conexión). El path manual conserva sus excepciones: sin guard
   anti-re-disparo (WHERE NOT EXISTS), `origen='manual'`, `tipo_disparo='manual'`.

## Verificación con pool mock

Multi-escenario (uno por disparador): acumulacion (valor real en plan_ejecuciones +
UPDATE watermark), fecha (UPDATE 'generada' + INSERT sucesora con fecha local),
evento (no-op), valor_sensor ('dentro_rango'). Ver: `track-mantenimiento-definicion`
→ `references/disparo-manual-post-fire.md` para el detalle completo y el mock.

**Pitfall del script:** los valores que van por bind params NO aparecen en el SQL
crudo — asertar sobre el array de params capturado, no con `sql.includes('literal')`
(falso negativo real: `includes("'manual'")` falló porque el origen es un `?`).
