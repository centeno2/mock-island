# Mock Island

Una isla pequeña para IA en tu escritorio Linux.

Mock Island es un panel flotante, ligero y minimalista para conversar con modelos de IA directamente desde tu sistema. Está pensado para funcionar como un asistente de escritorio, sin depender de una app pesada ni de un ecosistema complejo.

## ¿Qué hace?

- Abre una ventana compacta con tecla rápida
- Habla con modelos de IA en tiempo real
- Soporta proveedores locales y remotos
- Guarda historial y configuraciones
- Funciona como un “open code” simple y personalizable

## Proveedores compatibles

- OpenAI
- OpenRouter
- Anthropic
- Gemini
- NVIDIA
- Ollama
- LM Studio
- Custom / OpenAI-compatible API

## Requisitos

- Linux con Quickshell / Niri
- Python 3
- Acceso a un proveedor de IA o a un servidor local

## Instalación

```bash
chmod +x install.sh
./install.sh
```

## Comandos útiles

super + space

## Configuración de API

Puedes guardar claves para distintos proveedores y cambiar el modelo desde la propia interfaz o con comandos:

```bash
mock-island key openai
mock-island provider gemini
mock-island provider ollama llama3.1
```

## Idea del proyecto

Este proyecto es un asistente de escritorio orientado a open source, con foco en conectarse a clientes de API de IA y dejar la experiencia simple, rápida y útil.

## Autor

Heyner centeno - @centeno2
