# v13

- Restaurada la isla al borde inferior.
- Restaurada la paleta Material You completa de DMS; v12 actualizaba solo los acentos y dejaba la superficie casi negra.
- Recuperados bordes, contraste y superficies de la identidad visual previa sin revertir el Agent Runtime de v12.

# Changelog

## v12 — Agent real + rediseño de isla

- Rediseño visual completo de la superficie principal: isla superior centrada, fondo neutro oscuro, acento dinámico, menor altura y menos ruido visual.
- Mock deja la silueta de avatar rectangular: ahora es una cápsula suave con ojos integrados; las manos solo aparecen como reacción.
- El tema DMS ya no tiñe toda la interfaz según el wallpaper: solo aporta colores de acento.
- Respuestas finalizadas se renderizan como Markdown en lugar de mostrar `**`, tablas y backticks literalmente.
- El Agent Runtime ya no manda solicitudes accionables al chat por un filtro demasiado estrecho.
- Añadida `package.updates`: revisa actualizaciones reales del gestor del sistema, AUR cuando hay `paru`/`yay` y Flatpak cuando está disponible.
- Añadida `package.upgrade`: tras aprobación abre una terminal visible con el comando de actualización y deja la contraseña bajo control del usuario.
- Solicitudes deterministas como “revisa las actualizaciones pendientes” y “abre Firefox” se convierten directamente en planes de herramientas.
- El planificador recibe explícitamente que Mock sí tiene acceso al PC mediante su runtime y no debe contestar con “no tengo acceso a tu terminal”.
- Las comprobaciones del proyecto incluyen regresiones del planificador para evitar que esas acciones vuelvan a convertirse en respuestas de chat.
- Se mantiene el arreglo de voz aislando Whisper.cpp de `llama.cpp-git`/`ggml`.

## v11 — PC Agent + Voice Fix + Mascot Redesign

- Mock rediseñado: cuerpo flotante redondeado, sin visor/cara blanca tipo avatar, manos más pequeñas y animaciones más limpias.
- PC Agent activado por defecto con migración única de configuraciones anteriores.
- Placeholder y estado de UI dejan claro cuándo Mock puede actuar sobre el equipo.
- Nuevas herramientas `system.info`, `process.list`, `process.kill` y `file.mkdir`.
- `system.info` expone distro, kernel, CPU, memoria, GPU y capacidades del Desktop Adapter.
- `process.kill` solo puede terminar procesos del usuario actual y requiere aprobación.
- `voice-setup` deja de instalar `whisper-cpp`/`ggml` desde pacman, eliminando el choque con `llama.cpp-git`.
- Whisper.cpp se compila localmente en `~/.local/share/mock-island/whisper.cpp`; `voice_bridge.py` detecta ese binario automáticamente.
- Piper queda aislado en un venv y si falla no invalida la instalación de STT.

## v10 — Universal Linux Agent

- Desktop Adapter genérico para Niri, Hyprland, Sway/i3 y fallbacks KDE/X11.
- Herramientas del agente migradas de `niri.*` a `desktop.*`.
- `PanelWindow` usa propiedades portables de Quickshell en vez de API WlrLayershell directa.
- Fallbacks X11/Wayland para clipboard, audio y capturas.
- `mock-island desktop-status` y `doctor` multi-entorno.
- Atajos automáticos para Niri, Hyprland, Sway/i3; guía manual para otros escritorios.
- Secret Service para nuevas API keys cuando `secret-tool` está disponible.
- Mock Core con manos, saludo, reacción a clicks, mareo, corazones y hover peek.
- Documento de paridad funcional con Coucou y arquitectura objetivo.

## v9 — Agent

- Nuevo `backend/agent_runtime.py` con planificación estructurada y registro local de herramientas.
- Acciones Niri, apps, archivos, clipboard, media, volumen, systemd --user, notificaciones, screenshots, terminal y energía.
- Permission Card dentro de la isla para acciones confirmables/destructivas.
- Política local: el modelo no puede decidir por sí mismo qué acción es segura.
- `app.open` sin shell, sin ejecutables por ruta y con bloqueo de wrappers/intérpretes/utilidades peligrosas.
- Rutas de archivos restringidas al HOME resuelto.
- Terminal con aprobación, timeout, opción `allow_terminal` y bloqueo de elevación de privilegios/comandos destructivos comunes.
- Nuevo `backend/voice_bridge.py`: captura con PipeWire, STT con whisper.cpp y TTS con Piper.
- Botón `MIC`, estado visual `listening`, respuesta hablada opcional con `TTS`.
- Nuevo `Super+Alt+V` si el atajo está disponible.
- `scripts/setup-voice.sh` instala la capa de voz de forma opcional.
- Preferencias de Agent/TTS persistentes en `config.json`.
- Nuevos comandos `agent-status`, `voice`, `voice-status`, `voice-start`, `voice-stop`, `voice-setup`.
- `doctor` ampliado con `wpctl`, `grim`, PipeWire y `whisper-cli`.
- Documentación nueva: `AGENT.md` y `VOICE.md`.

## v8

- Mock Core, Context Rail y Pulse.
- Contexto explícito WIN / CLIP / FILE.
- Integración DMS/Niri/playerctl/notificaciones.
