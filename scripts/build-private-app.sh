#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="AmorDrop"
BUNDLE_ID="com.amor.personal.amordrop"
VERSION="1.2.0"
MINIMUM_MACOS_VERSION="15.6"
SIGNING_IDENTITY="${AMORDROP_SIGNING_IDENTITY:--}"
OUTPUT_APP_DIR="${AMORDROP_OUTPUT_APP_DIR:-$PWD/build/${APP_NAME}.app}"
# Sign outside the Documents file provider: it can recreate Finder metadata
# immediately after xattr cleanup, making in-place signing nondeterministic.
BUILD_STAGE="$(mktemp -d /private/tmp/AmorDrop-build.XXXXXX)"
trap 'rm -rf "$BUILD_STAGE"' EXIT
APP_DIR="${BUILD_STAGE}/${APP_NAME}.app"

mkdir -p .build/swiftpm-cache .build/swiftpm-config .build/swiftpm-security \
  .build/module-cache .build/clang-module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"
BUILD_ARGS=(-c release --arch arm64
  --cache-path .build/swiftpm-cache
  --config-path .build/swiftpm-config
  --security-path .build/swiftpm-security
  --scratch-path .build
  --manifest-cache local
  -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache")
xcrun swift build "${BUILD_ARGS[@]}" --product AmorDrop
xcrun swift build "${BUILD_ARGS[@]}" --product AmorDropClosedLidHelper
BIN_DIR="$(xcrun swift build "${BUILD_ARGS[@]}" --show-bin-path)"

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources" "${APP_DIR}/Contents/Library/LaunchDaemons"
cp "${BIN_DIR}/AmorDrop" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "${BIN_DIR}/AmorDropClosedLidHelper" "${APP_DIR}/Contents/MacOS/AmorDropClosedLidHelper"
cp Packaging/com.amor.personal.amordrop.closed-lid.plist "${APP_DIR}/Contents/Library/LaunchDaemons/"

RESOURCE_BUNDLE="${BIN_DIR}/AmorDrop_AmorDrop.bundle"
test -d "${RESOURCE_BUNDLE}"
cp -R "${RESOURCE_BUNDLE}" "${APP_DIR}/Contents/Resources/"
cp -R Sources/ShelfDemo/Resources/. "${APP_DIR}/Contents/Resources/"
cp LICENSE "${APP_DIR}/Contents/Resources/LICENSE"

/usr/libexec/PlistBuddy -c "Clear dict" "${APP_DIR}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ${APP_NAME}" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${BUNDLE_ID}" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string ${APP_NAME}" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION}" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string ${MINIMUM_MACOS_VERSION}" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSInputMonitoringUsageDescription string AmorDrop temporarily monitors keyboard events only while Keyboard Cleaning Lock is active, so it can suppress typing and recognize the unlock shortcut." "${APP_DIR}/Contents/Info.plist"

# These are freshly built local artifacts. File-provider/Finder metadata
# copied from the source tree must not become part of the signed bundle.
xattr -cr "${APP_DIR}"
codesign --force --deep --sign "${SIGNING_IDENTITY}" "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
mkdir -p "$(dirname "$OUTPUT_APP_DIR")"
ditto --noextattr --norsrc "${APP_DIR}" "${OUTPUT_APP_DIR}"

printf 'Built %s\n' "${OUTPUT_APP_DIR}"
