#!/bin/bash
# Machine-readable lsof fields avoid parsing its truncated, translated table.

port_validate_number() {
    case "$1" in ''|*[!0-9]*) return 2 ;; esac
    [ "${#1}" -le 5 ] && [ "$((10#$1))" -ge 1 ] && [ "$((10#$1))" -le 65535 ]
}

port_parse_lsof() {
    LC_ALL=C awk -v wanted="$1" -v filter="$2" '
      function emit( local_address, port, key) {
        if (pid !~ /^[1-9][0-9]*$/ || protocol != wanted) return
        if (wanted == "TCP" && state != "LISTEN") return
        local_address=address; sub(/->.*/, "", local_address)
        port=local_address; sub(/^.*:/, "", port)
        if (port !~ /^[0-9]+$/ || (filter != "" && port+0 != filter+0)) return
        key=pid SUBSEP protocol SUBSEP port
        if (!(key in rows)) {
          order[++count]=key
          rows[key]=pid "\t" protocol "\t" port "\t" user "\t" command
        }
        if (!seen[key SUBSEP local_address]++) {
          addresses[key]=addresses[key] (addresses[key] == "" ? "" : ", ") local_address
        }
      }
      {
        tag=substr($0,1,1); value=substr($0,2); gsub(/[[:cntrl:]]/, " ", value)
        if (tag=="p") { emit(); pid=value; user=""; command=""; protocol=""; address=""; state="" }
        else if (tag=="f") { emit(); protocol=""; address=""; state="" }
        else if (tag=="c") command=value
        else if (tag=="L") user=value
        else if (tag=="u" && user=="") user=value
        else if (tag=="P") protocol=value
        else if (tag=="n") address=value
        else if (tag=="T" && value ~ /^ST=/) state=substr(value,4)
      }
      END { emit(); for (i=1;i<=count;i++) { key=order[i]; print rows[key] "\t" addresses[key] } }
    '
}

port_identity() {
    LC_ALL=C ps -p "$1" -o lstart= 2>/dev/null | awk '{$1=$1; print}' || :
}

# TSV: PID, protocol, local port, user, executable name, addresses, start time.
port_snapshot() {
    local protocol=$1 filter=${2-} temp code pids
    local -a options
    case "$protocol" in TCP|UDP) ;; *) return 2 ;; esac
    [ -z "$filter" ] || port_validate_number "$filter" || return 2
    temp=$(mktemp -d "${TMPDIR:-/tmp}/hub-ports.XXXXXX") || return 2
    options=(-nP -i"$protocol" -FpcuLftPnT)
    [ "$protocol" != TCP ] || options+=(-sTCP:LISTEN)
    if lsof "${options[@]}" > "$temp/raw" 2> "$temp/error"; then code=0; else code=$?; fi
    if [ "$code" -gt 1 ] || { [ "$code" -ne 0 ] && [ -s "$temp/error" ]; }; then
        printf '端口读取失败：\n' >&2
        cat "$temp/error" >&2
        rm -rf "$temp"
        return 2
    fi
    port_parse_lsof "$protocol" "$filter" < "$temp/raw" > "$temp/rows"
    if [ -s "$temp/rows" ]; then
        pids=$(awk -F '\t' '!seen[$1]++ {printf "%s%s", separator, $1; separator=","}' "$temp/rows")
        LC_ALL=C ps -p "$pids" -o pid=,lstart= > "$temp/starts" 2>/dev/null || :
        awk -F '\t' '
          FILENAME==ARGV[1] {
            line=$0; sub(/^[[:space:]]+/, "", line); split(line,fields,/[[:space:]]+/)
            pid=fields[1]; sub(/^[0-9]+[[:space:]]+/, "", line)
            gsub(/[[:space:]]+/, " ", line); sub(/ $/, "", line); starts[pid]=line; next
          }
          starts[$1]!="" { print $0 "\t" starts[$1] }
        ' "$temp/starts" "$temp/rows"
    fi
    rm -rf "$temp"
    return 0
}

port_signal() {
    local pid=$1 expected=$2 protocol=$3 port=$4 signal=$5 current snapshot
    case "$pid" in ''|*[!0-9]*|0) printf '无效 PID。\n'; return 2 ;; esac
    case "$signal" in TERM|KILL) ;; *) return 2 ;; esac
    current=$(port_identity "$pid")
    if [ -z "$expected" ] || [ -z "$current" ] || [ "$current" != "$expected" ]; then
        printf '进程已退出或 PID 身份已变化，请刷新列表。\n'; return 3
    fi
    snapshot=$(port_snapshot "$protocol" "$port") || return 2
    if ! printf '%s\n' "$snapshot" | awk -F '\t' -v pid="$pid" -v started="$expected" '$1==pid && $7==started { found=1 } END { exit !found }'; then
        printf '该进程已不再占用此端口，请刷新列表。\n'; return 3
    fi
    if ! kill -"$signal" "$pid" 2>/dev/null; then
        printf '无法终止进程：权限不足，或进程已退出。\n'; return 1
    fi
    printf '已向 PID %s 发送 SIG%s。\n' "$pid" "$signal"
}

port_stop() {
    local pid=$1 expected=$2 protocol=$3 port=$4 signal=$5 current snapshot deadline
    port_signal "$@" || return $?
    deadline=$((SECONDS + 3))
    while [ "$SECONDS" -lt "$deadline" ]; do
        current=$(port_identity "$pid")
        if [ -z "$current" ] || [ "$current" != "$expected" ]; then
            printf '原进程已退出。\n'; return 0
        fi
        sleep 0.1
    done
    snapshot=$(port_snapshot "$protocol" "$port") || return 2
    if ! printf '%s\n' "$snapshot" | awk -F '\t' -v pid="$pid" -v started="$expected" '$1==pid && $7==started { found=1 } END { exit !found }'; then
        printf '端口已释放，进程仍在运行。\n'; return 0
    fi
    printf '进程仍在运行，端口仍被占用。\n'
    return 4
}

port_detail() {
    local pid protocol port user command addresses started current parent
    IFS=$'\t' read -r pid protocol port user command addresses started < "$1" || return 2
    printf '协议：%s\n本地端口：%s\n地址：%s\nPID：%s\n用户：%s\n进程：%s\n启动时间：%s\n' \
        "$protocol" "$port" "$addresses" "$pid" "$user" "$command" "$started"
    current=$(port_identity "$pid")
    [ "$current" = "$started" ] || { printf '\n进程已退出或身份变化，请刷新。\n'; return; }
    parent=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
    if [ -n "$parent" ]; then
        printf '父进程：%s ' "$parent"
        ps -p "$parent" -o comm= 2>/dev/null
    fi
    lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | awk '/^n/ { print "工作目录：" substr($0,2) }'
    printf '\n终止操作默认 SIGTERM，不会终止进程组。\n'
}

port_main() {
    local protocol=TCP port='' arg
    while [ "$#" -gt 0 ]; do
        arg=$1; shift
        case "$arg" in
            -h|--help) printf '%s\n' '用法：pinfo [端口]（TUI）' 'CLI：hub run port-info [--udp] [端口]' '默认仅列出 TCP LISTEN；--udp 列出 UDP 本地绑定。'; return 0 ;;
            --udp) protocol=UDP ;;
            *) [ -z "$port" ] && port_validate_number "$arg" || { printf '端口必须为 1–65535，且只能指定一个端口。\n' >&2; return 2; }; port=$((10#$arg)) ;;
        esac
    done
    command -v lsof >/dev/null 2>&1 || { printf '缺少 lsof。\n' >&2; return 2; }
    printf 'PID\t协议\t端口\t用户\t进程\t本地地址\t启动时间\n'
    port_snapshot "$protocol" "$port"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1-}" in
        --snapshot) shift; port_snapshot "$@" ;;
        --detail) shift; port_detail "$@" ;;
        --stop) shift; port_stop "$@" ;;
        *) port_main "$@" ;;
    esac
    exit $?
fi
