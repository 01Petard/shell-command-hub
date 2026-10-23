#!/bin/bash
# macOS 专用；可通过 bash zip-tidy.sh 或 zsh zip-tidy.sh 运行。
# 仅处理输入目录内深度 1、2 的 ZIP，不跟随子目录符号链接。

# EXIT trap 在 zsh 中执行时，函数的局部变量已退出作用域。
stage=''
run_dir=''
list=''
log=''
extract_pid=''

stop_extraction() {
    # Reap the active child before removing its staging directory.
    if [ -n "$extract_pid" ]; then
        kill -TERM "$extract_pid" 2>/dev/null || :
        kill -CONT "$extract_pid" 2>/dev/null || :
        wait "$extract_pid" 2>/dev/null || :
        extract_pid=''
    fi
}

main() {
    local root archive parent name target wrapper child leftover basename known retained candidate new_name
    local total=0 current=0 success=0 skipped=0 failed=0 started elapsed entry
    local moved=0 cleaned=0 renamed=0 directories_scanned=0
    local green='' yellow='' red='' cyan='' reset=''
    local -a archives issues wrappers directories
    archives=()
    issues=()
    wrappers=()
    directories=()

    if [ "$(/usr/bin/uname -s)" != Darwin ]; then
        printf '错误：此脚本仅支持 macOS。\n' >&2
        exit 2
    fi
    if [ "$#" -gt 1 ]; then
        printf '用法：zip-tidy.sh [目录路径]；使用 -h 或 --help 查看帮助。\n' >&2
        return 2
    fi
    case "${1-}" in
        -h|--help)
            /bin/cat <<'HELP'
用法：zip-tidy.sh <目录路径>
           （处理指定目录中的 ZIP 文件）
   或 zip-tidy.sh
           （提示输入待处理目录的路径）
   或 zip-tidy.sh -h
      zip-tidy.sh --help
           （显示此帮助信息并退出）

参数：
    <目录路径>
                  要处理的目录。命令行路径包含空格时，请用引号包裹；
                  在交互提示中输入路径时，无需加引号。
    -h, --help
                  显示帮助信息。

处理规则：
    扫描范围      输入目录及其直接子目录中的 ZIP 文件，扩展名不区分大小写。
                  不跟随子目录的符号链接，不递归处理新解压出的 ZIP。
    解压与删除    解压到输入目录下与 ZIP 同名的文件夹，成功后删除原 ZIP。
                  目标已存在时跳过；解压失败时保留 ZIP，继续处理其他文件。
    包装目录清理  下载包装目录只剩 .torrent、.js、.DS_Store 时，
                  连同残留一起删除；有未处理内容时保留。
                  旧的 xxxx.zip 目录内若有同名解压目录，会尝试移至输入目录。
    目录改名      去掉目录名开头的“[作者] ”及末尾的“ [AI Generated]”。
                  例如：[作者] 作品 [AI Generated] → 作品。
                  同样处理已有目录；未完成的包装目录保留原名，重名时跳过。
    完成输出      显示执行统计，并统一列出输入目录下所有一级文件夹的最终名称。
                  每行一个名称，无文件夹时显示提示。

示例：
    bash zip-tidy.sh "$HOME/Downloads"
    bash zip-tidy.sh "/Volumes/Data/待解压文件"
    zsh zip-tidy.sh --help

退出码：
    0             全部成功，或没有需要处理的文件。
    1             有失败或跳过的项目。
    2             参数无效，或初始扫描失败。
    130           用户中断（Ctrl+C）。
    143           收到终止信号（SIGTERM）。

运行环境：macOS；支持使用 Bash 或 Zsh 运行。
HELP
            return 0
            ;;
    esac
    root=${1-}
    if [ "$#" -eq 0 ]; then
        printf '请输入待处理目录的路径（无需加引号，可含空格）：'
        IFS= read -r root || return 2
    fi
    if [ -z "$root" ] || [ ! -d "$root" ]; then
        printf '错误：不是有效目录：%s\n' "$root" >&2
        return 2
    fi
    # 统一为绝对路径，避免以短横线开头的路径被工具当作选项。
    root=$(cd -- "$root" && pwd -P) || return 2
    if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then
        green=$(printf '\033[32m')
        yellow=$(printf '\033[33m')
        red=$(printf '\033[31m')
        cyan=$(printf '\033[36m')
        reset=$(printf '\033[0m')
    fi
    started=$(/bin/date +%s)
    run_dir=$(/usr/bin/mktemp -d /tmp/mac-unzip.XXXXXX) || return 2
    list="$run_dir/archives.list"
    log="$run_dir/errors.log"
    # 中断时清理尚未发布的解压目录；原 ZIP 保留，已有错误日志保留。
    trap '[ -z "$stage" ] || /bin/rm -rf -- "$stage"; /bin/rm -f -- "$list"; if [ ! -s "$log" ]; then /bin/rm -rf -- "$run_dir"; fi' EXIT
    trap 'stop_extraction; printf "\n已中断，未完成的 ZIP 将保留。\n错误日志：%s\n" "$log" >&2; exit 130' INT
    trap 'stop_extraction; printf "\n已终止，未完成的 ZIP 将保留。\n错误日志：%s\n" "$log" >&2; exit 143' TERM
    trap 'stop_extraction; printf "\n终端已关闭，未完成的 ZIP 将保留。\n错误日志：%s\n" "$log" >&2; exit 129' HUP

    printf '\n%sZIP 批量解压%s\n目录：%s\n范围：两层文件\n\n' "$cyan" "$reset" "$root"
    # 先固定文件清单，避免新解压的 ZIP 在本轮再次被处理；NUL 分隔支持特殊文件名。
    if ! /usr/bin/find "$root" -maxdepth 2 -type f -iname '*.zip' -print0 > "$list" 2> "$log"; then
        printf '%s扫描失败%s，未开始解压。\n' "$red" "$reset" >&2
        /bin/cat "$log" >&2
        printf '错误日志：%s\n' "$log" >&2
        exit 2
    fi
    while IFS= read -r -d '' archive; do
        archives+=("$archive")
        parent=${archive%/*}
        if [ "$parent" != "$root" ]; then
            known=0
            for candidate in "${wrappers[@]}"; do
                [ "$candidate" != "$parent" ] || known=1
            done
            [ "$known" -eq 1 ] || wrappers+=("$parent")
        fi
    done < "$list"
    # 已解压的旧包装目录没有 ZIP 文件，需要单独识别以便重跑修复。
    if ! /usr/bin/find "$root" -mindepth 1 -maxdepth 1 -type d -iname '*.zip' -print0 > "$list" 2>> "$log"; then
        printf '扫描包装目录失败，未开始解压。错误日志：%s\n' "$log" >&2
        exit 2
    fi
    while IFS= read -r -d '' wrapper; do
        known=0
        for candidate in "${wrappers[@]}"; do
            [ "$candidate" != "$wrapper" ] || known=1
        done
        [ "$known" -eq 1 ] || wrappers+=("$wrapper")
    done < "$list"
    total=${#archives[@]}
    printf '找到 %s 个 ZIP。\n\n' "$total"

    for archive in "${archives[@]}"; do
        current=$((current + 1))
        parent=${archive%/*}
        name=${archive##*/}
        name=${name%.*}
        target="$root/$name"
        printf '[%s/%s] %s\n' "$current" "$total" "$archive"
        if [ -z "$name" ] || [ -e "$target" ] || [ -L "$target" ]; then
            skipped=$((skipped + 1))
            issues+=("跳过：${archive}（目标已存在或压缩包名称为空）")
            printf '%s  跳过%s：目标已存在或压缩包名称为空，ZIP 已保留。\n\n' "$yellow" "$reset"
            continue
        fi
        printf '\n文件：%s\n目标：%s\n' "$archive" "$target" >> "$log"
        stage=$(/usr/bin/mktemp -d "$root/.mac-unzip.XXXXXX" 2>> "$log")
        if [ -z "$stage" ]; then
            failed=$((failed + 1))
            issues+=("失败：${archive}（无法创建临时解压目录）")
            printf '%s  失败%s：无法创建临时目录，ZIP 已保留。\n\n' "$red" "$reset"
            continue
        fi
        printf '  正在解压…\n'
        /usr/bin/ditto -x -k "$archive" "$stage" >> "$log" 2>&1 &
        extract_pid=$!
        if ! wait "$extract_pid"; then
            extract_pid=''
            failed=$((failed + 1))
            issues+=("失败：${archive}（解压错误）")
            printf '%s  失败%s：解压错误，ZIP 已保留。\n\n' "$red" "$reset"
            /bin/rm -rf -- "$stage"
            stage=''
            continue
        fi
        extract_pid=''
        if [ -e "$target" ] || [ -L "$target" ] || ! /bin/mv -n -- "$stage" "$target" 2>> "$log" || [ -d "$stage" ]; then
            failed=$((failed + 1))
            issues+=("失败：${archive}（无法保存解压目录）")
            printf '%s  失败%s：无法保存解压目录，ZIP 已保留。\n\n' "$red" "$reset"
            /bin/rm -rf -- "$stage"
            stage=''
            continue
        fi
        stage=''
        if ! /bin/rm -- "$archive" 2>> "$log"; then
            failed=$((failed + 1))
            issues+=("失败：${archive}（解压完成，但原 ZIP 删除失败）")
            printf '%s  失败%s：解压完成，但原 ZIP 删除失败。\n\n' "$red" "$reset"
            continue
        fi
        success=$((success + 1))
        printf '%s  成功%s → %s（原 ZIP 已删除）\n\n' "$green" "$reset" "$target"
    done

    for wrapper in "${wrappers[@]}"; do
        [ -d "$wrapper" ] && [ ! -L "$wrapper" ] || continue
        name=${wrapper##*/}
        child=''
        case "$name" in
            *.[zZ][iI][pP]) child="$wrapper/${name%.*}" ;;
        esac
        # 只清理已识别的下载残留；未完成的 ZIP、其他目录或文件会阻止清理。
        retained=0
        if ! /usr/bin/find "$wrapper" -mindepth 1 -maxdepth 1 -print0 > "$list" 2>> "$log"; then
            failed=$((failed + 1))
            issues+=("失败：${wrapper}（无法检查残留内容）")
            continue
        fi
        while IFS= read -r -d '' leftover; do
            if [ -n "$child" ] && [ "$leftover" = "$child" ] && [ -d "$child" ] && [ ! -L "$child" ]; then
                continue
            fi
            basename=${leftover##*/}
            if [ -f "$leftover" ] && [ ! -L "$leftover" ]; then
                case "$basename" in
                    *.[tT][oO][rR][rR][eE][nN][tT]|*.[jJ][sS]|.DS_Store) continue ;;
                esac
            fi
            retained=1
        done < "$list"
        if [ "$retained" -eq 1 ]; then
            skipped=$((skipped + 1))
            issues+=("保留：${wrapper}（有未处理的 ZIP 或其他内容）")
            printf '%s保留包装目录%s：%s（有未处理内容）\n' "$yellow" "$reset" "$wrapper"
            continue
        fi
        if [ -n "$child" ] && [ -d "$child" ]; then
            target="$root/${name%.*}"
            if [ -e "$target" ] || [ -L "$target" ]; then
                skipped=$((skipped + 1))
                issues+=("跳过整理：${wrapper}（目标已存在）")
                printf '%s跳过整理%s：%s（目标已存在）\n' "$yellow" "$reset" "$wrapper"
                continue
            fi
            if ! /bin/mv -n -- "$child" "$target" 2>> "$log" || [ -e "$child" ]; then
                failed=$((failed + 1))
                issues+=("失败：${wrapper}（无法移出已解压目录）")
                continue
            fi
            moved=$((moved + 1))
            printf '%s已移出%s → %s\n' "$green" "$reset" "$target"
        fi
        if ! /bin/rm -rf -- "$wrapper" 2>> "$log"; then
            failed=$((failed + 1))
            issues+=("失败：${wrapper}（包装目录清理失败）")
            continue
        fi
        cleaned=$((cleaned + 1))
        printf '%s已清理包装目录%s：%s\n' "$green" "$reset" "$wrapper"
    done

    # 在解压和包装清理后统一改名，兼容此前已经成功完成的目录。
    if ! /usr/bin/find "$root" -mindepth 1 -maxdepth 1 -type d -print0 > "$list" 2>> "$log"; then
        failed=$((failed + 1))
        issues+=("失败：${root}（无法扫描改名目录）")
    else
        while IFS= read -r -d '' candidate; do
            name=${candidate##*/}
            case "$name" in
                *.[zZ][iI][pP]|.mac-unzip.*) continue ;;
            esac
            known=0
            for wrapper in "${wrappers[@]}"; do
                [ "$candidate" != "$wrapper" ] || known=1
            done
            # 解压失败、跳过或原包删除失败的目标不计入成功结果。
            for archive in "${archives[@]}"; do
                if [ -f "$archive" ]; then
                    basename=${archive##*/}
                    [ "$name" != "${basename%.*}" ] || known=1
                fi
            done
            [ "$known" -eq 0 ] || continue
            new_name=$name
            case "$new_name" in
                \[*\]\ *) new_name=${new_name#*\] } ;;
            esac
            case "$new_name" in
                *' [AI Generated]') new_name=${new_name%' [AI Generated]'} ;;
            esac
            [ "$new_name" != "$name" ] || continue
            case "$new_name" in
                ''|.|..)
                    skipped=$((skipped + 1))
                    issues+=("跳过改名：${candidate}（去除标签后名称无效）")
                    printf '%s跳过改名%s：%s（新名称无效）\n' "$yellow" "$reset" "$candidate"
                    continue
                    ;;
            esac
            target="$root/$new_name"
            if [ -e "$target" ] || [ -L "$target" ]; then
                skipped=$((skipped + 1))
                issues+=("跳过改名：${candidate}（目标已存在：${new_name}）")
                printf '%s跳过改名%s：%s（目标已存在：%s）\n' "$yellow" "$reset" "$name" "$new_name"
                continue
            fi
            if ! /bin/mv -n -- "$candidate" "$target" 2>> "$log" || [ -e "$candidate" ]; then
                failed=$((failed + 1))
                issues+=("失败：${candidate}（目录改名失败）")
                printf '%s改名失败%s：%s\n' "$red" "$reset" "$candidate"
                continue
            fi
            renamed=$((renamed + 1))
            printf '%s已改名%s：%s → %s\n' "$green" "$reset" "$name" "$new_name"
        done < "$list"
    fi

    if ! /usr/bin/find "$root" -mindepth 1 -maxdepth 1 -type d -print0 > "$list" 2>> "$log"; then
        failed=$((failed + 1))
        issues+=("失败：${root}（无法扫描最终文件夹清单）")
    else
        directories_scanned=1
        while IFS= read -r -d '' candidate; do
            directories+=("${candidate##*/}")
        done < "$list"
    fi

    elapsed=$(( $(/bin/date +%s) - started ))
    printf '%s执行结果%s\n总数：%s  成功：%s  跳过：%s  失败：%s  耗时：%s 秒\n' \
        "$cyan" "$reset" "$total" "$success" "$skipped" "$failed" "$elapsed"
    printf '旧结果移出：%s  包装目录清理：%s  目录改名：%s\n' "$moved" "$cleaned" "$renamed"
    if [ "${#issues[@]}" -gt 0 ]; then
        printf '\n待处理文件（含所在目录）：\n'
        for entry in "${issues[@]}"; do
            printf '  • %s\n' "$entry"
        done
    fi
    if [ "$failed" -gt 0 ]; then
        printf '\n详细错误日志：%s\n' "$log"
    else
        /bin/rm -f -- "$log"
    fi
    printf '\n输入目录下的文件夹名称：\n'
    if [ "$directories_scanned" -eq 0 ]; then
        printf '（扫描失败，请查看上方错误日志）\n'
    elif [ "${#directories[@]}" -eq 0 ]; then
        printf '（无文件夹）\n'
    else
        for entry in "${directories[@]}"; do
            printf '%s\n' "$entry"
        done
    fi
    if [ "$failed" -eq 0 ] && [ "$skipped" -eq 0 ]; then
        exit 0
    fi
    exit 1
}

main "$@"
exit $?
