#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Hover"
SCHEME="Hover"
CONFIGURATION="Release"
BUILD_DIR="${BUILD_DIR:-build/release}"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
DMG_ROOT="${BUILD_DIR}/dmg-root"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"
ALLOW_UNSIGNED="${ALLOW_UNSIGNED:-0}"

if [[ -z "${IDENTITY}" && "${ALLOW_UNSIGNED}" != "1" ]]; then
  echo "Set DEVELOPER_ID_APPLICATION, or set ALLOW_UNSIGNED=1 for an unsigned supporter-preview DMG." >&2
  exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${EXPORT_DIR}" "${DMG_ROOT}"

if [[ -n "${IDENTITY}" ]]; then
  xcodebuild archive \
    -project Hover.xcodeproj \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    CODE_SIGN_IDENTITY="${IDENTITY}" \
    CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES
else
  echo "Building unsigned preview. macOS Gatekeeper will warn users." >&2
  xcodebuild archive \
    -project Hover.xcodeproj \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    CODE_SIGNING_ALLOWED=NO
fi

APP_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"

if [[ -n "${IDENTITY}" ]]; then
  codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
fi

cp -R "${APP_PATH}" "${DMG_ROOT}/"
ln -s /Applications "${DMG_ROOT}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

if [[ -n "${IDENTITY}" ]]; then
  codesign --force --sign "${IDENTITY}" "${DMG_PATH}"
fi

if [[ -n "${IDENTITY}" && -n "${NOTARY_PROFILE}" ]]; then
  xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${DMG_PATH}"
fi

if [[ -n "${IDENTITY}" ]]; then
  spctl --assess --type open --context context:primary-signature -v "${DMG_PATH}"
fi

echo "Created ${DMG_PATH}"
