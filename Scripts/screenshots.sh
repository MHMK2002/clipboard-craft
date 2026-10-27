#!/bin/zsh
# Regenerates docs/screenshots using the debug-only showcase mode (demo data, generated backdrop).
# The app's windows appear on screen for about a minute; the screen must be unlocked and the
# terminal needs Screen Recording permission.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh --debug
WORK=$(mktemp -d)
: > "$WORK/scenes.txt"
CC_DATA_DIR="$WORK/data" CC_SHOWCASE="$WORK/scenes.txt" \
  "build/Clipboard Craft.app/Contents/MacOS/ClipboardCraft" -AppleLocale en_US -AppleLanguages "(en)" >/dev/null 2>&1 &
APP_PID=$!

seen=0
start=$(date +%s)
while (( $(date +%s) - start < 180 )); do
  total=$(wc -l < "$WORK/scenes.txt" | tr -d ' ')
  while (( seen < total )); do
    seen=$((seen + 1))
    line=$(sed -n "${seen}p" "$WORK/scenes.txt")
    [[ "$line" == done ]] && break 3
    read name x y w h <<< "$line"
    screencapture -x -R "$x,$y,$w,$h" "$WORK/$name.png"
    echo "› $name"
  done
  kill -0 $APP_PID 2>/dev/null || break
  sleep 0.2
done
wait $APP_PID 2>/dev/null || true

mkdir -p docs/screenshots
for f in "$WORK"/*.png; do
  sips -Z 1600 -s format jpeg -s formatOptions 88 "$f" --out "docs/screenshots/$(basename "$f" .png).jpg" >/dev/null
done
rm -rf "$WORK"
echo "✓ docs/screenshots updated"
