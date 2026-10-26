#!/bin/bash
set -euo pipefail

# VaultKey local build.
#
#   ./build.sh            release build
#   CONFIG=debug ./build.sh
#   ./build.sh --test     also build and run the core self-test
#   CODESIGN_IDENTITY=- ./build.sh   ad-hoc signing
#
# No SwiftPM: this Command Line Tools install can't link Package.swift
# manifests, so the app is one module compiled directly with swiftc.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

APP="$ROOT/.build/VaultKey.app"
BIN="$APP/Contents/MacOS/VaultKey"
SDK="$(xcrun --show-sdk-path)"
TARGET="$(uname -m)-apple-macos14.0"
CONFIG="${CONFIG:-release}"

if [[ "$CONFIG" == "debug" ]]; then
    OPT_FLAGS=(-Onone -g)
else
    OPT_FLAGS=(-O -whole-module-optimization)
fi

FRAMEWORKS=(
    -framework SwiftUI
    -framework AppKit
    -framework Security
    -framework LocalAuthentication
    -framework IOKit
    -framework UniformTypeIdentifiers
)

echo "▸ Building VaultKey ($CONFIG, $(uname -m))"

if [[ "${1:-}" == "--test" ]]; then
    echo "▸ Running core self-test"
    swiftc -swift-version 5 -O \
        -sdk "$SDK" \
        -target "$TARGET" \
        -o .build/selftest \
        Sources/VaultKeyCore/*.swift Tests/main.swift \
        -framework Security \
        -framework LocalAuthentication \
        -framework AppKit \
        -framework IOKit
    .build/selftest
fi

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "▸ Generating app icon"
    swiftc -swift-version 5 -O -o .build/make_icon Tools/make_icon.swift -framework AppKit
    rm -rf Resources/AppIcon.iconset
    .build/make_icon Resources/AppIcon.iconset
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi

plutil -lint Resources/Info.plist >/dev/null

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ Compiling"
swiftc -swift-version 5 \
    "${OPT_FLAGS[@]}" \
    -parse-as-library \
    -sdk "$SDK" \
    -target "$TARGET" \
    -module-name VaultKey \
    -o "$BIN" \
    Sources/VaultKeyCore/*.swift Sources/VaultKey/*.swift \
    "${FRAMEWORKS[@]}"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    # Prefer a local development identity, but never hard-code one into the
    # repository. A clean checkout still builds ad hoc.
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Apple Development/ {print $2; exit}')"
fi

if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
    echo "▸ Signing ad hoc"
    codesign --force --options runtime --sign - "$APP"
elif security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "▸ Signing with $IDENTITY"
    codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
else
    echo "⚠︎ Signing identity not found; signing ad hoc"
    codesign --force --options runtime --sign - "$APP"
fi

codesign --verify --strict "$APP"
echo "▸ Built $APP"
echo "  $(du -sh "$APP" | cut -f1) · $(codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|TeamIdentifier|Signature)=' | tr '\n' ' ')"
