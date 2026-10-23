#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
version=$(cat "$ROOT/VERSION")
case "$version" in *[!0-9.]*|'') echo 'Invalid VERSION' >&2; exit 2 ;; esac
OUT="$ROOT/build/release"
mkdir -p "$OUT"
work=$(mktemp -d "${TMPDIR:-/tmp}/hub-app-build.XXXXXX")
trap 'rm -rf "$work"' EXIT
arch=$(/usr/bin/uname -m)
identity=${HUB_SIGN_IDENTITY:--}
sign_args=(--force --sign "$identity")
if [ "$identity" = - ]; then sign_args+=(--timestamp=none); else sign_args+=(--options runtime --timestamp); fi
/usr/bin/xcrun swiftc -swift-version 5 -O -target "$arch-apple-macosx13.0" -framework AppKit "$ROOT/app/HubApp.swift" -o "$work/HubApp"
/usr/bin/xcrun swift "$ROOT/scripts/generate-icon.swift" "$work"
/usr/bin/iconutil -c icns "$work/HubIcon.iconset" -o "$work/HubIcon.icns"
for mode in gui tui; do
    name='Shell Command Hub'
    [ "$mode" != tui ] || name='Shell Command Hub TUI'
    app="$work/$name.app"
    content="$app/Contents"
    mkdir -p "$content/MacOS" "$content/Resources/toolbox" "$content/Resources/runtime/bin" "$content/Resources/runtime/lib" "$content/Resources/licenses"
    cp "$work/HubApp" "$content/MacOS/HubApp"
    cp -R "$ROOT/hub" "$ROOT/catalog.tsv" "$ROOT/lib" "$ROOT/tools" "$ROOT/docs" "$content/Resources/toolbox/"
    cp "$ROOT/VERSION" "$content/Resources/"
    cp "$work/HubIcon.icns" "$content/Resources/"
    for executable in fzf mediainfo; do
        source_bin=$(command -v "$executable")
        cp -L "$source_bin" "$content/Resources/runtime/bin/$executable"
        source_real=$(realpath "$source_bin")
        source_prefix=$(dirname "$(dirname "$source_real")")
        for license in "$source_prefix"/LICENSE* "$source_prefix"/License* "$source_prefix"/COPYING*; do
            [ ! -f "$license" ] || cp "$license" "$content/Resources/licenses/$executable-$(basename "$license")"
        done
    done
    # Copy and relocate all non-system dylibs, recursively. No Homebrew paths remain.
    changed=1
    while [ "$changed" = 1 ]; do
        changed=0
        for binary in "$content/Resources/runtime/bin/"* "$content/Resources/runtime/lib/"*; do
            [ -f "$binary" ] || continue
            /usr/bin/codesign --remove-signature "$binary" 2>/dev/null || :
            while IFS= read -r dependency; do
                case "$dependency" in /System/*|/usr/lib/*|@*) continue ;; esac
                base=$(basename "$dependency")
                dest="$content/Resources/runtime/lib/$base"
                if [ ! -f "$dest" ]; then
                    cp -L "$dependency" "$dest"; changed=1
                    /usr/bin/codesign --remove-signature "$dest" 2>/dev/null || :
                    /usr/bin/install_name_tool -id "@rpath/$base" "$dest"
                    source_prefix=$(dirname "$(dirname "$(realpath "$dependency")")")
                    for license in "$source_prefix"/LICENSE* "$source_prefix"/License* "$source_prefix"/COPYING*; do
                        [ ! -f "$license" ] || cp "$license" "$content/Resources/licenses/$base-$(basename "$license")"
                    done
                fi
                case "$binary" in */bin/*) relocated="@loader_path/../lib/$base" ;; *) relocated="@loader_path/$base" ;; esac
                /usr/bin/install_name_tool -change "$dependency" "$relocated" "$binary"
            done < <(/usr/bin/otool -L "$binary" | awk 'NR>1 {print $1}')
        done
    done
    for binary in "$content/Resources/runtime/bin/"* "$content/Resources/runtime/lib/"*; do
        [ ! -f "$binary" ] || /usr/bin/codesign "${sign_args[@]}" "$binary"
    done
    cat > "$content/Resources/launch-tui.command" <<'LAUNCH'
#!/bin/zsh
root=${0:A:h}
export PATH="$root/runtime/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$HOME"
exec /bin/zsh "$root/toolbox/hub"
LAUNCH
    chmod +x "$content/Resources/launch-tui.command" "$content/MacOS/HubApp"
    /usr/bin/plutil -create xml1 "$content/Info.plist"
    /usr/bin/plutil -insert CFBundleExecutable -string HubApp "$content/Info.plist"
    /usr/bin/plutil -insert CFBundleIdentifier -string "io.shellcommandhub.$mode" "$content/Info.plist"
    /usr/bin/plutil -insert CFBundleName -string "$name" "$content/Info.plist"
    /usr/bin/plutil -insert CFBundleIconFile -string HubIcon.icns "$content/Info.plist"
    /usr/bin/plutil -insert CFBundlePackageType -string APPL "$content/Info.plist"
    /usr/bin/plutil -insert CFBundleShortVersionString -string "$version" "$content/Info.plist"
    /usr/bin/plutil -insert CFBundleVersion -string "$version" "$content/Info.plist"
    minimum=$({ printf '13.0\n'; for binary in "$content/Resources/runtime/bin/"* "$content/Resources/runtime/lib/"*; do /usr/bin/vtool -show-build "$binary" | awk '$1=="minos" {print $2}'; done; } | awk '{split($0,n,"."); value=n[1]*1000000+n[2]*1000+n[3]; if(value>maximum) {maximum=value; result=$0}} END {print result}')
    /usr/bin/plutil -insert LSMinimumSystemVersion -string "$minimum" "$content/Info.plist"
    /usr/bin/plutil -insert HubInterface -string "$mode" "$content/Info.plist"
    if [ -n "${HUB_UPDATE_URL:-}" ]; then /usr/bin/plutil -insert HubUpdateURL -string "$HUB_UPDATE_URL" "$content/Info.plist"; fi
    /usr/bin/codesign "${sign_args[@]}" "$app"
    "$content/MacOS/HubApp" --self-test
    /usr/bin/codesign --verify --deep --strict "$app"
    /usr/bin/ditto -c -k --keepParent "$app" "$work/$name-$version-$arch.zip"
    if [ -e "$OUT/$name.app" ]; then mv "$OUT/$name.app" "$work/previous-$mode.app"; fi
    mv "$app" "$OUT/$name.app"
    mv -f "$work/$name-$version-$arch.zip" "$OUT/$name-$version-$arch.zip"
    printf 'Built: %s\n' "$OUT/$name.app"
done
cp "$work/HubIcon.png" "$OUT/HubIcon.png"
