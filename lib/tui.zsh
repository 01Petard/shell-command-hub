# Native zsh TUI: ANSI alternate screen, terminal input, and shell subprocesses.
hub_clip() {
  local text=${1//[[:cntrl:]]/ } limit=$2 char result='' used=0 cost
  for char in "${(@s::)text}"; do
    if [[ $char == [\ -\~] ]]; then cost=1; else cost=2; fi
    (( used + cost > limit )) && break
    result+=$char; (( used += cost ))
  done
  REPLY=$result
}
hub_at() {
  local row=$1 col=$2 text=$3 style=${4-} limit=${5:-$((hub_columns-col))}
  (( row > 0 && row <= hub_rows && col > 0 && col < hub_columns )) || return 0
  hub_clip "$text" "$limit"
  printf '\033[%d;%dH%s%s\033[0m' "$row" "$col" "$style" "$REPLY"
}
hub_size() {
  local dimensions
  dimensions=(${=:-$(stty size 2>/dev/null)})
  hub_rows=${dimensions[1]:-24}; hub_columns=${dimensions[2]:-80}
}
hub_screen_enter() { printf '\033[?1049h\033[?25l\033[2J\033[H'; }
hub_screen_leave() { printf '\033[0m\033[?25h\033[?1049l'; }
hub_key() {
  local first='' second='' third=''
  local previous_rows=$hub_rows previous_columns=$hub_columns
  while ! read -rsk 1 -t 0.3 first; do
    hub_size
    if ((hub_rows != previous_rows || hub_columns != previous_columns)); then REPLY=resize; return; fi
  done
  if [[ $first == $'\e' ]]; then
    if read -rsk 1 -t 0.08 second; then
      if [[ $second == '[' || $second == O ]]; then
        read -rsk 1 -t 0.08 third
        case $third in
          A) REPLY=up; return ;;
          B) REPLY=down; return ;;
          5|6) read -rsk 1 -t 0.08 second; [[ $third == 5 ]] && REPLY=pageup || REPLY=pagedown; return ;;
        esac
      fi
    fi
    REPLY=escape
  else
    case $first in
      $'\n'|$'\r') REPLY=enter ;;
      $'\t') REPLY=tab ;;
      *) REPLY=$first ;;
    esac
  fi
}
hub_prompt() {
  local title=$1 default=$2 explanation=$3 value=''
  hub_size
  printf '\033[2J\033[H'
  hub_at 2 3 "$title" "$hub_accent"
  hub_at 4 3 "$explanation"
  [[ -z $default ]] || hub_at 6 3 "默认：$default"
  [[ -z ${4-} ]] || hub_at 6 3 "目标：$4"
  hub_at $((hub_rows-2)) 3 'Enter 确认 · Ctrl+U 清空输入 · 输入 :cancel 取消' "$hub_dim"
  printf '\033[8;3H\033[?25h> '
  if ! IFS= read -r value; then printf '\033[?25l'; return 1; fi
  printf '\033[?25l'
  [[ $value == :cancel ]] && return 1
  [[ -n $value ]] || value=$default
  REPLY=$value
}
hub_reader() {
  local title=$1 text=$2 offset=1 page key line i total
  local -a lines paragraphs
  paragraphs=("${(@f)text}")
  while true; do
    hub_size
    (( hub_rows < 12 || hub_columns < 40 )) && { printf '\033[2J\033[H请放大终端；q 返回。'; hub_key; [[ $REPLY == q || $REPLY == escape ]] && return; continue; }
    lines=()
    for line in "${paragraphs[@]}"; do
      if [[ -z $line ]]; then lines+=(''); continue; fi
      while [[ -n $line ]]; do
        hub_clip "$line" $((hub_columns-5))
        lines+=("$REPLY")
        line=${line[$((${#REPLY}+1)),-1]}
      done
    done
    page=$((hub_rows-6)); total=${#lines}
    ((offset > total-page+1)) && offset=$((total-page+1))
    ((offset < 1)) && offset=1
    printf '\033[2J\033[H'
    hub_at 2 3 "$title" "$hub_accent"
    for (( i=0; i<page && offset+i<=total; i++ )); do
      hub_at $((4+i)) 3 "${lines[offset+i]}"
    done
    hub_at $((hub_rows-1)) 3 "↑↓/jk 滚动 · PgUp/PgDn 翻页 · q/Esc 返回  $offset/$total" "$hub_dim"
    hub_key; key=$REPLY
    case $key in
      q|escape|enter) return ;;
      j|down) ((offset++)) ;;
      k|up) ((offset--)) ;;
      ' '|pagedown) ((offset+=page)) ;;
      pageup) ((offset-=page)) ;;
    esac
  done
}
hub_filter() {
  local id haystack group=${HUB_CATEGORIES[hub_category]}
  hub_visible=()
  for id in "${HUB_IDS[@]}"; do
    [[ $group == 全部 || ${HUB_GROUPS[$id]} == "$group" ]] || continue
    haystack="$id ${HUB_NAMES[$id]} ${HUB_GROUPS[$id]} ${HUB_SUMMARIES[$id]} ${HUB_ALIASES[$id]}"
    [[ ${(L)haystack} == *"${(L)hub_query}"* ]] && hub_visible+=("$id")
  done
  ((hub_selected > ${#hub_visible})) && hub_selected=${#hub_visible}
  ((hub_selected < 1)) && hub_selected=1
}
hub_draw() {
  hub_size; hub_filter
  local i id offset=$((hub_selected-(hub_rows-11))) split=$((hub_columns/3)) col label style
  ((offset < 0)) && offset=0
  printf '\033[2J\033[H'
  hub_at 2 3 'SHELL COMMAND HUB' "$hub_accent"
  hub_at 3 3 'vinfo / zidy / pinfo · Shell 工具箱' "$hub_dim"
  if ((hub_rows < 16 || hub_columns < 48)); then
    hub_at 6 3 '请放大终端至 48 列 × 16 行。'; hub_at 8 3 'q 退出'; return
  fi
  hub_at 5 3 "分类 [${HUB_CATEGORIES[hub_category]}]  Tab 切换    / 搜索：$hub_query" "$hub_accent"
  ((hub_columns < 90)) && split=$((hub_columns-2))
  for ((i=offset+1; i<=${#hub_visible} && i-offset<=hub_rows-11; i++)); do
    id=${hub_visible[i]}; style=''; label="  ${HUB_NAMES[$id]}"
    if ((i==hub_selected)); then style=$hub_selection; label="> ${HUB_NAMES[$id]}"; fi
    hub_at $((6+i-offset)) 3 "$label" "$style" $((split-3))
  done
  if ((${#hub_visible}==0)); then hub_at 7 3 '没有匹配的条目。'
  elif ((hub_columns>=90)); then
    id=${hub_visible[hub_selected]}; col=$((split+3))
    hub_at 7 $col "${HUB_NAMES[$id]}" "$hub_accent"
    hub_at 9 $col "$id  → ${HUB_ALIASES[$id]}"
    hub_at 11 $col "${HUB_SUMMARIES[$id]}"
    hub_at 13 $col '类型：可执行工具 · Enter 打开 · d 阅读说明'
    if hub_problems "$id"; then hub_at 15 $col '环境：已就绪'; else hub_at 15 $col "环境：${(j:；:)reply}"; fi
    [[ $id == zip-tidy ]] && hub_at 17 $col '成功解压后会删除原 ZIP 并整理目录。'
    [[ $id == port-info ]] && hub_at 17 $col '终止前确认 PID；默认 SIGTERM，可选强杀。'
  fi
  hub_at $((hub_rows-3)) 3 "$hub_notice" "$hub_dim"
  hub_at $((hub_rows-2)) 3 '↑↓/jk 选择  Enter 打开  d 说明  / 搜索  Tab 分类' "$hub_accent"
  hub_at $((hub_rows-1)) 3 'c 环境检查  ? 帮助  q 退出' "$hub_dim"
}
hub_tui_run() {
  local id=$1 code
  if ! hub_problems "$id"; then hub_reader '环境检查未通过' "${(F)reply}"; return; fi
  hub_screen_leave
  hub_tool_tui "$id"; code=$?
  if ((code != 0)); then IFS= read -r '?按 Enter 返回命令中心…'; fi
  hub_screen_enter
  hub_notice="${HUB_NAMES[$id]} 已结束，退出码 $code。"
}
hub_tui() {
  [[ -t 0 && -t 1 ]] || { print -ru2 -- 'TUI 需要交互终端。使用 ./hub list / ./hub show / ./hub run。'; return 2; }
  local hub_rows=24 hub_columns=80 hub_category=1 hub_selected=1 hub_query='' hub_notice='选择工具开始，或按 d 阅读说明。'
  local hub_accent=$'\e[1;36m' hub_dim=$'\e[2m' hub_selection=$'\e[30;46m' hub_saved_terminal=$(stty -g)
  local key id content
  local -a hub_visible
  trap 'stty "$hub_saved_terminal" 2>/dev/null; hub_screen_leave' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  hub_screen_enter
  while true; do
    hub_draw
    hub_key; key=$REPLY
    case $key in
      q|escape) break ;;
      j|down) ((hub_selected++)) ;;
      k|up) ((hub_selected--)) ;;
      tab) ((hub_category=hub_category%${#HUB_CATEGORIES}+1)); hub_selected=1 ;;
      /) if hub_prompt '搜索名称、类别或命令' '' '留空确认可清除搜索。'; then hub_query=$REPLY; hub_selected=1; fi ;;
      c) content=$(hub_doctor); hub_reader '环境检查' "$content" ;;
      \?) hub_reader '使用帮助' $'Tab 切换分类；/ 搜索。\n方向键或 j/k 选择工具。\nEnter 打开 fzf 工具界面；d 阅读说明。\n工具内输入文字搜索，Ctrl+R 刷新，Esc 返回。\n媒体/ZIP：Ctrl+O 切换目录。媒体：Ctrl+T 切换递归。\nZIP：Ctrl+X 确认整目录处理；执行中 Esc 中断。\n端口：Ctrl+U 切换 TCP/UDP；Enter 确认终止。\nq 或 Esc 返回/退出；Ctrl+C 中断。' ;;
      enter|d)
        ((${#hub_visible})) || continue
        id=${hub_visible[hub_selected]}
        if [[ $key == d ]]; then content=$(<"$HUB_ROOT/${HUB_DOCS[$id]}"); hub_reader "${HUB_NAMES[$id]}" "$content"
        else hub_tui_run "$id"
        fi ;;
    esac
  done
  stty "$hub_saved_terminal" 2>/dev/null
  hub_screen_leave
  trap - EXIT INT TERM
  return 0
}
