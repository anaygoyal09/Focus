#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Focus"
EXEC_NAME="FocusApp"
BUNDLE_DIR="$SCRIPT_DIR/${APP_NAME}.app"
SIGN_IDENTITY="${SIGN_IDENTITY:-48F55A8718339ED9347964BA0989E17BAC1B9A75}"

echo "==> Building release product ${EXEC_NAME}"
swift build --configuration release --product "$EXEC_NAME"

BIN_PATH="$(swift build --configuration release --product "$EXEC_NAME" --show-bin-path)/$EXEC_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Could not locate built binary at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling ${APP_NAME}.app"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$BIN_PATH" "$BUNDLE_DIR/Contents/MacOS/$EXEC_NAME"
chmod +x "$BUNDLE_DIR/Contents/MacOS/$EXEC_NAME"
cp "$SCRIPT_DIR/Sources/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"

# PkgInfo
printf 'APPL????' > "$BUNDLE_DIR/Contents/PkgInfo"

# Icon
if [[ -d "$SCRIPT_DIR/Focus.iconset" ]]; then
    echo "==> Building AppIcon.icns"
    iconutil -c icns "$SCRIPT_DIR/Focus.iconset" -o "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
fi

echo "==> Clearing extended attributes"
/usr/bin/xattr -cr "$BUNDLE_DIR" || true

# Signing intentionally disabled. Set FOCUS_SIGN=1 to re-enable codesigning
# with $SIGN_IDENTITY (default 48F55A8718339ED9347964BA0989E17BAC1B9A75).
if [[ "${FOCUS_SIGN:-0}" == "1" ]]; then
    echo "==> Codesigning with identity $SIGN_IDENTITY"
    codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$BUNDLE_DIR"
    echo "==> Verifying signature"
    codesign --verify --deep --strict --verbose=2 "$BUNDLE_DIR"
else
    echo "==> Skipping codesign (set FOCUS_SIGN=1 to enable)"
fi

echo "==> Done: $BUNDLE_DIR"
