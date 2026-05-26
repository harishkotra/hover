# Contributing to Hover

Thanks for considering a contribution. Hover is privacy-sensitive Mac software, so changes should be small, reviewable, and explicit about data flow.

## What Helps Most

- Bug fixes with clear reproduction steps.
- Provider compatibility fixes.
- Accessibility and permission UX improvements.
- Local-model setup improvements.
- Documentation for non-technical Mac users.

## Engineering Rules

- Keep Hover local-first.
- Do not add telemetry, analytics, crash reporting, or network calls without an explicit issue and privacy review.
- Do not log prompts, selected text, screenshots, responses, API keys, or transcripts.
- Store secrets only in macOS Keychain.
- Prefer small SwiftUI/AppKit changes that match the existing app structure.
- Keep idle CPU effectively zero.

## Pull Request Checklist

- Explain the user-facing change.
- Explain any new data that is read, stored, or sent.
- Include manual test steps.
- Run the Swift typecheck command from `README.md` when possible.
- Run `plutil -lint Hover/Info.plist Hover.xcodeproj/project.pbxproj`.

## Code Style

- Use explicit error handling.
- Avoid forced unwraps.
- Use structured concurrency for async work.
- Add comments where permissions, pasteboard, Accessibility, ScreenCaptureKit, or network security behavior is non-obvious.
- Keep UI copy short and plain.
