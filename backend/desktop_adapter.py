#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from typing import Any


def _run(cmd: list[str], timeout: float = 1.8) -> tuple[int, str, str]:
    try:
        p = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except (OSError, subprocess.SubprocessError) as exc:
        return 1, "", str(exc)


def _json_cmd(cmd: list[str], timeout: float = 1.8) -> Any:
    code, out, _ = _run(cmd, timeout)
    if code != 0 or not out:
        return None
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return None


def _which(name: str) -> bool:
    return shutil.which(name) is not None


def _desktop_tokens() -> set[str]:
    raw = ":".join(
        x for x in (
            os.environ.get("XDG_CURRENT_DESKTOP", ""),
            os.environ.get("DESKTOP_SESSION", ""),
            os.environ.get("XDG_SESSION_DESKTOP", ""),
        ) if x
    ).lower()
    return {x for x in re.split(r"[:;,_\- ]+", raw) if x}


def detect_backend() -> str:
    tokens = _desktop_tokens()
    if os.environ.get("NIRI_SOCKET") or "niri" in tokens:
        return "niri"
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") or "hyprland" in tokens:
        return "hyprland"
    if os.environ.get("SWAYSOCK") or "sway" in tokens:
        return "sway"
    if os.environ.get("I3SOCK") or "i3" in tokens:
        return "i3"
    if "plasma" in tokens or "kde" in tokens:
        return "kde"
    if "gnome" in tokens or "ubuntu" in tokens:
        return "gnome"
    if "cosmic" in tokens:
        return "cosmic"
    if os.environ.get("XDG_SESSION_TYPE", "").lower() == "x11" or os.environ.get("DISPLAY"):
        return "x11"
    return "generic"


def _empty_context(backend: str) -> dict[str, Any]:
    return {
        "available": False,
        "backend": backend,
        "app_id": "",
        "title": "",
        "workspace": "",
        "workspace_id": None,
        "output": "",
        "window_id": "",
    }


def _niri_context() -> dict[str, Any]:
    out = _empty_context("niri")
    if not _which("niri") or not os.environ.get("NIRI_SOCKET"):
        return out
    window = _json_cmd(["niri", "msg", "--json", "focused-window"]) or {}
    workspace = _json_cmd(["niri", "msg", "--json", "focused-workspace"]) or {}
    output = _json_cmd(["niri", "msg", "--json", "focused-output"]) or {}
    if isinstance(window, dict):
        out["app_id"] = str(window.get("app_id") or window.get("app-id") or "")
        out["title"] = str(window.get("title") or "")
        if window.get("workspace_id") is not None:
            out["workspace_id"] = window.get("workspace_id")
        if window.get("id") is not None:
            out["window_id"] = str(window.get("id"))
    if isinstance(workspace, dict):
        out["workspace_id"] = workspace.get("id", out["workspace_id"])
        label = workspace.get("name") or workspace.get("idx") or workspace.get("index") or workspace.get("id")
        out["workspace"] = str(label or "")
    if isinstance(output, dict):
        out["output"] = str(output.get("name") or "")
    out["available"] = any(out[k] for k in ("app_id", "title", "workspace", "output"))
    return out


def _hypr_context() -> dict[str, Any]:
    out = _empty_context("hyprland")
    if not _which("hyprctl"):
        return out
    window = _json_cmd(["hyprctl", "-j", "activewindow"]) or {}
    workspace = _json_cmd(["hyprctl", "-j", "activeworkspace"]) or {}
    monitors = _json_cmd(["hyprctl", "-j", "monitors"]) or []
    if isinstance(window, dict):
        out["app_id"] = str(window.get("class") or window.get("initialClass") or "")
        out["title"] = str(window.get("title") or "")
        out["window_id"] = str(window.get("address") or "")
        ws = window.get("workspace")
        if isinstance(ws, dict):
            out["workspace_id"] = ws.get("id")
            out["workspace"] = str(ws.get("name") or ws.get("id") or "")
    if isinstance(workspace, dict):
        out["workspace_id"] = workspace.get("id", out["workspace_id"])
        out["workspace"] = str(workspace.get("name") or workspace.get("id") or out["workspace"])
    if isinstance(monitors, list):
        focused = next((x for x in monitors if isinstance(x, dict) and x.get("focused")), None)
        if focused:
            out["output"] = str(focused.get("name") or "")
    out["available"] = any(out[k] for k in ("app_id", "title", "workspace", "output"))
    return out


def _find_focused(node: Any) -> dict[str, Any] | None:
    if isinstance(node, dict):
        if node.get("focused"):
            return node
        for key in ("nodes", "floating_nodes"):
            for child in node.get(key) or []:
                found = _find_focused(child)
                if found:
                    return found
    return None


def _sway_i3_context(backend: str) -> dict[str, Any]:
    out = _empty_context(backend)
    exe = "swaymsg" if backend == "sway" else "i3-msg"
    if not _which(exe):
        return out
    tree = _json_cmd([exe, "-t", "get_tree", "-r"]) or {}
    node = _find_focused(tree)
    if node:
        props = node.get("window_properties") if isinstance(node.get("window_properties"), dict) else {}
        out["app_id"] = str(node.get("app_id") or props.get("class") or props.get("instance") or "")
        out["title"] = str(node.get("name") or "")
        if node.get("id") is not None:
            out["window_id"] = str(node.get("id"))
    workspaces = _json_cmd([exe, "-t", "get_workspaces", "-r"]) or []
    if isinstance(workspaces, list):
        ws = next((x for x in workspaces if isinstance(x, dict) and x.get("focused")), None)
        if ws:
            out["workspace_id"] = ws.get("num") if ws.get("num") is not None else ws.get("id")
            out["workspace"] = str(ws.get("name") or out["workspace_id"] or "")
            out["output"] = str(ws.get("output") or "")
    out["available"] = any(out[k] for k in ("app_id", "title", "workspace", "output"))
    return out


def _x11_context(backend: str = "x11") -> dict[str, Any]:
    out = _empty_context(backend)
    if _which("xdotool"):
        code, wid, _ = _run(["xdotool", "getactivewindow"])
        if code == 0 and wid:
            out["window_id"] = wid
            _, title, _ = _run(["xdotool", "getwindowname", wid])
            _, klass, _ = _run(["xdotool", "getwindowclassname", wid])
            out["title"] = title
            out["app_id"] = klass
        code, ws, _ = _run(["xdotool", "get_desktop"])
        if code == 0 and ws.isdigit():
            out["workspace_id"] = int(ws) + 1
            out["workspace"] = str(int(ws) + 1)
    if backend == "kde":
        for qdbus in ("qdbus6", "qdbus"):
            if not _which(qdbus):
                continue
            code, desk, _ = _run([qdbus, "org.kde.KWin", "/KWin", "currentDesktop"])
            if code == 0 and desk:
                out["workspace"] = desk
                try:
                    out["workspace_id"] = int(desk)
                except ValueError:
                    pass
            break
    out["available"] = any(out[k] for k in ("app_id", "title", "workspace", "output"))
    return out


def desktop_context() -> dict[str, Any]:
    backend = detect_backend()
    if backend == "niri":
        core = _niri_context()
    elif backend == "hyprland":
        core = _hypr_context()
    elif backend in {"sway", "i3"}:
        core = _sway_i3_context(backend)
    elif backend == "kde":
        core = _x11_context("kde")
    elif backend == "x11":
        core = _x11_context("x11")
    else:
        core = _empty_context(backend)

    core["session_type"] = os.environ.get("XDG_SESSION_TYPE", "")
    core["desktop"] = os.environ.get("XDG_CURRENT_DESKTOP", "")
    core["capabilities"] = capabilities(backend)
    return core


def capabilities(backend: str | None = None) -> dict[str, bool]:
    backend = backend or detect_backend()
    caps = {
        "focus_workspace": False,
        "move_window_to_workspace": False,
        "toggle_overview": False,
        "close_window": False,
        "focused_window": False,
        "focused_output": False,
    }
    if backend == "niri" and _which("niri"):
        caps.update({k: True for k in caps})
    elif backend == "hyprland" and _which("hyprctl"):
        caps.update({
            "focus_workspace": True,
            "move_window_to_workspace": True,
            "close_window": True,
            "focused_window": True,
            "focused_output": True,
        })
    elif backend in {"sway", "i3"} and _which("swaymsg" if backend == "sway" else "i3-msg"):
        caps.update({
            "focus_workspace": True,
            "move_window_to_workspace": True,
            "close_window": True,
            "focused_window": True,
            "focused_output": True,
        })
    elif backend == "kde":
        caps["focused_window"] = _which("xdotool") or _which("kdotool")
        caps["close_window"] = _which("kdotool") or (_which("wmctrl") and os.environ.get("XDG_SESSION_TYPE") == "x11")
        if os.environ.get("XDG_SESSION_TYPE") == "x11" and _which("wmctrl"):
            caps["focus_workspace"] = True
            caps["move_window_to_workspace"] = True
    elif backend == "x11":
        caps["focused_window"] = _which("xdotool")
        caps["close_window"] = _which("wmctrl") or _which("xdotool")
        caps["focus_workspace"] = _which("wmctrl")
        caps["move_window_to_workspace"] = _which("wmctrl")
    return caps


def _workspace_ref(raw: Any) -> str:
    ref = str(raw or "").strip()
    if not ref or not re.fullmatch(r"[A-Za-z0-9_.:+\-]{1,64}", ref):
        raise RuntimeError("Referencia de workspace no válida")
    return ref


def _workspace_index(ref: str) -> str:
    if not ref.isdigit() or int(ref) <= 0:
        raise RuntimeError("En X11 el workspace debe ser numérico")
    return str(int(ref) - 1)


def _check(code: int, err: str, fallback: str) -> None:
    if code != 0:
        raise RuntimeError(err or fallback)


def focus_workspace(workspace: Any) -> str:
    ref = _workspace_ref(workspace)
    backend = detect_backend()
    if backend == "niri":
        code, _, err = _run(["niri", "msg", "action", "focus-workspace", ref])
        _check(code, err, "Niri rechazó el cambio de workspace")
    elif backend == "hyprland":
        code, _, err = _run(["hyprctl", "dispatch", "workspace", ref])
        _check(code, err, "Hyprland rechazó el cambio de workspace")
    elif backend in {"sway", "i3"}:
        exe = "swaymsg" if backend == "sway" else "i3-msg"
        cmd = [exe, "workspace", "number", ref] if ref.isdigit() else [exe, "workspace", ref]
        code, _, err = _run(cmd)
        _check(code, err, f"{backend} rechazó el cambio de workspace")
    elif backend in {"x11", "kde"} and os.environ.get("XDG_SESSION_TYPE", "").lower() == "x11" and _which("wmctrl"):
        code, _, err = _run(["wmctrl", "-s", _workspace_index(ref)])
        _check(code, err, "wmctrl no pudo cambiar de workspace")
    else:
        raise RuntimeError(f"Cambiar workspace no está disponible en {backend}")
    return f"Workspace {ref} enfocado ({backend})"


def move_window_to_workspace(workspace: Any, focus: bool = True) -> str:
    ref = _workspace_ref(workspace)
    backend = detect_backend()
    if backend == "niri":
        flag = "true" if focus else "false"
        code, _, err = _run(["niri", "msg", "action", "move-window-to-workspace", "--focus", flag, ref])
        if code != 0:
            code, _, err = _run(["niri", "msg", "action", "move-window-to-workspace", f"focus={flag}", ref])
        _check(code, err, "Niri no pudo mover la ventana")
    elif backend == "hyprland":
        action = "movetoworkspace" if focus else "movetoworkspacesilent"
        code, _, err = _run(["hyprctl", "dispatch", action, ref])
        _check(code, err, "Hyprland no pudo mover la ventana")
    elif backend in {"sway", "i3"}:
        exe = "swaymsg" if backend == "sway" else "i3-msg"
        cmd = [exe, "move", "container", "to", "workspace", "number", ref] if ref.isdigit() else [exe, "move", "container", "to", "workspace", ref]
        code, _, err = _run(cmd)
        _check(code, err, f"{backend} no pudo mover la ventana")
        if focus:
            focus_workspace(ref)
    elif backend in {"x11", "kde"} and os.environ.get("XDG_SESSION_TYPE", "").lower() == "x11" and _which("wmctrl"):
        code, _, err = _run(["wmctrl", "-r", ":ACTIVE:", "-t", _workspace_index(ref)])
        _check(code, err, "wmctrl no pudo mover la ventana")
        if focus:
            focus_workspace(ref)
    else:
        raise RuntimeError(f"Mover ventanas entre workspaces no está disponible en {backend}")
    return f"Ventana movida al workspace {ref} ({backend})"


def close_window() -> str:
    backend = detect_backend()
    if backend == "niri":
        code, _, err = _run(["niri", "msg", "action", "close-window"])
    elif backend == "hyprland":
        code, _, err = _run(["hyprctl", "dispatch", "killactive"])
    elif backend in {"sway", "i3"}:
        code, _, err = _run(["swaymsg" if backend == "sway" else "i3-msg", "kill"])
    elif backend == "kde" and _which("kdotool"):
        code, _, err = _run(["bash", "-lc", "kdotool getactivewindow windowclose"])
    elif _which("wmctrl"):
        code, _, err = _run(["wmctrl", "-c", ":ACTIVE:"])
    elif _which("xdotool"):
        code, _, err = _run(["bash", "-lc", "xdotool getactivewindow windowclose"])
    else:
        raise RuntimeError(f"Cerrar la ventana enfocada no está disponible en {backend}")
    _check(code, err, "No pude cerrar la ventana enfocada")
    return f"Ventana cerrada ({backend})"


def toggle_overview() -> str:
    backend = detect_backend()
    if backend == "niri":
        code, _, err = _run(["niri", "msg", "action", "toggle-overview"])
        _check(code, err, "Niri rechazó Overview")
        return "Overview alternado (niri)"
    raise RuntimeError(f"Overview genérico no está disponible en {backend}")


def perform(action: str, args: dict[str, Any] | None = None) -> str:
    args = args or {}
    if action == "focus_workspace":
        return focus_workspace(args.get("workspace"))
    if action == "move_window_to_workspace":
        return move_window_to_workspace(args.get("workspace"), bool(args.get("focus", True)))
    if action == "close_window":
        return close_window()
    if action == "toggle_overview":
        return toggle_overview()
    raise RuntimeError(f"Acción de escritorio desconocida: {action}")


def status() -> dict[str, Any]:
    backend = detect_backend()
    return {
        "ok": True,
        "backend": backend,
        "session_type": os.environ.get("XDG_SESSION_TYPE", ""),
        "desktop": os.environ.get("XDG_CURRENT_DESKTOP", ""),
        "capabilities": capabilities(backend),
        "dependencies": {
            name: _which(name)
            for name in ("niri", "hyprctl", "swaymsg", "i3-msg", "wmctrl", "xdotool", "kdotool", "qdbus6")
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Mock Desktop Adapter")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    sub.add_parser("context")
    sub.add_parser("output")
    act = sub.add_parser("action")
    act.add_argument("name", choices=["focus_workspace", "move_window_to_workspace", "close_window", "toggle_overview"])
    act.add_argument("--args", default="{}")
    ns = ap.parse_args()
    try:
        if ns.cmd == "status":
            print(json.dumps(status(), ensure_ascii=False))
        elif ns.cmd == "context":
            print(json.dumps(desktop_context(), ensure_ascii=False))
        elif ns.cmd == "output":
            print(desktop_context().get("output", ""))
        else:
            args = json.loads(ns.args)
            if not isinstance(args, dict):
                raise RuntimeError("--args debe ser un objeto JSON")
            print(json.dumps({"ok": True, "result": perform(ns.name, args)}, ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
