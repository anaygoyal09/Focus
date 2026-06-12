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

ENTITLEMENTS="$SCRIPT_DIR/Sources/Focus.entitlements"

# Signing intentionally disabled by default. Set FOCUS_SIGN=1 to enable.
#
# IMPORTANT: When signing with the hardened runtime (--options runtime),
# macOS blocks all Apple Events (browser/app automation) unless the bundle
# carries the com.apple.security.automation.apple-events entitlement. We
# therefore ALWAYS pass --entitlements so Automation permission works in the
# signed build the same way it does unsigned.
#
# If $SIGN_IDENTITY is not present in the keychain we fall back to ad-hoc
# signing ("-"), which still applies the entitlements. Note: ad-hoc builds get
# a new code-signing hash every build, so previously granted permissions may
# not persist across rebuilds. For grants that stick, sign with a stable
# identity (a Developer ID, or a self-signed code-signing certificate created
# in Keychain Access) and pass it via SIGN_IDENTITY.
if [[ "${FOCUS_SIGN:-0}" == "1" ]]; then
    if [[ ! -f "$ENTITLEMENTS" ]]; then
        echo "Missing entitlements file at $ENTITLEMENTS" >&2
        exit 1
    fi

    sign_id="$SIGN_IDENTITY"
    if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
        echo "==> Identity '$SIGN_IDENTITY' not found in keychain; falling back to ad-hoc (-)"
        sign_id="-"
    fi

    echo "==> Codesigning with identity: $sign_id (hardened runtime + entitlements)"
    codesign --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$sign_id" "$BUNDLE_DIR"

    echo "==> Verifying signature"
    codesign --verify --deep --strict --verbose=2 "$BUNDLE_DIR"
    echo "==> Entitlements embedded:"
    codesign -d --entitlements - "$BUNDLE_DIR" 2>/dev/null || true
else
    echo "==> Skipping codesign (set FOCUS_SIGN=1 to enable)"
fi

echo "==> Done: $BUNDLE_DIR"
