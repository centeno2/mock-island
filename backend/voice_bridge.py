#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from ai_bridge import DEFAULT_CONFIG, load_config

HOME = Path.home()
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "mock-island"
DATA_DIR = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "mock-island"
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/mock-island-{os.getuid()}")) / "mock-island"
VOICE_STATE = STATE_DIR / "voice-recording.json"
AUDIO_FILE = RUNTIME_DIR / "voice-input.wav"
TRANSCRIPT_PREFIX = RUNTIME_DIR / "voice-transcript"
TTS_FILE = RUNTIME_DIR / "voice-reply.wav"
VENV_PY = DATA_DIR / "voice-venv/bin/python"
VOICE_DIR = DATA_DIR / "voices"
LOCAL_WHISPER = DATA_DIR / "whisper.cpp/build/bin/whisper-cli"


def emit(**data: Any) -> None:
    print(json.dumps(data, ensure_ascii=False), flush=True)


def ensure_dirs() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    VOICE_DIR.mkdir(parents=True, exist_ok=True)


def _cfg() -> dict[str, Any]:
    return load_config().get("voice", DEFAULT_CONFIG["voice"])


def _whisper_bin() -> str:
    system = shutil.which("whisper-cli")
    if system:
        return system
    if LOCAL_WHISPER.is_file() and os.access(LOCAL_WHISPER, os.X_OK):
        return str(LOCAL_WHISPER)
    return ""


def _model_path() -> Path:
    raw = os.environ.get("MOCK_WHISPER_MODEL") or str(_cfg().get("whisper_model") or "")
    return Path(os.path.expandvars(os.path.expanduser(raw)))


def _piper_python() -> str:
    if VENV_PY.exists():
        return str(VENV_PY)
    try:
        p = subprocess.run([sys.executable, "-c", "import piper"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
        if p.returncode == 0:
            return sys.executable
    except Exception:
        pass
    return ""


def _recording_alive() -> bool:
    if not VOICE_STATE.exists():
        return False
    state = _read_state()
    pid = int(state.get("pid") or 0)
    if not pid:
        VOICE_STATE.unlink(missing_ok=True)
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        # A timeout may have ended the recorder while the UI was closed.
        # Keep the audio, but do not pretend the microphone is still live.
        VOICE_STATE.unlink(missing_ok=True)
        return False


def status() -> dict[str, Any]:
    cfg = _cfg()
    model = _model_path()
    whisper = _whisper_bin()
    return {
        "ok": True,
        "recording": _recording_alive(),
        "pw_record": bool(shutil.which("pw-record")),
        "pw_play": bool(shutil.which("pw-play")),
        "whisper_cli": bool(whisper),
        "whisper_path": whisper,
        "whisper_model": str(model),
        "whisper_model_ready": model.is_file(),
        "piper_ready": bool(_piper_python()),
        "language": str(cfg.get("language") or "es"),
        "piper_voice": str(cfg.get("piper_voice") or "es_ES-davefx-medium"),
        "tts_enabled": bool(cfg.get("tts_enabled", False)),
        "auto_send": bool(cfg.get("auto_send", True)),
        "setup_hint": "mock-island voice-setup",
    }


def _read_state() -> dict[str, Any]:
    try:
        return json.loads(VOICE_STATE.read_text())
    except Exception:
        return {}


def record_start() -> dict[str, Any]:
    ensure_dirs()
    if VOICE_STATE.exists():
        state = _read_state()
        pid = int(state.get("pid") or 0)
        if pid:
            try:
                os.kill(pid, 0)
                return {"ok": True, "recording": True, "message": "Mock ya está escuchando"}
            except OSError:
                pass
        VOICE_STATE.unlink(missing_ok=True)
    rec = shutil.which("pw-record")
    if not rec:
        raise RuntimeError("Falta pw-record (PipeWire)")
    AUDIO_FILE.unlink(missing_ok=True)
    # timeout prevents a forgotten recording from living forever.
    record_argv = [rec, "--rate", "16000", "--channels", "1", "--channel-map", "mono", "--format", "s16", str(AUDIO_FILE)]
    timeout_bin = shutil.which("timeout")
    argv = [timeout_bin, "30s", *record_argv] if timeout_bin else record_argv
    proc = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    VOICE_STATE.write_text(json.dumps({"pid": proc.pid, "started": time.time(), "file": str(AUDIO_FILE)}))
    return {"ok": True, "recording": True, "message": "Escuchando…"}


def _stop_recorder() -> None:
    state = _read_state()
    pid = int(state.get("pid") or 0)
    if pid:
        try:
            os.killpg(pid, signal.SIGINT)
        except ProcessLookupError:
            pass
        except PermissionError:
            try: os.kill(pid, signal.SIGINT)
            except OSError: pass
        for _ in range(12):
            try:
                os.kill(pid, 0)
            except OSError:
                break
            time.sleep(0.08)
        else:
            try: os.killpg(pid, signal.SIGTERM)
            except OSError: pass
    VOICE_STATE.unlink(missing_ok=True)
    time.sleep(0.12)


def transcribe_audio(path: Path) -> str:
    whisper = _whisper_bin()
    model = _model_path()
    if not whisper:
        raise RuntimeError("Falta whisper-cli. Instala whisper-cpp o ejecuta mock-island voice-setup")
    if not model.is_file():
        raise RuntimeError(f"Falta el modelo Whisper: {model}. Ejecuta mock-island voice-setup")
    if not path.is_file() or path.stat().st_size < 1200:
        raise RuntimeError("No se grabó audio suficiente")
    for suffix in (".txt", ".json", ".srt", ".vtt"):
        Path(str(TRANSCRIPT_PREFIX) + suffix).unlink(missing_ok=True)
    lang = str(_cfg().get("language") or "es")
    cmd = [
        whisper, "--model", str(model), "--file", str(path), "--language", lang,
        "--no-timestamps", "--output-txt", "--output-file", str(TRANSCRIPT_PREFIX), "--no-prints",
    ]
    p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120, check=False)
    txt = Path(str(TRANSCRIPT_PREFIX) + ".txt")
    text = txt.read_text(errors="replace").strip() if txt.exists() else p.stdout.strip()
    if p.returncode != 0 and not text:
        raise RuntimeError(p.stderr.strip()[-1000:] or "Whisper no pudo transcribir")
    if not text:
        raise RuntimeError("No detecté voz")
    return " ".join(text.split())


def record_stop() -> dict[str, Any]:
    ensure_dirs()
    if not VOICE_STATE.exists():
        raise RuntimeError("Mock no estaba grabando")
    _stop_recorder()
    text = transcribe_audio(AUDIO_FILE)
    return {"ok": True, "recording": False, "text": text, "message": "Voz transcrita"}


def speak(text: str) -> dict[str, Any]:
    ensure_dirs()
    text = " ".join(text.strip().split())
    if not text:
        raise RuntimeError("Texto vacío")
    py = _piper_python()
    if not py:
        raise RuntimeError("Piper TTS no está preparado. Ejecuta mock-island voice-setup")
    if not shutil.which("pw-play"):
        raise RuntimeError("Falta pw-play (PipeWire)")
    cfg = _cfg()
    voice = str(cfg.get("piper_voice") or "es_ES-davefx-medium")
    TTS_FILE.unlink(missing_ok=True)
    cmd = [py, "-m", "piper", "--data-dir", str(VOICE_DIR), "-m", voice, "-f", str(TTS_FILE), "--", text[:1800]]
    p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120, check=False)
    if p.returncode != 0 or not TTS_FILE.exists():
        raise RuntimeError(p.stderr.strip()[-1000:] or "Piper no pudo sintetizar")
    play = subprocess.run(["pw-play", str(TTS_FILE)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=180, check=False)
    if play.returncode != 0:
        raise RuntimeError((play.stderr or "").strip()[-1000:] or "pw-play no pudo reproducir la respuesta")
    return {"ok": True, "speaking": False, "message": "Respuesta hablada"}


def main() -> int:
    ensure_dirs()
    ap = argparse.ArgumentParser(description="Mock voice bridge")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    sub.add_parser("record-start")
    sub.add_parser("record-stop")
    sp = sub.add_parser("speak")
    sp.add_argument("--stdin", action="store_true")
    tr = sub.add_parser("transcribe")
    tr.add_argument("path")
    args = ap.parse_args()
    try:
        if args.cmd == "status": data = status()
        elif args.cmd == "record-start": data = record_start()
        elif args.cmd == "record-stop": data = record_stop()
        elif args.cmd == "speak": data = speak(sys.stdin.read() if args.stdin else "")
        elif args.cmd == "transcribe": data = {"ok": True, "text": transcribe_audio(Path(args.path).expanduser().resolve())}
        else: data = {"ok": False, "error": "Comando desconocido"}
        emit(**data)
        return 0 if data.get("ok") else 1
    except Exception as exc:
        emit(ok=False, error=str(exc), setup_hint="mock-island voice-setup")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
