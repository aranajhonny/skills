# Plugin missions — invocación vía Python cuando el toolset no carga

## El problema (validado 2026-08 en plataforma-track)

El usuario exige usar el plugin `missions` (misión durable + checkpoints por
sprint). Pero el toolset `missions` puede NO estar expuesto en la sesión
actual: las tools `mission_*` no aparecen en el catálogo de tools, y
`tool_search` no las encuentra. Causa típica: el plugin está habilitado en
`~/.hermes/config.yaml` (`plugins.enabled: [missions]`), pero el toolset
`missions` no figura en `platform_toolsets.cli` de la plataforma activa
(solo en `known_plugin_toolsets`), así que esta sesión no recibe las tools.

Síntoma claro: `hermes missions list` responde desde el CLI global
("No missions yet..."), pero no hay tools `mission_*` disponibles en la
sesión. El CLI global NO tiene `new`/`checkpoint` — esos son handlers
Python del plugin.

## Solución: importar el módulo del plugin y llamar a los handlers

Los handlers viven en `~/.hermes/plugins/missions/tools.py` y toman un dict
de args. Funciona desde `terminal` o `execute_code` con el python del
sistema:

```bash
python3 -c "
import sys, os, json
sys.path.insert(0, os.path.expanduser('~/.hermes/plugins'))
from missions import tools

# Crear misión (ver firma exacta en tools.py/README: name, objective, plan/scope)
r = tools.mission_new({'name': '...', 'objective': '...'})
print(r)   # devuelve mission_id tipo 'msn-598fc35e3ea9'

# Checkpoint tras cada paso/sprint: state = dict JSON serializable
print(tools.mission_checkpoint({
  'mission_id': 'msn-...',
  'state': {'sprint_1': 'COMPLETO', 'pendientes': [...]},
  'note': 'Sprint 1 verificado'
}))
# → devuelve {'mission_id', 'checkpoint_seq': N, 'note', 'message': 'Checkpoint saved at seq N.'}

# Estado
print(tools.mission_status({'mission_id': 'msn-...'}))
"
```

## Reglas operativas

- **Firma real**: leer `~/.hermes/plugins/missions/tools.py` (y el
  `skills/mission/SKILL.md` empaquetado) antes de llamar — `mission_new`
  usa `name` + `objective` (+ opcional `plan`/`scope`); `mission_checkpoint`
  usa `mission_id` + `state` + `note`. No inventar keys.
- **Los hooks `post_tool_call` NO corren** cuando invocas vía Python: el
  autologging de tool calls a la misión no aplica. Los checkpoints manuales
  son el equivalente — hazlos explícitamente tras cada hito.
- **Serializable**: `state` debe ser JSON puro (dicts/listas/strings).
- **Guardar el mission_id**: queda en el output de `mission_new`. Si la
  sesión se compacta, el mission_id puede perderse del contexto — anotarlo
  en el checkpoint anterior o en un archivo de estado del proyecto
  (`state/` no se versiona, sirve).
- **Para exponer las tools nativas** (y que los hooks funcionen): añadir
  `missions` a `platform_toolsets.cli` en `~/.hermes/config.yaml` y reiniciar
  la sesión. La vía Python no requiere reinicio y es equivalente en
  funcionalidad de registro.
