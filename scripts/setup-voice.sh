#!/usr/bin/env bash
set -euo pipefail

DATA="${XDG_DATA_HOME:-$HOME/.local/share}/mock-island"
MODEL_DIR="$DATA/models"
VOICE_DIR="$DATA/voices"
VENV="$DATA/voice-venv"
WHISPER_SRC="$DATA/whisper.cpp"
WHISPER_BIN="$WHISPER_SRC/build/bin/whisper-cli"
MODEL="$MODEL_DIR/ggml-base.bin"
MODEL_SHA1="465707469ff3a37a2b9b8d8f89f2f99de7299dac"
mkdir -p "$MODEL_DIR" "$VOICE_DIR"

echo '==> Dependencias base de voz (Arch Linux)'
if command -v pacman >/dev/null 2>&1; then
  # No instalamos whisper-cpp desde pacman: ese paquete arrastra ggml y puede
  # chocar con llama.cpp-git, que ya provee los mismos archivos. Mock compila
  # Whisper localmente dentro de ~/.local/share/mock-island y no toca /usr.
  sudo pacman -S --needed pipewire-audio curl python git cmake gcc make
  if pacman -Q llama.cpp-git >/dev/null 2>&1; then
    echo '✓ Detectado llama.cpp-git: no instalaré el paquete whisper-cpp/ggml del sistema, así evitamos el conflicto que te salió.'
  fi
else
  echo 'No detecté pacman. Asegúrate de tener PipeWire, curl, Python, git, CMake y un compilador C/C++.' >&2
fi

if command -v whisper-cli >/dev/null 2>&1; then
  echo "==> Whisper del sistema detectado: $(command -v whisper-cli)"
elif [[ -x "$WHISPER_BIN" ]]; then
  echo "==> Whisper local ya existe: $WHISPER_BIN"
else
  echo '==> Compilando Whisper.cpp de forma local (sin conflicto con llama.cpp/ggml)'
  if [[ -d "$WHISPER_SRC/.git" ]]; then
    git -C "$WHISPER_SRC" fetch --depth 1 origin master >/dev/null 2>&1 || true
    git -C "$WHISPER_SRC" reset --hard origin/master >/dev/null 2>&1 || true
  else
    rm -rf "$WHISPER_SRC"
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git "$WHISPER_SRC"
  fi
  cmake -S "$WHISPER_SRC" -B "$WHISPER_SRC/build" \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=ON \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_NATIVE=ON \
    -DCMAKE_BUILD_TYPE=Release
  cmake --build "$WHISPER_SRC/build" --target whisper-cli -j"$(nproc)"
  [[ -x "$WHISPER_BIN" ]] || { echo "ERROR: no se generó $WHISPER_BIN" >&2; exit 1; }
fi

if [[ ! -s "$MODEL" ]] || ! printf '%s  %s\n' "$MODEL_SHA1" "$MODEL" | sha1sum -c - >/dev/null 2>&1; then
  echo '==> Descargando Whisper base multilingüe (~142 MiB)'
  rm -f "$MODEL.part"
  curl -L --fail --progress-bar -o "$MODEL.part" 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin'
  printf '%s  %s\n' "$MODEL_SHA1" "$MODEL.part" | sha1sum -c -
  mv "$MODEL.part" "$MODEL"
else
  echo '==> Whisper base ya existe y su checksum es correcto'
fi

echo '==> Preparando Piper TTS aislado'
rm -rf "$VENV.new"
if python3 -m venv "$VENV.new"; then
  if "$VENV.new/bin/python" -m pip install --upgrade pip >/dev/null && \
     "$VENV.new/bin/python" -m pip install piper-tts && \
     "$VENV.new/bin/python" -m piper.download_voices --data-dir "$VOICE_DIR" es_ES-davefx-medium; then
    rm -rf "$VENV"
    mv "$VENV.new" "$VENV"
  else
    rm -rf "$VENV.new"
    echo '⚠ Piper TTS no pudo instalarse en esta versión de Python. STT con Whisper sí queda disponible.' >&2
  fi
else
  rm -rf "$VENV.new"
  echo '⚠ No pude crear el entorno de Piper. STT con Whisper sí queda disponible.' >&2
fi

echo
printf '✓ Voz preparada.\n  STT model: %s\n' "$MODEL"
if command -v whisper-cli >/dev/null 2>&1; then
  printf '  Whisper: %s\n' "$(command -v whisper-cli)"
else
  printf '  Whisper: %s\n' "$WHISPER_BIN"
fi
if [[ -x "$VENV/bin/python" ]]; then
  printf '  TTS: es_ES-davefx-medium\n'
else
  printf '  TTS: no disponible (opcional)\n'
fi
echo 'Prueba: mock-island voice-status'
