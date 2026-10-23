# Tool views use fzf; the existing hub remains the launcher.
hub_tool_fzf() {
  FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null SHELL=/bin/bash command fzf \
    --layout=reverse --border --height=100% --no-multi --no-sort \
    --delimiter=$'\t' --with-nth=2.. \
    --bind='pgdn:preview-page-down,pgup:preview-page-up' \
    --preview-window='right,55%,wrap,<50(down,45%,wrap)' "$@"
}

hub_tool_text() {
  local title=$1 file=$2
  LC_ALL=C tr '\000-\010\013-\037\177' '?' < "$file" |
    FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null command fzf \
      --layout=reverse --border --height=100% --disabled --no-sort \
      --header="$title · ↑↓ 滚动 · Enter/Esc 返回" --bind='enter:abort' || :
}

hub_tool_confirm() {
  local title=$1 detail=$2 selected
  print -r -- "$detail" | LC_ALL=C tr '\000-\010\013-\037\177' '?' > "$tool_work/confirm"
  selected=$(printf 'cancel\t取消\nrun\t确认执行\n' | hub_tool_fzf --disabled \
    --header="$title · 默认取消" --preview="cat ${(q)tool_work}/confirm") || return 1
  [[ ${selected%%$'\t'*} == run ]]
}

hub_tool_directory() {
  local value
  printf '\n目录（留空保留 %s；输入 :cancel 取消）：' "${(V)directory}" > /dev/tty
  IFS= read -r value < /dev/tty || return 1
  [[ $value == :cancel ]] && return 1
  [[ -n $value ]] || value=$directory
  [[ $value == '~' ]] && value=$HOME
  [[ $value == '~/'* ]] && value="$HOME/${value#\~/}"
  [[ -d $value ]] || { notice='目录不存在，未切换。'; return 1; }
  directory=${value:A}
}

hub_tool_actions() {
  local kind=$1 selected key row
  {
    printf 'q\tq 返回\nr\tr 刷新\nd\td 查看详情/规则\n'
    [[ $kind != media ]] || printf 't\tt 切换递归\n'
    [[ $kind != archive ]] || printf 'x\tx 执行整个目录\n'
  } > "$tool_work/actions"
  selected=$(hub_tool_fzf --disabled --expect=q,r,d,t,x --header='操作菜单 · 按对应单键，或方向键 + Enter' < "$tool_work/actions") || return 1
  key=${selected%%$'\n'*}; row=${selected#*$'\n'}
  REPLY=${key:-${row%%$'\t'*}}
}

hub_tool_cell() {
  local value=$1 width=$2 char out='' used=0 cost
  for char in "${(@s::)value}"; do
    [[ $char == [\ -\~] ]] && cost=1 || cost=2
    ((used+cost <= width)) || break
    out+=$char; ((used+=cost))
  done
  printf '%s%*s' "$out" $((width-used)) ''
}

hub_zip_worker() {
  local child='' code
  trap 'if [[ -n $child ]]; then kill -TERM "$child" 2>/dev/null; wait "$child" 2>/dev/null; fi; print -r -- 143 > "$2/result"; exit 143' TERM INT HUP
  NO_COLOR=1 /bin/bash "$HUB_ROOT/tools/archive/zip-tidy.sh" "$1" > "$2/run.log" 2>&1 &
  child=$!
  wait "$child"; code=$?
  printf '\n任务结束，退出码：%s。Enter 返回查看结果。\n' "$code" >> "$2/run.log"
  print -r -- "$code" > "$2/result"
}

hub_tool_zip_run() {
  local selected code
  hub_tool_confirm '确认 ZIP 整目录处理' "目录：$directory
将处理整个目录的两层 ZIP，成功后删除原包，并清理包装残留、整理已有目录名。
取消不会修改文件；执行中断仅保留未完成项目，已完成项目不回滚。" || return
  rm -f -- "$tool_work/result"
  : > "$tool_work/run.log"
  hub_zip_worker "$directory" "$tool_work" &
  tool_worker=$!
  while true; do
    selected=$(printf 'view\t查看执行日志（完成后 Enter 返回）\nstop\t中止并返回\n' |
      hub_tool_fzf --disabled --header='ZIP 执行进度 · 预览实时更新 · Esc 中断 · 已完成项目不回滚' \
      --preview-window='right,75%,wrap,follow,<80(down,70%,wrap,follow)' \
      --preview="/bin/bash ${(q)HUB_ROOT}/lib/tool-preview.sh log ${(q)tool_work} 0")
    code=$?
    if [[ -f "$tool_work/result" ]]; then
      wait "$tool_worker" 2>/dev/null || :
      tool_worker=''
      code=$(<"$tool_work/result")
      notice="ZIP 执行结束，退出码 $code。"
      hub_tool_text "$notice" "$tool_work/run.log"
      return 0
    fi
    if ((code != 0)) || [[ ${selected%%$'\t'*} == stop ]]; then
      kill -TERM "$tool_worker" 2>/dev/null || :
      wait "$tool_worker" 2>/dev/null || :
      tool_worker=''
      notice='已中断，未完成 ZIP 已保留，已完成项目不回滚。'
      hub_tool_text "$notice" "$tool_work/run.log"
      return 0
    fi
  done
}

hub_tool_files() {
  local id=$1 directory=$2 recursive=$3 notice='' file label selected key row item index code query='' rest destination
  local kind=media title='媒体信息 · vinfo'
  [[ $id == zip-tidy ]] && { kind=archive; title='解压整理 · zidy'; }
  while true; do
    rm -f -- "$tool_work"/*(N)
    printf '%s\0' "$directory" > "$tool_work/root.path"
    if [[ $kind == media ]]; then
      /bin/bash -c 'source "$1"; media_scan "$2" "$3"' _ "$HUB_ROOT/tools/media/videoinfo_beauty.sh" "$directory" "$recursive" > "$tool_work/paths" 2> "$tool_work/error"
    else
      find "$directory" -maxdepth 2 -type f -iname '*.zip' -print0 > "$tool_work/paths" 2> "$tool_work/error"
    fi
    code=$?
    if ((code != 0)); then hub_tool_text '扫描失败，未执行任何操作' "$tool_work/error"; return 1; fi
    index=0; : > "$tool_work/items"
    while IFS= read -r -d $'\0' file; do
      ((index++)); printf '%s\0' "$file" > "$tool_work/$index.path"
      label=${file#"$directory"/}; label=${label//[[:cntrl:]]/ }
      printf '%s\t%s\n' "$index" "$label" >> "$tool_work/items"
    done < "$tool_work/paths"
    if ((index == 0)); then
      [[ $kind == media ]] && label='（未找到媒体文件）' || label='（没有 ZIP，仍可整理已有目录）'
      printf '0\t%s\n' "$label" > "$tool_work/items"
    fi
    while true; do
      selected=$(hub_tool_fzf --print-query --query="$query" --bind='enter:accept-or-print-query' --prompt='路径或文件名 > ' --header="$title
目录：${(V)directory} · $index 项 · 递归 $recursive
输入路径 + Enter 切换目录 · Tab 操作菜单 · PgUp/PgDn 预览 · Esc 返回
$notice" --expect=tab \
        --preview="/bin/bash ${(q)HUB_ROOT}/lib/tool-preview.sh $kind ${(q)tool_work} {1}" < "$tool_work/items")
      code=$?
      ((code == 0 || code == 1)) || return 0
      query=${selected%%$'\n'*}; rest=${selected#*$'\n'}
      key=${rest%%$'\n'*}; row=${rest#*$'\n'}; item=${row%%$'\t'*}
      if [[ $key == tab ]]; then
        hub_tool_actions "$kind" || continue
        case $REPLY in
          r) query=''; break ;;
          t) [[ $kind == media ]] && { recursive=$((1-recursive)); query=''; break; } ;;
          x) [[ $kind == archive ]] && { hub_tool_zip_run; query=''; break; } ;;
          d) ;;
          *) continue ;;
        esac
      else
        destination=$query
        [[ $destination == '~' ]] && destination=$HOME
        [[ $destination == '~/'* ]] && destination="$HOME/${destination#\~/}"
        [[ $destination == /* ]] || destination="$directory/$destination"
        if [[ -n $query && -d $destination ]]; then
          directory=${destination:A}; query=''; notice='已切换目录。'; break
        fi
        if [[ -n $query && ( $query == */* || $query == '~'* || -z $item ) ]]; then
          notice='目录不存在，请输入有效路径后按 Enter。'; continue
        fi
      fi
      [[ $item == <-> ]] || continue
      /bin/bash "$HUB_ROOT/lib/tool-preview.sh" "$kind" "$tool_work" "$item" > "$tool_work/detail"
      hub_tool_text "$title" "$tool_work/detail"
    done
  done
}

hub_tool_ports() {
  local protocol=$1 filter=$2 notice='' selected key row item index pid user process addresses started code query rest selected_port
  local port_script="$HUB_ROOT/tools/network/port-info.sh"
  while true; do
    rm -f -- "$tool_work"/*(N)
    if ! /bin/bash "$port_script" --snapshot "$protocol" "$filter" > "$tool_work/rows" 2> "$tool_work/error"; then
      hub_tool_text '端口读取失败' "$tool_work/error"; return 2
    fi
    index=0
    {
      printf 'header\t'; hub_tool_cell '协议' 6; hub_tool_cell '端口' 8; hub_tool_cell 'PID' 10
      hub_tool_cell '进程' 24; hub_tool_cell '用户' 14; printf '本地地址\n'
    } > "$tool_work/items"
    while IFS= read -r row; do
      ((index++)); print -r -- "$row" > "$tool_work/$index.port"
      local -a fields=("${(@ps:\t:)row}")
      {
        printf '%s\t' "$index"
        hub_tool_cell "${fields[2]}" 6; hub_tool_cell "${fields[3]}" 8; hub_tool_cell "${fields[1]}" 10
        hub_tool_cell "${fields[5]}" 24; hub_tool_cell "${fields[4]}" 14; printf '%s\n' "${fields[6]}"
      } >> "$tool_work/items"
    done < "$tool_work/rows"
    ((index)) || printf '0\t（没有匹配的端口占用）\n' >> "$tool_work/items"
    selected=$(hub_tool_fzf --disabled --print-query --query="$filter" --prompt='精确端口 > ' --header-lines=1 \
      --header="端口管理 · pinfo · $protocol · 端口 ${filter:-全部}
输入端口 + Enter 精确查询（留空查询全部）
r 刷新 · u TCP/UDP · k 终止所选 · p 详情 · q/Esc 返回
$notice" --expect=r,u,k,q \
      --preview-window='default,down,35%,wrap,hidden' --bind='p:toggle-preview' \
      --preview="/bin/bash ${(q)HUB_ROOT}/lib/tool-preview.sh port ${(q)tool_work} {1}" < "$tool_work/items") || return 0
    query=${selected%%$'\n'*}; rest=${selected#*$'\n'}
    key=${rest%%$'\n'*}; row=${rest#*$'\n'}; item=${row%%$'\t'*}
    [[ $key != q ]] || return 0
    if [[ -n $query && ( $query != <1-65535> || ${#query} -gt 5 ) ]]; then notice='端口必须为 1–65535。'; continue; fi
    [[ -z $query ]] || query=$((10#$query))
    if [[ $key != k || $query != "$filter" ]]; then
      filter=$query
      [[ $key != u ]] || { [[ $protocol == TCP ]] && protocol=UDP || protocol=TCP; }
      notice='按本地端口精确查询。'; continue
    fi
    [[ $item == <1-> && -f "$tool_work/$item.port" ]] || continue
    IFS=$'\t' read -r pid protocol selected_port user process addresses started < "$tool_work/$item.port"
    hub_tool_confirm "终止 PID $pid · SIGTERM" "进程：$process
用户：$user
端口：$protocol $selected_port
地址：$addresses
启动时间：$started
将先发送 SIGTERM；不会终止进程组。" || continue
    /bin/bash "$port_script" --stop "$pid" "$started" "$protocol" "$selected_port" TERM > "$tool_work/result" 2>&1
    code=$?
    if ((code == 4)); then
      hub_tool_text 'SIGTERM 后进程仍在运行' "$tool_work/result"
      if hub_tool_confirm "强制终止 PID $pid · SIGKILL" "进程：$process
端口：$protocol $selected_port
将发送 SIGKILL（kill -9）。执行前会再次检查进程身份和端口归属。"; then
        /bin/bash "$port_script" --stop "$pid" "$started" "$protocol" "$selected_port" KILL > "$tool_work/result" 2>&1
      else
        print -r -- '已取消强杀。' >> "$tool_work/result"
      fi
    fi
    hub_tool_text '终止结果' "$tool_work/result"
    notice='已刷新端口列表。'
  done
}

hub_tool_tui() {
  emulate -L zsh
  setopt localtraps
  local id=$1; shift
  local directory=$PWD recursive=0 protocol=TCP filter='' seen=0 arg tool_work tool_worker='' saved_terminal
  for arg in "$@"; do
    if [[ $arg == -h || $arg == --help ]]; then hub_run "$id" --help; return $?; fi
  done
  [[ -t 0 && -t 1 ]] || { print -ru2 -- "TUI 需要交互终端；非交互调用请使用 hub run $id。"; return 2; }
  command -v fzf >/dev/null 2>&1 || { print -ru2 -- '缺少 fzf：brew install fzf；普通 CLI 请使用 hub run。'; return 2; }
  if ! hub_problems "$id"; then print -ru2 -- "${(F)reply}"; return 2; fi
  while (($#)); do
    arg=$1; shift
    case "$arg" in
      -t|--recursive) [[ $id == media-info ]] || { print -ru2 -- "未知参数：$arg"; return 2; }; recursive=1 ;;
      --udp) [[ $id == port-info ]] || return 2; protocol=UDP ;;
      --) (($# == 1 && seen == 0)) || return 2; directory=$1; seen=1; shift ;;
      *)
        ((seen == 0)) || { print -ru2 -- '只能指定一个目录或端口。'; return 2; }
        seen=1
        if [[ $id == port-info ]]; then
          [[ $arg == <1-65535> && ${#arg} -le 5 ]] || { print -ru2 -- '端口必须为 1–65535。'; return 2; }
          filter=$((10#$arg))
        else
          [[ $arg != -* ]] || { print -ru2 -- "未知参数：$arg"; return 2; }
          directory=$arg
        fi
        ;;
    esac
  done
  [[ -d $directory ]] || { print -ru2 -- "目录不存在：$directory"; return 2; }
  directory=${directory:A}
  tool_work=$(mktemp -d "${TMPDIR:-/tmp}/hub-tool-tui.XXXXXX") || return 2
  saved_terminal=$(stty -g)
  trap 'return 130' INT
  trap 'return 143' TERM
  trap 'return 129' HUP
  {
    if [[ $id == port-info ]]; then hub_tool_ports "$protocol" "$filter"
    else hub_tool_files "$id" "$directory" "$recursive"
    fi
  } always {
    if [[ -n $tool_worker ]]; then kill -TERM "$tool_worker" 2>/dev/null; wait "$tool_worker" 2>/dev/null || :; fi
    stty "$saved_terminal" 2>/dev/null
    rm -rf -- "$tool_work"
  }
}
