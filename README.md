# Hover

Hover is a local-first macOS menu bar app that opens an AI prompt next to your cursor. Select text anywhere, press `Command-Shift-X` or triple right-click, choose an action, and send the result back into the app you were using.

Hover supports LM Studio, Ollama, OpenAI, Featherless, and OpenAI-compatible endpoints. It does not require a Hover cloud account.

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
