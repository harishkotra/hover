# Release Process

Hover can be distributed outside the Mac App Store.

## Recommended Public Release

Use a signed and notarized DMG when selling to general Mac users.

Requires:

- Apple Developer Program.
- Developer ID Application certificate.
- Hardened runtime.
- Notarization with `notarytool`.

## Unsigned Supporter Preview

If you are not using the Apple Developer Program yet, you can ship an unsigned DMG to early supporters only if the download page clearly says:

- This is an early supporter preview.
- macOS may show an unidentified developer warning.
- Users should only install it if they trust the source.
- Signed builds are planned once revenue covers Developer ID.

Build with:

```bash
ALLOW_UNSIGNED=1 scripts/build_dmg.sh
```

## Signed DMG

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE="hover-notary" \
scripts/build_dmg.sh
```

If `NOTARYTOOL_PROFILE` is omitted, the script creates a signed but non-notarized DMG.

## Supporter Delivery

GitHub Sponsors supports one-time tiers. For a simple paid-download flow, create a one-time tier and use the welcome message to point supporters to the current DMG delivery location. If you want GitHub-controlled access, add a private download repository to the tier and publish versioned DMGs as release assets in that private repository.
