# Mock ↔ Coucou — mapa de paridad funcional

El objetivo es conseguir **paridad de capacidades**, no paridad visual. Coucou sirve como referencia de producto; Mock mantiene personaje, lenguaje visual, backend y comportamiento propios.

## Estado

| Capacidad | Coucou | Mock v13 | Dirección de Mock |
|---|---:|---:|---|
| Personaje animado | ✅ | ✅ | Mock Core con manos, estados, peek y reacciones |
| Chat con IA | ✅ | ✅ | varios proveedores + modelos locales |
| Drop de archivo + pregunta | ✅ | ✅ | contexto explícito y limitado |
| Contexto de ventana | ✅ | ✅ parcial por DE | Desktop Adapter |
| Voz STT/TTS | — / limitada | ✅ | local con Whisper + Piper |
| Agent Runtime del sistema | — | ✅ | herramientas Linux con permisos |
| Claude Code live sessions | ✅ | ⏳ | Session Hub + hook relay |
| Aprobar permisos de Claude/Codex | ✅ | ⏳ | Permission Inbox independiente del Agent Runtime |
| Gemini CLI / Antigravity sessions | ✅ | ⏳ | adapters de eventos |
| Pills por agente | ✅ | ⏳ | Activity Dock |
| GitHub/Vercel/n8n/etc. | ✅ | ⏳ | Integration Providers |
| Multimedia | ✅ | ✅ | MPRIS/playerctl |
| Ocultarse y aparecer al hover | ✅ | ✅ | hotspot del borde + peek |
| Credenciales seguras | ✅ | ✅ | Secret Service, fallback local |
| Multi-monitor | ✅ | ✅ | Quickshell.screens |
| Niri | — | ✅ | nativo |
| Hyprland | — | ✅ | adapter |
| Sway/i3 | — | ✅ | adapter |
| KDE/GNOME | parcial | parcial | degradación por capacidades |

## Arquitectura objetivo

```text
                         ┌──────────────────────┐
                         │      Mock Core       │
                         │ QML / interaction UI │
                         └──────────┬───────────┘
                                    │
             ┌──────────────────────┼─────────────────────────┐
             │                      │                         │
             ▼                      ▼                         ▼
     ┌──────────────┐      ┌────────────────┐       ┌────────────────┐
     │ Session Hub  │      │ Agent Runtime  │       │ Integrations   │
     │ AI tool live │      │ Linux actions  │       │ GitHub/n8n/... │
     └──────┬───────┘      └───────┬────────┘       └───────┬────────┘
            │                      │                        │
            └──────────────┬───────┴──────────────┬─────────┘
                           ▼                      ▼
                  ┌────────────────┐     ┌─────────────────┐
                  │ Desktop Adapter│     │ Secure Secrets  │
                  │ Niri/Hypr/...  │     │ Secret Service  │
                  └────────────────┘     └─────────────────┘
```

## Fases recomendadas

### Fase 1 — base portable ✅

- desacoplar Niri;
- Desktop Adapter;
- clipboard/audio/screenshots con fallbacks;
- PanelWindow sin API Wayland específica;
- Secret Service;
- Mock Core con manos, poke/dizzy/hearts y hover peek.

### Fase 2 — Session Hub

Crear un servicio único para sesiones externas:

```text
Claude Code hook ─┐
Codex event ──────┼─> Session Hub -> Activity model -> Mock UI
Gemini CLI hook ──┤
Antigravity ──────┘
```

Cada sesión debe tener: `id`, `agent`, `cwd`, `state`, `steps`, `started_at`, `badge`, `permission_request`.

La UI no debe tener lógica específica de Claude/Gemini: solo renderiza sesiones normalizadas.

### Fase 3 — Permission Inbox

Separar dos tipos de permisos:

1. **Mock Agent Permission**: Mock quiere actuar sobre Linux.
2. **External Agent Permission**: Claude/Codex pide permiso en su propia sesión.

Ambos pueden usar el mismo lenguaje visual, pero nunca el mismo estado interno. Así se evita aprobar accidentalmente el tipo equivocado.

### Fase 4 — Activity Dock / pills

En vez de copiar las pills de Coucou, Mock puede usar pequeños **Modules** laterales:

```text
[ Mock ] [Claude ●] [Codex !] [GitHub ✓] [Media ▶]
```

- `●` trabajando
- `!` permiso pendiente
- `✓` terminado
- `×` error

Al seleccionar un módulo, el cuerpo de la isla cambia al contexto correspondiente.

### Fase 5 — integraciones

Implementar providers independientes con caché y polling suspendido cuando no se usan:

- GitHub: PR/CI/notificaciones;
- Vercel: último deploy;
- n8n: ejecuciones;
- Stripe: eventos/pagos;
- Resend: entregas;
- Notion: páginas/tareas elegidas;
- Cal.com: próxima reserva.

Cada integración declara: `id`, `label`, `icon`, `accent`, `refresh_interval`, `secrets`, `summary` y `actions`.

## Diseño del personaje

Las manos no deben ser decoración fija. Deben comunicar estado:

| Estado | Ojos | Manos | Movimiento |
|---|---|---|---|
| idle | siguen cursor | relajadas | respiración lenta |
| hover | siguen cursor | saludo | wave corto |
| thinking | scanline | juntas/hacia delante | pulso |
| listening | abiertos | cerca del visor | audio bars |
| acting | concentrados | hacia delante | pulso rápido |
| permission | alerta | una mano levantada | quieto |
| happy | sonrisa | ambas arriba | bounce |
| error | tensos | caídas | leve shake |
| poke | molestos | reacción corta | tilt |
| dizzy | × × | desordenadas | inclinación |
| file drop | enfocados | extendidas | gesto de recibir |

La regla: la animación debe explicar qué está haciendo Mock antes de ser puro adorno.
