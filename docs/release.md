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

## GitHub-Hosted In-App Updates

Hover uses Sparkle 2 for direct macOS updates outside the Mac App Store.

The app checks this appcast:

```text
https://github.com/harishkotra/hover/releases/latest/download/appcast.xml
```

When a GitHub release is published, `.github/workflows/release.yml` builds only the OTA assets:

- `Hover-<version>.zip` for Sparkle in-app updates.
- `appcast.xml` for Hover's update checker.

Do not upload the paid installer DMG to the public GitHub release. The official DMG should be built locally and uploaded to Dodo Payments for paid delivery.

Sparkle update signing is separate from Apple Developer ID signing. Even unsigned supporter-preview builds need Sparkle's EdDSA update signature so Hover can reject tampered update ZIPs.

Before publishing the first release, generate Sparkle keys with Sparkle's `generate_keys` tool:

```bash
generate_keys
```

Store the generated values this way:

- Commit the public key in `Hover/Info.plist` as `SUPublicEDKey`.
- Store the full private key file contents in the GitHub Actions repository secret `SPARKLE_PRIVATE_KEY`.

Never commit the private Sparkle key. It signs update archives and controls which ZIPs Hover will trust.

To publish an update:

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Hover.xcodeproj`.
2. Update `CHANGELOG.md`.
3. Build the paid installer DMG locally with `scripts/build_dmg.sh` and upload it to Dodo Payments if new customers need the latest installer.
4. Create and publish a GitHub release from a tag such as `v0.1.1`.
5. The release workflow uploads only the Sparkle ZIP and appcast to the GitHub release.
6. Existing Hover installs see the update through the menu bar app's update checker.

## Signed DMG

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE="hover-notary" \
scripts/build_dmg.sh
```

If `NOTARYTOOL_PROFILE` is omitted, the script creates a signed but non-notarized DMG.

## DMG Icon

The release script embeds the app icon into the mounted `Hover` volume as `.VolumeIcon.icns`. It also applies a best-effort Finder custom icon to the local `Hover.dmg` file. The mounted volume icon is the reliable release behavior; file-level custom icons are macOS metadata and may be stripped by some upload or download paths.

## Paid DMG Delivery

Use Dodo Payments for the official paid DMG. Upload the latest locally built `Hover-<version>.dmg` there whenever a new installer should be available to new buyers.

GitHub Releases are only for OTA metadata and update archives. Do not attach the paid DMG to public GitHub releases unless you intentionally want it to be freely downloadable.
