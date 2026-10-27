#!/bin/zsh
# Builds "Clipboard Craft.app" with Swift Package Manager (no Xcode project needed).
#
#   ./build.sh            release build → build/Clipboard Craft.app
#   ./build.sh --run      build and launch
#   ./build.sh --install  build and copy to /Applications
#   ./build.sh --debug    debug build
#   ./build.sh --universal  Apple Silicon + Intel binary
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
RUN=0
INSTALL=0
ARCH_FLAGS=()
for arg in "$@"; do
  case $arg in
    --run) RUN=1 ;;
    --install) INSTALL=1 ;;
    --debug) CONFIG=debug ;;
    --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

APP_NAME="Clipboard Craft"
APP="build/$APP_NAME.app"

# With only the Command Line Tools installed, the macOS 27 SDK turns @State into a macro whose
# plugin ships with Xcode only. Fall back to the newest macOS 26 SDK in that case.
if [[ -z "${SDKROOT:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)
  if [[ -n "$SDK" ]]; then
    export SDKROOT="$SDK"
    echo "› Using SDK $(basename "$SDK")"
  fi
fi

echo "› Compiling ($CONFIG)…"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" 2>&1 | grep -v "search path '/Library/Developer/CommandLineTools/Developer" || true
BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)/ClipboardCraft"
[[ -x "$BIN" ]] || { echo "Build failed"; exit 1; }

if [[ ! -f Resources/AppIcon.icns ]]; then
  echo "› Rendering app icon…"
  TMP=$(mktemp -d)
  swift Scripts/make_icon.swift "$TMP/AppIcon.iconset" >/dev/null
  iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$TMP"
fi

echo "› Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClipboardCraft"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a stable, self-signed local identity. macOS ties Accessibility permission to the
# code signature: with ad-hoc signing every rebuild looks like a new app and the permission is
# lost. The identity lives in its own keychain under .signing/ (no password prompts, nothing
# added to the login keychain). Delete .signing/ to discard it.
SIGN_NAME="Clipboard Craft Local Signing"
SIGN_DIR="$PWD/.signing"
KEYCHAIN="$SIGN_DIR/signing.keychain-db"
KC_PASS="clipboard-craft-local"

ensure_identity() {
  if [[ ! -f "$KEYCHAIN" ]]; then
    echo "› Creating local signing identity (one time)…"
    mkdir -p "$SIGN_DIR"
    local tmp; tmp=$(mktemp -d)
    cat > "$tmp/cert.cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGN_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CFG
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cfg" \
      -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$SIGN_NAME" \
      -out "$tmp/identity.p12" -passout pass:"$KC_PASS"
    security create-keychain -p "$KC_PASS" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"
    security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
    security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$KC_PASS" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null
    rm -rf "$tmp"
  fi
  security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
}

SIGNED=0
if ensure_identity 2>/dev/null; then
  echo "› Signing with “$SIGN_NAME”…"
  # perl alarm: never hang the build on an unexpected keychain prompt.
  if perl -e 'alarm 60; exec @ARGV' codesign --force --deep --keychain "$KEYCHAIN" --sign "$SIGN_NAME" \
       --identifier app.clipboardcraft.mac "$APP" >/dev/null 2>&1; then
    SIGNED=1
  fi
fi
if [[ $SIGNED == 0 ]]; then
  echo "› Signing (ad-hoc fallback — Accessibility permission must be re-granted after each build)…"
  codesign --force --deep --sign - --identifier app.clipboardcraft.mac "$APP" >/dev/null
fi

if [[ $INSTALL == 1 ]]; then
  echo "› Installing to /Applications…"
  pkill -x ClipboardCraft 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  APP="/Applications/$APP_NAME.app"
fi

echo "✓ Built $APP"

if [[ $RUN == 1 ]]; then
  pkill -x ClipboardCraft 2>/dev/null || true
  sleep 0.3
  open "$APP"
fi
