#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
task_build="${WORDLENS_BUILD_DIR:-$task_root/work/build}"
task_dist="${WORDLENS_DIST_DIR:-$task_root/dist}"
mkdir -p "$task_build"
task_build="$(cd "$task_build" && pwd -P)"
clang -fobjc-arc -fmodules -fmodules-cache-path="$task_build/ModuleCache" -fblocks -Wall -Wextra -Wno-unused-parameter \
  -arch x86_64 -mmacosx-version-min=10.15 -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  "$task_root/Tests/CoreTests.m" "$task_root/Source/WLCore.m" "$task_root/Source/WLCompatibility.m" \
  -framework Cocoa -framework ApplicationServices -framework Carbon -framework Security -o "$task_build/CoreTests"
"$task_build/CoreTests"
clang -fobjc-arc -fmodules -fmodules-cache-path="$task_build/ModuleCache" -fblocks -Wall -Wextra -Wno-unused-parameter \
  -arch x86_64 -mmacosx-version-min=10.15 -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  "$task_root/Tests/CompatibilityTests.m" "$task_root/Source/WLCore.m" "$task_root/Source/WLCompatibility.m" \
  -framework Cocoa -framework ApplicationServices -framework Carbon -framework Security -o "$task_build/CompatibilityTests"
"$task_build/CompatibilityTests"
python3 - "$task_root" "$task_dist" <<'PY'
import pathlib
import plistlib
import sys

root = pathlib.Path(sys.argv[1])
dist = pathlib.Path(sys.argv[2])
for file in [root / 'Info.plist', dist / '划词译.app/Contents/Info.plist']:
    if not file.exists():
        continue
    ats = plistlib.loads(file.read_bytes())['NSAppTransportSecurity']
    assert ats.get('NSAllowsArbitraryLoads') is True, file
    # These more specific keys make macOS ignore NSAllowsArbitraryLoads.
    assert not {'NSAllowsLocalNetworking', 'NSAllowsArbitraryLoadsForMedia',
                'NSAllowsArbitraryLoadsInWebContent'} & ats.keys(), file
print('HTTP transport configuration checks passed')
PY
