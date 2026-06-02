# Changelog

All notable changes to Hover are documented here.

## Unreleased

Use this section for changes that have landed after the latest published release.

## 0.1.0 - 2026-06-02

### Added

- Added the first paid/supporter preview release of Hover for Mac.
- Added a macOS menu bar app that opens an AI assistant beside the cursor.
- Added global `Command-Shift-X` triggering and optional triple right-click triggering.
- Added action presets for explain, rewrite, summarize, reply, translate, fix grammar, and ask.
- Added empty prompt mode so users can ask Hover without selecting text first.
- Added output actions for copy result, replace selection, and paste to active app.
- Added local-first provider support for LM Studio and Ollama.
- Added OpenAI, Featherless, and custom OpenAI-compatible endpoint support.
- Added automatic local model discovery for LM Studio and Ollama when their local servers are available.
- Added secure API key storage through non-syncing macOS Keychain items.
- Added first-run onboarding for permissions, providers, model setup, and connection testing.
- Added connection health checks with plain-language error states.
- Added optional screen context and Accessibility text extraction.
- Added optional push-to-talk voice input.
- Added context transparency inside the floating panel so users can see what context is being used.
- Added a privacy tab explaining what stays local, what may be sent to external providers, and why permissions are needed.
- Added GitHub Releases-backed in-app updates through Sparkle.
- Added release automation that generates a DMG, Sparkle update ZIP, and signed `appcast.xml` for each GitHub release.
- Added OSS documentation, release guidance, security policy, contribution guide, and privacy policy.

### Notes

- This release can be distributed as an unsigned supporter-preview DMG. macOS Gatekeeper will warn users until Hover is signed and notarized with a Developer ID certificate.
- Sparkle update archives are signed separately from Apple Developer ID signing so Hover can reject tampered update downloads.

## 0.0.1 - 2026-06-02

### Added

- Added the initial public launch build of Hover for Mac.
