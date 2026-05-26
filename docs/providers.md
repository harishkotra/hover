# Providers

Hover talks to OpenAI-compatible chat completions endpoints.

## Supported Presets

- LM Studio: local, no API key by default.
- Ollama: local, no API key by default.
- OpenAI: remote HTTPS, API key required.
- Featherless: remote HTTPS, API key required.
- Compatible: custom HTTPS or localhost endpoint.

## Security Rules

- Remote endpoints must use HTTPS.
- Localhost HTTP is allowed for local model servers.
- API keys are stored in macOS Keychain.
- Provider redirects are blocked.
- Requests use ephemeral URLSession storage.

## Test Connection

Use Settings > Inference > Test Connection to verify:

- Base URL.
- API key.
- Model name.
- Streaming support.
