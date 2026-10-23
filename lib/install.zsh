# Atomic replacement and backups remain inside the rc directory.
hub_configure() {
  local action=$1; shift
  local rc=$HOME/.zshrc
  if (( $# )); then
    if [[ $# != 2 || $1 != --rc ]]; then print -ru2 -- '用法：./hub install|uninstall [--rc 文件]'; return 2; fi
    rc=$2
  fi
  rc=${rc:A}
  local parent=${rc:h} temp backup changed=0
  mkdir -p -- "$parent" || return 2
  temp=$(mktemp -d "$parent/.shell-command-hub.XXXXXX") || return 2
  {
    if [[ -e $rc ]]; then
      [[ -f $rc && -r $rc ]] || { print -ru2 -- 'rc 必须是可读普通文件'; return 2; }
      awk '
        $0 == "# >>> shell-command-hub >>>" { starts++; if (inside || ends) bad=1; inside=1 }
        $0 == "# <<< shell-command-hub <<<" { ends++; if (!inside) bad=1; inside=0 }
        END { if (bad || starts != ends || starts > 1 || inside) exit 2 }
      ' "$rc" || { print -ru2 -- '配置块标记不完整、重复或顺序错误，未修改配置。'; return 2; }
      cp -p -- "$rc" "$temp/next" || return 2
    else
      (umask 077; : > "$temp/next") || return 2
    fi
    if [[ $action == install ]]; then
      print -r -- '# >>> shell-command-hub >>>' > "$temp/block"
      print -r -- "source ${(q)HUB_ROOT}/lib/aliases.zsh" >> "$temp/block"
      print -r -- '# <<< shell-command-hub <<<' >> "$temp/block"
    else
      : > "$temp/block"
    fi
    if [[ -e $rc ]]; then
      HUB_BLOCK_FILE="$temp/block" awk '
        function block( line) { while ((getline line < ENVIRON["HUB_BLOCK_FILE"]) > 0) print line; close(ENVIRON["HUB_BLOCK_FILE"]) }
        $0 == "# >>> shell-command-hub >>>" { block(); found=1; inside=1; next }
        $0 == "# <<< shell-command-hub <<<" { inside=0; next }
        !inside { print }
        END { if (!found) block() }
      ' "$rc" > "$temp/next" || return 2
    else
      cat "$temp/block" > "$temp/next" || return 2
    fi
    if [[ -e $rc ]] && cmp -s -- "$rc" "$temp/next"; then
      print -r -- '配置已是最新状态。'; return 0
    fi
    if [[ $action == uninstall && ! -e $rc ]]; then print -r -- '尚未注册。'; return 0; fi
    if [[ -e $rc ]]; then
      backup="$rc.shell-command-hub.$(date +%Y%m%d%H%M%S).$$.bak"
      cp -p -- "$rc" "$backup" || return 2
      print -r -- "已备份：$backup"
    fi
    mv -f -- "$temp/next" "$rc" || return 2
    if [[ $action == install ]]; then print -r -- "已注册 hub / zidy / vinfo / pinfo：$rc"
    else print -r -- "已移除 hub 注册块：$rc"
    fi
    print -r -- '打开新终端，或执行：exec zsh'
  } always {
    local file
    for file in "$temp"/*(N); do unlink "$file"; done
    rmdir "$temp"
  }
}
