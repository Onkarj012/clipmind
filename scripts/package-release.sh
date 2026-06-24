#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="ClipMind"
PROJECT_PATH="ClipMind.xcodeproj"
SCHEME="ClipMind"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_ROOT="${ARCHIVE_ROOT:-build/Package}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ARCHIVE_ROOT}/DerivedData}"
DIST_DIR="${DIST_DIR:-dist}"
DMG_STAGING_PATH="${ARCHIVE_ROOT}/dmg-root"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ClipMind/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' ClipMind/Info.plist)"
ARTIFACT_NAME="${APP_NAME}-${VERSION}-unsigned.dmg"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${ARTIFACT_NAME}"

echo "Packaging ${APP_NAME} ${VERSION} (${BUILD})"

rm -rf "$DERIVED_DATA_PATH"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle was not produced: $APP_PATH" >&2
  exit 1
fi

rm -rf "$DMG_STAGING_PATH"
mkdir -p "$DMG_STAGING_PATH"
ditto "$APP_PATH" "$DMG_STAGING_PATH/${APP_NAME}.app"
ln -s /Applications "$DMG_STAGING_PATH/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "$DMG_STAGING_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
