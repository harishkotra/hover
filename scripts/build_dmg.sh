#!/usr/bin/env bash
#
# build_dmg.sh
# Builds the Hover macOS app archive and packages it into a distributable DMG.
# The script embeds Hover's generated app icon as the mounted volume icon and,
# when developer tools allow it, also applies a Finder custom icon to the local
# DMG file before signing/notarization.

set -euo pipefail

APP_NAME="Hover"
SCHEME="Hover"
CONFIGURATION="Release"
BUILD_DIR="${BUILD_DIR:-build/release}"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
DERIVED_DATA_PATH="${BUILD_DIR}/DerivedData"
EXPORT_DIR="${BUILD_DIR}/export"
DMG_ROOT="${BUILD_DIR}/dmg-root"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
TEMP_DMG_PATH="${BUILD_DIR}/${APP_NAME}-rw.dmg"
MOUNT_DIR="${BUILD_DIR}/mount"
APP_ICONSET_SOURCE="Hover/Resources/Assets.xcassets/AppIcon.appiconset"
DMG_VOLUME_ICON="${BUILD_DIR}/${APP_NAME}.icns"
DMG_FILE_ICON_PNG="${BUILD_DIR}/${APP_NAME}-file-icon.png"
DMG_FILE_ICON_RSRC="${BUILD_DIR}/${APP_NAME}-file-icon.rsrc"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"
ALLOW_UNSIGNED="${ALLOW_UNSIGNED:-0}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
MOUNTED_VOLUME=""

if [[ -z "${IDENTITY}" && "${ALLOW_UNSIGNED}" != "1" ]]; then
  echo "Set DEVELOPER_ID_APPLICATION, or set ALLOW_UNSIGNED=1 for an unsigned supporter-preview DMG." >&2
  exit 1
fi

cleanup() {
  if [[ -n "${MOUNTED_VOLUME}" ]]; then
    hdiutil detach "${MOUNTED_VOLUME}" -quiet >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

require_tool() {
  local tool="$1"
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Missing required tool: ${tool}" >&2
    exit 1
  fi
}

require_xcrun_tool() {
  local tool="$1"
  if ! xcrun --find "${tool}" >/dev/null 2>&1; then
    echo "Missing required Xcode tool: ${tool}" >&2
    exit 1
  fi
}

create_dmg_icon() {
  local app_path="$1"
  local compiled_icon="${app_path}/Contents/Resources/AppIcon.icns"

  if [[ -f "${compiled_icon}" ]]; then
    cp "${compiled_icon}" "${DMG_VOLUME_ICON}"
    return
  fi

  require_tool iconutil
  local fallback_iconset="${BUILD_DIR}/${APP_NAME}.iconset"
  rm -rf "${fallback_iconset}"
  mkdir -p "${fallback_iconset}"
  cp "${APP_ICONSET_SOURCE}"/icon_*.png "${fallback_iconset}/"
  iconutil -c icns "${fallback_iconset}" -o "${DMG_VOLUME_ICON}"
}

apply_volume_icon() {
  require_xcrun_tool SetFile

  cp "${DMG_VOLUME_ICON}" "${MOUNT_DIR}/.VolumeIcon.icns"
  xcrun SetFile -c icnC "${MOUNT_DIR}/.VolumeIcon.icns"
  xcrun SetFile -a V "${MOUNT_DIR}/.VolumeIcon.icns"
  xcrun SetFile -a C "${MOUNT_DIR}"
}

apply_local_dmg_file_icon() {
  if ! xcrun --find DeRez >/dev/null 2>&1 || ! xcrun --find Rez >/dev/null 2>&1; then
    echo "Skipping local Finder file icon because Rez/DeRez are unavailable." >&2
    return
  fi

  require_tool sips

  cp "${APP_ICONSET_SOURCE}/icon_512x512.png" "${DMG_FILE_ICON_PNG}"
  sips -i "${DMG_FILE_ICON_PNG}" >/dev/null
  xcrun DeRez -only icns "${DMG_FILE_ICON_PNG}" > "${DMG_FILE_ICON_RSRC}"
  xcrun Rez -append "${DMG_FILE_ICON_RSRC}" -o "${DMG_PATH}"
  xcrun SetFile -a C "${DMG_PATH}"
}

rm -rf "${BUILD_DIR}"
mkdir -p "${EXPORT_DIR}" "${DMG_ROOT}" "${MOUNT_DIR}"

if [[ -n "${IDENTITY}" ]]; then
  xcodebuild archive \
    -project Hover.xcodeproj \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    CODE_SIGN_IDENTITY="${IDENTITY}" \
    CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES \
    SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY}"
else
  echo "Building unsigned preview. macOS Gatekeeper will warn users." >&2
  xcodebuild archive \
    -project Hover.xcodeproj \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY}"
fi

APP_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
create_dmg_icon "${APP_PATH}"

if [[ -n "${IDENTITY}" ]]; then
  codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
fi

cp -R "${APP_PATH}" "${DMG_ROOT}/"
ln -s /Applications "${DMG_ROOT}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "${TEMP_DMG_PATH}"

hdiutil attach "${TEMP_DMG_PATH}" \
  -mountpoint "${MOUNT_DIR}" \
  -nobrowse \
  -quiet
MOUNTED_VOLUME="${MOUNT_DIR}"

apply_volume_icon
sync
hdiutil detach "${MOUNTED_VOLUME}" -quiet
MOUNTED_VOLUME=""

hdiutil convert "${TEMP_DMG_PATH}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "${DMG_PATH}"

apply_local_dmg_file_icon
rm -f "${TEMP_DMG_PATH}" "${DMG_VOLUME_ICON}" "${DMG_FILE_ICON_PNG}" "${DMG_FILE_ICON_RSRC}"

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
