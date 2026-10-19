#!/bin/bash
# Builds ScufBridge.app into ./build.
#
#   scripts/build_app.sh                 build only
#   scripts/build_app.sh --install       build, copy to /Applications and launch
#   scripts/build_app.sh --virtual-hid   also sign with the virtual-gamepad entitlement (see README)
#
# Signing: uses your "Apple Development" certificate if you have one (a free Apple ID added in
# Xcode creates one). A stable signature keeps macOS permissions across rebuilds. Without one the
# app is signed ad hoc, and you may need to re-allow Accessibility after each rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0
VIRTUAL_HID=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --virtual-hid) VIRTUAL_HID=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

echo "==> Building (release)"
swift build -c release --product ScufBridge
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/ScufBridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ScufBridge" "$APP/Contents/MacOS/ScufBridge"
cp Packaging/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
fi

SIGN_ARGS=(--force --sign "$IDENTITY")
if [ "$VIRTUAL_HID" = 1 ]; then
  SIGN_ARGS+=(--entitlements Packaging/VirtualHID.entitlements)
fi
echo "==> Signing with: $IDENTITY"
codesign "${SIGN_ARGS[@]}" "$APP"

(cd build && rm -f ScufBridge.zip && ditto -c -k --keepParent ScufBridge.app ScufBridge.zip)
echo "==> Built $APP"

if [ "$INSTALL" = 1 ]; then
  pkill -x ScufBridge 2>/dev/null || true
  sleep 1
  rm -rf /Applications/ScufBridge.app
  ditto "$APP" /Applications/ScufBridge.app
  open /Applications/ScufBridge.app
  echo "==> Installed to /Applications/ScufBridge.app and launched"
fi
