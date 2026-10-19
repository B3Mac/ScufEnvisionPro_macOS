#!/bin/bash
# Builds ScufBridge.app into ./build.
#
#   scripts/build_app.sh                    build for this Mac
#   scripts/build_app.sh --install          build, copy to /Applications and launch
#   scripts/build_app.sh --universal        build for Apple Silicon and Intel (used for releases)
#   scripts/build_app.sh --version 0.2.0    stamp a version into Info.plist
#   scripts/build_app.sh --dmg              also make build/ScufBridge-<version>.dmg
#   scripts/build_app.sh --virtual-hid      sign with the virtual-gamepad entitlement (see README)
#
# Signing: uses $SIGN_IDENTITY if set, otherwise your "Developer ID Application" or "Apple
# Development" certificate if you have one, otherwise ad hoc. A stable signature keeps macOS
# permissions across rebuilds; an ad-hoc one may need Accessibility re-allowed after each build.
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0
VIRTUAL_HID=0
UNIVERSAL=0
DMG=0
VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1 ;;
    --virtual-hid) VIRTUAL_HID=1 ;;
    --universal) UNIVERSAL=1 ;;
    --dmg) DMG=1 ;;
    --version) shift; VERSION="${1:?--version needs a value}" ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

APP="build/ScufBridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$UNIVERSAL" = 1 ]; then
  # One architecture at a time, then merge. Building both in one `swift build` needs full Xcode.
  SLICES=()
  for ARCH in arm64 x86_64; do
    echo "==> Building (release, $ARCH)"
    swift build -c release --triple "$ARCH-apple-macosx15.0" --product ScufBridge
    SLICES+=("$(swift build -c release --triple "$ARCH-apple-macosx15.0" --show-bin-path)/ScufBridge")
  done
  lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/ScufBridge"
else
  echo "==> Building (release)"
  swift build -c release --product ScufBridge
  cp "$(swift build -c release --show-bin-path)/ScufBridge" "$APP/Contents/MacOS/ScufBridge"
fi
echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/ScufBridge")"

cp Packaging/Info.plist "$APP/Contents/Info.plist"
for ART in Packaging/Artwork/*.png; do
  if [ -e "$ART" ]; then cp "$ART" "$APP/Contents/Resources/"; fi
done
if [ -n "$VERSION" ]; then
  BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
echo "==> Version $VERSION"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application|Apple Development/ { print $2; exit }')"
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
fi

SIGN_ARGS=(--force --sign "$IDENTITY")
if [ "$IDENTITY" != "-" ]; then
  # Hardened runtime and a secure timestamp are required for notarization.
  SIGN_ARGS+=(--options runtime --timestamp)
fi
if [ "$VIRTUAL_HID" = 1 ]; then
  SIGN_ARGS+=(--entitlements Packaging/VirtualHID.entitlements)
fi
echo "==> Signing with: $IDENTITY"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict "$APP"

(cd build && rm -f ScufBridge.zip && ditto -c -k --keepParent ScufBridge.app ScufBridge.zip)
echo "==> Built $APP"

if [ "$DMG" = 1 ]; then
  DMG_PATH="build/ScufBridge-$VERSION.dmg"
  STAGING="build/dmg"
  rm -rf "$STAGING" "$DMG_PATH"
  mkdir -p "$STAGING"
  ditto "$APP" "$STAGING/ScufBridge.app"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "ScufBridge $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
  rm -rf "$STAGING"
  if [ "$IDENTITY" != "-" ]; then
    codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
  fi
  echo "==> Built $DMG_PATH"
fi

if [ "$INSTALL" = 1 ]; then
  pkill -x ScufBridge 2>/dev/null || true
  sleep 1
  rm -rf /Applications/ScufBridge.app
  ditto "$APP" /Applications/ScufBridge.app
  open /Applications/ScufBridge.app
  echo "==> Installed to /Applications/ScufBridge.app and launched"
fi
