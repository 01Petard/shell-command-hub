# Shared catalog and execution functions. Data is read as text, never evaluated.
typeset -ga HUB_IDS HUB_CATEGORIES
typeset -gA HUB_NAMES HUB_GROUPS HUB_SUMMARIES HUB_ENTRIES HUB_RUNTIMES HUB_ALIASES HUB_DEPS HUB_PLATFORMS HUB_RECURSIVE HUB_DANGEROUS HUB_DOCS
hub_load_catalog() {
  local id name category summary entry runtime shortcut dependency platform recursive dangerous doc
  HUB_CATEGORIES=(全部)
  while IFS=$'\t' read -r id name category summary entry runtime shortcut dependency platform recursive dangerous doc; do
    [[ -z $id || $id == \#* ]] && continue
    if [[ -z $doc || -n ${HUB_NAMES[$id]-} ]]; then
      print -ru2 -- "命令清单无效：$id"; return 2
    fi
    HUB_IDS+=("$id")
    (( ${HUB_CATEGORIES[(Ie)$category]} )) || HUB_CATEGORIES+=("$category")
    HUB_NAMES[$id]=$name; HUB_GROUPS[$id]=$category; HUB_SUMMARIES[$id]=$summary
    HUB_ENTRIES[$id]=$entry; HUB_RUNTIMES[$id]=$runtime; HUB_ALIASES[$id]=$shortcut
    HUB_DEPS[$id]=$dependency; HUB_PLATFORMS[$id]=$platform
    HUB_RECURSIVE[$id]=$recursive; HUB_DANGEROUS[$id]=$dangerous; HUB_DOCS[$id]=$doc
  done < "$HUB_ROOT/catalog.tsv"
}
hub_lookup() {
  local id
  for id in "${HUB_IDS[@]}"; do
    if [[ $1 == "$id" || ( ${HUB_ALIASES[$id]} != - && $1 == "${HUB_ALIASES[$id]}" ) ]]; then
      REPLY=$id; return 0
    fi
  done
  print -ru2 -- "未知命令：$1"; return 2
}
hub_problems() {
  local id=$1 dep=${HUB_DEPS[$1]}
  reply=()
  [[ ${HUB_PLATFORMS[$id]} == darwin && $OSTYPE != darwin* ]] && reply+=('仅支持 macOS')
  [[ $dep != - ]] && ! command -v "$dep" >/dev/null 2>&1 && reply+=("缺少依赖：$dep")
  [[ -f "$HUB_ROOT/${HUB_DOCS[$id]}" ]] || reply+=('说明文档不存在')
  [[ ${HUB_ENTRIES[$id]} == - || -f "$HUB_ROOT/${HUB_ENTRIES[$id]}" ]] || reply+=('工具脚本不存在')
  (( ${#reply} == 0 ))
}
hub_list() {
  local query=${(L)1} id haystack
  for id in "${HUB_IDS[@]}"; do
    haystack="$id ${HUB_NAMES[$id]} ${HUB_GROUPS[$id]} ${HUB_SUMMARIES[$id]} ${HUB_ALIASES[$id]}"
    [[ ${(L)haystack} == *"$query"* ]] && print -r -- "$id  [${HUB_GROUPS[$id]}] ${HUB_NAMES[$id]} — ${HUB_SUMMARIES[$id]}"
  done
  return 0
}
hub_doctor() {
  local id failed=0
  if command -v fzf >/dev/null 2>&1; then print -r -- 'fzf TUI: OK'
  else print -r -- 'fzf TUI: 缺少 fzf，brew install fzf；普通 CLI 仍可使用。'; failed=1
  fi
  for id in "${HUB_IDS[@]}"; do
    if hub_problems "$id"; then print -r -- "$id: OK"
    else print -r -- "$id: ${(j:；:)reply}"; failed=1
    fi
  done
  return $failed
}
hub_run() {
  local id=$1; shift
  if [[ $id == port-info && ( ${1-} == --stop || ${1-} == --snapshot || ${1-} == --detail ) ]]; then
    print -ru2 -- '端口 CLI 仅支持查询；终止进程请使用 hub tui port-info。'; return 2
  fi
  if [[ ${HUB_ENTRIES[$id]} == - ]]; then
    print -ru2 -- '此条目未配置可执行脚本。'; return 2
  fi
  if ! hub_problems "$id"; then print -ru2 -- "${(F)reply}"; return 2; fi
  /bin/bash "$HUB_ROOT/${HUB_ENTRIES[$id]}" "$@"
}
