# Mock Island v13 — Linux Agent Shell

**Mock es un agente de escritorio para Linux construido con Quickshell.**

La idea no es clonar una Dynamic Island ni convertir Linux en macOS: Mock toma la presencia compacta de herramientas como Coucou y la lleva a un diseño propio, orientado al shell, al contexto del sistema, a la voz y a acciones reales sobre el escritorio.

## v13: qué cambia

### Se corrige la regresión visual de v12

La isla vuelve al **borde inferior**, donde vivía en las versiones anteriores, de modo que no compite con barras superiores como DMS. Se conserva el diseño compacto del Core y el renderizado Markdown de v12.

También vuelve la **paleta Material You completa de DMS**: no solo cambian los acentos, sino también superficies, contenedores, texto y bordes. Si DMS no está disponible, Mock usa su paleta oscura clásica como fallback.

### El Agent Runtime de v12 se conserva

Las peticiones del PC siguen convirtiéndose en planes y ejecutándose mediante el Agent Runtime. `package.updates` consulta el gestor real del sistema y, cuando existen, AUR y Flatpak. `package.upgrade` requiere aprobación y abre una terminal visible para que cualquier elevación de privilegios siga bajo control del usuario.

`system.info` ahora fuerza una salida estable de `lscpu` independientemente del idioma del sistema y filtra únicamente los bloques gráficos relevantes de `lspci`, para mostrar mejor el modelo de CPU y las GPU.

## Base heredada de v11

### Desktop Adapter

Mock ya no depende de Niri como contrato interno. La UI y el Agent Runtime usan acciones genéricas (`desktop.*`) y `backend/desktop_adapter.py` decide cómo resolverlas según el entorno detectado.

Compatibilidad actual:

| Entorno | Contexto | Workspaces | Mover ventana | Cerrar ventana | Notas |
|---|---:|---:|---:|---:|---|
| Niri | ✅ | ✅ | ✅ | ✅ | integración completa |
| Hyprland | ✅ | ✅ | ✅ | ✅ | mediante `hyprctl` |
| Sway | ✅ | ✅ | ✅ | ✅ | mediante `swaymsg` |
| i3 / X11 | ✅* | ✅ | ✅ | ✅ | usa `i3-msg`, `wmctrl` o `xdotool` |
| KDE Plasma | ✅* | ✅* | ✅* | ✅* | depende de X11 / `kdotool` / `wmctrl` para algunas acciones |
| GNOME Wayland | parcial | — | — | — | GNOME restringe control global de ventanas; el resto de Mock sigue funcionando |
| COSMIC / otros | base | — | — | — | chat, voz, archivos, multimedia y acciones no ligadas al compositor |

`*` depende de las herramientas disponibles en la sesión.

Comprueba qué detectó Mock con:

```bash
mock-island desktop-status
```

### Mock rediseñado

El personaje deja atrás el visor rectangular que se veía demasiado como un avatar de juego. Ahora es una criatura flotante compacta, sin cara blanca en bloque, con ojos y manos integrados al cuerpo:

- saluda con la mano al pasar el cursor;
- mantiene los ojos siguiendo el puntero;
- se molesta al tocarlo;
- tres toques seguidos lo marean;
- después de mantener el cursor encima aparecen corazones;
- las manos cambian de pose al pensar, fallar, terminar o recibir un archivo;
- cuando Mock está oculto queda un hotspot mínimo: al tocar el borde aparece un pequeño “peek” y un clic abre la isla.

No usa a Mochi ni assets, sonidos o iconos de Coucou.

### PC Agent activo por defecto

Mock arranca en modo agente y decide si una petición necesita conversación o acciones sobre el equipo. Las acciones de bajo riesgo se ejecutan directamente; leer/modificar contenido sensible, cerrar procesos, ejecutar terminal o realizar acciones destructivas sigue mostrando una aprobación.

Además de las herramientas anteriores, la base v11 añadió lectura de información del sistema, listado/cierre controlado de procesos del usuario y creación de carpetas. El encabezado muestra explícitamente cuando **PC Agent** está activo.

### Agent Runtime portable

Las herramientas ligadas a Niri pasaron a una interfaz genérica:

```text
desktop.focus_workspace
desktop.move_window_to_workspace
desktop.toggle_overview
desktop.close_window
```

El runtime mantiene la política de permisos: lectura de metadatos y acciones de bajo riesgo pueden ejecutarse directamente; archivos sensibles, terminal, servicios, cierre de ventanas y acciones destructivas requieren aprobación visible.

También se añadieron fallbacks para:

- portapapeles: `wl-clipboard` → `xclip` / `xsel`;
- volumen: `wpctl` → `pactl`;
- capturas: `grim` → `spectacle` → `gnome-screenshot` → `scrot`.

### Secret Service

Cuando `secret-tool` está disponible, las nuevas API keys se guardan mediante **Secret Service** (GNOME Keyring / KWallet compatibles) en vez de quedar en texto plano. `secrets.env` se conserva únicamente como fallback y para compatibilidad con configuraciones anteriores.

## Funciones actuales de Mock

- Chat con OpenAI, OpenRouter, Anthropic, Gemini, NVIDIA NIM, Ollama, LM Studio y endpoints OpenAI-compatible.
- Streaming de respuesta e historial local.
- Agent Runtime con planificación estructurada y Permission Card.
- Control de aplicaciones, archivos, clipboard, multimedia, volumen, `systemd --user`, capturas, notificaciones, terminal y energía.
- Contexto explícito de ventana/workspace, clipboard y archivos soltados.
- Voz local opcional: Whisper.cpp para STT y Piper para TTS.
- Pulse cuando Mock sigue trabajando con la UI cerrada.
- Integración de colores con DankMaterialShell si está disponible.
- Multi-monitor mediante `Quickshell.screens`.

## Paridad funcional con Coucou

El objetivo de Mock no es copiar el diseño de Coucou, sino cubrir su clase de funciones desde Linux. La matriz completa y el orden de implementación están en [`docs/COUCOU_PARITY.md`](docs/COUCOU_PARITY.md).

Las siguientes piezas todavía son trabajo pendiente para paridad amplia:

- monitor de sesiones de Claude Code / Codex / Gemini CLI / Antigravity;
- aprobación de permisos de agentes externos desde la isla;
- pills por agente e integración;
- integraciones GitHub, Vercel, n8n, Stripe, Resend, Notion y Cal.com;
- bandeja del sistema y panel de integraciones;
- drag de ventana como contexto donde el compositor lo permita.

## Requisitos

Base:

```text
Linux
Quickshell (qs)
Python 3
systemd --user recomendado
```

Recomendados según la sesión:

```text
Wayland: wl-clipboard, playerctl, wpctl, libnotify, grim
X11: xclip o xsel, playerctl, pactl/wpctl, libnotify, wmctrl/xdotool, scrot
Niri: niri
Hyprland: hyprctl
Sway: swaymsg
KDE: spectacle y opcional kdotool
```

Voz, solo si la quieres:

```text
PipeWire Audio: pw-record / pw-play
Whisper.cpp: sistema o build local de Mock
Piper TTS: preparado por scripts/setup-voice.sh
```

En Arch, `voice-setup` ya **no instala `whisper-cpp` con pacman**. Esto evita el conflicto de archivos `ggml` cuando tienes `llama.cpp-git`; Whisper se compila dentro de `~/.local/share/mock-island/whisper.cpp` y no toca `/usr`.

## Instalación / actualización

Desde la carpeta del proyecto:

```bash
chmod +x install.sh && ./install.sh
```

El instalador configura `mock-island.service`, el CLI `~/.local/bin/mock-island` y trata de instalar los atajos de forma segura en Niri, Hyprland, Sway o i3. En KDE/GNOME muestra los comandos que puedes asociar desde la configuración de atajos del escritorio.

## Comandos útiles

```bash
mock-island toggle
mock-island status
mock-island doctor
mock-island desktop-status
mock-island agent-status
mock-island context --clipboard
mock-island voice-status
mock-island voice
mock-island voice-setup
mock-island logs
./scripts/check.sh
```

## Privacidad

Mock separa **contexto**, **razonamiento** y **acción**. `WIN`, `CLIP` y `FILE` continúan siendo explícitos. El modelo no recibe una shell libre y el nivel de riesgo nunca se confía al modelo: lo impone `backend/agent_runtime.py`.

El micrófono se procesa localmente con Whisper.cpp y Piper. Las API keys usan Secret Service cuando está disponible. No hay telemetría.

## Estructura

```text
mock-island/
├── shell.qml
├── backend/
│   ├── ai_bridge.py
│   ├── agent_runtime.py
│   ├── desktop_adapter.py
│   ├── linux_context.py
│   └── voice_bridge.py
├── bin/mock-island
├── scripts/
├── systemd/
└── docs/
```

## Autor

Heyner Centeno — `@centeno2`


## v13 — corrección visual

- La isla vuelve al **borde inferior**, como en las versiones anteriores, para no competir con barras superiores como DMS.
- Se restaura la **paleta Material You completa de DMS**: surface, containers, texto, outline y acentos vuelven a seguir el esquema dinámico del escritorio.
- Si DMS no está disponible se utiliza la paleta oscura clásica de Mock en lugar del negro casi puro de v12.
- Se conserva íntegro el Agent Runtime de v12 y su enrutamiento de acciones Linux.
