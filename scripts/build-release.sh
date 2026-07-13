#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: scripts/build-release.sh VERSION}"
BUILD_NUMBER="${BUILD_NUMBER:-3}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/release-derived"
OUTPUT_DIR="$ROOT_DIR/releases/v$VERSION"
APP_SOURCE="$DERIVED_DATA/Build/Products/Release/fan.app"
APP_STAGE="$OUTPUT_DIR/fan.app"
DMG_MOUNT="/tmp/fan-$VERSION-dmg-mount"
RW_DMG="$OUTPUT_DIR/fan-$VERSION-macos-rw.dmg"

rm -rf "$OUTPUT_DIR" "$DMG_MOUNT"
mkdir -p "$OUTPUT_DIR"

xcodebuild \
  -project "$ROOT_DIR/fan.xcodeproj" \
  -scheme fan \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  clean build

ditto "$APP_SOURCE" "$APP_STAGE"
xattr -cr "$APP_STAGE"
codesign --force --deep --sign - "$APP_STAGE"
codesign --verify --deep --strict "$APP_STAGE"

ditto --norsrc --noextattr -c -k --keepParent "$APP_STAGE" "$OUTPUT_DIR/fan-$VERSION-macos.zip"
shasum -a 256 "$OUTPUT_DIR/fan-$VERSION-macos.zip" > "$OUTPUT_DIR/fan-$VERSION-macos.zip.sha256"

hdiutil create \
  -size 20m \
  -fs APFS \
  -volname "fan $VERSION" \
  -ov \
  "$RW_DMG"
mkdir -p "$DMG_MOUNT"
hdiutil attach -nobrowse -mountpoint "$DMG_MOUNT" "$RW_DMG"
ditto --norsrc --noextattr "$APP_STAGE" "$DMG_MOUNT/fan.app"
ln -s /Applications "$DMG_MOUNT/Applications"
hdiutil detach "$DMG_MOUNT"
hdiutil convert "$RW_DMG" -format UDZO -o "$OUTPUT_DIR/fan-$VERSION-macos.dmg"
rm -rf "$RW_DMG" "$DMG_MOUNT"
shasum -a 256 "$OUTPUT_DIR/fan-$VERSION-macos.dmg" > "$OUTPUT_DIR/fan-$VERSION-macos.dmg.sha256"

# File-provider metadata can be re-applied to the staged app while the DMG is
# assembled. Keep the local release copy independently verifiable as well.
xattr -cr "$APP_STAGE"
codesign --force --deep --sign - "$APP_STAGE"
codesign --verify --deep --strict "$APP_STAGE"

printf 'Release artifacts: %s\n' "$OUTPUT_DIR"
