#!/bin/zsh
emulate -R zsh
setopt errexit pipefail
ROOT=${0:A:h:h}
work=$(mktemp -d "${TMPDIR:-/tmp}/shell-hub-tests.XXXXXX")
checks=0
cleanup() {
  # Only remove fixtures owned by this run.
  find "$work" -type f -delete
  find "$work" -type l -delete
  find "$work" -depth -type d -delete
}
trap cleanup EXIT
fail() { print -ru2 -- "FAIL: $*"; exit 1; }
check() { checks=$((checks+1)); "$@" || fail "$*"; }
contains() { [[ $1 == *"$2"* ]]; }
expect_code() {
  local expected=$1; shift
  local code=0
  "$@" > "$work/output" 2>&1 || code=$?
  [[ $code == $expected ]] || { cat "$work/output"; fail "expected $expected, got $code: $*"; }
}
make_wave() {
  printf 'RIFF\x64\x06\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x40\x1f\x00\x00\x80\x3e\x00\x00\x02\x00\x10\x00data\x40\x06\x00\x00' > "$1"
  dd if=/dev/zero bs=1600 count=1 >> "$1" 2>/dev/null
}
check expect_code 0 "$ROOT/hub" --help
check expect_code 0 "$ROOT/hub" list 压缩
check contains "$(cat "$work/output")" zip-tidy
check expect_code 2 "$ROOT/hub" run unknown
check expect_code 2 "$ROOT/hub"
check test "$("$ROOT/hub" list | awk '{print $1}')" = $'media-info\nzip-tidy\nport-info'
check test -z "$("$ROOT/hub" list 命令手册)"
for id in media-info zip-tidy port-info; do
  check expect_code 0 "$ROOT/hub" show "$id"
done
# Product startup and doctor must run with only a declared list of native commands.
mkdir "$work/native"
for name in awk cat cp cmp date dirname find grep mkdir mktemp mv rm rmdir stty tr uname unlink wc ps lsof sleep tail fzf; do
  ln -s "$(command -v "$name")" "$work/native/$name"
done
if command -v mediainfo >/dev/null 2>&1; then ln -s "$(command -v mediainfo)" "$work/native/mediainfo"; fi
check expect_code 0 /usr/bin/env PATH="$work/native" "$ROOT/hub" list
check expect_code 0 /usr/bin/env PATH="$work/native" "$ROOT/hub" doctor
check expect_code 0 /usr/bin/env PATH="$work/native" "$ROOT/hub" run media-info --help
check expect_code 2 "$ROOT/hub" tui media-info
check expect_code 2 "$ROOT/hub" tui zip-tidy
check expect_code 2 "$ROOT/hub" tui port-info
check expect_code 2 "$ROOT/hub" run port-info 65536
check expect_code 0 "$ROOT/hub" run port-info --help
check expect_code 2 "$ROOT/hub" run port-info --stop
check expect_code 0 /bin/zsh -f -c 'source "$1/lib/tool-tui.zsh"; printf "1\tname.WAV\n2\tbroken.mp4\n" | hub_tool_fzf --filter=WAV' -- "$ROOT"
check contains "$(cat "$work/output")" name.WAV
mkdir "$work/no-fzf"
for executable in "$work/native"/*; do
  [[ ${executable:t} == fzf ]] || ln -s "$executable" "$work/no-fzf/${executable:t}"
done
check expect_code 0 /usr/bin/env PATH="$work/no-fzf" "$ROOT/hub" list
check expect_code 0 /usr/bin/env PATH="$work/no-fzf" "$ROOT/hub" show port-info
check expect_code 0 /usr/bin/env PATH="$work/no-fzf" "$ROOT/hub" tui vinfo --help
check expect_code 0 /usr/bin/env PATH="$work/no-fzf" "$ROOT/hub" run port-info 65535
check expect_code 1 /usr/bin/env PATH="$work/no-fzf" "$ROOT/hub" doctor
check contains "$(cat "$work/output")" '缺少 fzf'
rc="$work/.zshrc"
original=$'alias keep="printf preserved"\nalias vinfo="/old/tool"\n# example: # >>> shell-command-hub >>>\n'
print -rn -- "$original" > "$rc"
chmod 600 "$rc"
check expect_code 0 "$ROOT/hub" install --rc "$rc"
check test "$(stat -f %Lp "$rc")" = 600
cp "$rc" "$work/installed"
check expect_code 0 "$ROOT/hub" install --rc "$rc"
check cmp -s "$rc" "$work/installed"
check expect_code 0 /bin/zsh -f -c 'source "$1"; eval "vinfo --help"' -- "$rc"
check expect_code 0 /bin/zsh -f -c 'set -e; source "$1"; cd "$2"; alias hub zidy vinfo pinfo >/dev/null; eval "hub list"' -- "$rc" "$ROOT/lib"
check expect_code 0 /bin/zsh -f -c 'source "$1"; alias tidy="${(q)SHELL_COMMAND_HUB}/hub run zip-tidy"; source "$1"; ! alias tidy >/dev/null 2>&1 && eval "zidy --help"' -- "$rc"
check expect_code 0 /bin/zsh -f -c 'alias tidy="sh $HOME/Sites/zip-tidy.sh"; source "$1"; ! alias tidy >/dev/null 2>&1 && [[ $(whence -p tidy) == /usr/bin/tidy ]]' -- "$rc"
check expect_code 0 /bin/zsh -f -c 'alias tidy="printf custom"; source "$1"; [[ ${aliases[tidy]} == "printf custom" ]]' -- "$rc"
check expect_code 0 "$ROOT/hub" uninstall --rc "$rc"
print -rn -- "$original" > "$work/original"
check cmp -s "$rc" "$work/original"
print -r -- '# >>> shell-command-hub >>>' > "$rc"
cp "$rc" "$work/bad"
check expect_code 2 "$ROOT/hub" install --rc "$rc"
check cmp -s "$rc" "$work/bad"
copy="$work/hub '中文 space"
mkdir "$copy"
cp -R "$ROOT/lib" "$ROOT/tools" "$ROOT/docs" "$ROOT/hub" "$ROOT/catalog.tsv" "$copy/"
print -rn -- "$original" > "$rc"
check expect_code 0 "$copy/hub" install --rc "$rc"
check expect_code 0 /bin/zsh -f -c 'source "$1"; eval "vinfo --help"; eval "zidy --help"' -- "$rc"
mv "$copy" "$work/moved hub"
check expect_code 0 "$work/moved hub/hub" install --rc "$rc"
check expect_code 0 /bin/zsh -f -c 'set -e; source "$1"; eval "vinfo --help"; eval "zidy --help"' -- "$rc"
media="$work/音频 \" \$(touch OWNED)"
mkdir -p "$media/nested"
make_wave "$media/音频 \" \$(touch OWNED).WAV"
make_wave "$media/nested/second.wav"
ln -s "$media/nested/second.wav" "$media/linked.wav"
check expect_code 0 /usr/bin/env PATH="$work/native" "$ROOT/hub" run media-info "$media"
check contains "$(cat "$work/output")" '1 个媒体文件'
check contains "$(cat "$work/output")" '8000 Hz'
check expect_code 0 /usr/bin/env PATH="$work/native" "$ROOT/hub" run media-info -t "$media"
check contains "$(cat "$work/output")" '2 个媒体文件'
check test ! -e "$ROOT/OWNED"
print -r -- broken > "$media/broken.mp4"
check expect_code 1 "$ROOT/hub" run media-info "$media"
check expect_code 2 "$ROOT/hub" run media-info "$media/missing"
archive="$work/解压 目录"
mkdir -p "$archive/download.zip" "$work/source" "$work/outside"
print -r -- data > "$work/source/测试.txt"
(cd "$work/source" && /usr/bin/zip -q "$archive/download.zip/[作者] 作品 [AI Generated].ZIP" 测试.txt)
print -r -- residual > "$archive/download.zip/test.torrent"
(cd "$work/source" && /usr/bin/zip -q "$work/outside/untouched.zip" 测试.txt)
ln -s "$work/outside" "$archive/linked"
check expect_code 0 "$ROOT/hub" run zip-tidy "$archive"
check test -f "$archive/作品/测试.txt"
check test ! -e "$archive/download.zip"
check test -f "$work/outside/untouched.zip"
mkdir "$archive/existing"
(cd "$work/source" && /usr/bin/zip -q "$archive/existing.zip" 测试.txt)
print -r -- invalid > "$archive/corrupt.zip"
check expect_code 1 "$ROOT/hub" run zip-tidy "$archive"
check test -f "$archive/existing.zip"
check test -f "$archive/corrupt.zip"
check test ! -e "$archive/corrupt"
mkdir "$work/empty zip" "$work/empty zip/[作者] 已有目录 [AI Generated]"
check expect_code 0 "$ROOT/hub" run zip-tidy "$work/empty zip"
check test -d "$work/empty zip/已有目录"
# Remove only diagnostic files whose path is emitted by this test-owned ZIP invocation.
log=$(sed -n 's/.*错误日志：\(\/tmp\/mac-unzip\.[^ ]*\/errors.log\).*/\1/p' "$work/output" | tail -1)
if [[ $log == /tmp/mac-unzip.*/errors.log && -f $log ]]; then
  unlink "$log"
  [[ ! -f ${log:h}/archives.list ]] || unlink "${log:h}/archives.list"
  rmdir "${log:h}"
fi
if [[ -x /usr/bin/expect ]]; then
  mkdir "$work/tui archive"
  (cd "$work/source" && /usr/bin/zip -q "$work/tui archive/batch.zip" 测试.txt)
  check /usr/bin/expect "$ROOT/tests/test_tui.exp" "$ROOT" "$work/native" "$media" "$work/tui archive"
  check /usr/bin/expect "$ROOT/tests/test_tui_errors.exp" "$ROOT" "$work/no-fzf" "$work"
fi
check test -z "$(find "$ROOT" -type f -name '*.py' -print)"
print -r -- "PASS: $checks checks (native Shell only)"
