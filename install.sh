#!/usr/bin/env bash
set -euo pipefail

PROJECT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/Projects/mock-island"
OLD_TARGET="$HOME/Projects/centeno-island"
NEW_CFG="$HOME/.config/mock-island"
OLD_CFG="$HOME/.config/centeno-island"
NEW_STATE="$HOME/.local/state/mock-island"
OLD_STATE="$HOME/.local/state/centeno-island"
QS="$(command -v qs || true)"

if [[ -z "$QS" ]]; then
  echo "ERROR: no encuentro 'qs' (Quickshell)." >&2
  exit 1
fi

mkdir -p "$HOME/Projects" "$HOME/.local/bin" "$HOME/.config/systemd/user" "$NEW_CFG" "$NEW_STATE"

# Corrige branding antiguo guardado en configuraciones previas.
python3 - <<'PYMIG'
import json, os
from pathlib import Path
p = Path(os.path.expanduser("~/.config/mock-island/config.json"))
if p.exists():
    try:
        data = json.loads(p.read_text())
    except Exception:
        data = {}
    sp = str(data.get("system_prompt") or "")
    changed = False
    if "Centeno Island" in sp or "centeno island" in sp.lower():
        data["system_prompt"] = (
            "Eres Mock, un compañero técnico integrado al escritorio Linux. "
            "Responde en español salvo que el usuario pida otro idioma. "
            "Prioriza soluciones prácticas, comandos claros y explicaciones directas. "
            "Cuando el modo agente esté activo puedes usar las herramientas del runtime para observar y actuar sobre el PC con permisos explícitos para acciones sensibles."
        )
        changed = True
    migrations = data.setdefault("_migrations", {})
    if not migrations.get("v11_agent_default"):
        data.setdefault("agent", {})["enabled"] = True
        migrations["v11_agent_default"] = True
        changed = True
    if not migrations.get("v12_agent_prompt"):
        # Solo reemplaza prompts de fábrica conocidos; respeta prompts personalizados.
        if (not sp) or ("Eres Mock" in sp and "Agent Runtime" not in sp):
            data["system_prompt"] = (
                "Eres Mock, un compañero técnico integrado al escritorio Linux. "
                "Responde en español salvo que el usuario pida otro idioma. "
                "Prioriza soluciones prácticas y explicaciones directas. "
                "Mock Island incluye un Agent Runtime separado que sí puede inspeccionar y actuar sobre el PC mediante herramientas controladas; "
                "no afirmes de forma general que Mock carece de acceso al equipo o a la terminal."
            )
            changed = True
        data.setdefault("agent", {})["enabled"] = True
        migrations["v12_agent_prompt"] = True
        changed = True
    if changed:
        p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PYMIG

# Migración v3 -> v4 sin perder API keys, proveedor, modelo ni historial.
if [[ -d "$OLD_CFG" ]]; then
  for f in config.json secrets.env; do
    [[ -e "$NEW_CFG/$f" ]] || { [[ -e "$OLD_CFG/$f" ]] && cp -a "$OLD_CFG/$f" "$NEW_CFG/$f" || true; }
  done
fi
if [[ -d "$OLD_STATE" ]]; then
  [[ -e "$NEW_STATE/history.json" ]] || { [[ -e "$OLD_STATE/history.json" ]] && cp -a "$OLD_STATE/history.json" "$NEW_STATE/history.json" || true; }
fi

# Detén la generación anterior para que no queden dos superficies Quickshell.
systemctl --user disable --now centeno-island.service >/dev/null 2>&1 || true
systemctl --user stop mock-island.service >/dev/null 2>&1 || true

if [[ "$PROJECT" != "$TARGET" ]]; then
  rm -rf "$TARGET.new"
  cp -a "$PROJECT" "$TARGET.new"
  if [[ -d "$TARGET" ]]; then
    mv "$TARGET" "$TARGET.backup.$(date +%Y%m%d-%H%M%S)"
  fi
  mv "$TARGET.new" "$TARGET"
fi

chmod +x "$TARGET/backend/ai_bridge.py" "$TARGET/backend/linux_context.py" "$TARGET/backend/desktop_adapter.py" "$TARGET/backend/agent_runtime.py" "$TARGET/backend/voice_bridge.py" "$TARGET/bin/mock-island" "$TARGET/scripts/check.sh" "$TARGET/scripts/setup-voice.sh"
ln -sfn "$TARGET/bin/mock-island" "$HOME/.local/bin/mock-island"
# Compatibilidad: los comandos viejos siguen funcionando, pero todo apunta a Mock Island.
ln -sfn "$TARGET/bin/mock-island" "$HOME/.local/bin/centeno-island"

python3 "$TARGET/backend/ai_bridge.py" status >/dev/null

sed -e "s|@PROJECT@|$TARGET|g" -e "s|@QS@|$QS|g" \
  "$TARGET/systemd/mock-island.service.in" > "$HOME/.config/systemd/user/mock-island.service"

# Limpia branding/atajos antiguos de Niri si existen; otros escritorios no se tocan aquí.
NIRI_CFG="$HOME/.config/niri/config.kdl"
if [[ -f "$NIRI_CFG" ]]; then
  cp -f "$NIRI_CFG" "$NIRI_CFG.mock-island-migration.bak"
  sed -i '/^[[:space:]]*include[[:space:]]*"centeno-island\.kdl"[[:space:]]*$/d' "$NIRI_CFG"
fi
rm -f "$HOME/.config/niri/centeno-island.kdl"

systemctl --user daemon-reload
systemctl --user enable --now mock-island.service

"$HOME/.local/bin/mock-island" bind || true

echo
echo "✓ Mock Island v13 Agent Shell instalado en $TARGET"
echo "✓ Super + Espacio abre/cierra Mock"
echo "✓ Isla compacta restaurada al borde inferior + Pulse/Peek activados"
echo "✓ Paleta Material You completa restaurada desde DMS, con fallback oscuro si DMS no está disponible"
echo "✓ Desktop Adapter: Niri, Hyprland, Sway/i3 y fallbacks KDE/X11 detectados automáticamente"
echo "✓ Si cierras Mock mientras responde, Pulse mantiene el estado y avisa al terminar"
echo "✓ PC Agent real: sistema, paquetes, apps, archivos, procesos, workspaces, audio y terminal con permisos"
echo "✓ Voz local opcional: MIC + Whisper.cpp; TTS con Piper tras ejecutar mock-island voice-setup"
echo "✓ Atajos automáticos cuando el entorno permite editarlos con seguridad; KDE/GNOME muestran el comando a asignar"
echo "✓ Proveedores, streaming, historial y ajustes anteriores se conservan"
echo
echo "Pruebas útiles:"
echo "  mock-island status"
echo "  mock-island probe ollama"
echo "  mock-island models nvidia"
echo "  mock-island context --clipboard"
echo "  mock-island agent-status"
echo "  mock-island voice-status"
echo "  mock-island voice-setup    # solo una vez, descarga modelos"
echo "  mock-island doctor"
echo "  mock-island logs"
