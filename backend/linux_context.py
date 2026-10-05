#!/usr/bin/env python3
from __future__ import annotations

import json
import mimetypes
import os
import shutil
import subprocess
import time
import urllib.parse
from pathlib import Path
from typing import Any

from desktop_adapter import desktop_context as adapter_desktop_context


def _run(cmd: list[str], timeout: float = 1.5, input_text: str | None = None) -> tuple[int, str]:
    try:
        proc = subprocess.run(
            cmd,
            input=input_text,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return 1, ""


def _clipboard_preview(max_chars: int = 2400) -> dict[str, Any]:
    out = {"available": False, "text": "", "truncated": False, "backend": ""}
    commands: list[tuple[str, list[str]]] = []
    if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-paste"):
        commands.append(("wayland", ["wl-paste", "-n"]))
    if os.environ.get("DISPLAY") and shutil.which("xclip"):
        commands.append(("xclip", ["xclip", "-selection", "clipboard", "-o"]))
    if os.environ.get("DISPLAY") and shutil.which("xsel"):
        commands.append(("xsel", ["xsel", "--clipboard", "--output"]))
    for backend, cmd in commands:
        code, text = _run(cmd, timeout=1.0)
        if code == 0 and text:
            if len(text) > max_chars:
                text = text[:max_chars]
                out["truncated"] = True
            out.update({"available": True, "text": text, "backend": backend})
            return out
    return out


def _media_context() -> dict[str, Any]:
    out = {"available": False, "status": "", "player": "", "artist": "", "title": ""}
    if not shutil.which("playerctl"):
        return out
    code, status = _run(["playerctl", "status"], timeout=0.8)
    if code != 0:
        return out
    _, meta = _run([
        "playerctl",
        "metadata",
        "--format",
        "{{playerName}}\t{{artist}}\t{{title}}",
    ], timeout=0.8)
    parts = meta.split("\t", 2) if meta else []
    out.update({
        "available": True,
        "status": status,
        "player": parts[0] if len(parts) > 0 else "",
        "artist": parts[1] if len(parts) > 1 else "",
        "title": parts[2] if len(parts) > 2 else "",
    })
    return out


def desktop_context(include_clipboard: bool = False) -> dict[str, Any]:
    desktop = adapter_desktop_context()
    payload: dict[str, Any] = {
        "timestamp": int(time.time()),
        "session": {
            "desktop": os.environ.get("XDG_CURRENT_DESKTOP", ""),
            "session_type": os.environ.get("XDG_SESSION_TYPE", ""),
            "backend": desktop.get("backend", "generic"),
        },
        "desktop": desktop,
        "media": _media_context(),
    }
    # Compatibility for older QML/config consumers while v10 transitions to desktop.*
    payload["niri"] = desktop if desktop.get("backend") == "niri" else {
        "available": False, "app_id": "", "title": "", "workspace": "", "workspace_id": None, "output": ""
    }
    payload["clipboard"] = _clipboard_preview() if include_clipboard else {
        "available": False,
        "text": "",
        "truncated": False,
        "backend": "",
    }
    return payload


def _path_from_input(raw: str) -> Path:
    raw = raw.strip()
    if raw.startswith("file://"):
        parsed = urllib.parse.urlparse(raw)
        raw = urllib.parse.unquote(parsed.path)
    return Path(os.path.expanduser(raw)).resolve()


def file_context(raw_path: str, max_chars: int = 14000) -> dict[str, Any]:
    path = _path_from_input(raw_path)
    result: dict[str, Any] = {
        "ok": False,
        "path": str(path),
        "name": path.name,
        "mime": mimetypes.guess_type(path.name)[0] or "application/octet-stream",
        "text": "",
        "truncated": False,
        "error": "",
    }
    if not path.exists():
        result["error"] = "El archivo no existe"
        return result
    if not path.is_file():
        result["error"] = "Solo se pueden adjuntar archivos"
        return result
    try:
        size = path.stat().st_size
        if size > 8 * 1024 * 1024:
            result["error"] = "Archivo demasiado grande para contexto rápido (máx. 8 MiB)"
            return result
        data = path.read_bytes()[: max_chars * 4 + 4096]
    except OSError as exc:
        result["error"] = str(exc)
        return result

    if b"\x00" in data[:4096]:
        result["error"] = "El archivo parece binario; Mock no lo adjunta como texto"
        return result

    text = data.decode("utf-8", errors="replace")
    if len(text) > max_chars:
        text = text[:max_chars]
        result["truncated"] = True
    result["ok"] = True
    result["text"] = text
    return result
