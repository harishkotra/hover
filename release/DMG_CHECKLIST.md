# Hover DMG Release Checklist

## Required Accounts For A Signed Build
- Apple Developer Program membership.
- Developer ID Application certificate installed in Keychain.
- App Store Connect notary credentials or a stored `notarytool` keychain profile.
- Final GitHub Sponsors tier or download delivery URL.
- Public support email.

Unsigned supporter-preview DMGs can be created without Apple Developer ID, but the download page must clearly warn users that macOS will show Gatekeeper warnings.

## Preflight
1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Verify website links on `https://hoverformac.com`.
3. Build Release locally and run Hover from `/Applications`.
4. Verify first-run onboarding, permissions, provider setup, Test Connection, preset actions, Copy, Replace Selection, and Paste to Active App.
5. Test with at least one local provider and one remote HTTPS provider.

## Signing and Notarization
1. Build with hardened runtime enabled.
2. Sign with Developer ID Application.
3. Create the DMG.
4. Submit the DMG to Apple notarization.
5. Staple the notarization ticket.
6. Install the final DMG on another Mac that does not have Xcode.
7. Open the DMG and verify the mounted `Hover` volume uses the Hover icon.

## Unsigned Supporter Preview
1. Run `ALLOW_UNSIGNED=1 scripts/build_dmg.sh`.
2. Label the download as unsigned.
3. Include install instructions for macOS Gatekeeper warnings.
4. Do not present the unsigned build as a polished public release.

## Manual Delivery
- Use GitHub Sponsors or another supported payment channel.
- Send supporters the notarized DMG link and install guide.
- Keep a changelog and versioned DMG archive so customers can redownload the exact release.
