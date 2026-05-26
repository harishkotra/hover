# Architecture

Hover is a small macOS menu bar app built with SwiftUI, AppKit, Carbon hotkeys, Accessibility APIs, ScreenCaptureKit, Speech, and URLSession.

## Main Flow

1. `GlobalTriggerManager` receives the hotkey or triple right-click.
2. It copies the current selection with a normal Command-C and restores the previous pasteboard contents.
3. `FloatingPanelController` opens a non-activating floating panel near the cursor.
4. `FloatingResponseViewModel` coordinates presets, prompt input, context capture, streaming, copy, and paste.
5. `LLMClient` streams OpenAI-compatible chat completions.

## Privacy Boundaries

- `KeychainStore` is the only place that stores API keys.
- `ScreenContextService` captures context only when Hover is triggered.
- `LLMClient` validates transport before sending requests.
- Diagnostics never include user content or secrets.

## UI Boundaries

- `SettingsView` owns settings tabs and privacy controls.
- `OnboardingView` currently lives with settings UI because it reuses settings controls.
- `FloatingContentView` owns the panel presentation and result rendering.
