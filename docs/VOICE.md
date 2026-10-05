# Mock Voice

## Diseño

Mock Voice es push/toggle-to-talk por defecto. No hay escucha permanente ni wake word activo en segundo plano.

```text
MIC / Super+Alt+V
        │
        ▼
    pw-record
        │  16 kHz mono s16
        ▼
   whisper-cli
        │  texto
        ▼
     Mock
        │
        ▼
 Piper TTS (si TTS está activo)
        │
        ▼
     pw-play
```

La grabación tiene un límite externo de 30 segundos para evitar que un proceso olvidado quede capturando indefinidamente.

## Preparación

```bash
mock-island voice-setup
```

El script instala/usa:

- `whisper-cpp` del repositorio de Arch;
- `pipewire-audio` para `pw-record`/`pw-play`;
- `ggml-base.bin`, modelo multilingüe, con checksum verificado;
- Piper TTS dentro de `~/.local/share/mock-island/voice-venv`;
- voz `es_ES-davefx-medium` en `~/.local/share/mock-island/voices`.

Comprueba el estado con:

```bash
mock-island voice-status
```

## Uso

```text
clic MIC             empezar a escuchar
clic MIC otra vez    detener + transcribir
Super+Alt+V        mismo comportamiento global
TTS                   alternar respuesta hablada
```

La transcripción se introduce en el prompt y, por defecto, se envía automáticamente. `voice.auto_send` puede cambiarse en `~/.config/mock-island/config.json`.

## Configuración

```json
{
  "voice": {
    "tts_enabled": false,
    "auto_send": true,
    "language": "es",
    "whisper_model": "/home/USER/.local/share/mock-island/models/ggml-base.bin",
    "piper_voice": "es_ES-davefx-medium"
  }
}
```

También puedes apuntar a otro modelo con `MOCK_WHISPER_MODEL=/ruta/modelo.bin`.
