#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
[ -f "$ROOT/tools/network/port-info.sh" ] || { echo 'FAIL: port-info backend is missing'; exit 1; }
source "$ROOT/tools/network/port-info.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/hub-port-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT
cat > "$work/lsof" <<'DATA'
p101
cnode
u501
Ltester
f18
tIPv4
PTCP
n127.0.0.1:5176
TST=LISTEN
f19
tIPv6
PTCP
n[::1]:5176
TST=LISTEN
p102
cBrowser
u501
Ltester
f22
PTCP
n127.0.0.1:52524->127.0.0.1:5176
TST=ESTABLISHED
p103
cdns
u501
Ltester
f3
PUDP
n*:5353
f4
PUDP
n[::1]:5353->8.8.8.8:53
DATA
port_parse_lsof TCP '' < "$work/lsof" > "$work/rows"
[ "$(wc -l < "$work/rows" | tr -d ' ')" = 1 ]
grep -q $'^101\tTCP\t5176\ttester\tnode\t127.0.0.1:5176, \[::1\]:5176$' "$work/rows"
[ -z "$(port_parse_lsof TCP 52524 < "$work/lsof")" ]
[ -z "$(port_parse_lsof TCP 517 < "$work/lsof")" ]
[ "$(port_parse_lsof UDP 5353 < "$work/lsof" | wc -l | tr -d ' ')" = 1 ]
[ -z "$(port_parse_lsof UDP 53 < "$work/lsof")" ]
for value in 1 5176 65535 0053; do port_validate_number "$value"; done
for value in 0 65536 -1 1x 99999999999999999999999; do
    if port_validate_number "$value"; then echo "FAIL: accepted invalid port $value"; exit 1; fi
done
# Replace OS reads and signals only for identity/permission race scenarios.
identity='Fri Oct 23 12:00:00 2026'
port_identity() { printf '%s\n' "$identity"; }
port_snapshot() { printf '101\tTCP\t5176\ttester\tnode\t*:5176\t%s\n' "$identity"; }
kill() { printf '%s\n' "$*" >> "$work/signals"; return "${signal_result:-0}"; }
port_signal 101 "$identity" TCP 5176 TERM > "$work/output"
grep -q -- '-TERM 101' "$work/signals"
rm "$work/signals"
if port_signal 101 'old identity' TCP 5176 KILL > "$work/output"; then echo 'FAIL: reused PID signalled'; exit 1; fi
[ ! -e "$work/signals" ]
if port_signal -101 "$identity" TCP 5176 KILL > "$work/output"; then exit 1; fi
[ ! -e "$work/signals" ]
port_snapshot() { :; }
if port_signal 101 "$identity" TCP 5176 TERM > "$work/output"; then echo 'FAIL: stale endpoint signalled'; exit 1; fi
[ ! -e "$work/signals" ]
port_snapshot() { printf '101\tTCP\t5176\ttester\tnode\t*:5176\t%s\n' "$identity"; }
signal_result=1
if port_signal 101 "$identity" TCP 5176 TERM > "$work/output"; then echo 'FAIL: permission denial ignored'; exit 1; fi
grep -q '权限' "$work/output"
identity=''
if port_signal 101 'Fri Oct 23 12:00:00 2026' TCP 5176 TERM > "$work/output"; then echo 'FAIL: vanished PID accepted'; exit 1; fi
grep -q '退出' "$work/output"
# A service may release its socket yet keep running; do not offer an unnecessary KILL.
identity='Fri Oct 23 12:00:00 2026'
signal_result=0
port_snapshot() {
    [ ! -f "$work/queried" ] || return 0
    : > "$work/queried"
    printf '101\tTCP\t5176\ttester\tnode\t*:5176\t%s\n' "$identity"
}
port_stop 101 "$identity" TCP 5176 TERM > "$work/output"
grep -q '端口已释放，进程仍在运行' "$work/output"
echo 'PASS: port parsing, exact local ports, deduplication, identity and signal guards'
