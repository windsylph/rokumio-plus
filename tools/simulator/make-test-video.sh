#!/bin/sh
# Builds tools/simulator/web/test.mp4 (H.264) from a wallpaper video that ships
# with macOS, so the local test add-on has something to play. macOS only.
set -e
out="$(dirname "$0")/web/test.mp4"
src=""
for f in "/System/Library/Desktop Pictures/.wallpapers/Sonoma/Sonoma Graphic Dark Landscape.mov" \
         "/System/Library/Wallpapers/.default/Golden Gate.mov"; do
    if [ -f "$f" ]; then src="$f"; break; fi
done
if [ -z "$src" ]; then
    src="$(find /System/Library -name '*.mov' -size +1M 2>/dev/null | head -n 1)"
fi
if [ -z "$src" ]; then echo "No built-in macOS video found to convert."; exit 1; fi
echo "Converting: $src"
avconvert --source "$src" --preset Preset1280x720 --output "$out" --replace
echo "Wrote $out"
