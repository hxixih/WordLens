#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
task_build="${WORDLENS_BUILD_DIR:-$task_root/work/build}"
task_dist="${WORDLENS_DIST_DIR:-$task_root/dist}"
task_app="$task_dist/划词译.app"
mkdir -p "$task_build" "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
task_build="$(cd "$task_build" && pwd -P)"
task_sdk="$(xcrun --sdk macosx --show-sdk-path)"
clang -fobjc-arc -fmodules -fmodules-cache-path="$task_build/ModuleCache" -fblocks -Wall -Wextra -Wno-unused-parameter \
  -isysroot "$task_sdk" -arch x86_64 -mmacosx-version-min=10.15 \
  "$task_root/Source/main.m" "$task_root/Source/WLApp.m" "$task_root/Source/WLCore.m" "$task_root/Source/WLCompatibility.m" \
  -framework Cocoa -framework ApplicationServices -framework Carbon -framework Security -framework QuartzCore \
  -o "$task_app/Contents/MacOS/WordLens"
cp "$task_root/Info.plist" "$task_app/Contents/Info.plist"
clang -fobjc-arc -fmodules -fmodules-cache-path="$task_build/ModuleCache" -isysroot "$task_sdk" \
  -arch x86_64 -mmacosx-version-min=10.15 "$task_root/Source/MakeIcon.m" \
  -framework Foundation -framework CoreGraphics -framework CoreText -framework ImageIO -o "$task_build/MakeIcon"
"$task_build/MakeIcon" "$task_build/WordLens.iconset"
python3 "$task_root/make_icns.py" "$task_build/WordLens.iconset" "$task_app/Contents/Resources/WordLens.icns"
codesign --force --sign - --identifier cn.local.WordLens "$task_app"
printf '已构建：%s\n' "$task_app"
