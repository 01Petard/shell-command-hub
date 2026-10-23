#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
source "$ROOT/tools/network/port-info.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/hub-port-live.XXXXXX")
listener=''
cleanup() {
    if [ -n "$listener" ]; then kill -KILL "$listener" 2>/dev/null || :; wait "$listener" 2>/dev/null || :; fi
    rm -rf "$work"
}
trap cleanup EXIT
wait_for_port() {
    local protocol=$1 i
    for ((i=0; i<40; i++)); do
        port_snapshot "$protocol" '' > "$work/snapshot"
        row=$(awk -F '\t' -v pid="$listener" '$1==pid { print; exit }' "$work/snapshot")
        [ -z "$row" ] || return 0
        sleep 0.05
    done
    echo 'FAIL: test-owned listener did not bind' >&2
    return 1
}
/usr/bin/nc -l -k 127.0.0.1 0 < /dev/null > "$work/nc" 2>&1 &
listener=$!
wait_for_port TCP
IFS=$'\t' read -r pid protocol port _user _executable _addresses started <<< "$row"
[ "$pid" = "$listener" ]
port_stop "$pid" "$started" TCP "$port" TERM > "$work/result" 2>&1
grep -q '原进程已退出' "$work/result"
wait "$listener" 2>/dev/null || :
listener=''
[ -z "$(port_snapshot TCP "$port")" ]
# Ignore TERM in this test-owned nc, then exercise the explicit KILL path.
/bin/bash -c 'trap "" TERM; exec /usr/bin/nc -l -k 127.0.0.1 0' < /dev/null > "$work/nc" 2>&1 &
listener=$!
wait_for_port TCP
IFS=$'\t' read -r pid protocol port _user _executable _addresses started <<< "$row"
code=0
port_stop "$pid" "$started" TCP "$port" TERM > "$work/result" 2>&1 || code=$?
[ "$code" = 4 ]
kill -0 "$listener"
port_stop "$pid" "$started" TCP "$port" KILL > "$work/result" 2>&1
wait "$listener" 2>/dev/null || :
listener=''
/usr/bin/nc -u -l 127.0.0.1 0 < /dev/null > "$work/nc" 2>&1 &
listener=$!
wait_for_port UDP
IFS=$'\t' read -r pid protocol port _user _executable _addresses started <<< "$row"
[ "$protocol" = UDP ]
port_stop "$pid" "$started" UDP "$port" TERM > "$work/result" 2>&1
wait "$listener" 2>/dev/null || :
listener=''
if [ -x /usr/bin/expect ] && command -v fzf >/dev/null 2>&1; then
    /usr/bin/nc -l -k 127.0.0.1 0 < /dev/null > "$work/nc" 2>&1 &
    listener=$!
    wait_for_port TCP
    IFS=$'\t' read -r pid protocol port _user _executable _addresses started <<< "$row"
    /usr/bin/expect "$ROOT/tests/test_port_tui.exp" "$ROOT" "$port" "$pid"
    wait "$listener" 2>/dev/null || :
    listener=''
fi
echo 'PASS: real test-owned TCP/UDP listeners, SIGTERM timeout and explicit SIGKILL'
