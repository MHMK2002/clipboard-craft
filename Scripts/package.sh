#!/bin/zsh
# Builds a universal release and packages it as a DMG and a ZIP in releases/.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP="build/Clipboard Craft.app"
OUT=releases
mkdir -p "$OUT"

./build.sh --universal

echo "› Packaging $VERSION…"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT/ClipboardCraft-$VERSION.dmg" "$OUT/ClipboardCraft-$VERSION.zip"
hdiutil create -quiet -volname "Clipboard Craft $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT/ClipboardCraft-$VERSION.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/ClipboardCraft-$VERSION.zip"
rm -rf "$STAGE"

( cd "$OUT" && shasum -a 256 "ClipboardCraft-$VERSION.dmg" "ClipboardCraft-$VERSION.zip" > "ClipboardCraft-$VERSION.sha256" )
echo "✓ $OUT/ClipboardCraft-$VERSION.dmg"
echo "✓ $OUT/ClipboardCraft-$VERSION.zip"
