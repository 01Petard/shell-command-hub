#!/bin/bash
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
kind=$1
work=$2
item=${3:-0}
case "$item" in ''|*[!0-9]*) exit 2 ;; esac

if [ "$kind" = log ]; then
    lines=${FZF_PREVIEW_LINES:-20}
    case "$lines" in ''|*[!0-9]*) lines=20 ;; esac
    lines=$((lines - 3))
    [ "$lines" -ge 1 ] || lines=1
    while :; do
        # fzf supports clearing partial previews; keep the newest log lines visible.
        printf '\033[2J'
        if [ -f "$work/result" ]; then
            printf '任务结束，退出码：%s。Enter 查看结果。\n\n' "$(cat "$work/result")"
        else
            printf '正在执行 ZIP 整理… Esc 中断。\n\n'
        fi
        tail -n "$lines" "$work/run.log" | LC_ALL=C awk '{gsub(/[[:cntrl:]]/, " "); print; fflush()}'
        [ ! -f "$work/result" ] || exit 0
        sleep 0.2
    done
fi

preview() {
    local file name cache temp
    case "$kind" in
        media)
            [ "$item" != 0 ] || { printf '未找到媒体文件。Ctrl+O 切换目录，Ctrl+T 切换递归。\n'; return; }
            IFS= read -r -d '' file < "$work/$item.path" || return 2
            cache="$work/$item.info"
            if [ ! -f "$cache" ]; then
                temp="$cache.$$.tmp"
                preview_temp=$temp
                trap 'rm -f "$preview_temp"' EXIT
                source "$ROOT/tools/media/videoinfo_beauty.sh"
                media_inspect "$file" > "$temp" 2>&1
                mv -f "$temp" "$cache"
            fi
            cat "$cache"
            ;;
        archive)
            IFS= read -r -d '' file < "$work/root.path" || return 2
            printf '整理目录：%s\n\n' "$file"
            if [ "$item" != 0 ]; then
                local root=$file
                IFS= read -r -d '' file < "$work/$item.path" || return 2
                name=${file##*/}
                printf 'ZIP：%s\n预计解压位置：%s/%s\n\n' "$file" "$root" "${name%.*}"
            fi
            printf '%s\n' 'Ctrl+X 执行整个目录，不只处理当前选中 ZIP。' \
                '扫描两层 ZIP；成功解压后删除原包，失败保留。' \
                '同时清理已识别包装残留，并整理已有目录名称。' \
                '目标存在时跳过；不跟随子目录符号链接。' \
                '即使没有 ZIP，仍可执行已有目录整理。'
            ;;
        port)
            [ "$item" != 0 ] || { printf '没有匹配的端口占用。Ctrl+R 刷新，Ctrl+U 切换 TCP/UDP。\n'; return; }
            source "$ROOT/tools/network/port-info.sh"
            port_detail "$work/$item.port"
            ;;
    esac
}
# Paths and process names are data, never terminal escape sequences.
preview | LC_ALL=C awk '{gsub(/[[:cntrl:]]/, " "); print; fflush()}'
