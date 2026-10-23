#!/bin/bash
# MediaInfo raw identifiers keep parsing independent of display language.
media_scan() {
    local extension
    local -a find_args extensions
    extensions=(mov mp4 avi mkv flv wmv mpeg mpg m4v 3gp webm mp3 wav flac aac ogg m4a wma)
    find_args=("$1")
    [ "$2" -eq 1 ] || find_args+=(-maxdepth 1)
    find_args+=(-type f '(')
    for extension in "${extensions[@]}"; do find_args+=(-iname "*.$extension" -o); done
    unset 'find_args[${#find_args[@]}-1]'
    find "${find_args[@]}" ')' -print0
}

media_inspect() {
    local file=$1 info
    info=$(mediainfo --Language=raw "$file") || { printf '无法分析：%s\n' "$file" >&2; return 1; }
    if ! printf '%s\n' "$info" | grep -Eq '^(Video|Audio)( #[0-9]+)?$'; then
        printf '无法分析：%s\n' "$file" >&2; return 1
    fi
    printf '┌─ %s\n│ 完整路径：%s\n│ 文件大小：%s bytes\n' "${file##*/}" "$file" "$(wc -c < "$file" | tr -d ' ')"
    printf '%s\n' "$info" | awk '
      /^(General|Video|Audio)( #[0-9]+)?$/ { active=1; printf "│ [%s]\n", $0; next }
      /^[A-Za-z]+( #[0-9]+)?$/ { active=0 }
      active && index($0, ":") {
        key=substr($0, 1, index($0, ":")-1); gsub(/[[:space:]]+$/, "", key)
        value=substr($0, index($0, ":")+1); sub(/^[[:space:]]+/, "", value)
        label=""
        if (key=="Format/String") label="格式"
        if (key=="Duration/String") label="时长"
        if (key=="OverallBitRate/String") label="总比特率"
        if (key=="Width/String") label="宽度"
        if (key=="Height/String") label="高度"
        if (key=="FrameRate/String") label="帧率"
        if (key=="BitRate/String") label="比特率"
        if (key=="Channel(s)/String") label="声道数"
        if (key=="SamplingRate/String") label="采样率"
        if (label!="") printf "│ %s：%s\n", label, value
      }
    '
    printf '%s\n' '└─'
}

media_main() {
    local recursive=0 directory=. seen_directory=0 root work file count=0 failures=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help) printf '%s\n' '用法：vinfo [-t|--recursive] [目录]' 'CLI：hub run media-info [-t|--recursive] [目录]'; return 0 ;;
            -t|--recursive) recursive=1 ;;
            --) shift; [ "$#" -eq 1 ] || { printf '参数错误\n' >&2; return 2; }; directory=$1; seen_directory=1 ;;
            -*) printf '未知参数：%s\n' "$1" >&2; return 2 ;;
            *) [ "$seen_directory" -eq 0 ] || { printf '只能指定一个目录\n' >&2; return 2; }; directory=$1; seen_directory=1 ;;
        esac
        shift
    done
    [ -d "$directory" ] || { printf '目录不存在：%s\n' "$directory" >&2; return 2; }
    command -v mediainfo >/dev/null 2>&1 || { printf '缺少 mediainfo：brew install mediainfo\n' >&2; return 2; }
    root=$(cd -- "$directory" && pwd -P) || return 2
    work=$(mktemp -d "${TMPDIR:-/tmp}/shell-media.XXXXXX") || return 2
    media_work=$work
    trap 'rm -rf "$media_work"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if ! media_scan "$root" "$recursive" > "$work/list"; then
        printf '扫描失败，未开始分析。\n' >&2; return 1
    fi
    printf '扫描目录：%s\n递归模式：%s\n' "$root" "$([ "$recursive" -eq 1 ] && printf 是 || printf 否)"
    while IFS= read -r -d '' file; do
        count=$((count + 1))
        media_inspect "$file" || failures=$((failures + 1))
    done < "$work/list"
    printf '分析完成：%s 个媒体文件，失败 %s 个。\n' "$count" "$failures"
    [ "$failures" -eq 0 ]
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -o pipefail
    media_main "$@"
    exit $?
fi
