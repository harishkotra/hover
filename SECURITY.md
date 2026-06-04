# Security Policy

## Supported Versions

Security fixes target the latest public release and the current `main` branch.

## Reporting a Vulnerability

Please do not open a public issue for vulnerabilities involving API key exposure, prompt leakage, permission bypasses, or unsafe network behavior.

Email: `hey[at]hoverformac.com`

Include:

- Hover version or commit hash.
- macOS version.
- Reproduction steps.
- Impact assessment.
- Whether user content, API keys, screenshots, or local files are involved.

## Security Principles

- API keys are stored in non-syncing macOS Keychain items.
- Remote HTTP is blocked except for loopback local model servers.
- URLSession uses ephemeral configuration with no cookies, URL cache, or credential storage.
- Provider redirects are blocked so authorization headers do not follow a changed origin.
- Hover does not intentionally persist prompts, responses, screenshots, voice input, or selected text.
