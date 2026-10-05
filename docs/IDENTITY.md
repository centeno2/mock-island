# Mock Island — identidad de producto

Mock es un **agente del shell para Linux**, no una mascota de notch. Su identidad se construye alrededor de Core, Context Rail, Agent Runtime, Voice, Pulse y Desktop Adapter.

## Mock Core

El Core es un pequeño módulo técnico con visor digital y manos. Parpadea, sigue el cursor, saluda, reacciona a toques y usa el cuerpo para comunicar estados `idle`, `listening`, `thinking`, `acting`, `speaking`, `happy`, `error` y `offline`.

Las manos tienen función semántica: recibir archivo, celebrar, mostrar tensión, saludar o indicar actividad. Tres toques seguidos marean a Mock; una permanencia larga del cursor activa una reacción amistosa.

## Context Rail

- `AGENT`: planificación y herramientas del sistema.
- `TTS`: voz de salida.
- `WIN`: metadatos de ventana/workspace cuando el entorno lo permite.
- `CLIP`: portapapeles explícito.
- `FILE`: archivo soltado explícitamente.

Una fuente sensible no debe quedar invisible.

## Agent Runtime y Permission Card

El modelo produce un plan estructurado. El runtime vuelve a validar herramienta, argumentos y riesgo. Las acciones sensibles muestran **Cancelar / Ejecutar** antes de actuar.

## Desktop Adapter

Mock no conoce Niri directamente desde su lógica de producto. Pide acciones genéricas y el adaptador las traduce a Niri, Hyprland, Sway/i3, KDE/X11 o devuelve una capacidad no disponible.

La degradación es deliberada: si GNOME Wayland no permite una operación global, Mock no finge que puede hacerla.

## Voice

Push/toggle-to-talk con Whisper.cpp local y TTS local con Piper. No escucha permanentemente.

## Pulse y Peek

- cerrado + inactivo → hotspot mínimo invisible;
- hover del borde → Peek;
- abierto → isla completa;
- cerrado + trabajando → Pulse;
- trabajo terminado → Pulse / respuesta lista.

## Inspiración sin clonación

Coucou es referencia de interacción y amplitud funcional. Mock no reutiliza Mochi, iconos, sonidos, imágenes ni assets de Coucou. La dirección propia es un agente técnico Linux integrado al escritorio.
