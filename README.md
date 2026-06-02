# Hover

Hover is a local-first macOS menu bar app that opens an AI prompt next to your cursor. Select text anywhere, press `Command-Shift-X` or triple right-click, choose an action, and send the result back into the app you were using.

Hover supports LM Studio, Ollama, OpenAI, Featherless, and OpenAI-compatible endpoints. It does not require a Hover cloud account.

### Screenshots

<img width="890" height="734" alt="1" src="https://github.com/user-attachments/assets/bd6206d6-bae7-4a94-be5d-c3371315d4f9" />
<img width="840" height="732" alt="2" src="https://github.com/user-attachments/assets/6d87720b-0b8e-4737-a240-f42ca0244d71" />
<img width="836" height="714" alt="3" src="https://github.com/user-attachments/assets/cbe1a2ef-5e34-44c0-9edf-a90db20ca024" />
<img width="835" height="741" alt="4" src="https://github.com/user-attachments/assets/ebfee94e-3f13-4588-84e2-742e44d849d9" />
<img width="803" height="890" alt="5" src="https://github.com/user-attachments/assets/62b7c12a-c306-4eb6-9bf8-62825d02b640" />
<img width="799" height="881" alt="6" src="https://github.com/user-attachments/assets/2ec5fe1f-6d67-4b70-974a-022525ebdac1" />
<img width="795" height="885" alt="7" src="https://github.com/user-attachments/assets/6527c7fe-706e-48af-86a9-7628aa3db9e0" />
<img width="799" height="875" alt="9" src="https://github.com/user-attachments/assets/4fc9f4ba-2e2d-49e4-af98-5c79e97eb44a" />
<img width="716" height="459" alt="11" src="https://github.com/user-attachments/assets/e7295d48-6c76-4b53-bd78-77bd83424932" />
<img width="566" height="380" alt="10" src="https://github.com/user-attachments/assets/ecd51d43-02cf-4b79-aac0-35c656f09dbf" />


## Why Open Source

Hover sits close to a user's daily Mac workflow, so the code should be inspectable. The repository is open for transparency, review, and contributions.

The paid option is the official DMG distribution: a convenient build, setup guidance, support, and updates. Users can always build from source.

## Current Features

- Menu bar macOS app with `LSUIElement` background behavior.
- Global `Command-Shift-X` trigger and optional triple right-click trigger.
- Floating cursor-adjacent panel with action presets.
- Explain, rewrite, summarize, reply, translate, fix grammar, and ask modes.
- OpenAI-compatible streaming chat completions.
- LM Studio and Ollama local model detection.
- API keys stored in non-syncing macOS Keychain items.
- Optional screen context, screenshot context, and push-to-talk voice input.
- Copy result, replace selection, and paste to active app.
- First-run onboarding, connection testing, and privacy-safe diagnostics.
- GitHub Releases-backed in-app updates through Sparkle.

## Repository Layout

```text
Hover/              macOS app source
Hover.xcodeproj/    Xcode project
docs/               OSS and user documentation
release/            release checklist
scripts/            release scripts
```

The marketing site is intentionally kept in a separate repository so the app project stays focused.

## Build From Source

Requirements:

- macOS 14 or newer
- Xcode 16 or newer
- Swift 5

Steps:

1. Open `Hover.xcodeproj` in Xcode.
2. Select the `Hover` scheme.
3. Build and run.
4. Follow the setup guide from the menu bar app.

Command-line typecheck used during development:

```bash
swiftc -typecheck -module-cache-path /private/tmp/Hover-ModuleCache -target arm64-apple-macosx14.0 -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk Hover/HoverApp.swift Hover/AppEnvironment.swift Hover/Controllers/StatusBarController.swift Hover/Models/HoverAction.swift Hover/Services/GlobalTriggerManager.swift Hover/Services/LLMClient.swift Hover/Services/KeychainStore.swift Hover/Services/LocalModelDiscovery.swift Hover/Services/ScreenContextService.swift Hover/Services/SpeechTranscriptionService.swift Hover/ViewModels/SettingsViewModel.swift Hover/Views/SettingsView.swift Hover/Views/VisualEffectView.swift Hover/Windows/FloatingPanel.swift Hover/Views/FloatingContentView.swift
```

## Paid DMG Strategy

Hover does not need the Mac App Store. The official paid DMG can be distributed directly to supporters through a GitHub Sponsors tier or another purchase channel.

Important distinction:

- Signed and notarized DMG: best user trust, requires Apple Developer Program.
- Unsigned supporter-preview DMG: possible without the Apple Developer Program, but macOS will show Gatekeeper warnings.

See [docs/release.md](docs/release.md) and [release/DMG_CHECKLIST.md](release/DMG_CHECKLIST.md).

Published GitHub releases can include a Sparkle appcast and update ZIP so paid users install the DMG once and update from inside Hover.

Marketing site: [https://hoverformac.com](https://hoverformac.com)

## Documentation

- [Install guide](docs/install.md)
- [Local models](docs/local-models.md)
- [Providers](docs/providers.md)
- [Architecture](docs/architecture.md)
- [Release process](docs/release.md)
- [Privacy](PRIVACY.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

Code is licensed under GPL-3.0-only. The Hover name, logo, website copy, and official build identity are covered by the trademark policy.
