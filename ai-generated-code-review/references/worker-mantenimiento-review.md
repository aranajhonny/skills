# Review del worker de mantenimiento de NousTrack (generado por IA)

Checklist específico para `backend/src/modules/mantenimiento/mantenimiento-worker.service.ts`
(+ `.module.ts`) — worker de disparadores de planes (fecha / valor_sensor / acumulacion /
evento).
Aprendido revisando dos versiones generadas por IA: ambas pasaban `tsc --noEmit`
y ambas tenían bugs que solo aparecen contra el schema real.

Contexto de negocio: `docs/notas/mantenimiento-fundacion.md` (schema + reglas de
disparo) y `docs/guion-reunion-luis.md` (decisiones validadas). El plan de
trabajo vive en `plan-mantenimiento.md` (root del repo).

## Reglas del dominio (fuente: fundacion.md §BANDA DE TOLERANCIA)

- **Tolerancia de UN SOLO lado** para `>`,`>=`,`<`,`<=` (ej: `>` → `lectura > cv*(1-tol)`).
  Solo `==` es simétrica `[cv*(1-tol), cv*(1+tol)]`. Implementarla simétrica
  rompe el disparo (90°C con `> 80` quedaría "fuera_rango" y nunca dispara).
- **Histéresis edge-triggered**: dispara en transición fuera→dentro; NULL
  (primera evaluación) solo inicializa sin disparar; dentro→fuera solo actualiza
  estado. NO disparar por nivel (valor > umbral), sino por transición.
- **Acumulación**: `valor_min = limite × (1−tol)` (piso corrido, ej: "cada 500
  hrs" con 5% dispara a 475). Diferencia contra `acumulacion_ultimo_valor`
  (NO desde cero). Al disparar: `acumulacion_ultimo_valor = valor actual` y
  `acumulacion_ultimo_reseteo = NOW()`.
- **Evento QR**: agenda programación `fecha_evento + evento_dias_despues` SOLO
  si la solicitud es más reciente que la última ejecución; vincula
  `solicitudes_trabajo.ot_id`. El worker NO crea OT directa de evento — agenda.
- **Anti-re-disparo**: `ventana_re_arme_horas` (default 6) + `GET_LOCK` +
  INSERT condicional en `plan_ejecuciones`. INSERT...SELECT...WHERE NOT EXISTS
  NO es atómico bajo REPEATABLE READ (dos transacciones pueden pasar ambas) —
  el lock real es GET_LOCK.
- **Disparador fecha**: genera con `dias_anticipacion` (no solo vencidas),
  `fecha_vencimiento` = fecha programada 23:59:59, sucesora en la misma
  transacción (INSERT IGNORE), respetando `fecha_fin`.

## Bugs reales encontrados (v1 y v2)

1. **Cableado ausente** — `startPlanMantenimientoWorker()`/`startMantenimientoWorker()`
   existían pero nadie las llamaba. El arranque va en `index.ts` con carga
   condicional (WORKER_ENABLED=1 + import dinámico, patrón `cola-envio-worker`).
   Verificar con: `grep -rn "startMantenimientoWorker\|mantenimiento/worker" backend/src/ --include="*.ts" | grep -v "worker.ts:"`.
2. **Typo SQL invisible a tsc** — `p.evento_dias_desp after` (columna real:
   `evento_dias_despues`; `after` como alias sin AS) → ERROR 1054 en TODA
   corrida, worker genera 0 OTs silenciosamente.
3. **`sensores_instalados.activo` NO es booleano** — es VARCHAR(100) con
   valores reales `'en_servicio'`, `'pendiente'`, `'MANTENIMIENTO'`, `'ALMACEN'`,
   `'1'`. El check `sensor.activo === "baja"` (v1) era código muerto y dejaba
   pasar sensores en `pendiente`/`MANTENIMIENTO` como disponibles. Disponible
   solo si `activo = 'en_servicio'`.
4. **INNER JOIN mata planes por categoría** — planes con `activos_id NULL`
   (plan por categoría) desaparecen con `JOIN activos ON a.id = p.activos_id`.
   Usar LEFT JOIN y expandir activos de `categoria_activo_id`.
5. **Filtros de vigencia perdidos** — query de programaciones sin `p.activo = 1`
   ni `(p.fecha_fin IS NULL OR p.fecha_fin >= CURDATE())` → planes
   desactivados/terminados seguían generando OTs.
6. **Tipo OT sin validar** — `(disparo.tipoIntervencion as any) ?? "preventivo"`
   puede insertar un valor fuera del ENUM MySQL (`preventivo,correctivo,
   predictivo,inspeccion,emergencia`) → error 1265. Validar contra whitelist.
7. **`new Date(id)`** — `new Date(disparo.programacionId)` trata un id como
   fecha. Código muerto/incorrecto; usar la fila para la fecha base.
8. **Código OT sin retry** — carrera con creación manual del frontend
   (ER_DUP_ENTRY). Retry 3x re-generando el código.

## Bugs reales encontrados en la EVALUACIÓN (2026-08-12) — corregidos y verificados

La implementación final (`mantenimiento-worker.service.ts`) pasó la evaluación
estructural (D1-D10, batch Q1-Q5, GET_LOCK, histéresis unilateral, códigos OT con
retry, transacciones) pero tenía 4 bugs de lógica fina — todos en acumulación y
fechas. Verificación: test funcional con pool mock (tsx, 7/7 PASS) + script estático
(17/17 PASS) + tsc.

1. **🔴 Sensor de estado NUNCA leído** — `sembrarAcumuladores` hacía
   `UPDATE ... ultimo_estado = a.ultimo_estado ?? null` (el valor que YA tenía) →
   el estado quedaba clavado en 1 → horas acumuladas con la máquina apagada.
   Fix: batch `SELECT sensores_instalados_id, valor FROM lecturas_ultima WHERE
   sensores_instalados_id IN (?)` (patrón Q5 del diseño) → map `estadoSensor` (umbral
   0.5 para discretos 0/1) → sumar delta solo si `ultimo_estado === 1` (estaba
   operando) → persistir `nuevoEstado = lectura actual`. Sin lectura del sensor aún:
   no acumular ni cambiar estado (solo `ultima_lectura_fecha = NOW()`).

2. **🔴 Gate por TIPO de acumulador, no por nullabilidad** — el branch
   `sensor_estado_id === null` = "horas de calendario" aplicaba a TODOS los
   acumuladores sin sensor → eventos/ciclos/km sumaban horas de calendario ADEMÁS
   de su conteo real → plan "cada 3 partos" disparaba por tiempo. Fix: solo
   `tipo === "horas_operacion"` acumula tiempo; `eventos`/`ciclos` solo cuentan
   solicitudes (bloque aparte); `km`/`unidades_producidas` sin fuente V1 → warn una
   vez por corrida, no acumulan.

3. **🟡 TZ en `fecha_programada`** — el INSERT usaba `proxima.toISOString().slice(0,10)`
   (UTC) → de 20:00-23:59 local la fecha se corría al día siguiente. Y la BASE del
   cálculo era `new Date(fecha_inicio)` = medianoche UTC (20:00 local del día
   anterior) → "+30 días" caía el 10 en vez del 11. Fix: helper `parseFechaLocal`
   (componentes locales) para `fecha_inicio`, `MAX(fecha_programada)` histórico y el
   formateo del INSERT.

4. **🟡 Vencimiento OT por fecha** — `new Date(prog.fecha_programada)` = medianoche
   UTC = 20:00 local del día ANTERIOR; el diseño dice 23:59:59 local. Fix en `run()`
   (case "fecha"): parsear `YYYY-MM-DD` con componentes locales para la comparación
   (`fechaProgLocal <= limite`) y vencimiento `new Date(yy, mm-1, dd, 23,59,59,999)`.

Menores: prioridad de OT desde evento/solicitud ignorada (siempre 'media'); la
sucesora de programación se siembra en la corrida siguiente, no en la misma tx (D5 —
sin impacto funcional); hija con padre no resuelto se inserta como raíz (`?? null` —
defensa menor, el backend de planes ya valida).

Lección de clase: en workers de acumulación, revisar (a) si el estado del sensor se
LEE o se re-persiste, (b) si el branch por nullabilidad es semánticamente correcto
para TODOS los tipos de acumulador, (c) TODA fecha DATE parseada con componentes
locales (nunca `new Date('YYYY-MM-DD')` ni `toISOString().slice(0,10)`).

## Verificación

- `npx tsc --noEmit` en backend (gate mínimo, no suficiente).
- Extraer `normalizeTipoVariable`/funciones reales del archivo con regex y
  probarlas en Node (script ad-hoc) — sin tocar BD.
- Greps de invariantes: `Number(tipo_variable)`, `=== "1"`, `as any`,
  `new Date(` + id.
- BD prod = SOLO SELECT y los corre Jhonny (nunca ejecutar en el server).
