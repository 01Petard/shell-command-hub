#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/hub-bundle-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT
/usr/bin/xcrun swiftc "$ROOT/tests/test_app_icon.swift" -o "$work/test-app-icon"
for name in 'Shell Command Hub' 'Shell Command Hub TUI'; do
    app="$ROOT/build/release/$name.app"
    [ -d "$app" ] || { echo "Build apps first: ./scripts/build-app.sh" >&2; exit 2; }
    relocated="$work/移动 '$name.app"
    /usr/bin/ditto "$app" "$relocated"
    PATH=/usr/bin:/bin:/usr/sbin:/sbin "$relocated/Contents/MacOS/HubApp" --self-test > "$work/self-test"
    grep -q 'bundled runtime OK' "$work/self-test"
    /usr/bin/codesign --verify --deep --strict "$relocated"
    resources="$relocated/Contents/Resources"
    [ "$(/usr/bin/plutil -extract CFBundleIconFile raw "$relocated/Contents/Info.plist")" = HubIcon.icns ]
    /usr/bin/iconutil -c iconset "$resources/HubIcon.icns" -o "$work/icon-$name.iconset"
    [ -f "$work/icon-$name.iconset/icon_512x512@2x.png" ]
    "$work/test-app-icon" "$relocated"
    for binary in "$resources/runtime/bin/"* "$resources/runtime/lib/"*; do
        if /usr/bin/otool -L "$binary" | grep -q '/opt/homebrew\|/usr/local/'; then echo "FAIL: external runtime reference: $binary"; exit 1; fi
    done
    PATH="$resources/runtime/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$resources/toolbox/hub" doctor > "$work/doctor"
done
mkdir "$work/media" "$work/archive" "$work/source"
printf 'RIFF\x64\x06\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x40\x1f\x00\x00\x80\x3e\x00\x00\x02\x00\x10\x00data\x40\x06\x00\x00' > "$work/media/中文 ' audio.WAV"
dd if=/dev/zero bs=1600 count=1 >> "$work/media/中文 ' audio.WAV" 2>/dev/null
export PATH="$resources/runtime/bin:/usr/bin:/bin:/usr/sbin:/sbin"
"$resources/toolbox/hub" run media-info "$work/media" > "$work/media-output"
grep -q '8000 Hz' "$work/media-output"
printf data > "$work/source/file.txt"
(cd "$work/source" && /usr/bin/zip -q "$work/archive/batch.zip" file.txt)
"$resources/toolbox/hub" run zip-tidy "$work/archive" > "$work/archive-output"
[ ! -e "$work/archive/batch.zip" ] && [ -f "$work/archive/batch/file.txt" ]
"$resources/toolbox/hub" run port-info 65535 > "$work/port-output"
echo 'PASS: both apps relocated, signatures valid, no Homebrew references, bundled media/ZIP/port execution'
