#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="1.2.0"
MINIMUM_MACOS_VERSION="15.6"
ARCH="arm64"
ARTIFACT_DIR="${1:-/private/tmp}"
DMG_NAME="AmorDrop-macOS${MINIMUM_MACOS_VERSION}-${ARCH}-preview-${VERSION}.dmg"
BUILD_STAGE="$(mktemp -d /private/tmp/AmorDrop-release.XXXXXX)"
trap 'rm -rf "$BUILD_STAGE"' EXIT
APP_PATH="${BUILD_STAGE}/AmorDrop.app"
DMG_ROOT="${BUILD_STAGE}/DMG"

mkdir -p "$ARTIFACT_DIR" "$DMG_ROOT"
AMORDROP_OUTPUT_APP_DIR="$APP_PATH" bash scripts/build-private-app.sh
ditto "$APP_PATH" "${DMG_ROOT}/AmorDrop.app"
ln -s /Applications "${DMG_ROOT}/Applications"

DMG_PATH="${ARTIFACT_DIR}/${DMG_NAME}"
hdiutil create -volname "AmorDrop ${VERSION}" -srcfolder "$DMG_ROOT" \
  -ov -format UDZO "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "${DMG_PATH}.sha256"

printf 'DMG: %s\n' "$DMG_PATH"
cat "${DMG_PATH}.sha256"
