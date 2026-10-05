#!/usr/bin/env python3
from __future__ import annotations

import argparse
import getpass
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import unicodedata
from pathlib import Path
from typing import Dict, Iterable, List

from linux_context import desktop_context, file_context

APP = "mock-island"
HOME = Path.home()
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / APP
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / APP
CONFIG_FILE = CONFIG_DIR / "config.json"
SECRETS_FILE = CONFIG_DIR / "secrets.env"
HISTORY_FILE = STATE_DIR / "history.json"
DMS_COLORS = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "DankMaterialShell/dms-colors.json"

DEFAULT_CONFIG = {
    "provider": "mock",
    "system_prompt": (
        "Eres Mock, un compañero técnico integrado al escritorio Linux. "
        "Responde en español salvo que el usuario pida otro idioma. "
        "Prioriza soluciones prácticas y explicaciones directas. "
        "Mock Island incluye un Agent Runtime separado que sí puede inspeccionar y actuar sobre el PC mediante herramientas controladas; "
        "no afirmes de forma general que Mock carece de acceso al equipo o a la terminal. "
        "Si recibes bloques de contexto del escritorio, úsalos solo como contexto explícitamente adjuntado por el usuario."
    ),
    "max_history_messages": 16,
    "temperature": 0.7,
    "max_tokens": 4096,
    "agent": {
        "enabled": True,
        "auto_execute_safe": True,
        "max_actions": 6,
        "allow_terminal": True
    },
    "voice": {
        "tts_enabled": False,
        "auto_send": True,
        "language": "es",
        "whisper_model": str(Path.home() / ".local/share/mock-island/models/ggml-base.bin"),
        "piper_voice": "es_ES-davefx-medium"
    },
    "providers": {
        "mock": {"base_url": "", "model": "mock-1"},
        "ollama": {"base_url": "http://127.0.0.1:11434", "model": ""},
        "lmstudio": {"base_url": "http://127.0.0.1:1234/v1", "model": ""},
        "openai": {"base_url": "https://api.openai.com/v1", "model": ""},
        "openrouter": {"base_url": "https://openrouter.ai/api/v1", "model": ""},
        "anthropic": {"base_url": "https://api.anthropic.com/v1", "model": ""},
        "gemini": {"base_url": "https://generativelanguage.googleapis.com/v1beta", "model": ""},
        "nvidia": {"base_url": "https://integrate.api.nvidia.com/v1", "model": ""},
        "custom": {"base_url": "http://127.0.0.1:8000/v1", "model": ""},
    },
}

SECRET_ENV = {
    "openai": "OPENAI_API_KEY",
    "openrouter": "OPENROUTER_API_KEY",
    "anthropic": "ANTHROPIC_API_KEY",
    "gemini": "GEMINI_API_KEY",
    "nvidia": "NVIDIA_API_KEY",
    "custom": "CUSTOM_API_KEY",
}

PROVIDER_META = {
    "mock": {"local": True, "requires_key": False, "supports_key": False, "label": "Mock"},
    "ollama": {"local": True, "requires_key": False, "supports_key": False, "label": "Ollama"},
    "lmstudio": {"local": True, "requires_key": False, "supports_key": False, "label": "LM Studio"},
    "openai": {"local": False, "requires_key": True, "supports_key": True, "label": "OpenAI"},
    "openrouter": {"local": False, "requires_key": True, "supports_key": True, "label": "OpenRouter"},
    "anthropic": {"local": False, "requires_key": True, "supports_key": True, "label": "Anthropic"},
    "gemini": {"local": False, "requires_key": True, "supports_key": True, "label": "Gemini"},
    "nvidia": {"local": False, "requires_key": True, "supports_key": True, "label": "NVIDIA NIM"},
    "custom": {"local": True, "requires_key": False, "supports_key": True, "label": "Custom / OpenAI"},
}


def ensure_dirs() -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG_FILE.exists():
        CONFIG_FILE.write_text(json.dumps(DEFAULT_CONFIG, indent=2, ensure_ascii=False) + "\n")
    if not SECRETS_FILE.exists():
        SECRETS_FILE.write_text("# Mock Island secrets\n")
        SECRETS_FILE.chmod(0o600)


def deep_merge(base: dict, extra: dict) -> dict:
    out = dict(base)
    for k, v in extra.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def load_config() -> dict:
    ensure_dirs()
    try:
        user = json.loads(CONFIG_FILE.read_text())
    except Exception:
        user = {}
    return deep_merge(DEFAULT_CONFIG, user)


def save_config(cfg: dict) -> None:
    ensure_dirs()
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")


def _secret_service_lookup(provider: str) -> str:
    if not shutil.which("secret-tool"):
        return ""
    try:
        p = subprocess.run(
            ["secret-tool", "lookup", "service", APP, "provider", provider],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=4, check=False,
        )
        return p.stdout.strip() if p.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def _secret_service_store(provider: str, value: str) -> bool:
    if not shutil.which("secret-tool"):
        return False
    try:
        p = subprocess.run(
            ["secret-tool", "store", f"--label=Mock Island · {provider}", "service", APP, "provider", provider],
            input=value, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, text=True, timeout=20, check=False,
        )
        return p.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def _secret_service_clear(provider: str) -> None:
    if not shutil.which("secret-tool"):
        return
    try:
        subprocess.run(
            ["secret-tool", "clear", "service", APP, "provider", provider],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=6, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def _secret_entries() -> Dict[str, str]:
    ensure_dirs()
    entries: Dict[str, str] = {}
    try:
        for raw in SECRETS_FILE.read_text().splitlines():
            line = raw.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                entries[k.strip()] = v.strip()
    except OSError:
        pass
    return entries


def _write_secret_entries(entries: Dict[str, str]) -> None:
    content = "# Mock Island secrets · fallback when Secret Service is unavailable\n"
    if entries:
        content += "\n".join(f"{k}={v}" for k, v in sorted(entries.items())) + "\n"
    SECRETS_FILE.write_text(content)
    SECRETS_FILE.chmod(0o600)


def load_secrets() -> Dict[str, str]:
    ensure_dirs()
    env = dict(os.environ)
    legacy = _secret_entries()
    for provider, key in SECRET_ENV.items():
        if env.get(key):
            continue
        secure = _secret_service_lookup(provider)
        if secure:
            env[key] = secure
        elif legacy.get(key):
            env[key] = legacy[key]
    return env


def set_secret(provider: str, value: str) -> None:
    ensure_dirs()
    key = SECRET_ENV.get(provider)
    if not key:
        raise SystemExit(f"{provider} no usa clave API administrada por Mock")
    entries = _secret_entries()
    if _secret_service_store(provider, value):
        # Remove an older plaintext fallback once the secure store succeeds.
        entries.pop(key, None)
        _write_secret_entries(entries)
        return
    entries[key] = value
    _write_secret_entries(entries)


def clear_secret(provider: str) -> None:
    key = SECRET_ENV.get(provider)
    if not key:
        return
    _secret_service_clear(provider)
    entries = _secret_entries()
    entries.pop(key, None)
    _write_secret_entries(entries)


def emit(kind: str, **kwargs) -> None:
    try:
        print(json.dumps({"type": kind, **kwargs}, ensure_ascii=False), flush=True)
    except BrokenPipeError:
        raise SystemExit(0)


def _looks_like_token_soup(text: str) -> bool:
    """Detect the current Nemotron Ultra corruption pattern without flagging normal Spanish/English text."""
    if len(text) < 220:
        return False
    scripts = set()
    letters = 0
    for ch in text[-1400:]:
        if not ch.isalpha():
            continue
        letters += 1
        name = unicodedata.name(ch, "")
        if "LATIN" in name:
            scripts.add("latin")
        elif "CYRILLIC" in name:
            scripts.add("cyrillic")
        elif "ARABIC" in name:
            scripts.add("arabic")
        elif "HEBREW" in name:
            scripts.add("hebrew")
        elif "HIRAGANA" in name or "KATAKANA" in name:
            scripts.add("japanese")
        elif "HANGUL" in name:
            scripts.add("hangul")
        elif "CJK" in name or "IDEOGRAPH" in name:
            scripts.add("cjk")
        elif "DEVANAGARI" in name:
            scripts.add("devanagari")
        elif "THAI" in name:
            scripts.add("thai")
        elif "ARMENIAN" in name:
            scripts.add("armenian")
        elif "GEORGIAN" in name:
            scripts.add("georgian")
    # The reported corruption rapidly mixes many unrelated writing systems.
    return letters > 120 and len(scripts) >= 5


class SmoothEmitter:
    """Coalesce tiny provider tokens so QML is not forced to relayout per token."""

    def __init__(self, min_chars: int = 160, max_delay: float = 0.060):
        self.min_chars = min_chars
        self.max_delay = max_delay
        self.buf: List[str] = []
        self.size = 0
        self.last = time.monotonic()

    def feed(self, text: str) -> None:
        if not text:
            return
        self.buf.append(text)
        self.size += len(text)
        now = time.monotonic()
        if self.size >= self.min_chars or now - self.last >= self.max_delay or "\n" in text:
            self.flush()

    def flush(self) -> None:
        if not self.buf:
            return
        emit("delta", text="".join(self.buf))
        self.buf.clear()
        self.size = 0
        self.last = time.monotonic()


def theme_payload() -> dict:
    fallback = {
        "primary": "#9fc9ff",
        "secondary": "#b9c7dc",
        "tertiary": "#b9c9ff",
        "surface": "#11161c",
        "surface_container": "#171d24",
        "surface_high": "#1f2731",
        "surface_highest": "#27313d",
        "text": "#edf3fb",
        "muted": "#a9b4c0",
        "outline": "#51606f",
        "error": "#ffb4ab",
    }
    try:
        data = json.loads(DMS_COLORS.read_text())
        dark = data.get("colors", {}).get("dark", {})
        keys = {
            "primary": "primary",
            "secondary": "secondary",
            "tertiary": "tertiary",
            "surface": "surface",
            "surface_container": "surface_container",
            "surface_high": "surface_container_high",
            "surface_highest": "surface_container_highest",
            "text": "on_surface",
            "muted": "on_surface_variant",
            "outline": "outline_variant",
            "error": "error",
        }
        for dst, src in keys.items():
            val = dark.get(src)
            if isinstance(val, str) and val.startswith("#"):
                fallback[dst] = val
    except Exception:
        pass
    return fallback


def history_load() -> List[dict]:
    ensure_dirs()
    try:
        data = json.loads(HISTORY_FILE.read_text())
        return data if isinstance(data, list) else []
    except Exception:
        return []


def history_save(messages: List[dict], max_messages: int) -> None:
    ensure_dirs()
    messages = messages[-max(2, max_messages):]
    HISTORY_FILE.write_text(json.dumps(messages, indent=2, ensure_ascii=False) + "\n")


def http_request(url: str, payload: dict, headers: dict, timeout: int = 180):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", **headers}, method="POST")
    return urllib.request.urlopen(req, timeout=timeout)


def get_json(url: str, headers: dict | None = None, timeout: int = 8) -> dict:
    req = urllib.request.Request(url, headers=headers or {}, method="GET")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def sse_data_lines(resp) -> Iterable[str]:
    for raw in resp:
        line = raw.decode("utf-8", errors="replace").strip()
        if line.startswith("data:"):
            yield line[5:].strip()


def clean_model(provider: str, model: str | None) -> str:
    model = (model or "").strip()
    if provider != "mock" and model in {"demo", "mock-1"}:
        return ""
    return model


def _bearer(key: str) -> dict:
    return {"Authorization": f"Bearer {key}"} if key else {}


def _model_ids_from_openai_shape(data: dict) -> List[str]:
    models = []
    for item in data.get("data", []) if isinstance(data, dict) else []:
        if isinstance(item, dict) and item.get("id"):
            models.append(str(item["id"]))
    return models


def list_models(provider: str, base_url: str, api_key: str) -> List[str]:
    base = base_url.rstrip("/")
    if provider == "mock":
        return ["mock-1"]
    if provider == "ollama":
        data = get_json(base + "/api/tags", timeout=3)
        return [str(m.get("name")) for m in data.get("models", []) if isinstance(m, dict) and m.get("name")]
    if provider == "gemini":
        if not api_key:
            return []
        models: List[str] = []
        page_token = ""
        for _ in range(10):
            params = {"key": api_key, "pageSize": "1000"}
            if page_token:
                params["pageToken"] = page_token
            data = get_json(base + "/models?" + urllib.parse.urlencode(params), timeout=10)
            for item in data.get("models", []):
                if not isinstance(item, dict):
                    continue
                methods = item.get("supportedGenerationMethods", []) or []
                if methods and "generateContent" not in methods and "streamGenerateContent" not in methods:
                    continue
                name = str(item.get("name", ""))
                if name.startswith("models/"):
                    name = name[7:]
                if name:
                    models.append(name)
            page_token = str(data.get("nextPageToken", "") or "")
            if not page_token:
                break
        return models
    if provider == "anthropic":
        if not api_key:
            return []
        headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01"}
        models: List[str] = []
        after_id = ""
        for _ in range(20):
            query = {"limit": "1000"}
            if after_id:
                query["after_id"] = after_id
            data = get_json(base + "/models?" + urllib.parse.urlencode(query), headers=headers, timeout=10)
            batch = _model_ids_from_openai_shape(data)
            models.extend(batch)
            if not data.get("has_more") or not data.get("last_id"):
                break
            after_id = str(data.get("last_id"))
        return models

    headers = _bearer(api_key)
    if provider == "openrouter":
        headers.update({"HTTP-Referer": "https://localhost/mock-island", "X-Title": "Mock Island"})
    data = get_json(base + "/models", headers=headers, timeout=10)
    return _model_ids_from_openai_shape(data)


def provider_probe(provider: str | None = None) -> dict:
    cfg = load_config()
    secrets = load_secrets()
    provider = (provider or cfg.get("provider") or "mock").lower()
    if provider not in cfg.get("providers", {}):
        return {"provider": provider, "online": False, "message": "Proveedor desconocido", "models": []}

    pconf = cfg["providers"][provider]
    meta = PROVIDER_META.get(provider, {})
    model = clean_model(provider, pconf.get("model"))
    base_url = str(pconf.get("base_url", ""))
    secret_name = SECRET_ENV.get(provider, "")
    api_key = str(secrets.get(secret_name, "")) if secret_name else ""
    has_key = bool(api_key)
    requires_key = bool(meta.get("requires_key", False))
    supports_key = bool(meta.get("supports_key", False))
    local = bool(meta.get("local", False))
    online = False
    models: List[str] = []
    message = ""
    catalog_error = ""

    if provider == "mock":
        online = True
        models = ["mock-1"]
        model = "mock-1"
        message = "Mock listo · modo demo"
    elif requires_key and not has_key:
        message = f"Pega {secret_name} y pulsa Guardar"
    else:
        try:
            models = list_models(provider, base_url, api_key)
            # Remove duplicates while keeping names predictable.
            models = sorted(dict.fromkeys(x for x in models if x), key=str.casefold)
            online = True
            if not model and models:
                model = models[0]
            if provider in {"ollama", "lmstudio", "custom"}:
                source = {"ollama": "Ollama", "lmstudio": "LM Studio", "custom": "Endpoint custom"}[provider]
                message = f"{source} online · {len(models)} modelo{'s' if len(models) != 1 else ''}"
            else:
                message = f"API lista · {len(models)} modelo{'s' if len(models) != 1 else ''}"
            if not models:
                message = "Proveedor online · no devolvió modelos"
        except Exception as exc:
            catalog_error = str(exc)
            if provider in {"ollama", "lmstudio", "custom"}:
                online = False
                if provider == "ollama":
                    message = "Ollama no responde en 127.0.0.1:11434"
                elif provider == "lmstudio":
                    message = "LM Studio no responde en 127.0.0.1:1234"
                else:
                    message = "Endpoint custom no responde o no expone /models"
            else:
                # A key can be valid even if a provider does not expose model discovery.
                online = has_key
                message = "Clave guardada · no pude cargar el catálogo"

    return {
        "provider": provider,
        "label": meta.get("label", provider),
        "model": clean_model(provider, pconf.get("model")),
        "resolved_model": model,
        "base_url": base_url,
        "local": local,
        "online": online,
        "requires_key": requires_key,
        "supports_key": supports_key,
        "has_key": has_key,
        "secret_name": secret_name,
        "models": models,
        "model_count": len(models),
        "message": message,
        "catalog_error": catalog_error,
        "temperature": float(cfg.get("temperature", 0.7)),
        "max_tokens": int(cfg.get("max_tokens", 4096)),
        "system_prompt": str(cfg.get("system_prompt", DEFAULT_CONFIG["system_prompt"])),
        "agent": cfg.get("agent", DEFAULT_CONFIG["agent"]),
        "voice": cfg.get("voice", DEFAULT_CONFIG["voice"]),
    }


def provider_mock(prompt: str, emitter: SmoothEmitter) -> str:
    low = prompt.lower().strip()
    if any(x in low for x in ("hola", "hey", "buenas", "que onda", "qué onda")):
        text = "Ey 👋 Soy Mock. Ya estoy despierto. Puedes cambiar de proveedor, revisar modelos disponibles y probar la isla sin gastar tokens."
    elif "quien eres" in low or "quién eres" in low:
        text = "Soy Mock, el pequeño asistente de Mock Island. En modo mock no llamo a una IA externa: simulo la experiencia completa, incluido el streaming."
    elif "ollama" in low:
        text = "Si Ollama está activo en 127.0.0.1:11434, Mock consulta /api/tags y te muestra todos los modelos instalados en el selector."
    elif "modelo" in low or "modelos" in low:
        text = "Abre el selector de modelos. Mock consulta el catálogo real del proveedor elegido; para APIs cloud primero debes guardar la API key."
    else:
        text = (
            "Mock recibió tu mensaje 😎. Este modo sirve para probar animaciones, configuración, selección de modelos y streaming sin usar una API real.\n\n"
            f"Tu mensaje fue: {prompt}"
        )
    answer: List[str] = []
    step = 8
    for i in range(0, len(text), step):
        chunk = text[i:i + step]
        answer.append(chunk)
        emitter.feed(chunk)
        time.sleep(0.012)
    emitter.flush()
    return "".join(answer)


def provider_openai_compatible(provider: str, base_url: str, model: str, messages: List[dict], api_key: str, temperature: float, max_tokens: int, emitter: SmoothEmitter) -> str:
    if not model:
        raise RuntimeError(f"Falta modelo para {provider}")
    headers = _bearer(api_key)
    if provider == "openrouter":
        headers.update({"HTTP-Referer": "https://localhost/mock-island", "X-Title": "Mock Island"})
    url = base_url.rstrip("/") + "/chat/completions"
    payload = {"model": model, "messages": messages, "stream": True}
    if provider == "openai":
        payload["max_completion_tokens"] = max_tokens
    else:
        payload["max_tokens"] = max_tokens
        payload["temperature"] = temperature

    # Nemotron 3 Ultra tiene una incidencia pública reciente donde el endpoint
    # puede empezar a emitir una mezcla de idiomas/símbolos ("token soup").
    # Conservamos los parámetros documentados por NVIDIA y protegemos la UI:
    # los primeros caracteres se ponen en cuarentena hasta validar que son sanos.
    nvidia_ultra = provider == "nvidia" and "nemotron-3-ultra-550b-a55b" in model.lower()
    if nvidia_ultra:
        payload["temperature"] = 1.0
        payload["top_p"] = 0.95
        payload["chat_template_kwargs"] = {
            "enable_thinking": True,
            "medium_effort": True,
        }

    answer: List[str] = []
    quarantine: List[str] = []
    quarantine_released = not nvidia_ultra
    reasoning_seen = False
    last_reasoning_signal = 0.0

    def push_visible(text: str) -> None:
        nonlocal quarantine_released
        if not text:
            return
        answer.append(text)
        if not nvidia_ultra:
            emitter.feed(text)
            return

        current = "".join(answer)
        if _looks_like_token_soup(current):
            emitter.buf.clear()
            emitter.size = 0
            emit("reset")
            raise RuntimeError(
                "NVIDIA Nemotron 3 Ultra está devolviendo salida corrupta (mezcla de idiomas/token soup). "
                "Es una incidencia actual reportada también fuera de Mock Island. Selecciona otro modelo NVIDIA y reintenta."
            )

        if not quarantine_released:
            quarantine.append(text)
            # Evita enseñar basura inmediata. Si la salida parece normal, se libera
            # tras suficiente contexto; respuestas cortas se liberan al terminar.
            if len(current) >= 512 or (len(current) >= 220 and "\n\n" in current):
                for piece in quarantine:
                    emitter.feed(piece)
                quarantine.clear()
                quarantine_released = True
            return

        emitter.feed(text)

    with http_request(url, payload, headers, timeout=120) as resp:
        for data in sse_data_lines(resp):
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
            except json.JSONDecodeError:
                continue

            choices = obj.get("choices", []) if isinstance(obj, dict) else []
            if not choices:
                continue
            choice = choices[0] if isinstance(choices[0], dict) else {}
            delta_obj = choice.get("delta", {}) if isinstance(choice.get("delta", {}), dict) else {}

            # El reasoning se usa solo como estado visual; nunca se imprime como respuesta.
            reasoning = delta_obj.get("reasoning_content") or delta_obj.get("reasoning")
            if reasoning:
                now = time.monotonic()
                if (not reasoning_seen) or (now - last_reasoning_signal >= 2.0):
                    emit("state", state="reasoning")
                    reasoning_seen = True
                    last_reasoning_signal = now

            delta = delta_obj.get("content")
            if delta is None and isinstance(choice.get("message"), dict):
                delta = choice.get("message", {}).get("content")

            if isinstance(delta, str) and delta:
                push_visible(delta)
            elif isinstance(delta, list):
                for part in delta:
                    if not isinstance(part, dict):
                        continue
                    text = part.get("text")
                    if not isinstance(text, str):
                        nested = part.get("text", {})
                        if isinstance(nested, dict):
                            text = nested.get("value")
                    if isinstance(text, str) and text:
                        push_visible(text)

    if nvidia_ultra and not quarantine_released and quarantine:
        current = "".join(answer)
        if _looks_like_token_soup(current):
            emit("reset")
            raise RuntimeError(
                "NVIDIA Nemotron 3 Ultra está devolviendo salida corrupta (mezcla de idiomas/token soup). "
                "Selecciona otro modelo NVIDIA y reintenta."
            )
        for piece in quarantine:
            emitter.feed(piece)

    emitter.flush()
    if not answer:
        raise RuntimeError(
            "El proveedor terminó sin contenido visible. Prueba otro modelo o cambia el modo de razonamiento."
        )
    return "".join(answer)

def provider_ollama(base_url: str, model: str, messages: List[dict], temperature: float, max_tokens: int, emitter: SmoothEmitter) -> str:
    model = clean_model("ollama", model)
    if not model:
        model = provider_probe("ollama").get("resolved_model", "")
    if not model:
        raise RuntimeError("Ollama está sin modelo. Ejecuta `ollama pull <modelo>` o elige uno en Mock.")
    url = base_url.rstrip("/") + "/api/chat"
    payload = {
        "model": model,
        "messages": messages,
        "stream": True,
        "options": {"temperature": temperature, "num_predict": max_tokens},
    }
    answer: List[str] = []
    with http_request(url, payload, {}) as resp:
        for raw in resp:
            line = raw.decode("utf-8", errors="replace").strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                delta = obj.get("message", {}).get("content", "")
                if delta:
                    answer.append(delta)
                    emitter.feed(delta)
                if obj.get("done"):
                    break
            except Exception:
                continue
    emitter.flush()
    return "".join(answer)


def provider_anthropic(base_url: str, model: str, messages: List[dict], api_key: str, system_prompt: str, max_tokens: int, emitter: SmoothEmitter) -> str:
    if not api_key:
        raise RuntimeError("Falta ANTHROPIC_API_KEY")
    if not model:
        raise RuntimeError("Falta modelo de Anthropic")
    payload_messages = [m for m in messages if m.get("role") in ("user", "assistant")]
    payload = {"model": model, "max_tokens": max_tokens, "system": system_prompt, "messages": payload_messages, "stream": True}
    headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01"}
    answer: List[str] = []
    with http_request(base_url.rstrip("/") + "/messages", payload, headers) as resp:
        for data in sse_data_lines(resp):
            try:
                obj = json.loads(data)
                if obj.get("type") == "content_block_delta":
                    delta = obj.get("delta", {}).get("text", "")
                    if delta:
                        answer.append(delta)
                        emitter.feed(delta)
            except Exception:
                continue
    emitter.flush()
    return "".join(answer)


def _gemini_text(obj: dict) -> str:
    out: List[str] = []
    for cand in obj.get("candidates", []) if isinstance(obj, dict) else []:
        content = cand.get("content", {}) if isinstance(cand, dict) else {}
        for part in content.get("parts", []) if isinstance(content, dict) else []:
            if isinstance(part, dict) and isinstance(part.get("text"), str):
                out.append(part["text"])
    return "".join(out)


def provider_gemini(base_url: str, model: str, messages: List[dict], api_key: str, temperature: float, max_tokens: int, emitter: SmoothEmitter) -> str:
    if not api_key:
        raise RuntimeError("Falta GEMINI_API_KEY")
    if not model:
        raise RuntimeError("Falta modelo de Gemini")
    contents = []
    for m in messages:
        if m.get("role") == "system":
            continue
        role = "model" if m.get("role") == "assistant" else "user"
        contents.append({"role": role, "parts": [{"text": m.get("content", "")} ]})
    query = urllib.parse.urlencode({"alt": "sse", "key": api_key})
    url = base_url.rstrip("/") + f"/models/{urllib.parse.quote(model, safe='')}:streamGenerateContent?{query}"
    payload = {"contents": contents, "generationConfig": {"temperature": temperature, "maxOutputTokens": max_tokens}}
    answer: List[str] = []
    with http_request(url, payload, {}) as resp:
        for data in sse_data_lines(resp):
            try:
                delta = _gemini_text(json.loads(data))
                if delta:
                    answer.append(delta)
                    emitter.feed(delta)
            except Exception:
                continue
    emitter.flush()
    if not answer:
        raise RuntimeError("Gemini no devolvió una respuesta de texto")
    return "".join(answer)


def ask(args) -> int:
    cfg = load_config()
    secrets = load_secrets()
    provider = (args.provider or cfg.get("provider") or "mock").lower()
    pconf = cfg.get("providers", {}).get(provider, {})
    model = clean_model(provider, args.model if args.model is not None else pconf.get("model"))
    base_url = args.base_url or pconf.get("base_url", "")
    prompt = sys.stdin.read().strip() if not args.prompt else args.prompt.strip()
    if not prompt:
        emit("error", message="Prompt vacío")
        return 2

    if not model:
        model = provider_probe(provider).get("resolved_model", "")

    temperature = max(0.0, min(2.0, float(cfg.get("temperature", 0.7))))
    max_tokens = max(64, min(131072, int(cfg.get("max_tokens", 4096))))
    hist = [] if getattr(args, "no_history", False) else history_load()
    system_prompt = getattr(args, "system_prompt", None) or cfg.get("system_prompt", DEFAULT_CONFIG["system_prompt"])
    messages = [{"role": "system", "content": system_prompt}] + hist + [{"role": "user", "content": prompt}]
    emit("meta", provider=provider, model=model or "auto", temperature=temperature, max_tokens=max_tokens)
    emitter = SmoothEmitter()

    try:
        if provider == "mock":
            answer = provider_mock(prompt, emitter)
        elif provider in {"openai", "openrouter", "nvidia", "lmstudio", "custom"}:
            key = secrets.get(SECRET_ENV.get(provider, ""), "")
            if PROVIDER_META.get(provider, {}).get("requires_key") and not key:
                raise RuntimeError(f"Falta {SECRET_ENV[provider]}")
            answer = provider_openai_compatible(provider, base_url, model, messages, key, temperature, max_tokens, emitter)
        elif provider == "ollama":
            answer = provider_ollama(base_url, model, messages, temperature, max_tokens, emitter)
        elif provider == "anthropic":
            answer = provider_anthropic(base_url, model, messages, secrets.get("ANTHROPIC_API_KEY", ""), system_prompt, max_tokens, emitter)
        elif provider == "gemini":
            answer = provider_gemini(base_url, model, messages, secrets.get("GEMINI_API_KEY", ""), temperature, max_tokens, emitter)
        else:
            raise RuntimeError(f"Proveedor no soportado: {provider}")

        if not getattr(args, "no_history", False):
            hist.extend([{"role": "user", "content": prompt}, {"role": "assistant", "content": answer}])
            history_save(hist, int(cfg.get("max_history_messages", 16)))
        emit("done")
        return 0
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", errors="replace")[:1000]
        except Exception:
            pass
        emit("error", message=f"HTTP {e.code}: {body or e.reason}")
        return 1
    except urllib.error.URLError as e:
        emit("error", message=f"No pude conectar con {provider}: {e.reason}")
        return 1
    except Exception as e:
        emit("error", message=str(e))
        return 1


def cmd_status() -> None:
    print(json.dumps(provider_probe(), ensure_ascii=False))


def cmd_provider(provider: str, model: str | None) -> None:
    cfg = load_config()
    provider = provider.lower()
    if provider not in cfg.get("providers", {}):
        raise SystemExit("Proveedor válido: " + ", ".join(cfg.get("providers", {}).keys()))
    cfg["provider"] = provider
    if model is not None:
        cfg["providers"][provider]["model"] = clean_model(provider, model)
    save_config(cfg)
    print(json.dumps(provider_probe(provider), ensure_ascii=False))


def cmd_configure(stdin_mode: bool) -> None:
    if not stdin_mode:
        raise SystemExit("configure requiere --stdin")
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except Exception as exc:
        raise SystemExit(f"JSON inválido: {exc}")
    cfg = load_config()
    provider = str(data.get("provider") or cfg.get("provider") or "mock").lower()
    if provider not in cfg.get("providers", {}):
        raise SystemExit("Proveedor no válido")
    cfg["provider"] = provider
    if "model" in data:
        cfg["providers"][provider]["model"] = clean_model(provider, str(data.get("model") or ""))
    if "base_url" in data and str(data.get("base_url") or "").strip():
        cfg["providers"][provider]["base_url"] = str(data["base_url"]).strip()
    if "temperature" in data:
        try:
            cfg["temperature"] = max(0.0, min(2.0, float(data["temperature"])))
        except Exception:
            pass
    if "max_tokens" in data:
        try:
            cfg["max_tokens"] = max(64, min(131072, int(data["max_tokens"])))
        except Exception:
            pass
    if "system_prompt" in data and str(data.get("system_prompt") or "").strip():
        cfg["system_prompt"] = str(data["system_prompt"]).strip()
    if "agent_enabled" in data:
        cfg.setdefault("agent", {})["enabled"] = bool(data.get("agent_enabled"))
    if "agent_auto_execute_safe" in data:
        cfg.setdefault("agent", {})["auto_execute_safe"] = bool(data.get("agent_auto_execute_safe"))
    if "voice_tts_enabled" in data:
        cfg.setdefault("voice", {})["tts_enabled"] = bool(data.get("voice_tts_enabled"))
    if "voice_auto_send" in data:
        cfg.setdefault("voice", {})["auto_send"] = bool(data.get("voice_auto_send"))
    save_config(cfg)

    if bool(data.get("clear_api_key")):
        clear_secret(provider)
    api_key = str(data.get("api_key") or "").strip()
    if api_key and provider in SECRET_ENV:
        set_secret(provider, api_key)
    print(json.dumps(provider_probe(provider), ensure_ascii=False))


def cmd_key(provider: str) -> None:
    provider = provider.lower()
    keyname = SECRET_ENV.get(provider)
    if not keyname:
        raise SystemExit("Proveedor sin clave administrada: " + provider)
    value = getpass.getpass(f"{keyname}: ").strip()
    if not value:
        raise SystemExit("Clave vacía, sin cambios")
    set_secret(provider, value)
    print(f"Guardada en {SECRETS_FILE} (0600)")



def cmd_preferences() -> None:
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except Exception as exc:
        raise SystemExit(f"JSON inválido: {exc}")
    cfg = load_config()
    agent = cfg.setdefault("agent", {})
    voice = cfg.setdefault("voice", {})
    if "agent_enabled" in data:
        agent["enabled"] = bool(data.get("agent_enabled"))
    if "agent_auto_execute_safe" in data:
        agent["auto_execute_safe"] = bool(data.get("agent_auto_execute_safe"))
    if "voice_tts_enabled" in data:
        voice["tts_enabled"] = bool(data.get("voice_tts_enabled"))
    if "voice_auto_send" in data:
        voice["auto_send"] = bool(data.get("voice_auto_send"))
    save_config(cfg)
    print(json.dumps({"ok": True, "agent": agent, "voice": voice}, ensure_ascii=False))

def cmd_clear() -> None:
    ensure_dirs()
    HISTORY_FILE.write_text("[]\n")
    print("Historial borrado")


def cmd_context(include_clipboard: bool) -> None:
    print(json.dumps(desktop_context(include_clipboard=include_clipboard), ensure_ascii=False))


def cmd_file_context(path: str) -> None:
    print(json.dumps(file_context(path), ensure_ascii=False))


def main() -> int:
    ensure_dirs()
    ap = argparse.ArgumentParser(description="Mock Island AI bridge")
    sub = ap.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("ask")
    a.add_argument("--provider")
    a.add_argument("--model")
    a.add_argument("--base-url")
    a.add_argument("--prompt")
    a.add_argument("--no-history", action="store_true")
    a.add_argument("--system-prompt")

    sub.add_parser("status")
    sub.add_parser("theme")
    sub.add_parser("clear")
    sub.add_parser("preferences")
    ctx = sub.add_parser("context")
    ctx.add_argument("--clipboard", action="store_true")
    fc = sub.add_parser("file-context")
    fc.add_argument("path")
    pr = sub.add_parser("probe")
    pr.add_argument("--provider")
    p = sub.add_parser("provider")
    p.add_argument("provider")
    p.add_argument("model", nargs="?")
    c = sub.add_parser("configure")
    c.add_argument("--stdin", action="store_true")
    k = sub.add_parser("key")
    k.add_argument("provider")

    args = ap.parse_args()
    if args.cmd == "ask":
        return ask(args)
    if args.cmd == "status":
        cmd_status(); return 0
    if args.cmd == "probe":
        print(json.dumps(provider_probe(args.provider), ensure_ascii=False)); return 0
    if args.cmd == "theme":
        print(json.dumps(theme_payload())); return 0
    if args.cmd == "provider":
        cmd_provider(args.provider, args.model); return 0
    if args.cmd == "configure":
        cmd_configure(args.stdin); return 0
    if args.cmd == "key":
        cmd_key(args.provider); return 0
    if args.cmd == "clear":
        cmd_clear(); return 0
    if args.cmd == "preferences":
        cmd_preferences(); return 0
    if args.cmd == "context":
        cmd_context(args.clipboard); return 0
    if args.cmd == "file-context":
        cmd_file_context(args.path); return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
