# Hover Privacy

Hover does not track, store, sell, or upload user interactions to a Hover server.

## Local Storage

Hover stores:

- Provider preset, base URL, model name, prompt, and settings toggles in local app preferences.
- API keys in macOS Keychain using non-syncing items.

Hover does not store:

- Prompt history.
- Response history.
- Selected text.
- Screenshots.
- Voice recordings or transcripts.
- Analytics events.

## What Can Leave the Mac

If the user chooses a local provider such as LM Studio or Ollama on `localhost`, prompts and enabled context are sent to that local model server.

If the user chooses OpenAI, Featherless, or a custom remote HTTPS endpoint, Hover sends the prompt and enabled context to that provider. The provider's privacy policy and account settings control what happens after that.

## Permissions

- Accessibility and Input Monitoring: global shortcut, right-click trigger, and on-demand copy/paste automation.
- Screen Recording: optional screenshot context for vision-capable models.
- Microphone and Speech Recognition: push-to-talk voice input only.
- Local Network: detection and connection to local model servers.

Public website version: [https://hoverformac.com/#privacy](https://hoverformac.com/#privacy).
