#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
task_dist="${WORDLENS_DIST_DIR:-$task_root/dist}"
bash "$task_root/build.sh"
codesign --verify --deep --strict --verbose=2 "$task_dist/划词译.app"
python3 - "$task_root" "$task_dist" <<'PY'
import hashlib
import pathlib
import plistlib
import sys
import zipfile

root = pathlib.Path(sys.argv[1])
dist = pathlib.Path(sys.argv[2])
app = dist / '划词译.app'
info = plistlib.loads((root / 'Info.plist').read_bytes())
built_info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
assert built_info['CFBundleShortVersionString'] == version
assert all(part.isdigit() for part in version.split('.')), 'Unexpected version'
archive = dist / f'WordLens-v{version}-Intel.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as out:
    for path in sorted(app.rglob('*')):
        out.write(path, path.relative_to(dist).as_posix())
    for name in ['README.md', 'LICENSE']:
        out.write(root / name, name)
with zipfile.ZipFile(archive) as check:
    assert check.testzip() is None
    executable = check.getinfo('划词译.app/Contents/MacOS/WordLens')
    assert (executable.external_attr >> 16) & 0o111, 'Executable permission missing'
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
checksum = archive.with_suffix(archive.suffix + '.sha256')
checksum.write_text(f'{digest}  {archive.name}\n', encoding='utf-8')
print(f'Release archive: {archive}')
print(f'SHA-256 file: {checksum}')
PY
