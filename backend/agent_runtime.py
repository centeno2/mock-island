#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable

from ai_bridge import DEFAULT_CONFIG, history_load, history_save, load_config
from linux_context import desktop_context
from desktop_adapter import perform as desktop_perform, status as desktop_status

HERE = Path(__file__).resolve().parent
BRIDGE = HERE / "ai_bridge.py"
HOME = Path.home().resolve()

# Policy is enforced here, never trusted from model output.
TOOL_POLICY: dict[str, dict[str, Any]] = {
    "context.desktop": {"risk": "read", "description": "Leer ventana/workspace/media actuales"},
    "system.info": {"risk": "read", "description": "Leer información básica del equipo"},
    "process.list": {"risk": "read", "description": "Listar procesos del usuario"},
    "package.updates": {"risk": "read", "description": "Revisar actualizaciones disponibles del sistema"},
    "package.upgrade": {"risk": "confirm", "description": "Abrir una terminal visible para actualizar el sistema"},
    "process.kill": {"risk": "confirm", "description": "Terminar un proceso del usuario"},
    "desktop.focus_workspace": {"risk": "safe", "description": "Cambiar al workspace indicado"},
    "desktop.move_window_to_workspace": {"risk": "safe", "description": "Mover la ventana enfocada a otro workspace"},
    "desktop.toggle_overview": {"risk": "safe", "description": "Abrir/cerrar la vista general cuando el entorno lo soporte"},
    "desktop.close_window": {"risk": "confirm", "description": "Cerrar la ventana enfocada"},
    "app.open": {"risk": "safe", "description": "Abrir una aplicación sin pasar por shell"},
    "file.read": {"risk": "confirm", "description": "Leer el contenido de un archivo dentro del HOME"},
    "file.list": {"risk": "read", "description": "Listar una carpeta dentro del HOME"},
    "file.search": {"risk": "read", "description": "Buscar archivos por nombre dentro del HOME"},
    "file.write": {"risk": "confirm", "description": "Crear o modificar un archivo dentro del HOME"},
    "file.mkdir": {"risk": "confirm", "description": "Crear una carpeta dentro del HOME"},
    "file.move": {"risk": "confirm", "description": "Mover/renombrar un archivo dentro del HOME"},
    "file.delete": {"risk": "destructive", "description": "Eliminar un archivo/carpeta dentro del HOME"},
    "clipboard.read": {"risk": "confirm", "description": "Leer el portapapeles"},
    "clipboard.write": {"risk": "safe", "description": "Escribir texto al portapapeles"},
    "media.control": {"risk": "safe", "description": "Controlar reproducción multimedia"},
    "audio.volume": {"risk": "safe", "description": "Cambiar volumen del sistema"},
    "service.user": {"risk": "confirm", "description": "Iniciar/detener/reiniciar un servicio systemd de usuario"},
    "notify.send": {"risk": "safe", "description": "Enviar una notificación de escritorio"},
    "screenshot.capture": {"risk": "safe", "description": "Guardar una captura con grim"},
    "terminal.run": {"risk": "confirm", "description": "Ejecutar un comando visible en una shell de usuario"},
    "power.action": {"risk": "destructive", "description": "Apagar o reiniciar el equipo"},
}

ALIASES = {
    "vscode": ["code"], "visual studio code": ["code"], "code": ["code"],
    "firefox": ["firefox"], "dolphin": ["dolphin"], "kitty": ["kitty"],
    "terminal": ["kitty"], "konsole": ["konsole"], "obsidian": ["obsidian"],
    "steam": ["steam"], "vesktop": ["vesktop"], "discord": ["vesktop"],
}

PLANNER_SYSTEM = r"""Eres el planificador de Mock, un agente de escritorio Linux integrado mediante un adaptador de entorno.
Devuelve EXCLUSIVAMENTE un objeto JSON válido, sin Markdown.
No inventes herramientas. Máximo 6 acciones. IMPORTANTE: Mock SÍ tiene acceso al PC mediante las herramientas listadas abajo. Nunca respondas que no tienes acceso a terminal, archivos, procesos o al sistema: si la petición requiere inspeccionar o actuar sobre el PC, crea acciones. Si la solicitud solo necesita conversación/conocimiento y no requiere tocar el PC, devuelve {"mode":"chat","actions":[]}.
Si requiere el PC, devuelve {"mode":"agent","actions":[{"tool":"...","args":{...},"label":"frase corta"}]}.
Nunca declares el nivel de riesgo: el runtime lo impone.
Usa terminal.run solo si ninguna herramienta específica sirve. No uses sudo/doas/pkexec.
No asumas Niri, Hyprland, KDE, GNOME, Sway o X11: usa siempre desktop.*; el runtime traduce la acción al entorno detectado.
No conviertas una petición ambigua en una acción destructiva. Para apagar/reiniciar usa power.action.

Herramientas y argumentos:
- context.desktop {}
- system.info {}
- process.list {"query":"opcional"}
- process.kill {"pid":1234}
- package.updates {}
- package.upgrade {}
- desktop.focus_workspace {"workspace":"2"}
- desktop.move_window_to_workspace {"workspace":"3","focus":true}
- desktop.toggle_overview {}
- desktop.close_window {}
- app.open {"argv":["firefox"]} o {"argv":["code","/ruta"]}
- file.read {"path":"~/archivo"}
- file.list {"path":"~/carpeta"}
- file.search {"path":"~/Projects","query":"nombre"}
- file.write {"path":"~/archivo","content":"texto","overwrite":false}
- file.mkdir {"path":"~/carpeta"}
- file.move {"src":"~/a","dst":"~/b"}
- file.delete {"path":"~/archivo"}
- clipboard.read {}
- clipboard.write {"text":"..."}
- media.control {"action":"play-pause|play|pause|next|previous|stop"}
- audio.volume {"action":"set|up|down|mute","value":50}
- service.user {"action":"start|stop|restart","name":"servicio.service"}
- notify.send {"title":"...","body":"..."}
- screenshot.capture {"path":"~/Pictures/Screenshots/mock.png"}
- terminal.run {"command":"...","cwd":"~/Projects/proyecto"}
- power.action {"action":"poweroff|reboot"}
"""

ACTION_HINTS = re.compile(
    r"\b(abre|abrir|lanza|ejecuta|corre|inicia|reinicia|deten|detén|cierra|mueve|workspace|"
    r"copia|portapapeles|pausa|reproduce|siguiente|anterior|volumen|silencia|captura|screenshot|"
    r"borra|elimina|mueve|renombra|crea|carpeta|guarda|apaga|reinicia|terminal|servicio|systemctl|"
    r"procesos?|hardware|sistema|equipo|pc|kernel|memoria|ram|gpu|cpu|actualizaciones?|updates?|paquetes?|upgrade)\b",
    re.I,
)


def _json(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False)


def _safe_path(raw: str, *, must_exist: bool = False) -> Path:
    p = Path(os.path.expandvars(os.path.expanduser(str(raw or "~")))).resolve()
    try:
        p.relative_to(HOME)
    except ValueError as exc:
        raise RuntimeError("Mock solo puede operar archivos dentro de tu HOME") from exc
    if must_exist and not p.exists():
        raise RuntimeError(f"No existe: {p}")
    return p


def _run(argv: list[str], timeout: float = 12, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            argv, input=input_text, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=timeout, check=False,
        )
    except FileNotFoundError:
        raise RuntimeError(f"No encuentro {argv[0]}")
    except subprocess.TimeoutExpired:
        raise RuntimeError("La acción superó el tiempo máximo")


def _extract_model_text(proc: subprocess.CompletedProcess[str]) -> str:
    if proc.returncode != 0 and not proc.stdout:
        raise RuntimeError(proc.stderr.strip() or "El modelo no pudo crear el plan")
    chunks: list[str] = []
    err = ""
    for raw in proc.stdout.splitlines():
        try:
            e = json.loads(raw)
        except json.JSONDecodeError:
            continue
        typ = e.get("type")
        if typ == "reset":
            chunks = []
        elif typ == "delta":
            chunks.append(str(e.get("text") or ""))
        elif typ == "error":
            err = str(e.get("message") or "")
    text = "".join(chunks).strip()
    if not text and err:
        raise RuntimeError(err)
    return text


def _model_complete(prompt: str, system: str, provider: str, model: str) -> str:
    cmd = [sys.executable, str(BRIDGE), "ask", "--provider", provider, "--model", model or "", "--no-history", "--system-prompt", system]
    proc = _run(cmd, timeout=180, input_text=prompt + "\n")
    return _extract_model_text(proc)


def _extract_json(text: str) -> dict[str, Any]:
    t = text.strip()
    if t.startswith("```"):
        t = re.sub(r"^```(?:json)?\s*", "", t, flags=re.I)
        t = re.sub(r"\s*```$", "", t)
    try:
        data = json.loads(t)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    start, end = t.find("{"), t.rfind("}")
    if start >= 0 and end > start:
        data = json.loads(t[start:end + 1])
        if isinstance(data, dict):
            return data
    raise RuntimeError("El modelo no devolvió un plan JSON válido")


def _local_plan(request: str) -> dict[str, Any] | None:
    low = request.lower().strip()
    actions: list[dict[str, Any]] = []

    if re.search(r"\b(?:info|informaci[oó]n|datos|hardware|sistema).*(?:pc|equipo|computador|ordenador)|\b(?:cpu|gpu|ram|kernel)\b", low):
        actions.append({"tool": "system.info", "args": {}, "label": "Leer información del equipo"})

    if re.search(r"\b(?:lista|muestra|ver|qu[eé]).*procesos?\b|\bprocesos? activos?\b", low):
        actions.append({"tool": "process.list", "args": {}, "label": "Listar procesos"})

    if re.search(r"\b(?:revisa|revisar|mira|ver|lista|listar|comprueba|comprobar)?\s*(?:las\s+)?(?:actualizaciones|updates)(?:\s+pendientes|\s+disponibles)?\b|\bpaquetes?\s+(?:por\s+)?actualizar\b", low):
        actions.append({"tool": "package.updates", "args": {}, "label": "Revisar actualizaciones pendientes"})

    if re.search(r"\b(?:actualiza|actualizar|upgrade|pon\s+al\s+d[ií]a)\b.*\b(?:sistema|pc|equipo|paquetes?)\b|\b(?:actualiza|actualizar)\s+todo\b", low):
        actions.append({"tool": "package.upgrade", "args": {}, "label": "Actualizar el sistema"})

    m = re.search(r"(?:crea|crear|haz)\s+(?:una\s+)?carpeta\s+(?:llamada\s+)?[`\"']?([^`\"']+?)[`\"']?(?:\s+en\s+(.+))?$", request, re.I)
    if m:
        name = m.group(1).strip().rstrip(" .")
        base = (m.group(2) or "~").strip().strip("`\"'")
        if name and "/" not in name:
            actions.append({"tool": "file.mkdir", "args": {"path": str(Path(os.path.expanduser(base)) / name)}, "label": f"Crear carpeta {name}"})

    m = re.search(r"(?:abre|abrir|lanza|inicia)\s+(?:el\s+|la\s+)?(firefox|vscode|visual studio code|code|dolphin|kitty|terminal|konsole|obsidian|steam|vesktop|discord)\b", low)
    if m:
        name = m.group(1)
        actions.append({"tool": "app.open", "args": {"argv": ALIASES[name]}, "label": f"Abrir {name}"})

    m = re.search(r"(?:ve|cambia|ir|anda).*?workspace\s+(\d+)", low)
    if m and "mueve" not in low:
        actions.append({"tool": "desktop.focus_workspace", "args": {"workspace": m.group(1)}, "label": f"Ir al workspace {m.group(1)}"})

    m = re.search(r"mueve.*?workspace\s+(\d+)", low)
    if m:
        actions.append({"tool": "desktop.move_window_to_workspace", "args": {"workspace": m.group(1), "focus": True}, "label": f"Mover ventana al workspace {m.group(1)}"})

    if any(x in low for x in ("pausa la música", "pausa la musica", "play pause", "reproduce la música", "reproduce la musica")):
        actions.append({"tool": "media.control", "args": {"action": "play-pause"}, "label": "Alternar reproducción"})
    elif "siguiente" in low and any(x in low for x in ("canción", "cancion", "música", "musica")):
        actions.append({"tool": "media.control", "args": {"action": "next"}, "label": "Siguiente pista"})
    elif "anterior" in low and any(x in low for x in ("canción", "cancion", "música", "musica")):
        actions.append({"tool": "media.control", "args": {"action": "previous"}, "label": "Pista anterior"})

    m = re.search(r"volumen\D{0,12}(\d{1,3})\s*%?", low)
    if m:
        actions.append({"tool": "audio.volume", "args": {"action": "set", "value": min(100, int(m.group(1)))}, "label": f"Volumen {min(100, int(m.group(1)))}%"})

    if re.search(r"\b(apaga|apagar)\b", low):
        actions.append({"tool": "power.action", "args": {"action": "poweroff"}, "label": "Apagar el equipo"})
    elif re.search(r"\breinicia(?:r)?\s+(?:el\s+)?(?:pc|equipo|computador|ordenador)\b", low):
        actions.append({"tool": "power.action", "args": {"action": "reboot"}, "label": "Reiniciar el equipo"})

    m = re.search(r"(?:ejecuta|corre|terminal)\s*[:：]?\s*`([^`]+)`", request, re.I)
    if m:
        actions.append({"tool": "terminal.run", "args": {"command": m.group(1), "cwd": str(HOME)}, "label": "Ejecutar comando"})

    return {"mode": "agent", "actions": actions} if actions else None


def normalize_plan(data: dict[str, Any], request: str, max_actions: int) -> dict[str, Any]:
    mode = "agent" if data.get("mode") == "agent" else "chat"
    raw_actions = data.get("actions") if isinstance(data.get("actions"), list) else []
    actions: list[dict[str, Any]] = []
    for idx, item in enumerate(raw_actions[:max_actions]):
        if not isinstance(item, dict):
            continue
        tool = str(item.get("tool") or "")
        if tool not in TOOL_POLICY:
            continue
        policy = TOOL_POLICY[tool]
        args = item.get("args") if isinstance(item.get("args"), dict) else {}
        label = str(item.get("label") or policy["description"])
        detail = ""
        if tool == "terminal.run": detail = str(args.get("command") or "")
        elif tool in {"file.read", "file.write", "file.mkdir", "file.delete", "file.list", "file.search"}: detail = str(args.get("path") or "")
        elif tool == "file.move": detail = f"{args.get('src','')} → {args.get('dst','')}"
        elif tool == "service.user": detail = f"{args.get('action','')} {args.get('name','')}"
        elif tool.startswith("desktop.") and args.get("workspace") is not None: detail = f"workspace {args.get('workspace')}"
        elif tool == "app.open" and isinstance(args.get("argv"), list): detail = " ".join(str(x) for x in args.get("argv", []))
        elif tool == "process.kill": detail = "PID " + str(args.get("pid") or "")
        elif tool == "power.action": detail = str(args.get("action") or "")
        display = label + ((" · " + detail[:180]) if detail else "")
        actions.append({
            "id": idx + 1,
            "tool": tool,
            "args": args,
            "label": label,
            "display": display,
            "risk": policy["risk"],
            "requires_confirmation": policy["risk"] in {"confirm", "destructive"},
        })
    if not actions:
        mode = "chat"
    return {
        "ok": True,
        "mode": mode,
        "request": request,
        "actions": actions,
        "needs_confirmation": any(a["requires_confirmation"] for a in actions),
    }



def _project_inventory() -> list[str]:
    root = HOME / "Projects"
    if not root.is_dir():
        return []
    try:
        return [x.name for x in sorted(root.iterdir(), key=lambda q: q.name.casefold()) if x.is_dir()][:100]
    except OSError:
        return []

def plan(request: str, provider: str, model: str) -> dict[str, Any]:
    cfg = load_config()
    max_actions = max(1, min(10, int(cfg.get("agent", {}).get("max_actions", 6))))
    local = _local_plan(request)

    # Deterministic desktop/system intents should never be turned back into chat by
    # a remote model. This is what makes "revisa actualizaciones", "abre Firefox",
    # "muévelo al workspace 3", etc. actual agent requests instead of advice.
    if local:
        return normalize_plan(local, request, max_actions)

    if provider == "mock":
        return normalize_plan({"mode": "chat", "actions": []}, request, max_actions)

    context = desktop_context(include_clipboard=False)
    planner_input = (
        "Solicitud del usuario:\n" + request + "\n\n"
        "Contexto actual no sensible:\n" + json.dumps(context, ensure_ascii=False) + "\n\n"
        "Proyectos visibles en ~/Projects (solo nombres):\n" + json.dumps(_project_inventory(), ensure_ascii=False) + "\n"
    )
    try:
        raw = _model_complete(planner_input, PLANNER_SYSTEM, provider, model)
        parsed = normalize_plan(_extract_json(raw), request, max_actions)
    except Exception:
        # If planning fails for a clearly actionable request, do not silently tell
        # the user Mock has no PC access. Surface the planner failure instead.
        if ACTION_HINTS.search(request):
            raise
        return normalize_plan({"mode": "chat", "actions": []}, request, max_actions)

    if parsed["mode"] == "chat" and ACTION_HINTS.search(request):
        raise RuntimeError("El modelo intentó responder como chat a una solicitud de acción. Mock no ejecutó nada; vuelve a intentar o usa un modelo con mejor seguimiento de herramientas.")
    return parsed



def _tool_system_info(_: dict[str, Any]) -> dict[str, Any]:
    info: dict[str, Any] = {
        "hostname": os.uname().nodename,
        "kernel": os.uname().release,
        "architecture": os.uname().machine,
        "desktop": desktop_status(),
    }
    os_release = Path("/etc/os-release")
    if os_release.is_file():
        vals = {}
        for line in os_release.read_text(errors="replace").splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                vals[k] = v.strip().strip('"')
        info["os"] = vals.get("PRETTY_NAME") or vals.get("NAME") or "Linux"
    commands = {
        # Force C locale so parsing is stable even when the desktop language is Spanish.
        "cpu": ["env", "LC_ALL=C", "lscpu"],
        "memory": ["free", "-h"],
        "gpu": ["lspci", "-nnk"],
    }
    for key, argv in commands.items():
        required = "lscpu" if key == "cpu" else argv[0]
        if shutil.which(required):
            proc = _run(argv, timeout=5)
            if proc.returncode == 0:
                text = proc.stdout
                if key == "gpu":
                    # Keep only graphics-controller blocks and their own kernel driver/module lines.
                    lines = []
                    active = False
                    for line in text.splitlines():
                        is_device = bool(line and not line[0].isspace())
                        if is_device:
                            active = bool(re.search(r"VGA compatible controller|3D controller|Display controller", line, re.I))
                            if active:
                                lines.append(line.strip())
                            continue
                        if active and re.search(r"Kernel driver in use:|Kernel modules:", line, re.I):
                            lines.append(line.strip())
                    info[key] = "\n".join(lines[:12])
                elif key == "cpu":
                    keep = []
                    for line in text.splitlines():
                        if line.startswith(("Model name:", "CPU(s):", "Thread(s) per core:", "Core(s) per socket:", "Socket(s):")):
                            keep.append(line)
                    info[key] = "\n".join(keep)
                else:
                    info[key] = "\n".join(text.splitlines()[:4])
    return info


def _tool_process_list(args: dict[str, Any]) -> list[dict[str, Any]]:
    query = str(args.get("query") or "").strip().casefold()
    proc = _run(["ps", "-u", str(os.getuid()), "-o", "pid=,pcpu=,pmem=,comm=,args="], timeout=5)
    if proc.returncode:
        raise RuntimeError(proc.stderr.strip() or "ps falló")
    rows: list[dict[str, Any]] = []
    for line in proc.stdout.splitlines():
        parts = line.strip().split(None, 4)
        if len(parts) < 4:
            continue
        pid, cpu, mem, comm = parts[:4]
        args_text = parts[4] if len(parts) > 4 else comm
        hay = f"{comm} {args_text}".casefold()
        if query and query not in hay:
            continue
        rows.append({"pid": int(pid), "cpu": cpu, "mem": mem, "command": comm, "args": args_text[:240]})
        if len(rows) >= 80:
            break
    return rows


def _clean_lines(text: str, limit: int = 250) -> list[str]:
    return [line.strip() for line in text.splitlines() if line.strip()][:limit]


def _detect_package_manager() -> str:
    for name in ("pacman", "apt", "dnf", "yum", "zypper", "apk"):
        if shutil.which(name):
            return name
    return "unknown"


def _tool_package_updates(_: dict[str, Any]) -> dict[str, Any]:
    manager = _detect_package_manager()
    result: dict[str, Any] = {"manager": manager, "system": [], "aur": [], "flatpak": [], "notes": []}

    if manager == "pacman":
        if shutil.which("checkupdates"):
            proc = _run(["checkupdates"], timeout=90)
            if proc.returncode not in {0, 2}:
                result["notes"].append(proc.stderr.strip() or "checkupdates no pudo refrescar el índice")
            result["system"] = _clean_lines(proc.stdout)
            result["source"] = "checkupdates"
        else:
            proc = _run(["pacman", "-Qu"], timeout=20)
            if proc.returncode not in {0, 1}:
                result["notes"].append(proc.stderr.strip() or "pacman -Qu falló")
            result["system"] = _clean_lines(proc.stdout)
            result["source"] = "pacman -Qu (metadatos locales; instala pacman-contrib para checkupdates fresco)"
        aur = shutil.which("paru") or shutil.which("yay")
        if aur:
            proc = _run([aur, "-Qua"], timeout=45)
            if proc.returncode in {0, 1}:
                result["aur"] = _clean_lines(proc.stdout)
            elif proc.stderr.strip():
                result["notes"].append(proc.stderr.strip())
    elif manager == "apt":
        proc = _run(["apt", "list", "--upgradable"], timeout=30)
        result["system"] = [x for x in _clean_lines(proc.stdout) if not x.lower().startswith("listing")]
        result["source"] = "apt (metadatos locales)"
        if proc.returncode not in {0, 100} and proc.stderr.strip():
            result["notes"].append(proc.stderr.strip())
    elif manager in {"dnf", "yum"}:
        proc = _run([manager, "check-upgrade"], timeout=90)
        result["system"] = _clean_lines(proc.stdout)
        result["source"] = manager
        if proc.returncode not in {0, 100} and proc.stderr.strip():
            result["notes"].append(proc.stderr.strip())
    elif manager == "zypper":
        proc = _run(["zypper", "--non-interactive", "list-updates"], timeout=90)
        result["system"] = _clean_lines(proc.stdout)
        result["source"] = "zypper"
        if proc.returncode not in {0, 100} and proc.stderr.strip():
            result["notes"].append(proc.stderr.strip())
    elif manager == "apk":
        proc = _run(["apk", "version", "-l", "<"], timeout=30)
        result["system"] = _clean_lines(proc.stdout)
        result["source"] = "apk"
        if proc.returncode and proc.stderr.strip():
            result["notes"].append(proc.stderr.strip())
    else:
        result["notes"].append("No detecté un gestor de paquetes del sistema compatible")

    if shutil.which("flatpak"):
        proc = _run(["flatpak", "remote-ls", "--updates", "--columns=application,branch"], timeout=60)
        if proc.returncode == 0:
            result["flatpak"] = _clean_lines(proc.stdout)
        elif proc.stderr.strip():
            result["notes"].append("Flatpak: " + proc.stderr.strip())

    result["counts"] = {
        "system": len(result["system"]),
        "aur": len(result["aur"]),
        "flatpak": len(result["flatpak"]),
    }
    return result


def _spawn_terminal(command: str) -> str:
    shell_cmd = command + '; code=$?; printf "\\n\\n[Mock] comando terminado (código %s).\\n" "$code"; printf "Puedes cerrar esta terminal cuando quieras.\\n"; exec "${SHELL:-/bin/bash}" -l'
    candidates: list[list[str]] = []
    terminal_env = os.environ.get("TERMINAL", "").strip()
    if terminal_env:
        try:
            base = shlex.split(terminal_env)
            if base:
                candidates.append(base + ["-e", "bash", "-lc", shell_cmd])
        except ValueError:
            pass
    known = [
        ("kitty", ["kitty", "-e", "bash", "-lc", shell_cmd]),
        ("foot", ["foot", "-e", "bash", "-lc", shell_cmd]),
        ("alacritty", ["alacritty", "-e", "bash", "-lc", shell_cmd]),
        ("wezterm", ["wezterm", "start", "--", "bash", "-lc", shell_cmd]),
        ("konsole", ["konsole", "-e", "bash", "-lc", shell_cmd]),
        ("gnome-terminal", ["gnome-terminal", "--", "bash", "-lc", shell_cmd]),
    ]
    candidates.extend(argv for exe, argv in known if shutil.which(exe))
    for argv in candidates:
        try:
            subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            return argv[0]
        except OSError:
            continue
    raise RuntimeError("No encuentro una terminal gráfica compatible (kitty, foot, alacritty, wezterm, konsole o gnome-terminal)")


def _tool_package_upgrade(_: dict[str, Any]) -> str:
    manager = _detect_package_manager()
    commands = {
        "pacman": "sudo pacman -Syu",
        "apt": "sudo apt update && sudo apt upgrade",
        "dnf": "sudo dnf upgrade",
        "yum": "sudo yum update",
        "zypper": "sudo zypper update",
        "apk": "doas apk upgrade",
    }
    command = commands.get(manager)
    if not command:
        raise RuntimeError("No detecté un gestor de paquetes compatible para actualizar el sistema")
    terminal = _spawn_terminal(command)
    return f"Abrí {terminal} con `{command}` para que la elevación de privilegios sea visible y tú introduzcas la contraseña."


def _tool_process_kill(args: dict[str, Any]) -> str:
    try:
        pid = int(args.get("pid"))
    except Exception as exc:
        raise RuntimeError("PID no válido") from exc
    if pid <= 1 or pid == os.getpid():
        raise RuntimeError("PID bloqueado")
    proc_path = Path(f"/proc/{pid}")
    if not proc_path.exists():
        raise RuntimeError(f"El PID {pid} ya no existe")
    try:
        owner = proc_path.stat().st_uid
    except OSError as exc:
        raise RuntimeError("No pude comprobar el propietario del proceso") from exc
    if owner != os.getuid():
        raise RuntimeError("Mock solo puede terminar procesos de tu usuario")
    os.kill(pid, signal.SIGTERM)
    return f"SIGTERM enviado al PID {pid}"


def _tool_context(_: dict[str, Any]) -> Any:
    return desktop_context(include_clipboard=False)


def _workspace_ref(args: dict[str, Any]) -> str:
    ref = str(args.get("workspace") or "").strip()
    if not ref:
        raise RuntimeError("Falta workspace")
    if not re.fullmatch(r"[A-Za-z0-9_.:-]{1,64}", ref):
        raise RuntimeError("Referencia de workspace no válida")
    return ref


def _tool_desktop_focus(args: dict[str, Any]) -> str:
    return desktop_perform("focus_workspace", args)


def _tool_desktop_move(args: dict[str, Any]) -> str:
    return desktop_perform("move_window_to_workspace", args)


def _tool_desktop_overview(args: dict[str, Any]) -> str:
    return desktop_perform("toggle_overview", args)


def _tool_desktop_close(args: dict[str, Any]) -> str:
    return desktop_perform("close_window", args)


def _tool_app_open(args: dict[str, Any]) -> str:
    argv = args.get("argv")
    if not isinstance(argv, list) or not argv or not all(isinstance(x, str) and x for x in argv):
        raise RuntimeError("app.open necesita argv")
    if "/" in argv[0] or "\\" in argv[0]:
        raise RuntimeError("app.open solo acepta nombres de aplicaciones, no ejecutables por ruta")
    name = argv[0]
    blocked = {
        "sh", "bash", "dash", "zsh", "fish", "python", "python3", "perl", "ruby", "node", "php",
        "env", "xargs", "find", "awk", "sed", "make", "cmake", "ninja", "cargo", "npm", "pnpm", "yarn",
        "git", "java", "rm", "rmdir", "mv", "cp", "dd", "curl", "wget", "systemctl", "pkill", "kill",
        "killall", "sudo", "doas", "pkexec", "niri", "hyprctl", "swaymsg", "i3-msg", "wmctrl", "shutdown", "reboot", "poweroff"
    }
    if name in blocked:
        raise RuntimeError("Ese ejecutable debe pasar por terminal.run y aprobación")
    # Arguments can turn an otherwise harmless command into a command runner.
    # Keep them to known desktop apps; unknown apps may still be launched bare.
    allow_args = {
        "code", "codium", "firefox", "chromium", "google-chrome", "dolphin", "nautilus", "thunar",
        "kitty", "konsole", "alacritty", "foot", "obsidian", "steam", "vesktop", "discord", "spotify",
        "fastpotify", "spotifast", "openrgb", "prismlauncher", "prism-launcher", "lutris", "xdg-open"
    }
    if len(argv) > 1 and name not in allow_args:
        raise RuntimeError(f"Mock no permite argumentos automáticos para {name}; usa terminal.run con aprobación")
    if name in {"kitty", "konsole", "alacritty", "foot"} and any(x in {"-e", "--execute", "-c", "--command"} for x in argv[1:]):
        raise RuntimeError("Ejecutar comandos desde un terminal requiere terminal.run y aprobación")
    exe = shutil.which(name)
    if not exe:
        raise RuntimeError(f"No encuentro la aplicación: {name}")
    subprocess.Popen([exe, *argv[1:]], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return f"Abierto: {name}"


def _tool_file_read(args: dict[str, Any]) -> str:
    p = _safe_path(str(args.get("path") or ""), must_exist=True)
    if not p.is_file(): raise RuntimeError("No es un archivo")
    data = p.read_text(errors="replace")
    return data[:12000] + ("\n[recortado]" if len(data) > 12000 else "")


def _tool_file_list(args: dict[str, Any]) -> list[str]:
    p = _safe_path(str(args.get("path") or "~"), must_exist=True)
    if not p.is_dir(): raise RuntimeError("No es una carpeta")
    return [x.name + ("/" if x.is_dir() else "") for x in sorted(p.iterdir(), key=lambda q: (not q.is_dir(), q.name.casefold()))[:200]]


def _tool_file_search(args: dict[str, Any]) -> list[str]:
    root = _safe_path(str(args.get("path") or "~"), must_exist=True)
    query = str(args.get("query") or "").strip().casefold()
    if not query: raise RuntimeError("Falta texto de búsqueda")
    found: list[str] = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in {".git", "node_modules", "build", ".cache"}]
        for name in dirs + files:
            if query in name.casefold():
                found.append(str(Path(base, name)))
                if len(found) >= 80:
                    return found
    return found


def _tool_file_write(args: dict[str, Any]) -> str:
    p = _safe_path(str(args.get("path") or ""))
    content = str(args.get("content") or "")
    overwrite = bool(args.get("overwrite", False))
    if p.exists() and not overwrite: raise RuntimeError("El archivo existe y overwrite=false")
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    return f"Escrito {p} ({len(content)} caracteres)"



def _tool_file_mkdir(args: dict[str, Any]) -> str:
    p = _safe_path(str(args.get("path") or ""))
    if p.exists():
        if p.is_dir():
            return f"La carpeta ya existe: {p}"
        raise RuntimeError("Ya existe un archivo con ese nombre")
    p.mkdir(parents=True, exist_ok=False)
    return f"Carpeta creada: {p}"


def _tool_file_move(args: dict[str, Any]) -> str:
    src = _safe_path(str(args.get("src") or ""), must_exist=True)
    dst = _safe_path(str(args.get("dst") or ""))
    if dst.exists(): raise RuntimeError("El destino ya existe")
    dst.parent.mkdir(parents=True, exist_ok=True)
    src.rename(dst)
    return f"Movido: {src} → {dst}"


def _tool_file_delete(args: dict[str, Any]) -> str:
    p = _safe_path(str(args.get("path") or ""), must_exist=True)
    # Never delete HOME itself or broad top-level collections through the agent.
    if p == HOME or p.parent == HOME and p.name in {"Projects", "Documents", "Downloads", "Descargas", "Pictures", ".config", ".local"}:
        raise RuntimeError("Ruta demasiado amplia para borrado desde Mock")
    if p.is_dir():
        shutil.rmtree(p)
    else:
        p.unlink()
    return f"Eliminado: {p}"


def _tool_clip_read(_: dict[str, Any]) -> str:
    commands: list[list[str]] = []
    if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-paste"):
        commands.append(["wl-paste", "-n"])
    if os.environ.get("DISPLAY") and shutil.which("xclip"):
        commands.append(["xclip", "-selection", "clipboard", "-o"])
    if os.environ.get("DISPLAY") and shutil.which("xsel"):
        commands.append(["xsel", "--clipboard", "--output"])
    for cmd in commands:
        p = _run(cmd, timeout=3)
        if p.returncode == 0:
            return p.stdout[:12000]
    raise RuntimeError("No pude leer el portapapeles; instala wl-clipboard (Wayland) o xclip/xsel (X11)")


def _tool_clip_write(args: dict[str, Any]) -> str:
    text = str(args.get("text") or "")
    commands: list[list[str]] = []
    if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-copy"):
        commands.append(["wl-copy"])
    if os.environ.get("DISPLAY") and shutil.which("xclip"):
        commands.append(["xclip", "-selection", "clipboard"])
    if os.environ.get("DISPLAY") and shutil.which("xsel"):
        commands.append(["xsel", "--clipboard", "--input"])
    for cmd in commands:
        p = _run(cmd, timeout=3, input_text=text)
        if p.returncode == 0:
            return f"Copiados {len(text)} caracteres"
    raise RuntimeError("No pude escribir al portapapeles; instala wl-clipboard (Wayland) o xclip/xsel (X11)")


def _tool_media(args: dict[str, Any]) -> str:
    action = str(args.get("action") or "play-pause")
    if action not in {"play-pause", "play", "pause", "next", "previous", "stop"}:
        raise RuntimeError("Acción multimedia no válida")
    p = _run(["playerctl", action], timeout=3)
    if p.returncode: raise RuntimeError(p.stderr.strip() or "playerctl falló")
    return f"Multimedia: {action}"


def _tool_volume(args: dict[str, Any]) -> str:
    action = str(args.get("action") or "set")
    value = max(0, min(100, int(args.get("value", 50))))
    if shutil.which("wpctl"):
        if action == "mute":
            argv = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        elif action == "up":
            argv = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{value/100:.2f}+"]
        elif action == "down":
            argv = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{value/100:.2f}-"]
        else:
            argv = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{value/100:.2f}"]
    elif shutil.which("pactl"):
        if action == "mute":
            argv = ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]
        elif action == "up":
            argv = ["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"+{value}%"]
        elif action == "down":
            argv = ["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"-{value}%"]
        else:
            argv = ["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{value}%"]
    else:
        raise RuntimeError("No encuentro wpctl ni pactl para controlar el volumen")
    p = _run(argv, timeout=3)
    if p.returncode: raise RuntimeError(p.stderr.strip() or "No pude cambiar el volumen")
    return "Volumen actualizado"


def _tool_service(args: dict[str, Any]) -> str:
    action = str(args.get("action") or "restart")
    name = str(args.get("name") or "").strip()
    if action not in {"start", "stop", "restart"}: raise RuntimeError("Acción systemd no válida")
    if not re.fullmatch(r"[A-Za-z0-9@_.:-]+", name): raise RuntimeError("Nombre de servicio no válido")
    p = _run(["systemctl", "--user", action, name], timeout=20)
    if p.returncode: raise RuntimeError(p.stderr.strip() or "systemctl falló")
    return f"{name}: {action}"


def _tool_notify(args: dict[str, Any]) -> str:
    title = str(args.get("title") or "Mock")[:120]
    body = str(args.get("body") or "")[:600]
    p = _run(["notify-send", "--app-name=Mock Island", title, body], timeout=3)
    if p.returncode: raise RuntimeError("notify-send falló")
    return "Notificación enviada"


def _tool_screenshot(args: dict[str, Any]) -> str:
    default = HOME / "Pictures/Screenshots" / f"mock-{time.strftime('%Y%m%d-%H%M%S')}.png"
    p = _safe_path(str(args.get("path") or default))
    p.parent.mkdir(parents=True, exist_ok=True)
    if os.environ.get("WAYLAND_DISPLAY") and shutil.which("grim"):
        cmd = ["grim", str(p)]
    elif shutil.which("spectacle"):
        cmd = ["spectacle", "-b", "-n", "-o", str(p)]
    elif shutil.which("gnome-screenshot"):
        cmd = ["gnome-screenshot", "-f", str(p)]
    elif shutil.which("scrot"):
        cmd = ["scrot", str(p)]
    else:
        raise RuntimeError("No encuentro grim, spectacle, gnome-screenshot ni scrot")
    proc = _run(cmd, timeout=12)
    if proc.returncode: raise RuntimeError(proc.stderr.strip() or "La captura falló")
    return f"Captura guardada en {p}"


TERMINAL_DENY = re.compile(
    r"(^|[;&|]\s*)(sudo|doas|pkexec|su)\b|"
    r"(^|[;&|]\s*)(rm|rmdir|shred|wipefs|mkfs(?:\.[A-Za-z0-9]+)?|fdisk|parted|shutdown|reboot|poweroff)\b|"
    r"\bdd\s+.*\bof=/dev/|"
    r"\b(curl|wget)\b[^\n|]*\|\s*(sh|bash|zsh|fish)\b|"
    r": *\(\) *\{ *: *\| *: *&",
    re.I,
)


def _tool_terminal(args: dict[str, Any]) -> dict[str, Any]:
    command = str(args.get("command") or "").strip()
    if not command: raise RuntimeError("Comando vacío")
    if len(command) > 3000: raise RuntimeError("Comando demasiado largo")
    if TERMINAL_DENY.search(command): raise RuntimeError("Comando bloqueado por la política de seguridad de Mock")
    cwd = _safe_path(str(args.get("cwd") or HOME), must_exist=True)
    if not cwd.is_dir(): raise RuntimeError("cwd no es una carpeta")
    try:
        p = subprocess.run(["bash", "-lc", command], cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45, check=False)
    except subprocess.TimeoutExpired:
        raise RuntimeError("El comando superó 45 segundos")
    return {"exit_code": p.returncode, "stdout": p.stdout[-6000:], "stderr": p.stderr[-3000:]}


def _tool_power(args: dict[str, Any]) -> str:
    action = str(args.get("action") or "").strip()
    if action not in {"poweroff", "reboot"}: raise RuntimeError("Acción de energía no válida")
    subprocess.Popen(["systemctl", action], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return "Apagado solicitado" if action == "poweroff" else "Reinicio solicitado"


TOOLS: dict[str, Callable[[dict[str, Any]], Any]] = {
    "context.desktop": _tool_context,
    "system.info": _tool_system_info,
    "process.list": _tool_process_list,
    "package.updates": _tool_package_updates,
    "package.upgrade": _tool_package_upgrade,
    "process.kill": _tool_process_kill,
    "desktop.focus_workspace": _tool_desktop_focus,
    "desktop.move_window_to_workspace": _tool_desktop_move,
    "desktop.toggle_overview": _tool_desktop_overview,
    "desktop.close_window": _tool_desktop_close,
    "app.open": _tool_app_open,
    "file.read": _tool_file_read,
    "file.list": _tool_file_list,
    "file.search": _tool_file_search,
    "file.write": _tool_file_write,
    "file.mkdir": _tool_file_mkdir,
    "file.move": _tool_file_move,
    "file.delete": _tool_file_delete,
    "clipboard.read": _tool_clip_read,
    "clipboard.write": _tool_clip_write,
    "media.control": _tool_media,
    "audio.volume": _tool_volume,
    "service.user": _tool_service,
    "notify.send": _tool_notify,
    "screenshot.capture": _tool_screenshot,
    "terminal.run": _tool_terminal,
    "power.action": _tool_power,
}


def _format_tool_result(tool: str, value: Any) -> str:
    if tool == "package.updates" and isinstance(value, dict):
        counts = value.get("counts", {})
        total = int(counts.get("system", 0)) + int(counts.get("aur", 0)) + int(counts.get("flatpak", 0))
        lines = [f"Actualizaciones encontradas: {total} (sistema {counts.get('system', 0)}, AUR {counts.get('aur', 0)}, Flatpak {counts.get('flatpak', 0)})."]
        for label, key in (("Sistema", "system"), ("AUR", "aur"), ("Flatpak", "flatpak")):
            items = value.get(key) or []
            if items:
                lines.append(label + ":")
                lines.extend("  • " + str(x) for x in items[:30])
                if len(items) > 30:
                    lines.append(f"  … y {len(items) - 30} más")
        notes = value.get("notes") or []
        lines.extend("Nota: " + str(x) for x in notes[:3])
        return "\n".join(lines)
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, indent=2)[:7000]
    return str(value)[:7000]


def _fallback_summary(results: list[dict[str, Any]]) -> str:
    chunks: list[str] = []
    for r in results:
        label = str(r.get("label") or r.get("tool") or "Acción")
        if r.get("ok"):
            rendered = _format_tool_result(str(r.get("tool") or ""), r.get("result"))
            chunks.append(label + ("\n" + rendered if rendered else " · listo"))
        else:
            chunks.append(f"{label}\nError: {r.get('error', 'falló')}")
    return "\n\n".join(chunks) or "No había acciones para ejecutar."


def execute(plan_data: dict[str, Any], approved: bool, provider: str, model: str) -> dict[str, Any]:
    actions = plan_data.get("actions") if isinstance(plan_data.get("actions"), list) else []
    request = str(plan_data.get("request") or "")
    cfg = load_config()
    agent_cfg = cfg.get("agent", {})
    auto_safe = bool(agent_cfg.get("auto_execute_safe", True))
    allow_terminal = bool(agent_cfg.get("allow_terminal", True))
    max_actions = max(1, min(10, int(agent_cfg.get("max_actions", 6))))
    results: list[dict[str, Any]] = []

    for action in actions[:max_actions]:
        if not isinstance(action, dict): continue
        tool = str(action.get("tool") or "")
        policy = TOOL_POLICY.get(tool)
        if not policy or tool not in TOOLS:
            results.append({"ok": False, "tool": tool, "label": action.get("label", tool), "error": "Herramienta no permitida"})
            continue
        risk = policy["risk"]
        if tool == "terminal.run" and not allow_terminal:
            results.append({"ok": False, "tool": tool, "label": action.get("label", tool), "error": "La terminal está desactivada en la configuración de Mock"})
            continue
        if risk in {"confirm", "destructive"} and not approved:
            results.append({"ok": False, "tool": tool, "label": action.get("label", tool), "error": "Requiere aprobación"})
            continue
        if risk in {"read", "safe"} and not auto_safe and not approved:
            results.append({"ok": False, "tool": tool, "label": action.get("label", tool), "error": "La ejecución automática está desactivada"})
            continue
        try:
            value = TOOLS[tool](action.get("args") if isinstance(action.get("args"), dict) else {})
            results.append({"ok": True, "tool": tool, "label": action.get("label", tool), "result": value})
        except Exception as exc:
            results.append({"ok": False, "tool": tool, "label": action.get("label", tool), "error": str(exc)})

    summary = _fallback_summary(results)
    deterministic_output = any(r.get("tool") in {"package.updates"} for r in results)
    if provider != "mock" and request and not deterministic_output:
        payload = json.dumps(results, ensure_ascii=False)
        sys_prompt = (
            "Eres Mock. Las acciones descritas abajo YA fueron ejecutadas por tu Agent Runtime en el PC del usuario. "
            "Resume en español, de forma breve y concreta, los resultados reales. No digas que no tienes acceso al PC o a la terminal. "
            "No inventes nada y si algo falló, dilo."
        )
        try:
            summary = _model_complete(f"Solicitud original: {request}\nResultados: {payload}", sys_prompt, provider, model).strip() or summary
        except Exception:
            pass

    if request and summary:
        hist = history_load()
        hist.extend([{"role": "user", "content": request}, {"role": "assistant", "content": summary}])
        history_save(hist, int(cfg.get("max_history_messages", 16)))

    return {"ok": all(r.get("ok") for r in results) if results else True, "request": request, "results": results, "summary": summary}


def status() -> dict[str, Any]:
    deps = {x: bool(shutil.which(x)) for x in [
        "wl-copy", "wl-paste", "xclip", "xsel", "playerctl", "wpctl", "pactl",
        "notify-send", "grim", "spectacle", "gnome-screenshot", "scrot", "bash"
    ]}
    return {"ok": True, "tools": TOOL_POLICY, "dependencies": deps, "desktop_adapter": desktop_status()}


def main() -> int:
    ap = argparse.ArgumentParser(description="Mock Agent Runtime")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--provider", default="mock")
    p.add_argument("--model", default="")
    p.add_argument("--stdin", action="store_true")
    e = sub.add_parser("execute")
    e.add_argument("--provider", default="mock")
    e.add_argument("--model", default="")
    e.add_argument("--approved", action="store_true")
    e.add_argument("--stdin", action="store_true")
    sub.add_parser("status")
    args = ap.parse_args()

    try:
        if args.cmd == "status":
            print(_json(status())); return 0
        if args.cmd == "plan":
            req = sys.stdin.read().strip() if args.stdin else ""
            if not req: raise RuntimeError("Solicitud vacía")
            print(_json(plan(req, args.provider, args.model))); return 0
        if args.cmd == "execute":
            raw = sys.stdin.read().strip() if args.stdin else ""
            if not raw: raise RuntimeError("Plan vacío")
            data = json.loads(raw)
            print(_json(execute(data, args.approved, args.provider, args.model))); return 0
    except Exception as exc:
        print(_json({"ok": False, "error": str(exc)}))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
