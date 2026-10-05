# Mock Agent Runtime

## Flujo

```text
Solicitud
   │
   ▼
Agent Planner
   │  JSON estructurado
   ▼
Policy / Tool Registry
   ├─ read/safe ──────────────┐
   └─ confirm/destructive ─┐  │
                          ▼  ▼
                    Permission Card
                          │
                          ▼
                    Tool Executor
                          │
                          ▼
                    Resultado + resumen
```

El modelo nunca ejecuta comandos directamente. `agent_runtime.py` vuelve a validar nombre de herramienta, argumentos y nivel de riesgo antes de hacer cualquier cambio.

## Política

`read`: metadatos o listados que no leen contenido sensible.

`safe`: acciones reversibles/de baja consecuencia como abrir una aplicación, cambiar workspace o controlar multimedia.

`confirm`: requiere clic en **Ejecutar**. Incluye terminal, lectura de archivos, clipboard, servicios de usuario y escrituras.

`destructive`: siempre requiere clic y tiene validaciones adicionales. Incluye borrado y energía.

El runtime limita operaciones de archivos al `HOME` real después de resolver symlinks. `terminal.run` limita el directorio de trabajo al HOME, tiene timeout y bloquea elevación de privilegios y comandos destructivos comunes; borrados explícitos deben pasar por `file.delete`, donde Mock puede aplicar validación de rutas.

## Herramientas

```text
context.desktop
desktop.focus_workspace
desktop.move_window_to_workspace
desktop.toggle_overview
desktop.close_window
app.open
file.read
file.list
file.search
file.write
file.move
file.delete
clipboard.read
clipboard.write
media.control
audio.volume
service.user
notify.send
screenshot.capture
terminal.run
power.action
```

## Decisiones deliberadas

- `systemctl` se restringe a `--user`; servicios del sistema no se modifican desde esa herramienta.
- `app.open` usa argv directo, nunca `shell=True`, y bloquea shells/intérpretes/utilidades destructivas.
- cualquier comando general va por `terminal.run`, que siempre pide aprobación.
- apagar/reiniciar tiene herramienta propia para que no se esconda dentro de un comando de terminal.
- si la petición es conversación normal, el Agent Planner devuelve `mode=chat` y Mock usa el flujo de chat habitual.

## Extender herramientas

Toda herramienta nueva debe añadirse a `TOOL_POLICY` y `TOOLS`. No confíes en `risk` generado por un modelo: `normalize_plan()` lo sustituye siempre por la política local.


## Desktop Adapter

Las herramientas `desktop.*` no ejecutan comandos de compositor directamente desde el planificador. `backend/desktop_adapter.py` detecta la sesión y traduce la acción. Si el entorno no expone una capacidad, la acción falla de forma explícita en vez de intentar un comando incorrecto.
